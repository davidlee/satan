# REV REV-013 — reconcile SL-029: every maxima unit required

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

REV-012 recorded in REQ-004 that a policy must carry `maxima.wall_clock_s`. A
review of the reconcile arc found that this still admitted a wall-clock-only
policy with no spend ceiling, against DEC-057's reading that a wall-clock
backstop alone does not satisfy REQ-004 (SL-029 notes, governing context). The
user chose to require all four units. The code now refuses a policy missing any
of `requests`, `tokens`, `cost_usd` or `wall_clock_s` (`pi/mcp/policy.ts`).

- **REQ-004** rationale, last paragraph. Before: "a policy whose `maxima` lacks
  `wall_clock_s`, or carries a non-positive maximum, is refused". After: "a
  policy whose `maxima` lacks any of `requests`, `tokens`, `cost_usd` or
  `wall_clock_s`, or carries a non-positive maximum, is refused … The wall clock
  … does not stand in for a spend ceiling (DEC-057)." Status stays `pending`.

User agreement: "Require all four" (2026-10-21, this session).

## Reconcile narrative

- [Review of the SL-029 reconcile arc, point 1]: the rationale and the code
  admitted a policy with no spend ceiling; both now require every unit.
