"""Provider factory: one OpenAI-compatible endpoint, the LLM gateway.

The gateway (LiteLLM) fronts every upstream model; the harness names a
model by gateway alias and never sees upstream credentials. It reads
three variables:

  SATAN_MODEL        gateway model alias (e.g. `deepseek-flash`); set by
                     the broker, forwarded by the jail
  LLM_GATEWAY_URL    gateway base URL (OpenAI v1 chat-completions); set
                     by the jail launcher
  LLM_GATEWAY_KEY    the key issued for this jail; passed in by the jail
                     launcher

Any other variables (e.g. provider selectors from an older broker) are
ignored.
"""

from __future__ import annotations

import os

from .base import CompletionResult, OpenAICompatibleProvider, Provider


def build_provider() -> tuple[Provider, str]:
    model = _required("SATAN_MODEL")
    url = _required("LLM_GATEWAY_URL")
    key = _required("LLM_GATEWAY_KEY")
    return OpenAICompatibleProvider(key, base_url=url), model


def _required(var: str) -> str:
    value = os.environ.get(var) or ""
    if not value:
        raise RuntimeError(f"{var} not set")
    return value


__all__ = [
    "CompletionResult",
    "OpenAICompatibleProvider",
    "Provider",
    "build_provider",
]
