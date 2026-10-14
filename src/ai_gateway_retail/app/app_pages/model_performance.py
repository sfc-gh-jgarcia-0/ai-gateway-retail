import streamlit as st
import pandas as pd
import altair as alt

st.header("Model performance")

df: pd.DataFrame = st.session_state["df"]
usage_df: pd.DataFrame = st.session_state["usage_df"]

if df.empty:
    st.info("No trace data for the selected filters.")
    st.stop()

# ---------------------------------------------------------------------------
# Model comparison table
# ---------------------------------------------------------------------------
st.subheader("Model comparison")

ok = df[df["STATUS_CODE"] == "STATUS_CODE_OK"].copy()

if ok.empty:
    st.warning("No successful spans to analyze.")
    st.stop()

model_stats = (
    ok.groupby("REQUEST_MODEL")
    .agg(
        SPANS=("SPAN_ID", "count"),
        AVG_LATENCY=("DURATION_MS", "mean"),
        P50_LATENCY=("DURATION_MS", "median"),
        P95_LATENCY=("DURATION_MS", lambda x: x.quantile(0.95)),
        AVG_OUTPUT_TOKENS=("OUTPUT_TOKENS", "mean"),
    )
    .reset_index()
)

# Tokens per second
model_stats["TOKENS_PER_SEC"] = (
    model_stats["AVG_OUTPUT_TOKENS"] / (model_stats["AVG_LATENCY"] / 1000)
).round(1)

# Error rate from full df
total_by_model = df.groupby("REQUEST_MODEL").size().reset_index(name="TOTAL")
errors_by_model = (
    df[df["STATUS_CODE"] == "STATUS_CODE_ERROR"]
    .groupby("REQUEST_MODEL")
    .size()
    .reset_index(name="ERRORS")
)
err_merged = total_by_model.merge(errors_by_model, on="REQUEST_MODEL", how="left")
err_merged["ERRORS"] = err_merged["ERRORS"].fillna(0)
err_merged["ERROR_RATE_%"] = (err_merged["ERRORS"] / err_merged["TOTAL"] * 100).round(1)

model_stats = model_stats.merge(
    err_merged[["REQUEST_MODEL", "ERROR_RATE_%"]], on="REQUEST_MODEL", how="left"
)

st.dataframe(
    model_stats,
    column_config={
        "AVG_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
        "P50_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
        "P95_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
        "AVG_OUTPUT_TOKENS": st.column_config.NumberColumn(format="%.0f"),
        "TOKENS_PER_SEC": st.column_config.NumberColumn(format="%.1f tok/s"),
        "ERROR_RATE_%": st.column_config.NumberColumn(format="%.1f%%"),
    },
    hide_index=True,
)

# ---------------------------------------------------------------------------
# Latency & throughput charts
# ---------------------------------------------------------------------------
st.subheader("Latency and throughput")

col_lat, col_thr = st.columns(2)

with col_lat:
    st.caption("Latency by model (p50 vs p95)")
    lat_data = model_stats.melt(
        id_vars="REQUEST_MODEL",
        value_vars=["P50_LATENCY", "P95_LATENCY"],
        var_name="PERCENTILE",
        value_name="MS",
    )
    lat_data["PERCENTILE"] = lat_data["PERCENTILE"].map(
        {"P50_LATENCY": "p50", "P95_LATENCY": "p95"}
    )
    chart_lat = (
        alt.Chart(lat_data)
        .mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("REQUEST_MODEL:N", title="Model"),
            y=alt.Y("MS:Q", title="Latency (ms)"),
            color=alt.Color("PERCENTILE:N", scale=alt.Scale(range=["#4A90D9", "#E74C3C"])),
            xOffset="PERCENTILE:N",
        )
    )
    st.altair_chart(chart_lat)

with col_thr:
    st.caption("Output throughput (tokens/sec)")
    chart_thr = (
        alt.Chart(model_stats)
        .mark_bar(color="#2ECC71", cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("REQUEST_MODEL:N", title="Model", sort="-y"),
            y=alt.Y("TOKENS_PER_SEC:Q", title="Tokens/sec"),
        )
    )
    st.altair_chart(chart_thr)

# ---------------------------------------------------------------------------
# User x Model matrix
# ---------------------------------------------------------------------------
st.subheader("User x Model matrix")

pivot = pd.crosstab(df["USER_NAME"], df["REQUEST_MODEL"])
st.dataframe(pivot)

with st.expander("Full span detail"):
    st.dataframe(
        df[["TRACE_ID", "USER_NAME", "REQUEST_MODEL", "STATUS_CODE", "DURATION_MS", "INPUT_TOKENS", "OUTPUT_TOKENS", "START_TIMESTAMP"]]
        .sort_values("START_TIMESTAMP", ascending=False),
        hide_index=True,
        height=400,
    )

# ---------------------------------------------------------------------------
# Cost per model
# ---------------------------------------------------------------------------
if not usage_df.empty:
    st.subheader("Cost per model")
    cost_model = usage_df.groupby("MODEL")["CREDITS"].sum().reset_index()
    chart_cost = (
        alt.Chart(cost_model)
        .mark_bar(color="#F39C12", cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("MODEL:N", title="Model", sort="-y"),
            y=alt.Y("CREDITS:Q", title="Credits"),
        )
    )
    st.altair_chart(chart_cost)
