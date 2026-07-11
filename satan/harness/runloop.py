"""SATAN harness turn loop.

`run` drives one chat-completions session: assemble the system prompt
from the broker-supplied bundle, then loop until the model emits
`satan_final`, no tools, or the token budget is exhausted.

Progressive token degradation: as usage approaches the budget, tools
are progressively withdrawn (tier 0→1→2→3) and system messages signal
the model to wind down.  See docs/satan/resilience-design.md §2.
"""

from __future__ import annotations

import json
import os
import time
from dataclasses import dataclass, field
from typing import Any

from bundle import build_system_prompt, build_tools, load_bundle, load_manifest
from protocol import (
    emit_error,
    emit_final,
    emit_log,
    emit_ready,
    emit_tool_call,
    read_tool_result,
)
from providers import build_provider


# -- Tool tier classification ------------------------------------------------
# Each set lists tools DROPPED when entering that tier (cumulative).

TIER_1_DROP = frozenset({
    "docs_search", "docs_read", "docs_list",
    "activity_read", "notes_recent", "hippocampus_grep",
})

TIER_2_DROP = TIER_1_DROP | frozenset({
    "org_read_context", "bough_read", "agenda_read",
    "hippocampus_list", "hippocampus_read", "notes_at_satan_scan",
    "memory_resonate", "memory_show_trace",
    "patch_job_create", "patch_job_status", "proposal_stage",
})

TIER_MESSAGES = {
    1: ("Context budget pressure. Survey tools withdrawn. "
        "Focused reads and writes remain. Begin winding down."),
    2: ("Context nearly exhausted. External reads withdrawn. "
        "Save findings to memory, then call satan_final."),
    3: ("Context exhausted. Call satan_final now with your findings."),
}

TIER_THRESHOLDS = (0.70, 0.85, 0.95)


def _tool_name(tool: dict) -> str:
    return tool["function"]["name"]


def filter_tools_for_tier(all_tools: list[dict], tier: int) -> list[dict]:
    if tier == 0:
        return list(all_tools)
    if tier >= 3:
        return [t for t in all_tools if _tool_name(t) == "satan_final"]
    drop = TIER_1_DROP if tier == 1 else TIER_2_DROP
    return [t for t in all_tools if _tool_name(t) not in drop]


def compute_tier(
    tokens_total: int,
    budget_tokens: int,
    elapsed: float,
    timeout_seconds: int,
    current_tier: int,
) -> int:
    """Return the tier that should be active.  Never decreases."""
    tier = current_tier
    if budget_tokens:
        ratio = tokens_total / budget_tokens
        if ratio >= TIER_THRESHOLDS[2]:
            tier = max(tier, 3)
        elif ratio >= TIER_THRESHOLDS[1]:
            tier = max(tier, 2)
        elif ratio >= TIER_THRESHOLDS[0]:
            tier = max(tier, 1)
    if timeout_seconds and elapsed >= timeout_seconds * 0.85:
        tier = max(tier, 3)
    return tier


# -- State -------------------------------------------------------------------

@dataclass
class RunState:
    messages: list[dict] = field(default_factory=list)
    tokens_in: int = 0
    tokens_out: int = 0
    turn: int = 0
    tier: int = 0
    start_time: float = field(default_factory=time.monotonic)

    @property
    def tokens_total(self) -> int:
        return self.tokens_in + self.tokens_out

    @property
    def elapsed(self) -> float:
        return time.monotonic() - self.start_time


# -- Error classification ---------------------------------------------------

def classify_error(e: Exception) -> str:
    msg = str(e).lower()
    if "rate" in msg or "429" in msg or "quota" in msg:
        return "rate_limit"
    if "auth" in msg or "401" in msg or "403" in msg:
        return "auth"
    if "500" in msg or "502" in msg or "503" in msg:
        return "server"
    if "timeout" in msg or "timed out" in msg:
        return "timeout"
    return "unknown"


# -- Message helpers ---------------------------------------------------------

def append_assistant_with_tools(
    state: RunState,
    content: str,
    tool_calls: list[dict],
    reasoning_content: str | None = None,
) -> None:
    msg: dict[str, Any] = {"role": "assistant", "content": content or None}
    if tool_calls:
        msg["tool_calls"] = [
            {
                "id": tc["id"],
                "type": "function",
                "function": {
                    "name": tc["name"],
                    "arguments": json.dumps(tc["args"]),
                },
            }
            for tc in tool_calls
        ]
    if reasoning_content:
        msg["reasoning_content"] = reasoning_content
    state.messages.append(msg)


def append_tool_result(state: RunState, call_id: str, result: dict) -> None:
    state.messages.append({
        "role": "tool",
        "tool_call_id": call_id,
        "content": json.dumps(result),
    })


# -- Run loop ----------------------------------------------------------------

