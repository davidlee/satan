---
name: satan-protocol
description: SATAN JSONL protocol — canonical message-type spec for the broker/harness membrane
metadata:
  type: design
  topic: satan
  status: canon
  updated_at: 03398479
  verified_at: 03398479
---

# SATAN JSONL protocol

Canonical spec for the membrane between broker (trusted) and harness
(untrusted). Newline-delimited JSON; one object per line; no streaming
fragments. Either side ignores blank lines.

This document is **mechanism**. It belongs in dotfiles, not in
`~/notes/satan/`. The broker enforces it; the harness must produce
conforming output; tests on both sides load
`protocol/fixtures.json` and assert validator behaviour matches the
fixture's `kind`.

## Directions

| Direction | Sender  | Receiver | Types                                       |
|-----------|---------|----------|---------------------------------------------|
| `in`      | harness | broker   | `ready`, `log`, `tool_call`, `final`, `error` |
| `out`     | broker  | harness  | `tool_result`                                |

## Messages

Every message is a JSON object with a `"type"` string. Unknown types
are protocol errors. Unknown additional fields on a known type are
permitted (forward compatibility) but the listed required fields must
be present and well-typed.

### `ready` (in)

Emitted once by the harness after init, before any tool calls.

| Field    | Type   | Required | Notes                                       |
|----------|--------|----------|---------------------------------------------|
| `type`   | string | yes      | literal `"ready"`                           |
| `run_id` | string | yes      | echoes `SATAN_RUN_ID`                       |

### `log` (in)

Operational telemetry. Free-form `kind` namespace; known kinds:

- `usage` — token accounting. Fields: `tokens_in`, `tokens_out`,
  `tokens_total` (all non-negative integers). The broker's daily
  budget gate enumerates these.
- `budget_warning` — emitted once when `tokens_total` first crosses
  the run's `SATAN_BUDGET_TOKENS`. Fields: `tokens_total`,
  `budget_tokens`. Followed by a system-role message into the model
  asking it to call `satan_final` next turn. If the model fails to
  finalise after the warning, the harness force-terminates with
  `final{reason: "budget_tokens"}`.

| Field    | Type   | Required | Notes                            |
|----------|--------|----------|----------------------------------|
| `type`   | string | yes      | literal `"log"`                  |
| `kind`   | string | yes      | category tag; routes consumers   |

### `tool_call` (in)

Request a broker-owned tool. Broker validates, dispatches, sends
`tool_result` referencing the same `id`.

| Field   | Type   | Required | Notes                                      |
|---------|--------|----------|--------------------------------------------|
| `type`  | string | yes      | literal `"tool_call"`                      |
| `id`    | string | yes      | harness-chosen correlator                  |
| `name`  | string | yes      | must match `^[a-zA-Z0-9_-]+$`              |
| `args`  | object | yes      | JSON object; may be empty                  |

### `final` (in)

Terminal message. Broker captures, defers to sentinel for output
handling.

| Field     | Type   | Required | Notes                                           |
|-----------|--------|----------|-------------------------------------------------|
| `type`    | string | yes      | literal `"final"`                               |
| `summary` | string | yes      | model-facing summary                            |
| `actions` | array  | yes      | array of action objects (may be empty)          |
| `reason`  | string | no       | `no_tool_calls`, `budget_tokens`, etc.          |

Each action object:

| Field   | Type   | Required | Notes                                      |
|---------|--------|----------|--------------------------------------------|
| `type`  | string | yes      | action-kind tag                            |
| `args`  | object | no       | may be omitted or null                     |

### `error` (in)

Fatal harness error. Broker records and marks run failed.

| Field   | Type   | Required | Notes                            |
|---------|--------|----------|----------------------------------|
| `type`  | string | yes      | literal `"error"`                |
| `error` | string | yes      | human-readable diagnostic        |

### `tool_result` (out)

