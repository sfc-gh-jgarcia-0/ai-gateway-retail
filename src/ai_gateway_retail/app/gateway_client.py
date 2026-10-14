"""Minimal client for the Cortex AI Gateway inference endpoint.

Auth order:
  1. st.secrets["gateway_pat"]      -> PAT bound to the app via SECRETS (optional)
  2. /snowflake/session/token       -> container-runtime session token (default in SiS)
  3. SNOWFLAKE_PAT env var / SNOWFLAKE_PAT_FILE (default ~/.snowflake/ai_gateway_retail.pat)
                                    -> local `streamlit run`

Every call sends a W3C `traceparent` so the request can be found in
AGENT_TRACE_TABLE and the Snowsight AI Gateway page by trace_id.
"""

from __future__ import annotations

import os
import time
import uuid
from dataclasses import dataclass

import requests
import streamlit as st

TOKEN_PATH = "/snowflake/session/token"


def new_traceparent() -> tuple[str, str]:
    trace_id = uuid.uuid4().hex
    return f"00-{trace_id}-{uuid.uuid4().hex[:16]}-01", trace_id


def _host() -> str:
    host = os.getenv("SNOWFLAKE_HOST") or os.getenv("GATEWAY_HOST")
    if not host:
        account = os.getenv("SNOWFLAKE_ACCOUNT", "")
        host = f"{account}.snowflakecomputing.com"
    return host.replace("_", "-")


def _auth_headers() -> tuple[dict, str]:
    try:
        pat = st.secrets.get("gateway_pat")
    except Exception:
        pat = None
    if pat and not pat.startswith("replace-with"):
        return {"Authorization": f"Bearer {pat}"}, "PAT secret"
    if os.path.exists(TOKEN_PATH):
        token = open(TOKEN_PATH).read().strip()
        return {
            "Authorization": f"Bearer {token}",
            "X-Snowflake-Authorization-Token-Type": "OAUTH",
        }, "session token"
    pat = os.getenv("SNOWFLAKE_PAT")
    pat_file = os.path.expanduser(os.getenv("SNOWFLAKE_PAT_FILE", "~/.snowflake/ai_gateway_retail.pat"))
    if not pat and os.path.exists(pat_file):
        pat = open(pat_file).read().strip()
    if pat:
        return {"Authorization": f"Bearer {pat}"}, "SNOWFLAKE_PAT env"
    raise RuntimeError(
        "No gateway credential: bind a PAT secret to the app, run on the "
        "container runtime, or set SNOWFLAKE_PAT locally."
    )


@dataclass
class GatewayResult:
    trace_id: str
    ok: bool
    status_code: int
    content: str
    latency_ms: float
    input_tokens: int | None
    output_tokens: int | None
    auth_mode: str


def chat(
    prompt: str,
    model: str,
    system: str | None = None,
    max_tokens: int = 512,
    temperature: float = 0.0,
    traceparent: str | None = None,
    conversation_id: str | None = None,
) -> GatewayResult:
    """One inference call through the gateway (Claude -> /v1/messages, others -> /v1/chat/completions)."""
    if traceparent is None:
        traceparent, trace_id = new_traceparent()
    else:
        trace_id = traceparent.split("-")[1]

    headers, auth_mode = _auth_headers()
    headers.update({"Content-Type": "application/json", "traceparent": traceparent})
    if conversation_id:
        headers["x-snowflake-ai-gateway-conversation-id"] = conversation_id

    base = f"https://{_host()}/api/v2/aigateways/SNOWFLAKE/v1"
    is_claude = model.startswith("claude")
    if is_claude:
        # Claude models are served only on the Anthropic-compatible Messages API
        url = f"{base}/messages"
        body = {"model": model, "max_tokens": max_tokens, "temperature": temperature,
                "messages": [{"role": "user", "content": prompt}]}
        if system:
            body["system"] = system
    else:
        url = f"{base}/chat/completions"
        messages = ([{"role": "system", "content": system}] if system else []) + [
            {"role": "user", "content": prompt}
        ]
        # GPT-5 family takes max_completion_tokens; only gpt-5.4* accepts a custom temperature
        body = {"model": model, "messages": messages, "max_completion_tokens": max_tokens}
        if model.startswith("openai-gpt-5.4"):
            body["temperature"] = temperature

    t0 = time.perf_counter()
    try:
        resp = requests.post(url, headers=headers, json=body, timeout=120)
    except requests.RequestException as e:
        return GatewayResult(trace_id, False, 0, str(e), 0, None, None, auth_mode)
    latency = (time.perf_counter() - t0) * 1000

    if resp.status_code >= 400:
        return GatewayResult(trace_id, False, resp.status_code, resp.text[:500],
                             latency, None, None, auth_mode)
    data = resp.json()
    usage = data.get("usage") or {}
    if is_claude:
        content = "".join(b.get("text", "") for b in data.get("content", []))
        return GatewayResult(trace_id, True, resp.status_code, content, latency,
                             usage.get("input_tokens"), usage.get("output_tokens"), auth_mode)
    content = (data.get("choices") or [{}])[0].get("message", {}).get("content") or ""
    return GatewayResult(trace_id, True, resp.status_code, content, latency,
                         usage.get("prompt_tokens"), usage.get("completion_tokens"),
                         auth_mode)
