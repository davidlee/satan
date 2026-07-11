---
name: resilience-design
description: Design foundations for structured error reporting and progressive rate-limit degradation
metadata:
  type: design-note
  topic: broker/resilience
  status: draft
  updated_at: 2026-05-24
---

# Resilience — error reporting + progressive degradation

Two related problems: (1) crashes discard diagnostic context, and (2)
rate limits cause hard termination when graceful degradation would let
the run salvage value.

---

## 1. Structured error reporting before termination

### 1.1 Current state

The broker has five terminal status paths:

| Status | Trigger | Diagnostic capture |
|---|---|---|
| `done` | `satan_final` tool call | full: transcript + final.json + actions.json |
| `failed` | harness sends `error` msg | transcript up to error + stderr.log |
| `timed-out` | timeout timer fires | transcript up to kill + stderr.log |
| `invalid-protocol` | protocol validation fail | transcript with protocol-error event |
| `budget-exceeded` | daily gate denial | synthetic audit bundle (no child spawned) |

**Problem.** On `failed` and `timed-out`, the broker kills the child
process and writes whatever partial transcript exists, but does NOT
capture:

- **Harness-side state**: message count, token subtotals, tool call
  history, which turn was in flight.
- **Provider error detail**: the raw exception (rate limit 429 vs
  auth failure vs server error) is flattened to a generic string in
  `emit_error(f"provider call failed: {e}")` (runloop.py:112).
- **Broker-side context**: which observers/sensors ran, what the
  attribute snapshot was, which pre-spawn actions completed.
- **Run-ctx diagnostic snapshot**: the `satan-run` struct has
  `:tool-calls-done`, `:status`, `:final` — none of this is persisted
  on crash paths.

### 1.2 Proposed: crash context event

On every non-`done` terminal path, the broker emits a
`broker/crash-context` event to the transcript before calling
`satan-audit-close`. This is a structured snapshot of the run's
state at the moment of failure:

```json
{
  "ts": "<ISO8601>",
  "dir": "broker",
  "event": "crash-context",
  "payload": {
    "status": "failed|timed-out|invalid-protocol",
    "tool_calls_done": 7,
    "tool_calls_budget": 15,
    "tokens_total": 82341,
    "tokens_budget": 100000,
    "elapsed_seconds": 47.2,
    "timeout_seconds": 120,
    "last_tool_call": "hippocampus_read",
    "error_class": "rate_limit|auth|server|timeout|protocol|unknown",
    "error_detail": "<raw exception string>",
    "attributes_snapshot": {"shame": 0.5, "doubt": 0.5, ...},
    "observers_ran": ["sensor-alerts", "panopticon"],
    "pre_spawn_completed": true
  }
}
```

**Placement.** `satan-broker--finalize` (broker.el:389), before
`satan-audit-close`. One `satan-audit-record` call with the
snapshot plist. Pure data assembly — no new I/O.

### 1.3 Proposed: harness-side error classification

runloop.py:111-112 catches all provider exceptions generically.
Classify before emitting:

```python
except Exception as e:
    error_class = classify_error(e)
    emit_error(json.dumps({
        "class": error_class,
        "detail": str(e),
        "tokens_total": state.tokens_total,
        "messages_count": len(state.messages),
        "turn": state.turn_count,
    }))
    return 1
```

Classification heuristic (provider-agnostic):

```python
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
```

This classification feeds both error reporting AND the progressive
degradation system (§2).

### 1.4 Tank integration

The tank's LAST RUN section already shows status + error_msg. Extend
it to parse the `crash-context` event and show a compact diagnostic
block when the last run is non-`done`:

```
LAST RUN
────────
20260524T151938-tick-agent-55f9b8
mode: tick-agent  ·  status: failed  ·  dur: 12.3s
tokens: 42000/100000  ·  tcalls: 3/15
error: rate_limit — 429 Too Many Requests
last tool: hippocampus_read
attributes: shame=0.50 doubt=0.50
```

---

## 2. Progressive token exhaustion

### 2.1 Current state

Token budget enforcement is binary: soft-warn at threshold, then
force-final on next turn. No intermediate behaviour. The run's partial
work (tool calls already completed, memory writes already persisted)
is abandoned — the model never gets to call `satan_final` to summarise
what it learned.

### 2.2 Three-tier tool degradation

As the harness approaches the token budget, progressively restrict
tool availability rather than terminating. Each tier reduces the
available tool set; the model receives a system message explaining the
restriction and is expected to wind down gracefully.

**Tier 0 — normal.** Full tool set per mode spec. No restrictions.

**Tier 1 — conserve.** Triggered by: token usage crosses 70% of budget.