Broker's response to `tool_call`. Exactly one of `result` (when `ok =
true`) or `error` (when `ok = false`).

| Field    | Type    | Required | Notes                                        |
|----------|---------|----------|----------------------------------------------|
| `type`   | string  | yes      | literal `"tool_result"`                      |
| `id`     | string  | yes      | mirrors the corresponding `tool_call.id`     |
| `ok`     | boolean | yes      | success flag                                 |
| `result` | any     | iff ok   | tool-defined; commonly an object             |
| `error`  | string  | iff !ok  | reason for denial / failure                  |

## Invariants

- One JSON object per line. Trailing partial lines are buffered until
  newline arrives.
- No streaming chunk semantics. A message is whole or not present.
- Arrays serialised as JSON arrays. Elisp callers must coerce non-plist
  lists to vectors via `dl-satan-jsonl-prepare` (see jsonl module).
- `satan_final` is a **synthetic tool**: the harness intercepts a
  `tool_call` with `name = "satan_final"` and translates it into a
  `final` record. The broker never sees a `tool_call` of that name.
  Plain-content model output with no tool calls is also coerced into
  `final` with `reason = "no_tool_calls"`.
- Budget-exhaustion: harness self-terminates with synthetic
  `final{reason: "budget_tokens"}`. See thread #4 — eventual softer
  exit is planned.

## Validation

Both sides ship a thin validator. Each consumes the same fixture file
(`protocol/fixtures.json`), and the test suites assert validator
behaviour matches the fixture's `kind`.

- elisp: `dl-satan-protocol-validate` in `dl-satan-protocol.el`.
- python: `validate` / `check` in `harness/protocol.py`. Both sides
  ship the validator as its own module (since phase 3B).

Adding a message type or required field means: update this doc, add
fixtures, update both validators. Tests fail loudly otherwise.

## Audit log event types (broker-internal)

The events below do **not** cross the membrane. They are emitted
broker-side into `runs/<run-id>/transcript.jsonl` via
`dl-satan-audit-record` and consumed only by broker / observer code +
the projection rebuild CLI. The harness never sees them. They share
the file with membrane records (which carry `:dir in|out`) but use
`:dir broker`.

Authority for vocabulary: [`attributes/outcome-semantics.md`](attributes/outcome-semantics.md)
§9. The validator (`dl-satan-audit-validate-intervention-event` in
`satan/dl-satan-audit.el`) enforces this shape; tests live in
`satan/test/dl-satan-audit-intervention-test.el`.

Closed sets at the audit boundary are **strings**, not elisp keywords
(`"worked"`, not `:worked`).

### Event names

- `intervention.created` — emitted by the user-facing tool handler
  (`notify_send`, `inbox_append`, `proposal_stage`, `patch_job_create`,
  `sway_border_set`) at tool-call time.
- `intervention.outcome_classified` — emitted by the observer (auto)
  or the manual-mark writer when the maturity gate fires.
- `intervention.outcome_revised` — emitted when a later run updates a
  prior classification (auto only while `:mature`; manual any time).

### `intervention.created` payload

| Field                    | Type                  | Notes |
|--------------------------|-----------------------|-------|
| `intervention_id`        | string                | Stable id; recommended schema `<run-id>.iv<N>` (e.g. `20260523T120000-morning-deadbe.iv03`). Per-run handler-assigned counter. |
| `run_id`                 | string                | Owning run. |
| `ts`                     | string (ISO8601)      | Emission time (broker `:time_now` frozen at `--prepare`). |
| `mode`                   | string                | Owning mode (e.g. `"morning"`). |
| `kind`                   | string (enum)         | One of `inbox`, `notify`, `visible_sign`, `proposal`, `patch_job`, `accuse`, `ask`, `delay`, `quarantine`, `surface`. |
| `target_surface`         | string                | Concrete surface (e.g. `"sway-mainbar"`, `"/notes/inbox.org"`). |
| `message`                | string                | User-visible payload. |
| `related_motive_id`      | string \| null        | Motive tie or `null`. |
| `cue_handles`            | array&lt;string&gt;   | Bough cue handles. May be empty. |
| `expected_outcome`       | string                | Freeform; handler-picked counterfactual. |
| `outcome_window_minutes` | non-negative integer  | Per-kind handler default per outcome-semantics §3.3. |
| `severity`               | string (enum)         | `"low" | "medium" | "high"`. |

### `intervention.outcome_classified` payload

| Field             | Type                | Notes |
|-------------------|---------------------|-------|
| `intervention_id` | string              | Must match a prior `intervention.created` in the same audit stream (replay safety). |
| `classification`  | string (enum)       | `worked | neutral | ignored | contradicted | harmful | unknown`. |
| `confidence`      | string (enum)       | `low | medium | high`. |
| `evidence`        | object              | Classification-specific (outcome-semantics §5). Required, may be `{}`. |
| `maturity`        | string (enum)       | `pending | mature | stale`. `pending` ⇒ `classification` must be `unknown`. |
| `next_revisit_at` | string (ISO8601)    | Window close. |
| `source`          | string (enum)       | `auto | manual`. v1 rejects `auto` + (`harmful` | `contradicted`). |
| `classified_at`   | string (ISO8601)    | Emission time. |
| `marked_by`       | string \| null      | Optional; `"interactive-command" | "notes-directive" | null`. |
| `notes`           | string \| null      | Optional manual-mark notes. |

### `intervention.outcome_revised` payload

Same as `outcome_classified` plus:

| Field     | Type   | Notes |
|-----------|--------|-------|
| `revises` | string | `intervention_id` of the prior verdict this supersedes; must be a known `intervention.created`. |

### Validator-rejected combinations

The validator refuses any record where:

1. `classification = "harmful"` and `source = "auto"`.
2. `classification = "contradicted"` and `source = "auto"` (v1 only; v2 amendment may relax).
3. `maturity = "pending"` and `classification ≠ "unknown"`.
4. `intervention_id` references no prior `intervention.created` in the same stream.
5. (on `outcome_revised`) `revises` is missing, or names no prior `intervention.created`.

Adding an event kind or field means: update this section, extend
`dl-satan-audit-intervention-events` (and the relevant closed-set
constants), add ert coverage in
`dl-satan-audit-intervention-test.el`, and amend
`outcome-semantics.md` §9 if the contract itself moves.
