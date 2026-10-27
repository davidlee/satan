# Notes SL-034: malebolge wakeups: SATAN schedules its own turns in the room daemon

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-27, exploring)

Evidence: `research/research.md` (G = governance rows, C = cross-thread, S = spike).

**User rulings (2026-10-27):** no spend/rate limits in v0; wake turns share
`interactive`'s tool allowlist, kind `scheduled` is audit attribution only; a
wake off switch is in scope; ledger rows, owner token and a no-limits decision
record are written in this slice. Quiet hours: the ~23:20–07:00 suspend window
is off limits for large jobs. Two episode classes with opposite presence rules:
observation/intervention vs seclusion/self-work.

**Design theme (user, 2026-10-27): cheapest, simplest approach that works.**
Not hacks — but anything not carrying its weight, or that would add a lot of
code, is deferred. Apply it to every inquiry: prefer the answer that reuses
pi-durable / existing malebolge seams and leaves a follow-up over one that
builds machinery now. (E.g. presence source, pre-compaction, a separate
allowlist, rich task_list output are all candidates to defer or keep minimal.)

**Shaping decisions carried from research:**
- Wakes are pi-durable background tasks owned by the target conversation;
  no host table, no host timer (S3–S6, C2).
- Delivery: input with `entry:{kind:"satan.wake"}` and
  `requestId:"wake:<task>"` — idempotent fire (S1, S2, C3).
- Decider: pure function at schedule time (clamp) and fire time (gate/defer).

**Constraining governance:** ADR-017 §3/§4 (one owner per duty; fail closed),
ADR-018 D2/D3 (read policy, never copy; in-process control plane), DEC-121/125
(`scheduled` kind; pool per conversation × kind), DEC-083/085 (service stop is
not a kill switch; satan-mcp off leaves room tools live), REQ-013 (one schema
owner — satisfied by using pi-durable's tables), CON-005 (room stays offline),
POL-001 (disable switch per extraction).

**Open questions:** inq-1 … inq-11 in the design run (`doctrine design show 34`).

**Risks:**
- Unattended spend with no owned ceiling (accepted v0; gateway key cap is the backstop, outside the ledger — DEC-043).
- A wake that calls no satan-mcp tool mints no satan-mcp run/audit (DEC-122/125) — the percept fetch normally mints one.
- Heartbeat races producing two pending wakes, or none.
- Startup ordering: tasks resuming before tool refresh / index backfill.

**Assumptions:**
- The room daemon is long-running (SL-028 user unit); with it down, no wakes fire.
- pi-durable 1.4.0 semantics as spiked hold for the pinned version.

## Inquiry outcomes (2026-10-27, inquiring → all 11 resolved)

| inq | Record | Gist |
|---|---|---|
| 1 | DEC-127 | `satan.wake` background task owned by target; one `fire` phase; no topic/parent snapshot (index via `contextOf`) |
| 3 | DEC-128 | async `WakePolicy` seam + injected `env` (user: wants randomness, budget, history later); weighted presence (~60/40) |
| 4 | DEC-129 | presence = satan-mcp `activity_read{scope:current}` over `scheduled` |
| 2 | DEC-130 | `wake_*` tools; target = caller or known topic's latest at schedule |
| 5 | DEC-131 | one perpetual recurring heartbeat, topic `room` |
| 7 | DEC-132 | `MALEBOLGE_WAKES=on` at start; off defers |
| 6 | DEC-133 | fire composition; `requestId wake:<task>:<at>` (heartbeat would dedupe otherwise) |
| 8 | DEC-134 | failure → journal + `notify_send` (lands in satan-tank) |
| 9 | DEC-135 | no pre-compaction (IMP-056) |
| 10 | DEC-136 | ledger token `room-daemon`, rows 7b/6d/4d; plus DEC-137 (no limits v0), DEC-138 (shared allowlist) |
| 11 | DEC-139 | daemon wiring; 5 env keys, rest code constants (narrows DEC-128) |

Runbook steps `inquire.knowledge` and `inquire.scope` discharged (rev 23–24);
scope rewritten. Outstanding before drafting: GPT sense check of the map (user
direction), then the user's `sufficiency-accepted`.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-27 · design/inquiring (run rev 24) · SL-034 inquiry uncommitted until this commit

### Produced
- SL-034 scope (rewritten), notes; research (`research/`, gitignored); design run dr-01a17c58 (inquiring, 11/11 resolved).
- DEC-127 … DEC-139 (accepted, shape SL-034); IMP-056, IMP-057, IMP-058.

### Learned
- mem.fact.pi-durable.scheduled-turn-mechanics (spike S1–S6).

### Open
- GPT sense check of the inquiry map; user `sufficiency-accepted`; then drafting.
- ASM-c (scope): model_error vs settled submission — verify in implementation.
- Candidate backlog at close: close IDE-014 / IDE-017 as absorbed.
