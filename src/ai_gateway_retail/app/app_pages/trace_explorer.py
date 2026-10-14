import json

import pandas as pd
import streamlit as st

from trace_queries import load_trace, span_waterfall

st.header("Trace explorer")

conn = st.session_state["conn"]
df: pd.DataFrame = st.session_state["df"]

recent = (
    df.groupby("TRACE_ID")
    .agg(STARTED=("START_TIMESTAMP", "min"), SPANS=("SPAN_ID", "count"),
         MODEL=("REQUEST_MODEL", "first"), USER=("USER_NAME", "first"),
         ERRORS=("STATUS_CODE", lambda s: (s == "STATUS_CODE_ERROR").sum()))
    .reset_index()
    .sort_values("STARTED", ascending=False)
)

default_id = st.session_state.get("explore_trace_id", "")
options = [default_id] if default_id else []
options += [t for t in recent["TRACE_ID"].head(200) if t != default_id]
if not options:
    st.info("No traces in the selected window yet. Run lab/live_agent.py to send one.")
    st.stop()

trace_id = st.selectbox(
    "Trace", options,
    format_func=lambda t: (
        f"{t[:12]}...  " + (
            " | ".join(str(v) for v in recent.loc[recent.TRACE_ID == t,
                       ["MODEL", "SPANS", "USER"]].iloc[0])
            if (recent.TRACE_ID == t).any() else "(live)"
        )
    ),
)

spans = load_trace(conn, trace_id, days=30)
if spans.empty:
    st.warning("No spans found for this trace_id yet.")
    st.stop()

with st.container(border=True):
    k = st.columns(4)
    k[0].metric("Spans", len(spans))
    k[1].metric("Wall time", f"{(spans['OFFSET_MS'] + spans['DURATION_MS']).max():,.0f} ms")
    k[2].metric("Tokens", f"{spans['INPUT_TOKENS'].sum() + spans['OUTPUT_TOKENS'].sum():,.0f}")
    k[3].metric("Errors", int((spans["STATUS_CODE"] == "STATUS_CODE_ERROR").sum()))

st.altair_chart(span_waterfall(spans), use_container_width=True)


def _parse(v):
    if v is None or (isinstance(v, float) and pd.isna(v)):
        return None
    if isinstance(v, str):
        try:
            return json.loads(v)
        except ValueError:
            return v
    return v


st.subheader("Span payloads")
if spans["INPUT_MESSAGES"].isna().all():
    st.info(
        "No prompt/response content on these spans. Payload capture records content "
        "only when `logging.capture_payload.request_response: true` is in the gateway spec."
    )
for _, row in spans.iterrows():
    label = f"{row['SPAN_NAME']}  -  {row['DURATION_MS']:,.0f} ms  -  {row['STATUS_CODE']}"
    with st.expander(label):
        c1, c2 = st.columns(2)
        c1.markdown("**Input**")
        sys_i = _parse(row["SYSTEM_INSTRUCTIONS"])
        if sys_i:
            c1.json(sys_i, expanded=False)
        c1.json(_parse(row["INPUT_MESSAGES"]) or {}, expanded=True)
        c2.markdown("**Output**")
        c2.json(_parse(row["OUTPUT_MESSAGES"]) or {}, expanded=True)