def run() -> int:
    run_id = os.environ.get("SATAN_RUN_ID", "")
    run_dir = os.environ.get("SATAN_RUN_DIR", "")
    budget_tokens = int(os.environ.get("SATAN_BUDGET_TOKENS", "0") or 0)
    max_budget_tokens = int(os.environ.get("SATAN_MAX_BUDGET_TOKENS", "0") or 0)
    if not run_dir:
        emit_error("SATAN_RUN_DIR not set")
        return 1

    try:
        bundle = load_bundle(run_dir)
        manifest = load_manifest(run_dir)
        provider, model = build_provider()
    except Exception as e:
        emit_error(f"init failed: {e}")
        return 1

    try:
        all_tools = build_tools(manifest)
    except RuntimeError as e:
        emit_error(str(e))
        return 1

    mode_meta = manifest.get("mode", {})
    timeout_seconds = mode_meta.get("timeout_seconds", 0) or 0

    state = RunState()
    state.messages.append({"role": "system", "content": build_system_prompt(bundle)})
    tools = list(all_tools)

    emit_ready(run_id)

    # tier 3 gives model one more turn; if it doesn't finalise, force.
    tier3_warned = False

    while True:
        try:
            comp = provider.complete(state.messages, tools, model)
        except Exception as e:
            emit_error(json.dumps({
                "class": classify_error(e),
                "detail": str(e),
                "tokens_total": state.tokens_total,
                "turn": state.turn,
            }))
            return 1

        state.tokens_in += comp.input_tokens
        state.tokens_out += comp.output_tokens
        state.turn += 1
        emit_log({
            "kind": "usage",
            "tokens_in": comp.input_tokens,
            "tokens_out": comp.output_tokens,
            "tokens_total": state.tokens_total,
        })

        # Hard backstop: absolute token ceiling (default 1M).
        if max_budget_tokens and state.tokens_total >= max_budget_tokens:
            emit_final(
                f"(hard backstop: {state.tokens_total} tokens exceeds "
                f"max budget {max_budget_tokens})",
                [],
                reason="max_budget_tokens",
            )
            return 0

        # satan_final is terminal regardless of tier.
        for tc in comp.tool_calls:
            if tc["name"] == "satan_final":
                args = tc["args"] or {}
                summary = args.get("summary") or comp.content or ""
                actions = args.get("actions") or []
                emit_final(summary, actions)
                return 0

        # Tier 3 post-warning: model didn't finalise, force it.
        if tier3_warned:
            emit_final(
                f"(budget exhausted at {state.tokens_total} tokens; "
                f"model did not finalise after warning)",
                [],
                reason="budget_tokens",
            )
            return 0

        if comp.tool_calls:
            append_assistant_with_tools(
                state, comp.content, comp.tool_calls,
                reasoning_content=comp.reasoning_content,
            )
            for tc in comp.tool_calls:
                emit_tool_call(tc["id"], tc["name"], tc["args"])
                result = read_tool_result()
                append_tool_result(state, tc["id"], result)
        else:
            emit_final(
                comp.content or "(no summary)",
                [],
                reason="no_tool_calls",
            )
            return 0

        # -- Tier check after each turn --
        new_tier = compute_tier(
            state.tokens_total, budget_tokens,
            state.elapsed, timeout_seconds,
            state.tier,
        )
        if new_tier > state.tier:
            old_tier = state.tier
            state.tier = new_tier
            tools = filter_tools_for_tier(all_tools, new_tier)
            removed = ([_tool_name(t) for t in all_tools
                        if _tool_name(t) not in {_tool_name(tt) for tt in tools}])
            trigger = _tier_trigger(
                state.tokens_total, budget_tokens,
                state.elapsed, timeout_seconds, new_tier,
            )
            emit_log({
                "kind": "tier_changed",
                "from_tier": old_tier,
                "to_tier": new_tier,
                "trigger": trigger,
                "tokens_total": state.tokens_total,
                "tokens_budget": budget_tokens,
                "elapsed_seconds": round(state.elapsed, 1),
                "tools_removed": removed,
                "tools_remaining": len(tools),
            })
            state.messages.append({
                "role": "system",
                "content": TIER_MESSAGES.get(new_tier, TIER_MESSAGES[3]),
            })
            if new_tier >= 3:
                tier3_warned = True


def _tier_trigger(
    tokens_total: int,
    budget_tokens: int,
    elapsed: float,
    timeout_seconds: int,
    tier: int,
) -> str:
    if timeout_seconds and elapsed >= timeout_seconds * 0.85:
        return "timeout_85"
    if budget_tokens:
        ratio = tokens_total / budget_tokens
        if tier >= 3 and ratio >= TIER_THRESHOLDS[2]:
            return "budget_95"
        if tier >= 2 and ratio >= TIER_THRESHOLDS[1]:
            return "budget_85"
        if tier >= 1 and ratio >= TIER_THRESHOLDS[0]:
            return "budget_70"
    return "unknown"


def main() -> int:
    try:
        return run()
    except Exception as e:
        emit_error(f"unhandled: {e}")
        return 1