- Drop high-context survey tools: `docs_search`, `docs_read`,
  `docs_list`, `activity_read`, `notes_recent`, `hippocampus_grep`.
- Keep: all read/write tools for notes, memory, bough. All action
  tools (notify, inbox, motive, patch).
- System message: "Context budget pressure. Survey tools withdrawn.
  Focused reads and writes remain. Begin winding down."

**Tier 2 — wind-down.** Triggered by: token usage crosses 85% of budget.

- Drop external reads: `org_read_context`, `bough_read`,
  `agenda_read`, `hippocampus_list`, `hippocampus_read`,
  `notes_at_satan_scan`, `memory_resonate`, `memory_show_trace`,
  `patch_job_create`, `patch_job_status`, `proposal_stage`.
- Keep: memory writes (`memory_mark`, `hippocampus_write`,
  `hippocampus_overwrite`), `inbox_append`, `notify_send`,
  `satan_final`.
- System message: "Context nearly exhausted. External reads withdrawn.
  Save findings to memory, then call satan_final."

**Tier 3 — final-only.** Triggered by: token usage crosses 95% of
budget, OR 85% of timeout elapsed.

- Only tool: `satan_final`.
- System message: "Context exhausted. Call satan_final now with your
  findings."
- If model still doesn't finalise on next turn: force synthetic final
  (current behaviour, but now only as last resort after 3 chances).

### 2.3 Implementation shape

**Harness side (runloop.py).**

- New `TierState` dataclass tracking current tier + tier-change
  timestamps.
- `degrade_tier()` function: bumps tier, rebuilds tool list by
  filtering the manifest's tools against tier allowlists, emits
  `tier_changed` log event.
- Token-budget thresholds checked after each turn (replace current
  single-threshold `warned` boolean with tier progression).

**Broker side (satan-broker.el).**

- Tool-call dispatch (`satan-broker--on-tool-call`) already checks
  tool allowlist per mode. No change needed — the harness controls
  which tools it offers the model, and the broker validates against
  the mode's full list (which is a superset of any tier's list).
- New `tier_changed` log event type accepted by the audit validator.
- Tank LAST RUN section shows tier transitions.

**Mode spec (satan-mode.el).**

- New optional `:tier-toolsets` plist on mode specs. When absent,
  default tier definitions apply. When present, overrides per-mode
  (e.g. tick-agent's full set is already narrow — tier 1 might be
  identical to tier 0).

### 2.4 Backstop termination

Hard termination only on:

- **30 minutes elapsed** (`:timeout-seconds 1800`, now uniform across
  modes). This is the hard backstop — progressive degradation should
  cause most runs to finalise well before this.
- **1M tokens cumulative** (configurable, mode-level
  `:max-budget-tokens`). Well past any normal run; catches infinite
  loops.

These backstops exist only to prevent infinite runs. Normal
termination is always via `satan_final` — either model-initiated or
forced at tier 3.

### 2.5 Notification integration

- **Tier 1 entry**: no notification (routine pressure, self-corrects).
- **Tier 2 entry**: log event. Tank shows yellow indicator.
- **Tier 3 entry**: desktop notification via `notify_send` (from
  broker, not model). "SATAN run degraded to final-only."
- **Backstop kill**: existing `announce-failure` path (syslog +
  streak-gated notification).

### 2.6 Audit trail

Every tier transition emits a transcript event:

```json
{
  "ts": "<ISO8601>",
  "dir": "harness",
  "event": "log",
  "payload": {
    "kind": "tier_changed",
    "from_tier": 0,
    "to_tier": 1,
    "trigger": "budget_70|budget_85|budget_95|timeout_85",
    "tokens_total": 72000,
    "tokens_budget": 300000,
    "elapsed_seconds": 45.2,
    "tools_removed": ["docs_search", "docs_read", "activity_read"],
    "tools_remaining": 12
  }
}
```

---

## 3. Tool tier classification

Reference classification for the default tier toolsets. Modes with
narrow tool lists apply the same tier logic; if a tier removes no
tools from a given mode, the system message still signals the
transition.

