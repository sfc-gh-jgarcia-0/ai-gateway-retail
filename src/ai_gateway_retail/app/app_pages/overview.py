import streamlit as st
import pandas as pd
import altair as alt

st.header("Overview")

df: pd.DataFrame = st.session_state["df"]
usage_df: pd.DataFrame = st.session_state["usage_df"]

if df.empty:
    st.info("No trace data for the selected filters.")
    st.stop()

# ---------------------------------------------------------------------------
# KPI row
# ---------------------------------------------------------------------------
total = len(df)
errors = (df["STATUS_CODE"] == "STATUS_CODE_ERROR").sum()
error_rate = errors / total * 100 if total else 0
avg_latency = df["DURATION_MS"].mean()
total_tokens = df["INPUT_TOKENS"].sum() + df["OUTPUT_TOKENS"].sum()
model_count = df["REQUEST_MODEL"].nunique()
user_count = df["USER_NAME"].nunique()

with st.container(border=True):
    row = st.columns(6)
    row[0].metric("Total requests", f"{total:,}")
    row[1].metric("Error rate", f"{error_rate:.1f}%")
    row[2].metric("Avg latency", f"{avg_latency:,.0f} ms")
    row[3].metric("Total tokens", f"{total_tokens:,.0f}")
    row[4].metric("Models", model_count)
    row[5].metric("Users", user_count)

# ---------------------------------------------------------------------------
# Cost summary
# ---------------------------------------------------------------------------
if not usage_df.empty:
    total_credits = usage_df["CREDITS"].sum()
    avg_credits = total_credits / len(usage_df) if len(usage_df) else 0
    total_in = usage_df["INPUT_TOKENS"].sum()
    total_out = usage_df["OUTPUT_TOKENS"].sum()

    with st.container(border=True):
        row2 = st.columns(4)
        row2[0].metric("Total credits", f"{total_credits:.4f}")
        row2[1].metric("Avg credits/request", f"{avg_credits:.6f}")
        row2[2].metric("Input tokens (usage)", f"{total_in:,.0f}")
        row2[3].metric("Output tokens (usage)", f"{total_out:,.0f}")

# ---------------------------------------------------------------------------
# Hourly traffic
# ---------------------------------------------------------------------------
st.subheader("Hourly traffic")

hourly = df.copy()
hourly["HOUR"] = pd.to_datetime(hourly["START_TIMESTAMP"]).dt.floor("h")
volume = hourly.groupby("HOUR").size().reset_index(name="REQUESTS")
error_hourly = (
    hourly[hourly["STATUS_CODE"] == "STATUS_CODE_ERROR"]
    .groupby("HOUR")
    .size()
    .reset_index(name="ERRORS")
)

col_vol, col_err = st.columns(2)
with col_vol:
    st.caption("Request volume by hour")
    chart_vol = (
        alt.Chart(volume)
        .mark_bar(color="#4A90D9", cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("HOUR:T", title="Hour"),
            y=alt.Y("REQUESTS:Q", title="Requests"),
        )
    )
    st.altair_chart(chart_vol)

with col_err:
    st.caption("Errors by hour")
    if error_hourly.empty:
        st.info("No errors in this window.")
    else:
        chart_err = (
            alt.Chart(error_hourly)
            .mark_bar(color="#E74C3C", cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
            .encode(
                x=alt.X("HOUR:T", title="Hour"),
                y=alt.Y("ERRORS:Q", title="Errors"),
            )
        )
        st.altair_chart(chart_err)

# ---------------------------------------------------------------------------
# Requests by model / user
# ---------------------------------------------------------------------------
st.subheader("Distribution")

col_m, col_u = st.columns(2)

with col_m:
    st.caption("Requests by model")
    by_model = df.groupby("REQUEST_MODEL").size().reset_index(name="REQUESTS")
    chart_model = (
        alt.Chart(by_model)
        .mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("REQUEST_MODEL:N", title="Model", sort="-y"),
            y=alt.Y("REQUESTS:Q", title="Requests"),
            color=alt.value("#4A90D9"),
        )
    )
    st.altair_chart(chart_model)

with col_u:
    st.caption("Requests by user")
    by_user = df.groupby("USER_NAME").size().reset_index(name="REQUESTS")
    chart_user = (
        alt.Chart(by_user)
        .mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3)
        .encode(
            x=alt.X("USER_NAME:N", title="User", sort="-y"),
            y=alt.Y("REQUESTS:Q", title="Requests"),
            color=alt.value("#29B5E8"),
        )
    )
    st.altair_chart(chart_user)

# ---------------------------------------------------------------------------
# Trace explorer
# ---------------------------------------------------------------------------
with st.expander("Trace explorer — recent traces"):
    trace_summary = (
        df.groupby("TRACE_ID")
        .agg(
            SPANS=("SPAN_ID", "count"),
            TOTAL_INPUT=("INPUT_TOKENS", "sum"),
            TOTAL_OUTPUT=("OUTPUT_TOKENS", "sum"),
            AVG_LATENCY=("DURATION_MS", "mean"),
            FIRST_SPAN=("START_TIMESTAMP", "min"),
        )
        .sort_values("FIRST_SPAN", ascending=False)
        .head(20)
        .reset_index()
    )
    trace_summary["TOTAL_TOKENS"] = trace_summary["TOTAL_INPUT"] + trace_summary["TOTAL_OUTPUT"]
    st.dataframe(
        trace_summary[["TRACE_ID", "SPANS", "TOTAL_TOKENS", "AVG_LATENCY", "FIRST_SPAN"]],
        column_config={
            "AVG_LATENCY": st.column_config.NumberColumn(format="%.0f ms"),
            "TOTAL_TOKENS": st.column_config.NumberColumn(format="%d"),
        },
        hide_index=True,
    )
