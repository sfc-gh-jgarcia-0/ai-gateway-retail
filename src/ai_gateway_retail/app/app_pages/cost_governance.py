import json
from datetime import date
from pathlib import Path

import pandas as pd
import streamlit as st

st.header("Cost governance")
st.caption(
    "Attribute gateway spend to users and cost centers, cap it with budgets and per-user "
    "quotas, and see who the platform has blocked. Quota data refreshes within minutes; "
    "ACCOUNT_USAGE views can lag up to a few hours."
)

conn = st.session_state["conn"]
session = conn.session()
SCHEMA = "CORTEX_GATEWAY_RETAIL_LAB.PUBLIC"
BUDGET = f"{SCHEMA}.GATEWAY_BUDGET"
DENIAL_FILE = Path(__file__).resolve().parent.parent / "output" / "last_quota_denial.json"
month_start = date.today().replace(day=1).isoformat()
today = date.today().isoformat()


def sql_df(query: str, params=None) -> pd.DataFrame | None:
    """Run a query or quota method; return None (and say why) if it isn't available."""
    try:
        rows = session.sql(query, params=params).collect()
        return pd.DataFrame([{k.strip('"').upper(): v for k, v in r.as_dict().items()} for r in rows])
    except Exception as e:  # missing privilege, object not created yet, etc.
        st.caption(f":gray[Unavailable: `{query.split('(')[0][:60]}` - {str(e).splitlines()[0][:140]}]")
        return None


@st.cache_data(ttl="2m", show_spinner=False)
def gateway_spend(since: str) -> pd.DataFrame:
    df = session.sql(
        """SELECT u.NAME AS USER_NAME, DATE(g.START_TIME) AS DAY, SUM(g.CREDITS) AS CREDITS
           FROM SNOWFLAKE.ACCOUNT_USAGE.AI_GATEWAY_USAGE_HISTORY g
           LEFT JOIN SNOWFLAKE.ACCOUNT_USAGE.USERS u ON u.USER_ID = g.USER_ID
           WHERE g.START_TIME >= ? GROUP BY 1, 2""", params=[since]).to_pandas()
    df["CREDITS"] = pd.to_numeric(df["CREDITS"], errors="coerce")
    return df


@st.cache_data(ttl="2m", show_spinner=False)
def cost_centers(users: tuple) -> pd.DataFrame:
    # SYSTEM$GET_TAG reads the live tag; TAG_REFERENCES can lag by hours.
    def tag(u):
        try:
            return session.sql("SELECT SYSTEM$GET_TAG(?, ?, 'USER')",
                               params=[f"{SCHEMA}.COST_CENTER", u]).collect()[0][0]
        except Exception:  # e.g. system-created app users the role can't describe
            return None
    return pd.DataFrame([(u, tag(u)) for u in users if u], columns=["USER_NAME", "COST_CENTER"])


quotas = sql_df(f"SHOW SNOWFLAKE.CORE.QUOTA IN SCHEMA {SCHEMA}")
quota_names = quotas["NAME"].tolist() if quotas is not None and "NAME" in quotas else []
default_q = quota_names.index("GATEWAY_RETAIL_QUOTA") if "GATEWAY_RETAIL_QUOTA" in quota_names else 0
quota = st.selectbox("Per-user quota", quota_names, index=default_q) if quota_names else None
qfq = f"{SCHEMA}.{quota}" if quota else None

# ---------------------------------------------------------------------------
# KPIs
# ---------------------------------------------------------------------------
spend = gateway_spend(month_start)
mtd = spend["CREDITS"].sum()
budget_limit = sql_df(f"CALL {BUDGET}!GET_SPENDING_LIMIT()")
cfg = sql_df(f"CALL {qfq}!GET_CONFIG()") if qfq else None
users_in = sql_df(f"CALL {qfq}!GET_USERS()") if qfq else None
blocks = sql_df(f"CALL {qfq}!GET_ACTIVE_BLOCKS_V2()") if qfq else None

limits = {}
if cfg is not None and not cfg.empty:
    for cycle, col in (("Monthly", "PER_USER_LIMIT"), ("Weekly", "PER_USER_LIMIT_WEEKLY"),
                       ("Daily", "PER_USER_LIMIT_DAILY")):
        v = pd.to_numeric(cfg.iloc[0].get(col), errors="coerce")
        if pd.notna(v):
            limits[cycle] = float(v)

k = st.columns(4)
k[0].metric("Gateway credits this month", f"{mtd:,.3f}")
if budget_limit is not None and not budget_limit.empty:
    k[1].metric("Budget limit (GATEWAY_BUDGET)", f"{float(budget_limit.iloc[0, 0]):,.0f}")
k[2].metric("Users in quota", len(users_in) if users_in is not None else "-")
k[3].metric("Users blocked now", len(blocks) if blocks is not None else "-",
            delta="enforced" if blocks is not None and len(blocks) else None, delta_color="inverse")
