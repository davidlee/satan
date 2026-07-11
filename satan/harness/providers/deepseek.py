"""DeepSeek provider: OpenAI v1 chat-completions via api.deepseek.com.

DeepSeek's chat API is OpenAI-compatible. Reasoning models
(`deepseek-reasoner`) attach `reasoning_content` to the message — we do
not surface it; `msg.content` already carries the final answer and
tool_calls use the standard shape.
"""

from __future__ import annotations

from .base import OpenAICompatibleProvider


class DeepSeekProvider(OpenAICompatibleProvider):
    base_url = "https://api.deepseek.com"
