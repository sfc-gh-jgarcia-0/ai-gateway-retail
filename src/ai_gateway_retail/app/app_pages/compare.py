import pandas as pd
import streamlit as st

from optimize_config import estimate_credits

st.header("Before / after")

conn = st.session_state["conn"]
rates = st.session_state.get("credit_rates", {})

runs = conn.query(
    "SELECT RUN_ID, LABEL, MODEL, MAX_TOKENS, SYSTEM_PROMPT, SOURCE_FINDING, CREATED_AT "
    "FROM OPTIMIZATION_RUNS ORDER BY CREATED_AT DESC LIMIT 100",
    ttl=0,
)
if runs.empty:
    st.info("No experiment runs yet. Start one from the Experiments page.")
    st.stop()

ids = runs["RUN_ID"].tolist()
cfg = runs.set_index("RUN_ID")


def pair_of(run_id: str) -> str:
    return run_id.split("-", 1)[-1]


# Default to the experiment just run, else the newest complete baseline/candidate pair.
b_def, c_def = st.session_state.get("compare_runs", (None, None))
if b_def not in ids or c_def not in ids:
    b_def = c_def = None
    for rid in ids:
        if rid.startswith("candidate-") and f"baseline-{pair_of(rid)}" in ids:
            b_def, c_def = f"baseline-{pair_of(rid)}", rid
            break


def describe(rid: str) -> str:
    r = cfg.loc[rid]
    finding = f" - {r['SOURCE_FINDING'][:40]}" if isinstance(r["SOURCE_FINDING"], str) else ""
    return f"{rid} | {r['MODEL']} / {r['MAX_TOKENS']} tok{finding}"


c1, c2 = st.columns(2)
b_id = c1.selectbox("Baseline run", ids, index=ids.index(b_def) if b_def else min(1, len(ids) - 1),
                    format_func=describe)
c_id = c2.selectbox("Candidate run", ids, index=ids.index(c_def) if c_def else 0,
                    format_func=describe)
if b_id == c_id:
    st.warning("Pick two different runs to compare.")
    st.stop()
if pair_of(b_id) != pair_of(c_id):
    st.caption("These runs come from different experiments; eval prompts may differ.")

