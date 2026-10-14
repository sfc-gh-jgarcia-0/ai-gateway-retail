"""Shared trace queries used by the Live, Trace explorer and Experiments pages."""

from __future__ import annotations

import pandas as pd

TRACE_DETAIL_SQL = """
SELECT
    TRACE:"span_id"::STRING                                        AS SPAN_ID,
    RECORD:"parent_span_id"::STRING                                AS PARENT_SPAN_ID,
    RECORD:"name"::STRING                                          AS SPAN_NAME,
    SCOPE:"name"::STRING                                           AS SCOPE_NAME,
    START_TIMESTAMP                                                AS SPAN_START,
    TIMESTAMP                                                      AS SPAN_END,
    DATEDIFF('millisecond', START_TIMESTAMP, TIMESTAMP)            AS DURATION_MS,
    DATEDIFF('millisecond', MIN(START_TIMESTAMP) OVER (), START_TIMESTAMP) AS OFFSET_MS,
    RECORD:"status":"code"::STRING                                 AS STATUS_CODE,
    TRY_TO_NUMBER(RECORD_ATTRIBUTES:"http.status_code"::STRING)    AS HTTP_STATUS,
    RECORD_ATTRIBUTES:"gen_ai.request.model"::STRING               AS REQUEST_MODEL,
    TRY_TO_NUMBER(RECORD_ATTRIBUTES:"gen_ai.request.max_tokens"::STRING)  AS MAX_TOKENS,
    TRY_TO_NUMBER(RECORD_ATTRIBUTES:"gen_ai.usage.input_tokens"::STRING)  AS INPUT_TOKENS,
    TRY_TO_NUMBER(RECORD_ATTRIBUTES:"gen_ai.usage.output_tokens"::STRING) AS OUTPUT_TOKENS,
    RESOURCE_ATTRIBUTES:"user"::STRING                             AS USER_NAME,
    RECORD_ATTRIBUTES:"gen_ai.system_instructions"                 AS SYSTEM_INSTRUCTIONS,
    RECORD_ATTRIBUTES:"gen_ai.input.messages"                      AS INPUT_MESSAGES,
    RECORD_ATTRIBUTES:"gen_ai.output.messages"                     AS OUTPUT_MESSAGES
FROM TABLE(AGENT_TRACE_TABLE('SNOWFLAKE'))
WHERE TIMESTAMP > DATEADD('day', -{days}, CURRENT_TIMESTAMP())
  AND TRACE:"trace_id"::STRING = '{trace_id}'
ORDER BY SPAN_START
"""


def load_trace(conn, trace_id: str, days: int = 7) -> pd.DataFrame:
    """All spans for one trace_id (no cache: used for live polling)."""
    safe_id = "".join(c for c in trace_id if c.isalnum())
    df = conn.query(TRACE_DETAIL_SQL.format(trace_id=safe_id, days=int(days)), ttl=0)
    for col in ("DURATION_MS", "OFFSET_MS", "INPUT_TOKENS", "OUTPUT_TOKENS",
                "HTTP_STATUS", "MAX_TOKENS"):
        df[col] = pd.to_numeric(df[col], errors="coerce")
    return df


def span_waterfall(df: pd.DataFrame):
    """Altair Gantt of spans relative to trace start."""
    import altair as alt

    plot = df.assign(
        END_MS=df["OFFSET_MS"] + df["DURATION_MS"],
        LABEL=df["SPAN_NAME"].fillna("span") + " (" + df["SCOPE_NAME"].fillna("") + ")",
    )
    return (
        alt.Chart(plot)
        .mark_bar(cornerRadius=3)
        .encode(
            x=alt.X("OFFSET_MS:Q", title="ms from trace start"),
            x2="END_MS:Q",
            y=alt.Y("LABEL:N", sort=None, title=None),
            color=alt.Color("STATUS_CODE:N", title="Status"),
            tooltip=["SPAN_NAME", "REQUEST_MODEL", "DURATION_MS",
                     "INPUT_TOKENS", "OUTPUT_TOKENS", "HTTP_STATUS"],
        )
        .properties(height=max(80, 36 * len(plot)))
    )
