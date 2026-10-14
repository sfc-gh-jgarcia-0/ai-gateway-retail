import time

import streamlit as st

from gateway_client import chat
from trace_queries import load_trace, span_waterfall

st.header("Live prompt")
st.caption(
    "Send a prompt through the Cortex AI Gateway, then watch its trace land in "
    "AGENT_TRACE_TABLE. Open AI & ML > Cortex AI Gateway in Snowsight and search "
    "the same trace_id to see it there too."
)

conn = st.session_state["conn"]

MODELS = ["openai-gpt-5.4", "openai-gpt-5.4-mini", "openai-gpt-5-mini", "openai-gpt-5-nano",
          "claude-haiku-4-5", "claude-sonnet-4-5", "kimi-k3", "deepseek-v4-flash", "not-a-real-model"]

with st.form("live_prompt"):
    prompt = st.text_area(
        "Prompt",
        "In 3 bullets, how should an athletic apparel brand reduce churn among "
        "High-Value At-Risk customers?",
        height=100,
    )
    c1, c2, c3 = st.columns(3)
    model = c1.selectbox("Model", MODELS, help="'not-a-real-model' produces an error span")
    max_tokens = c2.number_input("max_tokens", 16, 4096, 400, step=50)
    temperature = c3.slider("temperature", 0.0, 1.0, 0.0, 0.1)
    system = st.text_input("System prompt (optional)", "You are a concise retail analytics assistant.")
    submitted = st.form_submit_button(":material/send: Send through gateway", type="primary")

if submitted:
    with st.spinner("Calling gateway..."):
        res = chat(prompt, model, system=system or None,
                   max_tokens=int(max_tokens), temperature=temperature)
    st.session_state["live_last"] = res

res = st.session_state.get("live_last")
if res is None:
    st.stop()

with st.container(border=True):
    m = st.columns(5)
    m[0].metric("HTTP", res.status_code)
    m[1].metric("Client latency", f"{res.latency_ms:,.0f} ms")
    m[2].metric("Input tokens", res.input_tokens if res.input_tokens is not None else "-")
    m[3].metric("Output tokens", res.output_tokens if res.output_tokens is not None else "-")
    m[4].metric("Auth", res.auth_mode)
    st.code(res.trace_id, language=None)
    if res.ok:
        st.markdown(res.content)
    else:
        st.error(res.content)

st.subheader("Gateway trace")
placeholder = st.empty()
spans = load_trace(conn, res.trace_id, days=1)
if spans.empty:
    with st.spinner("Waiting for the trace to land (usually under a minute)..."):
        for _ in range(12):
            time.sleep(5)
            spans = load_trace(conn, res.trace_id, days=1)
            if not spans.empty:
                break

if spans.empty:
    placeholder.info("Trace not visible yet. Click refresh in a moment.")
    if st.button(":material/refresh: Check again"):
        st.rerun()
else:
    st.altair_chart(span_waterfall(spans), use_container_width=True)
    st.dataframe(
        spans[["SPAN_NAME", "SCOPE_NAME", "REQUEST_MODEL", "STATUS_CODE", "HTTP_STATUS",
               "DURATION_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "MAX_TOKENS", "USER_NAME"]],
        hide_index=True, use_container_width=True,
    )
    st.session_state["explore_trace_id"] = res.trace_id
    st.page_link("app_pages/trace_explorer.py", label="Open in Trace explorer",
                 icon=":material/account_tree:")
