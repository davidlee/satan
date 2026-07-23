# DEC-002: PHASE-03 also converts satan-tank.el's require from satan-broker to satan-run

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->

## Context

[[SL-013]] PHASE-03 moves the run-directory layout cluster
(`satan-broker-locate-run-dir` / `-list-run-dirs` / `-run-dirs-for-date` and
three private helpers) from `satan-broker.el` to `satan-run.el`. Design §5.4
lists five reachers whose require-cycle scaffolding this relieves
(`satan-budget`, `satan-observer`, `satan-tools-atsatan`,
`satan-intervention-mark`, `satan-attribute-listener`) and lists
`satan-tank.el` only as "call sites repointed" — no mention of its
`require` line.

`.doctrine/slice/013/notes.md`'s Census for PHASE-03 flagged that
`satan-tank.el` is a **full convert**: verified against the live tree, its
only references to `satan-broker` are `satan-broker-list-run-dirs` (×2, via
`satan-tank--recent-runs`), `satan-broker-locate-run-dir`
(`satan-tank--read-run-events`), and `satan-broker--run-id-from-leaf`
(`satan-tank--recent-runs`) — all three in PHASE-03's moved set. No other
`satan-broker-*` symbol appears anywhere in `satan-tank.el` or
`satan-tank-test.el`.

## Decision

PHASE-03 repoints tank.el's three call sites to the `satan-run-*` names
(forced regardless, by EX-1's zero-hit grep over the full moved set) **and**
drops its `(require 'satan-broker)` at `satan-tank.el:25` to
`(require 'satan-run)`.

Encoded as a new EX/VA appended to `plan.toml`'s PHASE-03 entry — ids are
immutable-append, never renumbered, so this is a genuine addition to the
authored plan, not a silent scope change absorbed into an existing criterion.

## Rationale

- After the three calls are renamed, the require is vestigial — tank.el
  depends on nothing else in `satan-broker.el`.
- The marginal diff is one line beyond work the phase must do anyway.
- It relieves exactly the pressure design.md §2.3 measures in the other five
  reachers: paying for the broker's ~20 transitive requires to reach three
  functions that now live in a leaf every dependant may hard-require (§5.1).
  Tank was "the same pressure … in a sixth module nobody counted" (notes.md).
- Alternative considered: leave the require standing since neither
  `plan.toml` nor design.md §5.4 names it, and treat scope as strictly
  bounded to authored criteria (the same discipline EX-6/I3 enforces
  elsewhere in this phase). Rejected by the user in `/consult`: the
  criteria-only reading would leave a live module coupled to the broker for
  no functional reason, immediately after fixing the identical coupling in
  five siblings — worse resulting design for a cost the phase already pays.

## Decided by

User, via `/consult` during `/phase-plan` for PHASE-03, 2026-07-23. See the
consult transcript for the full options considered (in scope now / leave
require standing / defer to backlog — user chose "in scope now").

## Links

- [[SL-013]] — governing slice.
- Extends design.md §5.4 (phase lifecycle table) and §2.3 (the require-cycle
  pressure five other reachers pay).
