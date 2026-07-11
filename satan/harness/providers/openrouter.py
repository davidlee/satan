"""OpenRouter provider: OpenAI v1 chat-completions via openrouter.ai."""

from __future__ import annotations

from .base import OpenAICompatibleProvider


class OpenRouterProvider(OpenAICompatibleProvider):
    base_url = "https://openrouter.ai/api/v1"