if limits:
    st.caption("Per-user limits: " + ", ".join(f"{c} {v:g} credits" for c, v in limits.items())
               + f" - block enforcement {'on' if str(cfg.iloc[0].get('BLOCK_ENFORCEMENT_ENABLED')).upper() == 'TRUE' else 'off'}")

# ---------------------------------------------------------------------------
# Attribute: spend by cost center
# ---------------------------------------------------------------------------
st.subheader("Attribute: spend by cost center")
by_user = spend.groupby("USER_NAME", dropna=False)["CREDITS"].sum().reset_index()
by_user = by_user.merge(cost_centers(tuple(by_user["USER_NAME"].dropna())), on="USER_NAME", how="left")
by_user["COST_CENTER"] = by_user["COST_CENTER"].fillna("(untagged)")
c1, c2 = st.columns([2, 3])
c1.bar_chart(by_user.groupby("COST_CENTER")["CREDITS"].sum(), horizontal=True)
c2.dataframe(by_user.sort_values("CREDITS", ascending=False), hide_index=True, use_container_width=True,
             column_config={"CREDITS": st.column_config.NumberColumn(format="%.4f")})
st.caption("Users are tagged with COST_CENTER; the same tag drives budget scope and this chargeback view.")

# ---------------------------------------------------------------------------
# Cap: per-user spend against the quota
# ---------------------------------------------------------------------------
st.subheader(f"Cap: per-user spend in {quota or 'quota'}")
if qfq:
    detail = sql_df(f"CALL {qfq}!GET_SPENDING_DETAILS_BY_USERS(?, ?)", params=[month_start, today])
    if detail is not None and not detail.empty:
        detail["CREDITS_SPEND"] = pd.to_numeric(detail["CREDITS_SPEND"], errors="coerce")
        detail["DAY"] = pd.to_datetime(detail["USAGE_TIMESTAMP"].astype(str).str[:10])
        per = detail.groupby("USER_NAME").agg(
            MONTH=("CREDITS_SPEND", "sum"),
            TODAY=("CREDITS_SPEND", lambda s: s[detail.loc[s.index, "DAY"] == pd.Timestamp(today)].sum()),
        ).reset_index()
        if "Daily" in limits:
            per["DAILY_USED_PCT"] = (100 * per["TODAY"] / limits["Daily"]).round(1)
        if "Monthly" in limits:
            per["MONTHLY_USED_PCT"] = (100 * per["MONTH"] / limits["Monthly"]).round(1)
        st.dataframe(per.sort_values("MONTH", ascending=False), hide_index=True, use_container_width=True,
                     column_config={c: st.column_config.ProgressColumn(c, min_value=0, max_value=100, format="%.0f%%")
                                    for c in ("DAILY_USED_PCT", "MONTHLY_USED_PCT") if c in per})
    elif detail is not None:
        st.info("No finalized spend for users in this quota yet this month.")

# ---------------------------------------------------------------------------
# Enforce: blocks
# ---------------------------------------------------------------------------
st.subheader("Enforce: blocked users")
if blocks is not None and not blocks.empty:
    st.error(f"{len(blocks)} user(s) blocked by {quota}: new AI requests are denied until the cycle "
             "resets or the limit is raised.")
    st.dataframe(blocks, hide_index=True, use_container_width=True)
elif blocks is not None:
    st.success(f"No users currently blocked by {quota}.")

if DENIAL_FILE.exists():
    d = json.loads(DENIAL_FILE.read_text())
    with st.container(border=True):
        st.markdown(f"**Last gateway denial** - `{d['user']}` on `{d['model']}`, HTTP {d['status']}, "
                    f"captured {d['captured_at']}")
        st.code(d["body"], language="json")

history = sql_df(
    "SELECT ACTION_AT, QUOTA_NAME, USER_NAME, CYCLE, ACTION, PER_USER_LIMIT, CREDITS, BLOCKED_UNTIL "
    "FROM SNOWFLAKE.ACCOUNT_USAGE.QUOTA_ACCESS_BLOCK_HISTORY "
    "WHERE ACTION_AT > DATEADD('day', -30, CURRENT_TIMESTAMP()) ORDER BY ACTION_AT DESC LIMIT 50")
if history is not None:
    st.markdown("**Block history (30 days, all quotas)**")
    if history.empty:
        st.caption("No blocks recorded yet (this view can lag behind active blocks).")
    else:
        st.dataframe(history, hide_index=True, use_container_width=True)

with st.expander("Raise the limit (clears blocks in about 5-10 minutes)"):
    st.code(f"CALL {qfq or SCHEMA + '.<quota>'}!SET_PER_USER_LIMIT(<credits>, 'DAILY');", language="sql")
    st.caption("One limit applies to every user in a quota. For a different tier, tag the user into "
               "another quota (INTERSECTION on a QUOTA_TIER tag).")
