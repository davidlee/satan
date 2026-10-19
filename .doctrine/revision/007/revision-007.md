# REV REV-007 — reconcile SL-023

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

The SL-023 audit (RV-029) found the system spec still describing the retired
Go `satan-patcher` and its `pg_notify` coupling, the runner tech spec DEC-064
owed at reconcile still unwritten, and SPEC-003 OQ-3 open (finding F-25).
This revision lands all three, from the reconciled SL-023 design and this
audit's corrections. No new decision is taken here — each change restates
what SL-023 decided and built. Approved by the reconcile agent acting on the
orchestrator's delegation (approval is invoker-blind); this is not a recorded
user act, and the user has not reviewed SPEC-004's prose yet.

## Reconcile narrative

- [RV-029 F-25, DEC-064] **SPEC-004 — Patch runner** (new; `container`,
  parent SPEC-002, no PRD; governed by ADR-017, ADR-018, POL-001; bound-by
  SPEC-001). Scaffolded with `spec new` and authored in this pass: overview
  and component map, the control-socket, job, state, git-channel-port and
  execution-environment contracts, concerns, hypotheses, decisions D1..D6
  (each citing its DEC). Requirements REQ-026..REQ-032 (FR-001..FR-007) and
  REQ-033 (NF-001), all `pending`: one consumer and state owner; unjailed
  validated socket with no real-repo writes; work only as collected git,
  judged at collection; promotion in Emacs, verified; ceilings at the provider
  boundary; room outages pause without spending; written recovery table; the
  door behind one port. The `modify` row records the spec as touched; it was
  created, not amended (the REV `create` action is for requirements only).
- [RV-029 F-25] **SPEC-002** — container row (patch runner = `satan-runner`
  from `malebolge`, SPEC-004), confinement row (oubliette rooms in use),
  shared-database row (no patch jobs), current-topology text diagram and
  coupling prose (runner over UDS RPC, not `pg_notify`), transports (the
  `pg_notify` row now broker ⇄ attrd only; new rows for the runner's control
  socket and the room door / git channel), end-state paragraph and the
  container hypothesis (the runner's home is decided). `diagrams.py` updated
  (context: `satan-runner` with an RPC edge, Postgres zone shrunk; composition:
  two `path:` inputs; end-state: the runner is built, not proposed) and the
  three HTML diagrams regenerated.
- [RV-029 F-25] **REQ-013** (SPEC-002 NF-001) rationale — `satan-patcher`'s
  `just migrate` removed from `satan_memory`'s migrators (retired; 0009
  dropped the tables; the runner owns its own store). Status unchanged
  (`pending`).
- [RV-029 F-25] **SPEC-003** — OQ-3 resolved (neither old runner survives;
  SPEC-004 governs the runner); the "out of scope" note no longer names the
  deleted elisp patch adapter.

Not in this REV (not REV-targetable kinds, landed directly): DEC-055, DEC-057,
DEC-065 revision notes and facet edits; `.doctrine/governance.md` ledger
ownership line (F-26).
