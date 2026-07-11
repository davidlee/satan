"""Provider abstraction: completion contract + result type + OAI-v1 base.

`Provider` is the ABC the runloop sees. `OpenAICompatibleProvider`
collapses every provider whose wire shape is OpenAI v1 chat-completions
(OpenRouter, DeepSeek, etc.) into one concrete implementation
parameterised by `base_url` and `api_key`. Concrete adapters subclass it
purely as a configuration row.

DeepSeek's reasoning models (and any future thinking-mode provider)
emit a `reasoning_content` field on the assistant message outside the
OpenAI schema. DeepSeek then *requires* that the field be echoed back
on the next request or rejects with HTTP 400. We capture it on
`CompletionResult` and the runloop attaches it to the assistant message
it appends to history, so the next provider call carries it through.
"""

from __future__ import annotations

import json
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class CompletionResult:
    content: str
    tool_calls: list[dict]  # [{"id": str, "name": str, "args": dict}]
    input_tokens: int
    output_tokens: int
    reasoning_content: str | None = None


class Provider(ABC):
    @abstractmethod
    def complete(
        self,
        messages: list[dict],
        tools: list[dict],
        model: str,
    ) -> CompletionResult: ...


class OpenAICompatibleProvider(Provider):
    """Concrete adapter over any OpenAI v1 chat-completions endpoint."""

    base_url: str = ""

    def __init__(self, api_key: str, base_url: str | None = None):
        try:
            from openai import OpenAI
        except ImportError as e:
            raise RuntimeError(f"openai SDK not installed: {e}") from e
        url = base_url or self.base_url
        if not url:
            raise RuntimeError(
                f"{type(self).__name__}: base_url not configured")
        self._client = OpenAI(api_key=api_key, base_url=url)

    def complete(self, messages, tools, model):
        resp = self._client.chat.completions.create(
            model=model,
            messages=messages,
            tools=tools if tools else None,
        )
        choice = resp.choices[0]
        msg = choice.message
        content = msg.content or ""
        tool_calls = []
        for tc in (msg.tool_calls or []):
            try:
                args = json.loads(tc.function.arguments or "{}")
            except json.JSONDecodeError:
                args = {}
            tool_calls.append({
                "id": tc.id,
                "name": tc.function.name,
                "args": args,
            })
        usage = resp.usage
        reasoning = getattr(msg, "reasoning_content", None) or None
        return CompletionResult(
            content=content,
            tool_calls=tool_calls,
            input_tokens=getattr(usage, "prompt_tokens", 0) or 0,
            output_tokens=getattr(usage, "completion_tokens", 0) or 0,
            reasoning_content=reasoning,
        )
