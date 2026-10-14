import streamlit as st
import pandas as pd

from optimize_config import (CONCISE_MAX_TOKENS, CONCISE_SYSTEM, config, dominant_model,
                             other_model, proposal)

st.header("Advisor")

df: pd.DataFrame = st.session_state["df"]
usage_df: pd.DataFrame = st.session_state["usage_df"]

if df.empty:
    st.info("No trace data for the selected filters.")
    st.stop()

# ---------------------------------------------------------------------------
# Tunable thresholds
# ---------------------------------------------------------------------------
LATENCY_THRESHOLD_MS = 10_000
ERROR_RATE_THRESHOLD = 5.0
MIN_ERRORS_FOR_SPIKE = 3
TOKEN_BLOAT_THRESHOLD = 2000
TOKEN_BLOAT_MIN_REQUESTS = 3
SLOW_MODEL_MS = 5000
FAST_MODEL_MS = 3000
SINGLE_MODEL_MIN_REQUESTS = 5

# ---------------------------------------------------------------------------
# Recommendation engine
# ---------------------------------------------------------------------------
recommendations: list[dict] = []


CONCISE = {"max_tokens": CONCISE_MAX_TOKENS, "system_prompt": CONCISE_SYSTEM}


def add_rec(severity: str, title: str, detail: str, fix: dict | None = None,
            baseline: dict | None = None):
    """fix = config changes to test; baseline = the config of the flagged traffic."""
    recommendations.append({"severity": severity, "title": title, "detail": detail,
                            "proposal": proposal(title, baseline, **fix) if fix else None})


# Rule 1: High latency patterns
user_lat = df.groupby("USER_NAME")["DURATION_MS"].mean()
for user, avg_ms in user_lat.items():
    if avg_ms > LATENCY_THRESHOLD_MS:
        add_rec(
            "HIGH",
            f"High avg latency for {user}: {avg_ms:,.0f} ms",
            "Consider using faster models, reducing prompt length, or adding "
            "max_tokens to limit output size. For interactive workloads, target "
            "sub-5s latency.",
            CONCISE,
            config(dominant_model(df[df["USER_NAME"] == user])),
        )

# Rule 2: Error rate spikes
total_by_model = df.groupby("REQUEST_MODEL").size()
errors_by_model = df[df["STATUS_CODE"] == "STATUS_CODE_ERROR"].groupby("REQUEST_MODEL").size()
for model in total_by_model.index:
    err_count = errors_by_model.get(model, 0)
    rate = err_count / total_by_model[model] * 100
    if rate > ERROR_RATE_THRESHOLD and err_count >= MIN_ERRORS_FOR_SPIKE:
        add_rec(
            "HIGH",
            f"Error rate spike for {model}: {rate:.1f}% ({err_count} errors)",
            "Check HTTP status codes for patterns (429 = rate limit, 500 = server "
            "error). Consider adding retry logic with exponential backoff or "
            "configuring a fallback model in the Gateway spec.",
            {"model": other_model(model, "openai-gpt-5.4")},
            config(model),
        )

# Rule 3: Token bloat
combo = df.groupby(["USER_NAME", "REQUEST_MODEL"]).agg(
    REQUESTS=("SPAN_ID", "count"),
    AVG_OUTPUT=("OUTPUT_TOKENS", "mean"),
).reset_index()
bloated = combo[(combo["AVG_OUTPUT"] > TOKEN_BLOAT_THRESHOLD) & (combo["REQUESTS"] >= TOKEN_BLOAT_MIN_REQUESTS)]
for _, row in bloated.iterrows():
    add_rec(
        "MEDIUM",
        f"Token bloat: {row['USER_NAME']} + {row['REQUEST_MODEL']} avg {row['AVG_OUTPUT']:,.0f} output tokens",
        "Set max_tokens in the API call, use structured output instructions "
        '("respond in JSON", "limit to 3 bullet points"), or add a system '
        "prompt that constrains verbosity.",
        CONCISE,
        config(row["REQUEST_MODEL"]),
    )

# Rule 4: Underutilized fast models
model_avg_lat = df.groupby("REQUEST_MODEL").agg(
    AVG_LAT=("DURATION_MS", "mean"),
    VOLUME=("SPAN_ID", "count"),
).reset_index()
slow = model_avg_lat[model_avg_lat["AVG_LAT"] > SLOW_MODEL_MS]
fast = model_avg_lat[model_avg_lat["AVG_LAT"] < FAST_MODEL_MS]
if not slow.empty and not fast.empty:
    slow_vol = slow["VOLUME"].sum()
    fast_vol = fast["VOLUME"].sum()
    if fast_vol > 0 and slow_vol >= 2 * fast_vol:
        slow_model = slow.sort_values("VOLUME").iloc[-1]["REQUEST_MODEL"]
        fast_model = fast.sort_values("AVG_LAT").iloc[0]["REQUEST_MODEL"]
        add_rec(
            "MEDIUM",
            f"Slow models handle {slow_vol} requests vs {fast_vol} on fast models",
            "Consider rebalancing workloads: route simpler tasks to faster, "
            "cheaper models and reserve high-latency models for complex reasoning.",
            {"model": fast_model},
            config(slow_model),
        )

# Rule 5: No conversation threading
if "CONVERSATION_ID" in df.columns:
    non_null = df["CONVERSATION_ID"].dropna()
    non_empty = non_null[non_null.astype(str).str.strip() != ""]
    if non_empty.empty:
        add_rec(
            "LOW",
            "No conversation threading detected",
            "Add the x-snowflake-ai-gateway-conversation-id header to group "
            "multi-turn conversations. This enables conversation-level tracing "
            "and analytics. Especially useful since this LangChain agent makes "
            "multiple gateway calls per turn.",
        )

