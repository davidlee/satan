# IMP-053: malebolge interactive daemon ceilings: one bound on unattended turns (parallel conversations, startup resume, self-scheduled wakeups)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

The interactive daemon `malebolge` has no ceilings. The patch runner does:
ADR-017 §3 ledger row 5b, the per-job ceiling, owned by `patch-runner`. Three
sources start model turns that nobody types, and they need one bound, not
three:

1. **Parallel conversations.** SL-030 made any number of concurrent
   conversations reachable, and accepted it for a single user (SL-030 risks).
   pi-durable has no cap on concurrent runs across conversations.
2. **Startup resume.** `harness.resume()` at daemon start restarts every
   conversation's unfinished turn, unattended and uncapped.
3. **Self-scheduled wakeups (IDE-017).** Sleep deadlines survive reopens, so a
   daemon that restarts after downtime fires every overdue wakeup at once.

Handed off from malebolge RFC-002 OQ-3 (2026-10-23). That RFC covers how
conversations are organised, not cost or authority.

## Questions

- Owner: which ADR-017 §3 ledger row, and who holds it? Probably not
  malebolge itself (IDE-017 asks the same question).
- Mechanism: a cap on concurrent runs (a submission waits), a spend budget
  (refuse or defer), a rate limit on wakeups, or one ceiling that covers all
  three. Can it reuse the runner's per-job ceiling (row 5b)?
- The check must be structural, in a place no tool or model can get around.

## Relations

- Prerequisite of IDE-017 (wakeups need backpressure before they can ship).
- REQ-004 / REQ-010 (via REC-002): the daemon half of the ceilings is not
  built; reconciling those requirements should cite this item.
- IMP-014 (budget-breach sensor alert), ISS-050 (no append-only audit of the
  daemon's tool calls).
