"""Configs shared by the Advisor and Experiments pages.

An Advisor finding seeds Experiments with a full baseline (what traffic looks
like today) and a full candidate (baseline + the proposed fix), so the
experiment always isolates the change being tested.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

MODELS = ["openai-gpt-5.4", "openai-gpt-5.4-mini", "openai-gpt-5-mini", "openai-gpt-5-nano",
          "claude-haiku-4-5", "claude-sonnet-4-5", "kimi-k3", "deepseek-v4-flash"]
DEFAULT_MODEL = "openai-gpt-5.4"
# Traces do not record the client's max_tokens, so the baseline uses the
# unconstrained default the lab traffic was generated with.
DEFAULT_MAX_TOKENS = 2048
DEFAULT_SYSTEM = (
    "You are a detailed retail analytics assistant. Always give comprehensive, thorough "
    "responses with specific numbers and examples."
)
CONCISE_SYSTEM = (
    "You are a concise retail analytics assistant. Answer in at most 3 short sentences or "
    "3 bullets. Lead with the number or the direct answer."
)
CONCISE_MAX_TOKENS = 300
ALT_MODEL = "openai-gpt-5.4-mini"


def config(model: str = DEFAULT_MODEL, max_tokens: int = DEFAULT_MAX_TOKENS,
           system_prompt: str = DEFAULT_SYSTEM) -> dict:
    return {"model": model, "max_tokens": int(max_tokens), "system_prompt": system_prompt}


def dominant_model(df: pd.DataFrame) -> str:
    models = df["REQUEST_MODEL"].dropna()
    return models.value_counts().index[0] if not models.empty else DEFAULT_MODEL


def other_model(model: str, preferred: str = ALT_MODEL) -> str:
    """An alternative to `model`, so a model-swap candidate never equals its baseline."""
    if model != preferred:
        return preferred
    return "openai-gpt-5-nano" if preferred != "openai-gpt-5-nano" else DEFAULT_MODEL


def proposal(finding: str, baseline: dict, **changes) -> dict:
    return {"finding": finding, "baseline": baseline, "candidate": {**baseline, **changes}}


def fit_credit_rates(usage: pd.DataFrame, min_requests: int = 5) -> dict:
    """Per-model credits per input and output token, fitted from AI_GATEWAY_USAGE_HISTORY.

    Each usage row is one request on one model, so least squares on
    credits ~ in_rate * input_tokens + out_rate * output_tokens recovers the rates
    this account is actually billed, with no hard-coded price table.
    """
    rates = {}
    cols = {"MODEL", "CREDITS", "INPUT_TOKENS", "OUTPUT_TOKENS"}
    if usage is None or usage.empty or not cols <= set(usage.columns):
        return rates
    for model, g in usage.dropna(subset=list(cols)).groupby("MODEL"):
        if len(g) < min_requests:
            continue
        x = g[["INPUT_TOKENS", "OUTPUT_TOKENS"]].to_numpy(dtype=float)
        (r_in, r_out), *_ = np.linalg.lstsq(x, g["CREDITS"].to_numpy(dtype=float), rcond=None)
        if r_in >= 0 and r_out > 0:
            rates[model] = (r_in, r_out)
    return rates


def estimate_credits(model: str, input_tokens, output_tokens, rates: dict):
    if model not in rates:
        return None
    r_in, r_out = rates[model]
    return r_in * (input_tokens or 0) + r_out * (output_tokens or 0)