# Rule 6: Single-model usage
unique_models = df["REQUEST_MODEL"].nunique()
if unique_models == 1 and len(df) >= SINGLE_MODEL_MIN_REQUESTS:
    model_name = df["REQUEST_MODEL"].iloc[0]
    add_rec(
        "LOW",
        f"All {len(df)} requests use a single model: {model_name}",
        "Consider testing alternative models for cost/latency optimization. "
        "Configure model fallback in the AI Gateway spec so requests "
        "automatically route to a backup when the primary is slow or unavailable.",
        {"model": other_model(model_name)},
        config(model_name),
    )

# Rule 7: Spend against per-user quotas (today's spend vs each quota's daily limit)
QUOTA_WARN_PCT = 80


@st.cache_data(ttl="2m", show_spinner=False)
def quota_pressure() -> pd.DataFrame:
    """One row per (quota, user) at or above QUOTA_WARN_PCT of the daily limit, or blocked."""
    session = st.session_state["conn"].session()
    today = pd.Timestamp.now().date().isoformat()
    out = []
    try:
        quotas = [r["name"] for r in session.sql(
            "SHOW SNOWFLAKE.CORE.QUOTA IN SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC").collect()]
    except Exception:
        return pd.DataFrame()
    for q in quotas:
        fq = f"CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.{q}"
        try:
            limit = session.sql(f"CALL {fq}!GET_CONFIG()").collect()[0].as_dict().get("PER_USER_LIMIT_DAILY")
            blocked = {r.as_dict().get("USER_NAME") for r in session.sql(f"CALL {fq}!GET_ACTIVE_BLOCKS_V2()").collect()}
            spend = pd.DataFrame([r.as_dict() for r in session.sql(
                f"CALL {fq}!GET_SPENDING_DETAILS_BY_USERS(?, ?)", params=[today, today]).collect()])
        except Exception:
            continue
        per_user = (spend.groupby("USER_NAME")["CREDITS_SPEND"].sum() if not spend.empty
                    else pd.Series(dtype=float))
        for user in set(per_user.index) | blocked:
            pct = 100 * float(per_user.get(user, 0)) / float(limit) if limit else None
            if user in blocked or (pct is not None and pct >= QUOTA_WARN_PCT):
                out.append({"QUOTA": q, "USER_NAME": user, "PCT": pct, "BLOCKED": user in blocked})
    return pd.DataFrame(out)


for _, row in quota_pressure().iterrows():
    state = "is blocked" if row["BLOCKED"] else f"is at {row['PCT']:.0f}% of its daily limit"
    user_df = df[df["USER_NAME"] == row["USER_NAME"]]
    add_rec(
        "HIGH" if row["BLOCKED"] else "MEDIUM",
        f"{row['USER_NAME']} {state} in quota {row['QUOTA']}",
        "The quota blocks this user's AI requests at the limit. Cut cost per request "
        "(concise prompts, lower max_tokens, a smaller model), or raise the limit or move "
        "the user to a higher-tier quota. See the Cost governance page.",
        CONCISE,
        config(dominant_model(user_df if not user_df.empty else df)),
    )

# ---------------------------------------------------------------------------
# Display recommendations
# ---------------------------------------------------------------------------
st.subheader("Recommendations")

SEVERITY_ORDER = {"HIGH": 0, "MEDIUM": 1, "LOW": 2}
SEVERITY_COLOR = {"HIGH": "red", "MEDIUM": "orange", "LOW": "blue"}

recommendations.sort(key=lambda r: SEVERITY_ORDER.get(r["severity"], 9))

if not recommendations:
    st.success("No issues detected — your gateway usage looks healthy.")
else:
    for i, rec in enumerate(recommendations):
        color = SEVERITY_COLOR[rec["severity"]]
        with st.container(border=True):
            st.markdown(f":{color}[**{rec['severity']}**] — {rec['title']}")
            st.caption(rec["detail"])
            p = rec["proposal"]
            if p:
                changed = {k: v for k, v in p["candidate"].items() if p["baseline"][k] != v}
                st.caption(f"Baseline `{p['baseline']['model']}`. Proposed change: " + ", ".join(
                    f"`{k}`={str(v)[:40]}" for k, v in changed.items()))
                if st.button(":material/science: Test this fix", key=f"exp_{i}"):
                    st.session_state["experiment_seed"] = p
                    st.switch_page("app_pages/experiments.py")

# ---------------------------------------------------------------------------
# Best practices
# ---------------------------------------------------------------------------
st.subheader("Gateway and prompting best practices")

practices = [
    (
        ":material/format_list_bulleted: Structured prompts",
        "Use clear section markers (System, Context, Task, Format) in prompts "
        "for consistent, parseable outputs.",
    ),
    (
        ":material/smart_toy: System prompts",
        "Set a system prompt that defines the assistant's role, constraints, and "
        "output format. This reduces output token waste.",
    ),
    (
        ":material/token: max_tokens",
        "Always set max_tokens to prevent runaway generation. Match it to the "
        "expected output size for your use case.",
    ),
    (
        ":material/swap_vert: Model tier selection",
        "Use smaller/faster models for classification, extraction, and simple Q&A. "
        "Reserve large models for complex reasoning and creative tasks.",
    ),
    (
        ":material/link: W3C traceparent header",
        "Pass a traceparent header on every gateway call so all spans from one "
        "agent turn share a single trace_id. Without it each call appears as "
        "an unrelated event.",
    ),
    (
        ":material/forum: Conversation-id header",
        "Use x-snowflake-ai-gateway-conversation-id for multi-turn sessions. "
        "This groups related turns for analytics and enables conversation-level "
        "cost tracking.",
    ),
]

for title, tip in practices:
    with st.container(border=True):
        st.markdown(f"**{title}**")
        st.caption(tip)
