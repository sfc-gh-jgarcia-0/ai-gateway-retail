# Cortex AI Gateway for Retail Analytics: Govern, Observe and Optimize Every LLM Call

Cortex AI Gateway gives agents and SDKs one governed inference endpoint. It records every request as an OpenTelemetry span in your own account and attributes and caps spend per user. This module runs a LangChain agent through the gateway with a Snowflake MCP server that exposes one governed Cortex Agent tool for an athletic apparel retailer: two Cortex Analyst tools over customer + churn and executive KPI semantic views, with churn scores from an XGBoost model in the Snowflake Model Registry. It then uses a Streamlit Trace Analyzer to close the loop: observe traces, diagnose problems, replay an eval set with a candidate config, compare before and after, and promote the winner.

## Audience

SEs, solution architects, platform engineers, and teams evaluating centralized AI governance and observability.

## Topics Covered

- **Gateway fundamentals**: auto-provisioned `SNOWFLAKE` gateway, Chat Completions and Messages APIs, model allowlist, logging and payload capture
- **LangChain + MCP**: `ChatOpenAI` pointed at the gateway; Snowflake MCP server exposing one governed tool, a Cortex Agent that runs two Cortex Analyst tools (no raw SQL tool)
- **Governed ML**: train an XGBoost churn model, log it to the Model Registry, batch-score in the warehouse with `mv.run()`, attach a Model Monitor; the agent answers from the new scores with no client change
- **Observability**: `AGENT_TRACE_TABLE('SNOWFLAKE')` spans, W3C `traceparent` grouping, conversation ids, Snowsight AI Gateway page
- **Optimization loop**: Advisor findings -> eval-set experiments through the gateway -> LLM-judge scoring -> before/after -> promote
- **Live prompt**: `live-agent` sends one request that is visible in both Snowsight and the Trace Analyzer
- **Admin and cost controls**: spec management, USAGE vs MONITOR, `AI_GATEWAY_USAGE_HISTORY`, chargeback by cost-center tag, shared-resource budgets, per-user quotas with a live block on a demo user

## Contents

| File | Description |
|------|-------------|
| `presentations/ai-gateway.html` | Slide deck (23 slides) |
| `presentations/ai-gateway-speaker-notes.md` | Per-slide talking points and references |
| `demo_script.md` | Live run-of-show for the demo |
| `sql/setup.sql` | Database, warehouse, retail data (13 tables, Oct 2024 - Sep 2025), two semantic views, churn predictions table, Cortex Agent, MCP server, gateway spec + grants, eval/optimization tables, app access |
| `sql/cleanup.sql` | Tear everything down to start fresh |
| `notebooks/ai-gateway-lab.ipynb` | Hands-on notebook: gateway + LangChain + MCP, churn model (registry, batch inference, monitor), observability, cost management |
| `src/ai_gateway_retail/cli/live_agent.py` | CLI: send one live prompt through the agent and print its trace_id |
| `src/ai_gateway_retail/cli/generate_traffic.py` | Generates varied traffic (multi-span, verbose, error) so the dashboards have data |
| `src/ai_gateway_retail/app/` | Trace Analyzer, a Streamlit in Snowflake app (container runtime) |

## Hands-On Lab

### Prerequisites

- AWS commercial region account (Cortex AI Gateway is in preview, AWS-only)
- ACCOUNTADMIN for setup (gateway spec, grants, integration); the lab objects are owned by SYSADMIN
- A programmatic access token (PAT) for the local notebook and scripts. PATs follow your account's network and authentication policies.
  ```sql
  ALTER USER <you> ADD PROGRAMMATIC ACCESS TOKEN ai_gateway_demo ROLE_RESTRICTION = 'SYSADMIN' DAYS_TO_EXPIRY = 7;
  ```
