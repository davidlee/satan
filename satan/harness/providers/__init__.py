"""Provider registry: dispatch on SATAN_PROVIDER env to a concrete adapter.

Adapters speak OpenAI v1 chat-completions via the shared
`OpenAICompatibleProvider` base. Adding a new OAI-compatible provider is
a two-line subclass + a row here.
"""

from __future__ import annotations

import os

from .base import CompletionResult, OpenAICompatibleProvider, Provider
from .deepseek import DeepSeekProvider
from .openrouter import OpenRouterProvider

# provider name -> (subclass, key env var)
_REGISTRY: dict[str, tuple[type[OpenAICompatibleProvider], str]] = {
    "openrouter": (OpenRouterProvider, "OPENROUTER_API_KEY"),
    "deepseek":   (DeepSeekProvider,   "DEEPSEEK_API_KEY"),
}


def build_provider() -> tuple[Provider, str]:
    provider_name = os.environ.get("SATAN_PROVIDER", "openrouter").lower()
    model = os.environ.get("SATAN_MODEL") or ""
    if not model:
        raise RuntimeError("SATAN_MODEL not set")
    entry = _REGISTRY.get(provider_name)
    if entry is None:
        raise RuntimeError(f"unknown SATAN_PROVIDER: {provider_name}")
    cls, key_var = entry
    key = os.environ.get(key_var)
    if not key:
        raise RuntimeError(f"{key_var} not set")
    if key.startswith("op://"):
        raise RuntimeError(
            f"{key_var} is an unresolved op:// reference; "
            "broker should have resolved this before spawn"
        )
    return cls(key), model


__all__ = [
    "CompletionResult",
    "DeepSeekProvider",
    "OpenAICompatibleProvider",
    "OpenRouterProvider",
    "Provider",
    "build_provider",
]