# Gateway-side duration comes from the trace table, joined on the trace_id we sent.
res = conn.query(
    f"""
    WITH spans AS (
        SELECT TRACE:"trace_id"::STRING AS TRACE_ID,
               MAX(DATEDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)) AS GATEWAY_MS
        FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
        WHERE TIMESTAMP > DATEADD('day', -7, CURRENT_TIMESTAMP())
          AND SCOPE:"name"::STRING = 'aigateway/tracing'
        GROUP BY 1
    )
    SELECT x.*, s.GATEWAY_MS, e.PROMPT, e.CATEGORY
    FROM OPTIMIZATION_RESULTS x
    LEFT JOIN spans s USING (TRACE_ID)
    JOIN EVAL_PROMPTS e USING (PROMPT_ID)
    WHERE x.RUN_ID IN ('{b_id}', '{c_id}')
    """,
    ttl=0,
)
for col in ("LATENCY_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "JUDGE_SCORE", "GATEWAY_MS"):
    res[col] = pd.to_numeric(res[col], errors="coerce")


def summarize(run_id):
    r = res[res["RUN_ID"] == run_id]
    ok = r[r["STATUS"] == "OK"]
    model = cfg.loc[run_id, "MODEL"]
    cost = ok.apply(lambda x: estimate_credits(model, x["INPUT_TOKENS"], x["OUTPUT_TOKENS"], rates), axis=1)
    return {
        "Quality (judge)": ok["JUDGE_SCORE"].mean(),
        "p50 latency ms": ok["LATENCY_MS"].median(),
        "p95 latency ms": ok["LATENCY_MS"].quantile(0.95),
        "Avg output tokens": ok["OUTPUT_TOKENS"].mean(),
        "Credits / 1k req": 1000 * cost.mean() if len(cost) and cost.notna().all() else None,
        "Error rate %": 100 * (1 - len(ok) / len(r)) if len(r) else None,
    }


b, c = summarize(b_id), summarize(c_id)
lower_is_better = {"p50 latency ms", "p95 latency ms", "Avg output tokens",
                   "Credits / 1k req", "Error rate %"}

with st.container(border=True):
    cols = st.columns(len(b))
    for col, key in zip(cols, b):
        bv, cv = b[key], c[key]
        if pd.isna(cv):
            col.metric(key, "-")
            continue
        delta = None if pd.isna(bv) else cv - bv
        fmt = "{:.2f}" if key in ("Quality (judge)", "Credits / 1k req") else "{:,.0f}"
        col.metric(key, fmt.format(cv),
                   delta=None if delta is None else fmt.format(delta),
                   delta_color="inverse" if key in lower_is_better else "normal",
                   help=f"Baseline: {fmt.format(bv) if not pd.isna(bv) else '-'}")

st.caption(
    f"Baseline `{cfg.loc[b_id, 'MODEL']}` / max_tokens {cfg.loc[b_id, 'MAX_TOKENS']}  ->  "
    f"Candidate `{cfg.loc[c_id, 'MODEL']}` / max_tokens {cfg.loc[c_id, 'MAX_TOKENS']}. "
    "Credits use per-model rates fitted from this account's AI_GATEWAY_USAGE_HISTORY."
)

# Projected saving at the current gateway volume
usage_df = st.session_state.get("usage_df")
b_cost, c_cost = b["Credits / 1k req"], c["Credits / 1k req"]
if usage_df is not None and not usage_df.empty and b_cost and c_cost:
    span_days = max((usage_df["START_TIME"].max() - usage_df["START_TIME"].min()).days, 1)
    monthly_req = len(usage_df) / span_days * 30
    saving = (b_cost - c_cost) / 1000 * monthly_req
    st.info(f"At the current volume (~{monthly_req:,.0f} gateway requests/month), the candidate "
            f"{'saves' if saving >= 0 else 'adds'} about **{abs(saving):,.2f} credits/month** "
            f"({abs(1 - c_cost / b_cost):.0%} {'less' if saving >= 0 else 'more'} per request).")

st.subheader("Per prompt")
wide = res.pivot_table(index=["PROMPT_ID", "PROMPT"], columns="RUN_ID",
                       values=["JUDGE_SCORE", "OUTPUT_TOKENS", "LATENCY_MS"]).reset_index()
wide.columns = [" ".join(str(p) for p in c if p).replace(b_id, "base").replace(c_id, "cand")
                for c in wide.columns]
st.dataframe(wide, hide_index=True, use_container_width=True)

with st.expander("Response side by side"):
    pid = st.selectbox("Prompt", sorted(res["PROMPT_ID"].unique()))
    s1, s2 = st.columns(2)
    for col, rid, name in ((s1, b_id, "Baseline"), (s2, c_id, "Candidate")):
        row = res[(res.RUN_ID == rid) & (res.PROMPT_ID == pid)]
        if not row.empty:
            col.markdown(f"**{name}** - score {row.iloc[0]['JUDGE_SCORE']}, trace `{row.iloc[0]['TRACE_ID'][:12]}...`")
            col.write(row.iloc[0]["RESPONSE"])

# ---------------------------------------------------------------------------
# Promote
# ---------------------------------------------------------------------------
st.subheader("Promote")
quality_ok = not pd.isna(c["Quality (judge)"]) and (
    pd.isna(b["Quality (judge)"]) or c["Quality (judge)"] >= b["Quality (judge)"] - 0.05)
if b_cost and c_cost:
    cheaper = c_cost < b_cost
else:  # no fitted rate for a model: compare output tokens instead
    cheaper = not pd.isna(c["Avg output tokens"]) and not pd.isna(b["Avg output tokens"]) \
        and c["Avg output tokens"] < b["Avg output tokens"]

if quality_ok and cheaper:
    st.success("Candidate holds quality within 0.05 of baseline at lower cost: promote it.")
elif quality_ok:
    st.info("Candidate holds quality but is not cheaper. Promote only if latency matters more.")
else:
    st.warning("Candidate loses quality. Keep the baseline, or iterate on the candidate.")

model = cfg.loc[c_id, "MODEL"]
st.markdown("**1. Application config** - ship the candidate settings in the client:")
st.code(
    f'llm = ChatOpenAI(model="{model}", base_url=GATEWAY_URL, api_key=PAT,\n'
    f'                 max_tokens={cfg.loc[c_id, "MAX_TOKENS"]})\n'
    f'SYSTEM_PROMPT = """{cfg.loc[c_id, "SYSTEM_PROMPT"]}"""',
    language="python",
)
st.markdown("**2. Gateway guardrail** - pin the allowlist to the promoted model "
            "(run as ACCOUNTADMIN; the spec is replaced as a whole):")
# Keep the baseline model allowed during rollout only if it differs from the promoted one
allow = f"  - name: '{model}'"
base_model = cfg.loc[b_id, "MODEL"]
if base_model != model:
    allow += f"\n  - name: '{base_model}'   # baseline: remove after rollout"
st.code(
    f"""ALTER AI GATEWAY SNOWFLAKE FROM SPECIFICATION $$
schema_version: 1
models:
{allow}
logging:
  enabled: true
  enable_client_telemetry: true
  capture_payload:
    request_response: true
$$;""",
    language="sql",
)
st.markdown("**3. Cost guardrail** - cap per-user gateway spend:")
st.code(
    """CREATE SNOWFLAKE.CORE.QUOTA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_USER_QUOTA();
CALL CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_USER_QUOTA!ADD_SHARED_RESOURCE('AI GATEWAY');
CALL CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_USER_QUOTA!SET_PER_USER_LIMIT(5, 'DAILY');
CALL CORTEX_GATEWAY_RETAIL_LAB.PUBLIC.GATEWAY_USER_QUOTA!SET_BLOCK_ENFORCEMENT_ENABLED(TRUE, FALSE);""",
    language="sql",
)
st.caption("Then return to Overview: new traffic on the promoted config closes the loop.")