- Python 3.12.15+ managed by [uv](https://docs.astral.sh/uv/)
- Snowflake CLI 3.14+ to deploy the container-runtime app

### Setup

1. Install dependencies:
   ```bash
   uv sync              # core dependencies (app + CLI tools)
   uv sync --extra ml   # include notebook ML dependencies (snowflake-ml-python)
   ```

2. Edit the account host in `sql/setup.sql` section 10 (`GATEWAY_APP_EGRESS`), then run it:
   ```bash
   snow sql -f sql/setup.sql
   ```
   This creates `CORTEX_GATEWAY_RETAIL_LAB` (13 retail tables with deterministic synthetic data, CHURN_PREDICTIONS seeded from the legacy score, semantic views CUSTOMER_INTERACTIONS_SV and CONVERSATIONAL_BI_SV, Cortex Agent RETAIL_ANALYTICS_AGENT, MCP server RETAIL_MCP, the EVAL_PROMPTS view, OPTIMIZATION_RUNS, OPTIMIZATION_RESULTS), the warehouse `GATEWAY_RETAIL_WH`, and the integration `GATEWAY_RETAIL_APP_EAI`. It turns on gateway logging with client telemetry and payload capture, and grants SYSADMIN gateway MONITOR plus the usage, budget and quota roles.

3. Export credentials for the local tools:
   ```bash
   export SNOWFLAKE_ACCOUNT=<org-account> SNOWFLAKE_USER=<you>
   export SNOWFLAKE_PAT=<pat>          # or SNOWFLAKE_PAT_FILE=~/.snowflake/ai_gateway_retail.pat
   ```

4. Generate background traffic: `uv run generate-traffic`

5. Run the notebook locally:
   ```bash
   uv run --extra ml jupyter notebook notebooks/ai-gateway-lab.ipynb
   ```

6. Run the app locally (use this for demos; see [Where to run the app](#where-to-run-the-app)):
   ```bash
   cd src/ai_gateway_retail/app
   SNOWFLAKE_DEFAULT_CONNECTION_NAME=<connection in ~/.snowflake/config.toml> \
   GATEWAY_HOST=<org-account>.snowflakecomputing.com \
   uv run streamlit run streamlit_app.py
   ```
   Gateway calls use `SNOWFLAKE_PAT` or `SNOWFLAKE_PAT_FILE` (default `~/.snowflake/ai_gateway_retail.pat`). Use dashes, not underscores, in the host.

7. Optional: deploy the app to Snowflake for read-only analysis: `cd src/ai_gateway_retail/app && snow streamlit deploy --replace`

8. Before a demo, block the cost demo user so Cost governance has something to enforce:
   ```bash
   uv run generate-traffic --burst   # uses ~/.snowflake/gateway_retail_cost.pat
   ```
   Section 9b of `setup.sql` creates `GATEWAY_RETAIL_COST_DEMO`, a service user tagged `COST_CENTER = 'MERCHANDISING'` and `QUOTA_TIER = 'RETAIL_DEMO'`, and `GATEWAY_RETAIL_QUOTA`: 1 credit per day, block enforcement on, scoped to that tag only. The burst spends about 1.5 credits until the gateway returns HTTP 403 ("exceeded the usage quota limit"), and saves the response to `src/ai_gateway_retail/app/output/last_quota_denial.json`. The block lasts until 00:00 UTC. Keep real users out of this quota: a block covers every AI domain the user touches.

### Lab Sections

1. Install dependencies
2. Configuration (PAT, gateway endpoint)
3. Gateway LLM with `traceparent`
4. MCP tools over streamable HTTP
5. LangChain ReAct agent
6. Queries: executive KPIs (business_kpi_analyst), customers and churn (customer_interactions_analyst), cross-domain (both)
7. Churn model: feature view, XGBoost vs legacy score, Model Registry, `mv.run()` batch inference into CHURN_PREDICTIONS, Model Monitor, then the churn question again through the gateway
8. Observability: recent traces, credit usage, single-trace drill-down, conversation reconstruction
9. Cost management: spend by user, shared-resource budget, per-user quota

### Trace Analyzer app

| Group | Page | What it shows |
|-------|------|---------------|
| Act (local only) | Live prompt | Sends one prompt through the gateway and polls until its trace lands, then shows the span waterfall |
| Observe | Overview, Model performance, User deep dive | KPIs, latency, errors, tokens and credits by model and user |
| Observe | Trace explorer | One trace: span timeline plus captured system prompt, input and output messages |
| Optimize | Advisor | Rules over telemetry (latency, error spikes, token bloat, model mix, cost), each with a proposed change and a "Test this fix" button |
| Optimize | Experiments | Replays EVAL_PROMPTS through the gateway with baseline vs candidate config; scores each answer 0-1 with an AI_COMPLETE judge |
| Optimize | Before / after | Quality, p50/p95, tokens, credits per 1k requests (rates fitted from billed usage) and error-rate deltas, projected monthly saving, per-prompt and side-by-side answers, plus the client config, gateway allowlist and quota SQL to promote |
| Govern | Cost governance | Month-to-date gateway credits, spend by `COST_CENTER` tag, budget limit, per-user spend against quota limits, active blocks, block history and the last captured gateway denial |

#### Where to run the app

Run it locally with `uv run streamlit run` for demos. The Experiments and Live prompt pages need gateway calls to be traced, and that works only with a PAT sent from outside Snowflake:

| Where | Gateway credential | Served | Traced |
|-------|-------------------|--------|--------|
| Laptop (`streamlit run`) | PAT | Yes | Yes, in about a minute |
| Streamlit in Snowflake | Container session token | Yes | No (in testing) |
| Streamlit in Snowflake | PAT secret | No: HTTP 401 `INCOMING_REQUEST_BLOCKED` when the account has a network policy | - |

An IP allowlist does not fix the in-Snowflake PAT case. LOGIN_HISTORY records gateway PAT calls with `CLIENT_IP = 0.0.0.0`, so there is no container address to allow, short of opening the policy to all IPs.

The deployed app still runs the Observe pages, Advisor and Before/After. Its Experiments results land in OPTIMIZATION_RESULTS without gateway traces, and Live prompt is hidden there.

### Run in Snowflake (Workspaces / Git)

The SQL and the app can run entirely from Snowsight:

1. Snowsight -> **Projects -> Workspaces -> Create Workspace from Git repository**, pointing at this repository.
2. Open `sql/setup.sql` and run it.
3. Create the Streamlit app from `src/ai_gateway_retail/app` (container runtime, compute pool `SYSTEM_COMPUTE_POOL_CPU`, integration `GATEWAY_RETAIL_APP_EAI`).

The LangChain notebook, `live-agent` and the traced Experiments play the external client, so they run on a laptop with a PAT.

## Key Concepts

- **Gateway endpoint**: `https://<account-host>/api/v2/aigateways/SNOWFLAKE/v1` plus `/chat/completions` (non-Claude) or `/messages` (Claude). Use hyphens in the host.
- **GPT-5 parameters**: use `max_completion_tokens`, not `max_tokens`. Only `openai-gpt-5.4*` accepts a custom temperature.
- **Trace hierarchy**: conversation (`x-snowflake-ai-gateway-conversation-id`) -> trace (`traceparent`) -> span (one inference call).
- **Payload capture**: prompts and responses are recorded only with `logging.capture_payload.request_response: true`. Treat the trace table as sensitive.
- **Spec replacement**: `ALTER AI GATEWAY ... FROM SPECIFICATION` replaces the whole spec, so start from `DESCRIBE AI GATEWAY`.
- **Privileges**: `USAGE` to call (granted to PUBLIC by default), `MONITOR` to read traces and usage.

## Cleanup

Run `sql/cleanup.sql`. It drops the database, warehouse and integration. The shared gateway spec reset and grant revokes are included but commented out; review them before running.

## References

- [Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway)
- [Inference with Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/inference)
- [Observability for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/observability)
- [Cost management for Cortex AI Gateway](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-ai-gateway/cost-management)
- [Snowflake-managed MCP server](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents-mcp)
- [Per-user quotas](https://docs.snowflake.com/en/user-guide/budgets/per-user-quotas)
- [Streamlit secrets and container runtime](https://docs.snowflake.com/en/developer-guide/streamlit/app-development/secrets-and-configuration)
