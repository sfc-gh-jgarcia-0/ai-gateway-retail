import streamlit as st
import pandas as pd
import altair as alt

st.header("User deep dive")

df: pd.DataFrame = st.session_state["df"]

if df.empty:
    st.info("No trace data for the selected filters.")
    st.stop()

# ---------------------------------------------------------------------------
# User selector
# ---------------------------------------------------------------------------
users = sorted(df["USER_NAME"].dropna().unique())
if not users:
    st.warning("No users found.")
    st.stop()

selected = st.selectbox("Select user", users)
udf = df[df["USER_NAME"] == selected]

if udf.empty:
    st.info(f"No spans for {selected}.")
    st.stop()

# ---------------------------------------------------------------------------
# KPI row
# ---------------------------------------------------------------------------
total = len(udf)
errors = (udf["STATUS_CODE"] == "STATUS_CODE_ERROR").sum()
error_rate = errors / total * 100 if total else 0
avg_lat = udf["DURATION_MS"].mean()
p95_lat = udf["DURATION_MS"].quantile(0.95)
in_tok = udf["INPUT_TOKENS"].sum()
out_tok = udf["OUTPUT_TOKENS"].sum()

with st.container(border=True):
    row = st.columns(6)
    row[0].metric("Requests", f"{total:,}")
    row[1].metric("Error rate", f"{error_rate:.1f}%")
    row[2].metric("Avg latency", f"{avg_lat:,.0f} ms")
    row[3].metric("p95 latency", f"{p95_lat:,.0f} ms")
    row[4].metric("Input tokens", f"{in_tok:,.0f}")
    row[5].metric("Output tokens", f"{out_tok:,.0f}")

# ---------------------------------------------------------------------------
# Models used + latency distribution
# ---------------------------------------------------------------------------
col_tbl, col_chart = st.columns(2)

with col_tbl:
    st.subheader("Models used")
    ok = udf[udf["STATUS_CODE"] == "STATUS_CODE_OK"]
    if not ok.empty:
        models_tbl = (
            ok.groupby("REQUEST_MODEL")
            .agg(
                REQUESTS=("SPAN_ID", "count"),
                AVG_LATENCY=("DURATION_MS", "mean"),
                P50_LATENCY=("DURATION_MS", "median"),
                AVG_OUTPUT_TOKENS=("OUTPUT_TOKENS", "mean"),
            )
            .reset_index()
        )
        st.dataframe(
            models_tbl,
            column_config={
                "AVG_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
                "P50_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
                "AVG_OUTPUT_TOKENS": st.column_config.NumberColumn(format="%.0f"),
            },
            hide_index=True,
        )
    else:
        st.info("No successful spans.")

with col_chart:
    st.subheader("Latency distribution")
    chart_lat = (
        alt.Chart(udf)
        .mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("DURATION_MS:Q", bin=alt.Bin(maxbins=30), title="Latency (ms)"),
            y=alt.Y("count()", title="Spans"),
            color=alt.value("#4A90D9"),
        )
    )
    st.altair_chart(chart_lat)

# ---------------------------------------------------------------------------
# Conversation threading
# ---------------------------------------------------------------------------
st.subheader("Conversation threading")

trace_groups = udf.groupby("TRACE_ID").size().reset_index(name="SPAN_COUNT")
multi = trace_groups[trace_groups["SPAN_COUNT"] > 1]
single = trace_groups[trace_groups["SPAN_COUNT"] == 1]

col_a, col_b = st.columns(2)
col_a.metric("Multi-span traces (agent turns)", len(multi))
col_b.metric("Single-span traces", len(single))

if not multi.empty:
    st.caption("Multi-span traces indicate agent turns with multiple gateway calls")
    top_traces = multi.sort_values("SPAN_COUNT", ascending=False).head(10)
    enriched = top_traces.merge(
        udf.groupby("TRACE_ID").agg(
            TOTAL_TOKENS=("INPUT_TOKENS", "sum"),
            MODELS=("REQUEST_MODEL", "nunique"),
        ),
        on="TRACE_ID",
        how="left",
    )
    enriched["TOTAL_TOKENS"] = enriched["TOTAL_TOKENS"] + udf.groupby("TRACE_ID")["OUTPUT_TOKENS"].sum().reindex(enriched["TRACE_ID"]).values
    st.dataframe(enriched, hide_index=True)

# ---------------------------------------------------------------------------
# Span detail
# ---------------------------------------------------------------------------
st.subheader("Span detail")
st.dataframe(
    udf[["TRACE_ID", "REQUEST_MODEL", "STATUS_CODE", "HTTP_STATUS", "DURATION_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "START_TIMESTAMP"]]
    .sort_values("START_TIMESTAMP", ascending=False),
    hide_index=True,
    height=400,
)
