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

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-27 · design/inquiring (run rev 11) · 2bac37c (SL-034 uncommitted)

### Produced
- SL-034 scope, notes; research round (`research/`, gitignored); design run dr-01a17c58 (inquiring).

### Learned
- mem.fact.pi-durable.scheduled-turn-mechanics (spike S1–S6).

### Open
- inq-1 … inq-11 (design run). Candidate backlog at close: close IDE-014 / IDE-017 as absorbed.
