"""Send one live prompt through the Cortex AI Gateway with a LangChain agent + MCP tools.

The agent's LLM is ChatOpenAI pointed at the gateway; its tools come from the
Snowflake MCP server RETAIL_MCP, which exposes one governed tool: the Cortex Agent
RETAIL_ANALYTICS_AGENT (two Cortex Analyst tools over the customer + churn and
executive KPI semantic views; Analyst runs its own SQL).
Every gateway call the agent makes in this turn carries the same W3C traceparent,
so the whole turn is one trace_id in AGENT_TRACE_TABLE, in Snowsight
(AI & ML > Cortex AI Gateway), and on the Trace Analyzer app's Trace explorer page.

Usage:
    export SNOWFLAKE_ACCOUNT=<org-account>          # e.g. myorg-myaccount
    export SNOWFLAKE_PAT=<pat>                      # or SNOWFLAKE_PAT_FILE=<path>
    python live_agent.py "Which customer segments have the highest churn risk?"
    python live_agent.py --model openai-gpt-5.4-mini --max-tokens 800 "..."
"""

from __future__ import annotations

import argparse
import asyncio
import os
import time
import uuid
from pathlib import Path

from langchain_mcp_adapters.client import MultiServerMCPClient
from langchain_openai import ChatOpenAI
from langgraph.prebuilt import create_react_agent

DATABASE, SCHEMA, MCP_SERVER = "CORTEX_GATEWAY_RETAIL_LAB", "PUBLIC", "RETAIL_MCP"

SYSTEM_PROMPT = """You are a retail analytics assistant for an athletic apparel brand. For any
question about sales, products, stores, customers, campaigns or churn risk, call
retail_analytics_agent with the user's question; it queries governed Snowflake data and returns
the answer.

Always cite specific numbers when available. Round currency to 2 decimal places.
The data covers October 2024 through September 2025."""


def load_pat() -> str:
    pat = os.getenv("SNOWFLAKE_PAT")
    if not pat:
        path = Path(os.path.expanduser(os.getenv("SNOWFLAKE_PAT_FILE", "~/.snowflake/ai_gateway_retail.pat")))
        if path.exists():
            pat = path.read_text().strip()
    if not pat:
        raise SystemExit("Set SNOWFLAKE_PAT (or SNOWFLAKE_PAT_FILE) to a programmatic access token.")
    return pat


def account_host() -> str:
    account = os.getenv("SNOWFLAKE_ACCOUNT")
    if not account:
        raise SystemExit("Set SNOWFLAKE_ACCOUNT, e.g. myorg-myaccount.")
    # Hostnames need hyphens, not underscores, for a valid TLS certificate
    return f"{account}.snowflakecomputing.com".replace("_", "-").lower()


async def run(question: str, model: str, max_tokens: int, conversation_id: str | None) -> str:
    host, pat = account_host(), load_pat()
    trace_id = uuid.uuid4().hex
    headers = {"traceparent": f"00-{trace_id}-{uuid.uuid4().hex[:16]}-01"}
    if conversation_id:
        headers["x-snowflake-ai-gateway-conversation-id"] = conversation_id

    llm = ChatOpenAI(
        model=model,
        base_url=f"https://{host}/api/v2/aigateways/SNOWFLAKE/v1",
        api_key=pat,
        max_completion_tokens=max_tokens,  # GPT-5 family rejects max_tokens
        default_headers=headers,
    )
    mcp = MultiServerMCPClient({
        "snowflake": {
            "transport": "http",
            "url": f"https://{host}/api/v2/databases/{DATABASE}/schemas/{SCHEMA}/mcp-servers/{MCP_SERVER}",
            "headers": {"Authorization": f"Bearer {pat}"},
        }
    })
    tools = await mcp.get_tools()
    agent = create_react_agent(model=llm, tools=tools, prompt=SYSTEM_PROMPT)

    print(f"trace_id : {trace_id}")
    print(f"model    : {model}   tools: {[t.name for t in tools]}\n")
    t0 = time.perf_counter()
    try:
        result = await agent.ainvoke({"messages": [{"role": "user", "content": question}]})
    except Exception as e:  # e.g. unknown model -> HTTP 400; the gateway still records an error span
        print(f"Gateway error: {str(e)[:300]}")
        print(f"The error span is still recorded: search trace_id {trace_id}")
        return trace_id
    elapsed = time.perf_counter() - t0

    llm_calls = 0
    for msg in result["messages"]:
        if msg.type == "ai":
            llm_calls += 1
            for tc in getattr(msg, "tool_calls", None) or []:
                print(f"  -> tool {tc['name']}({str(tc['args'])[:120]})")
    print("\n" + result["messages"][-1].content)
    print(f"\n{llm_calls} gateway calls in {elapsed:.1f}s")
    print("Find this turn in Snowsight: AI & ML > Cortex AI Gateway > Traces, search the trace_id,")
    print("or paste it into the Trace explorer page of the Trace Analyzer app.")
    return trace_id


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("question", nargs="?", default="Which customer segments have the highest churn risk, and how many customers in each are predicted to churn?")
    ap.add_argument("--model", default="openai-gpt-5.4")
    ap.add_argument("--max-tokens", type=int, default=4096)
    ap.add_argument("--conversation-id", default=None)
    args = ap.parse_args()
    asyncio.run(run(args.question, args.model, args.max_tokens, args.conversation_id))


if __name__ == "__main__":
    main()
