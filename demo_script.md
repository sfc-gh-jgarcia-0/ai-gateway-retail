# Demo Script: Cortex AI Gateway

About 23 minutes. Before you present, run `lab/setup.sql` and run `python lab/generate_traffic.py` once so the dashboards have history. Run the Trace Analyzer locally: gateway calls are traced only with a PAT from outside Snowflake (see the README section "Where to run the app").

## Pre-flight (5 min before)

- Terminal 1: `export SNOWFLAKE_ACCOUNT=<org-account> SNOWFLAKE_PAT_FILE=~/.snowflake/ai_gateway_retail.pat`
- Terminal 2: start the Trace Analyzer and leave it running:
  ```bash
  cd app
  SNOWFLAKE_DEFAULT_CONNECTION_NAME=<connection> GATEWAY_HOST=<org-account>.snowflakecomputing.com \
  streamlit run streamlit_app.py
  ```
- Check the PAT hasn't expired: send one prompt on the **Live prompt** page and confirm the waterfall appears.
- At least 10 minutes before, block the cost demo user: `python lab/generate_traffic.py --burst`. It spends about 1.5 credits as `GATEWAY_RETAIL_COST_DEMO` until the gateway returns HTTP 403, then saves the denial. Confirm **Cost governance** shows 1 user blocked. The block lasts until 00:00 UTC.
- Browser tab 1: Snowsight -> **AI & ML -> Cortex AI Gateway**
- Browser tab 2: Trace Analyzer at http://localhost:8501, lookback set to 1 day
- Deck open at the Architecture slide

## 1. Frame it (deck, 3 min)

Slides 1-3. One governed endpoint, MCP for data, telemetry you own.

## 2. Live prompt from an external agent (4 min)

```bash
python lab/live_agent.py "Which customer segments have the highest churn risk, and what is their average lifetime value?"
```

- Point out the single tool call printed (`retail_analytics_agent`) and the `trace_id`. The agent behind the MCP server picked the customer analyst and ran its SQL itself. The churn scores come from the registered XGBoost model (`MODEL_VERSION = 'V1'` in CHURN_PREDICTIONS), so model output reaches the external agent through the same governed path.
- "Two gateway calls in one agent turn, all under one trace. The client never got a raw SQL tool, so it can't go around the semantic views."
- Alternative without the terminal: on the **Live prompt** page, send a prompt, then pick `not-a-real-model` to show an error span.

## 3. Find it in Snowsight (2 min)

Tab 1, AI Gateway traces. Search the trace_id and open it: the spans, model, tokens and captured messages.
"Same data, no SQL. It lives in an event table in this account."

## 4. Find it in the Trace Analyzer (3 min)

- **Trace explorer**: pick the trace and show the waterfall and the system prompt, input and output for each span.
- **Overview**: the error rate and token charts now include those calls.

## 5. Close the loop (6 min)

1. **Advisor**: find the token-bloat or latency finding (the generator's verbose scenario produces one) and click **Test this fix**.
2. **Experiments**: both configs are pre-filled. The baseline is the flagged traffic's model at its current settings; the candidate changes only the proposed fix (smaller max tokens and a concise system prompt, or a different model). The banner names the finding. Keep about 6 prompts selected and click **Run experiment**. It takes about a minute.
3. **Before / after**: opens on the pair you just ran. Lead with cost: credits per 1,000 requests and the projected monthly saving at current volume. Credits use per-model rates fitted from this account's own billed usage. In our validation run the candidate held judge quality (0.98 vs 0.98) at 76% fewer credits per request. Your numbers will vary.
4. Every experiment call carries a traceparent: open one in **Trace explorer** to show it in the gateway telemetry.
5. Scroll to **Promote**: client config, the allowlist `ALTER AI GATEWAY`, and a per-user quota. "We ship the evidence, not a hunch."

## 6. Govern spend (3 min)

On **Cost governance** (Govern group):

1. **Attribute**: spend by cost center. Users carry a `COST_CENTER` tag, and the same tag scopes the budget. "Chargeback without a ticket: every gateway call lands on a user, and every user on a cost center."
2. **Cap**: pick `GATEWAY_RETAIL_QUOTA`. `GATEWAY_RETAIL_COST_DEMO` is over its 1-credit daily limit. Point out it went past 100%: the block lands within minutes of the spend, not on each request, so size limits with headroom.
3. **Enforce**: the user is blocked until 00:00 UTC. Open **Last gateway denial**: HTTP 403, code 391936, "exceeded the usage quota limit defined by your administrator", with the restore time. "The platform enforces it. The client didn't have to implement anything."
4. **Advisor** now leads with a HIGH finding for the blocked user, which feeds back into the optimization loop.
5. Optional: open the **Raise the limit** expander and explain that raising the limit clears the block in about 5-10 minutes. One limit applies to everyone in a quota; tag users into a second quota for a higher tier.

## 7. Governance close (deck, 2 min)

Slides 13-15: USAGE vs MONITOR, the spec replaces as a whole. Then next steps.

## Recovery tips

- Trace Analyzer doesn't show the trace yet: traces normally land within a minute; refresh the Trace explorer.
- Gateway returns 401 locally: the PAT expired or a network policy blocked it (are you on the VPN?). Create a new PAT.
- Experiments results show HTTP 401 or no gateway trace: you are on the deployed Snowflake app. Switch to the local app.
- No **Live prompt** page: it only appears in the local app.
- **Cost governance** shows no block: enforcement can take a few minutes after the burst. Re-run `--burst`, or show the saved denial and block history. After 00:00 UTC the block has reset, so run the burst again before the demo.
- Spend by cost center looks low: `AI_GATEWAY_USAGE_HISTORY` lags behind the quota figures by a few minutes to hours. The per-user quota table is the up-to-date view.
- `unknown model`: that model isn't available on this account's Chat Completions API, and Claude only works on `/v1/messages`.
