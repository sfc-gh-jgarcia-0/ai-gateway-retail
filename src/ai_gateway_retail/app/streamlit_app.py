import os
import streamlit as st
import pandas as pd

from optimize_config import fit_credit_rates

st.set_page_config(
    page_title="AI Gateway Trace Analyzer",
    page_icon=":material/monitoring:",
    layout="wide",
)

# ---------------------------------------------------------------------------
# Connection
# ---------------------------------------------------------------------------
conn = st.connection("snowflake")
conn.session().sql("USE SCHEMA CORTEX_GATEWAY_RETAIL_LAB.PUBLIC").collect()


# ---------------------------------------------------------------------------
# Data loading (cached)
# ---------------------------------------------------------------------------
@st.cache_data(ttl="5m")
def load_traces(lookback_days: int) -> pd.DataFrame:
    df = conn.query(
        f"""
        SELECT
            TRACE:"trace_id"::STRING           AS TRACE_ID,
            TRACE:"span_id"::STRING            AS SPAN_ID,
            RECORD:"name"::STRING              AS SPAN_NAME,
            RECORD_ATTRIBUTES:"gen_ai.operation.name"::STRING   AS OPERATION,
            RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING    AS REQUEST_MODEL,
            RECORD_ATTRIBUTES:"gen_ai.response.model"::STRING   AS RESPONSE_MODEL,
            RESOURCE_ATTRIBUTES:"user"::STRING                  AS USER_NAME,
            RECORD:"status":"code"::STRING                      AS STATUS_CODE,
            TRY_TO_NUMBER(RECORD_ATTRIBUTES:"http.status_code"::STRING) AS HTTP_STATUS,
            START_TIMESTAMP,
            TIMESTAMP                                           AS END_TIMESTAMP,
            DATEDIFF('millisecond', START_TIMESTAMP, TIMESTAMP) AS DURATION_MS,
            TRY_TO_NUMBER(RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::STRING)  AS INPUT_TOKENS,
            TRY_TO_NUMBER(RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::STRING) AS OUTPUT_TOKENS,
            RECORD_ATTRIBUTES:"gen_ai.conversation.id"::STRING  AS CONVERSATION_ID,
            SCOPE:"name"::STRING                                AS SCOPE_NAME
        FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
        WHERE TIMESTAMP > DATEADD('day', -{lookback_days}, CURRENT_TIMESTAMP())
        ORDER BY START_TIMESTAMP DESC
        """,
        ttl="5m",
    )
    for col in ("DURATION_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "HTTP_STATUS"):
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


@st.cache_data(ttl="5m")
def load_usage(lookback_days: int) -> pd.DataFrame:
    df = conn.query(
        f"""
        SELECT
            g.START_TIME,
            g.GATEWAY_NAME,
            g.CREDITS,
            f.key                          AS MODEL,
            f.value:"input_tokens"::INT    AS INPUT_TOKENS,
            f.value:"output_tokens"::INT   AS OUTPUT_TOKENS
        FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY g,
             LATERAL FLATTEN(input => g.OPERATION_DETAILS) f
        WHERE g.START_TIME > DATEADD('day', -{lookback_days}, CURRENT_TIMESTAMP())
        ORDER BY g.START_TIME DESC
        """,
        ttl="5m",
    )
    for col in ("CREDITS", "INPUT_TOKENS", "OUTPUT_TOKENS"):
        if col in df.columns:
            df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


# ---------------------------------------------------------------------------
# Sidebar
# ---------------------------------------------------------------------------
with st.sidebar:
    st.title(":material/monitoring: Trace Analyzer")

    topic = st.text_input("Topic area", placeholder="e.g. retail, cost")
    lookback = st.selectbox("Lookback window", [1, 7, 14, 30], index=1, format_func=lambda d: f"{d} day{'s' if d != 1 else ''}")

    raw_df = load_traces(lookback)
    usage_df = load_usage(lookback)

    # Apply topic filter
    if topic:
        mask = (
            raw_df["USER_NAME"].str.contains(topic, case=False, na=False)
            | raw_df["SPAN_NAME"].str.contains(topic, case=False, na=False)
        )
        if mask.any():
            filtered = raw_df[mask]
        else:
            st.info(f'No matches for "{topic}" — showing all data.')
            filtered = raw_df
    else:
        filtered = raw_df

    # User filter
    all_users = sorted(filtered["USER_NAME"].dropna().unique())
    users = st.multiselect("Users", all_users, default=all_users)
    if users:
        filtered = filtered[filtered["USER_NAME"].isin(users)]

    # Model filter
    all_models = sorted(filtered["REQUEST_MODEL"].dropna().unique())
    models = st.multiselect("Models", all_models, default=all_models)
    if models:
        filtered = filtered[filtered["REQUEST_MODEL"].isin(models)]

    if st.button(":material/refresh: Refresh", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

    st.caption(f"{len(filtered):,} spans")

# Store in session state for pages
st.session_state["df"] = filtered
st.session_state["raw_df"] = raw_df
st.session_state["usage_df"] = usage_df
# Credits per token by model, fitted from billed usage (used for experiment cost estimates)
st.session_state["credit_rates"] = fit_credit_rates(usage_df)
st.session_state["conn"] = conn
st.session_state["topic"] = topic

# ---------------------------------------------------------------------------
# Navigation
# ---------------------------------------------------------------------------
pages = {
    "Observe": [
        st.Page("app_pages/overview.py", title="Overview", icon=":material/dashboard:"),
        st.Page("app_pages/model_performance.py", title="Model performance", icon=":material/speed:"),
        st.Page("app_pages/user_deep_dive.py", title="User deep dive", icon=":material/person_search:"),
        st.Page("app_pages/trace_explorer.py", title="Trace explorer", icon=":material/account_tree:"),
    ],
    "Optimize": [
        st.Page("app_pages/advisor.py", title="Advisor", icon=":material/lightbulb:"),
        st.Page("app_pages/experiments.py", title="Experiments", icon=":material/science:"),
        st.Page("app_pages/compare.py", title="Before / after", icon=":material/compare_arrows:"),
    ],
    "Govern": [
        st.Page("app_pages/cost_governance.py", title="Cost governance", icon=":material/savings:"),
    ],
}
# Gateway calls are traced only with a PAT, which works from a laptop but not from
# the SiS container, so the Live prompt page appears only in a local `streamlit run`.
if not os.path.exists("/snowflake/session/token"):
    pages = {"Act": [st.Page("app_pages/live.py", title="Live prompt", icon=":material/send:")],
             **pages}
pg = st.navigation(pages)
pg.run()
