# SATAN follow-ups superseded by backlog

# SATAN follow-ups superseded by backlog

## Summary

Owner-less SATAN next-actions / follow-ups now live as **spec-driver backlog
items**, not in hand-maintained markdown trackers. Capture new ones with
`spec-driver create {issue|improvement|risk} "…"`. Do **not** re-fork a markdown
follow-up list.

## Context

Migrated 2026-05-30. `docs/satan/follow-ups.md` is now a redirect stub (status
`superseded`). Mixed design/status docs keep their bodies but carry per-entry
`→ <ID>` pointers to the backlog:

- `docs/satan/bough-gaps.md` §B2 → `IMPR-004`
- `docs/satan/resilience-design.md` §6 #2 → `RISK-001`, #5 → `IMPR-005`
- `docs/satan/refactor/plan.md` T-attr-1d → `IMPR-003`
- `docs/satan/follow-ups.md` A1 → `ISSUE-001`, A16 → `IMPR-001`,
  A13 → `IMPR-002`

Gated items carry an unblock condition in the body + a `blocked` tag.

Not migrated (2026-05-30): `docs/HANDOVER.md` "Open SATAN.md threads"
(#2/#3/#7/#8/#10) + deferred (3C-full, Path B/Hybrid) — owner couldn't confirm
liveness, left in place for a later pass. `docs/satan/memory/handover.md`
quality sweep was already shipped (struck, not migrated).