| Tool | Tier 0 | Tier 1 | Tier 2 | Tier 3 |
|---|---|---|---|---|
| `docs_search` | yes | - | - | - |
| `docs_read` | yes | - | - | - |
| `docs_list` | yes | - | - | - |
| `activity_read` | yes | - | - | - |
| `notes_recent` | yes | - | - | - |
| `hippocampus_grep` | yes | - | - | - |
| `org_read_context` | yes | yes | - | - |
| `bough_read` | yes | yes | - | - |
| `agenda_read` | yes | yes | - | - |
| `hippocampus_list` | yes | yes | - | - |
| `hippocampus_read` | yes | yes | - | - |
| `notes_at_satan_scan` | yes | yes | - | - |
| `memory_resonate` | yes | yes | - | - |
| `memory_show_trace` | yes | yes | - | - |
| `patch_job_create` | yes | yes | - | - |
| `patch_job_status` | yes | yes | - | - |
| `proposal_stage` | yes | yes | - | - |
| `hippocampus_write` | yes | yes | yes | - |
| `hippocampus_overwrite` | yes | yes | yes | - |
| `hippocampus_delete` | yes | yes | yes | - |
| `hippocampus_rename` | yes | yes | yes | - |
| `memory_mark` | yes | yes | yes | - |
| `motive_read` | yes | yes | yes | - |
| `motive_replace` | yes | yes | yes | - |
| `inbox_append` | yes | yes | yes | - |
| `notify_send` | yes | yes | yes | - |
| `notes_at_satan_done` | yes | yes | yes | - |
| `notes_at_satan_intervention_done` | yes | yes | yes | - |
| `sway_border_set` | yes | yes | yes | - |
| `sway_border_reset` | yes | yes | yes | - |
| `org_update_owned_block` | yes | yes | yes | - |
| `satan_final` | yes | yes | yes | yes |

**Design principle.** Tier drops go: survey → focused reads →
writes-only → final. At each step the model loses the ability to
gather new context but retains the ability to persist what it already
knows. The most valuable thing a degraded run can do is save its
partial findings to memory before terminating.

---

## 4. Budget changes (2026-05-24)

Mode budgets raised to give progressive degradation room to work.
With tier 1 at 70%, most runs will start winding down well before
the new ceiling. Better to get partial results after 220K than
nothing after crashing at 100K.

| Mode | Timeout | Token budget | Tool calls | Change |
|---|---|---|---|---|
| morning | 1800s | 300K | 100 | was 90s/100K/8 |
| motd | 1800s | 100K | 100 | was 45s/80K/4 |
| self-edit-mech | 1800s | 300K | 100 | was 180s/100K/20 |
| self-edit-mind | 1800s | 300K | 100 | was 180s/100K/20 |
| ruminate | 1800s | 400K | 100 | was 180s/400K/30 |

Daily ceiling: 2.5M (unchanged).

---

## 5. Implementation sequence

Suggested order (each is a standalone PR):

1. **Error classification** (harness-side). Classify provider errors
   in runloop.py. Structured error payload in `emit_error`. No broker
   changes.
2. **Crash context event** (broker-side). Emit `crash-context` on
   non-done finalize paths. Tank shows diagnostic block. Tests.
3. **Tier degradation** (harness-side). `TierState`, tier toolset
   filtering, system message injection, `tier_changed` log events.
   Broker audit validator accepts new event kind.
4. **Backstop thresholds** (both sides). New mode-spec keys
   `:max-budget-tokens`. Harness checks; broker wires defaults.
5. **Notification + tank** (broker-side). Tier-aware notification.
   Tank shows tier transitions in LAST RUN + RECENT EVENTS.

---

## 6. Resolved decisions

1. **Tier thresholds.** 70/85/95% of token budget. Global defaults,
   mode-level override via `:tier-thresholds '(0.70 0.85 0.95)`.
2. **Token-only triggers.** Rate-limit degradation deferred — 0/91
   recent failures were 429s. All failures were config errors or
   budget ceiling. Rate-limit retry is a follow-up if it becomes
   a real problem. → backlog **RISK-001** (2026-05-30).
3. **No tick-mode collapse.** All modes use same tier logic. If a
   tier removes zero tools from a narrow mode, the system message
   still signals wind-down intent.
4. **`memory_resonate` → tier 2 drop.** Reactive not exploratory, but
   can return significant context. Dropped at wind-down alongside
   other reads.
5. **Provider error typing.** Deferred. String heuristic in
   crash-context is diagnostic-only, not a control signal.
   Provider-agnosticism goal means any typed exception layer must
   support N providers — not worth it until rate limits are real.
   → backlog **IMPR-005** (2026-05-30).
6. **Tool-call budgets.** Set to 100 across the board (effectively
   uncapped). Progressive token degradation replaces tool-call limits
   as the wind-down mechanism. Machinery stays wired for future use.
7. **Timeout as tier trigger.** 85% of timeout (25.5min at 1800s)
   triggers tier 3. Insurance against runs that consume tokens slowly
   but burn wall-clock time.

## 7. Open questions

(No open questions remain — all resolved in §6.)
