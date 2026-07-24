# Stand up the ADR-017 §3 authority ledger

## Context

ADR-017 §3 requires that every item of SATAN authority — budget ceilings,
mode/tool allowlists, audit append, permission profiles, kill switches, arrival
policy — has **exactly one owner at any time**, recorded in a ledger as it
migrates. Today the Emacs client owns them all, and the ledger does not exist.
ADR-017 lists it as an obligation *due before the first authority item migrates*,
and its verification ("authority ledger exists and is current"; "no dual
enforcement") is uncheckable without it.

RFC-017 places this as gate **G2** on the extraction critical path
`G1 (SPEC-001) → G2 (this slice) → D4.2 (policy/registry extraction)`. SPEC-001
(G1) landed the protocol contract as addressable requirements REQ-001..012; this
slice stands up the instrument that binds each authority item to a single owner
and to the SPEC-001 invariant it enforces, so D4.2's cutover can move a row
rather than fork enforcement.

This is not a new decision (ADR-017 decided single-ownership; SPEC-001 owns the
contract) and not evergreen spec — it is the concrete creation and initial
population of one artifact. A slice is the right altitude.

## Scope & Objectives

- **Enumerate the authority items.** Derive the row set from ADR-017 §3 and
  SPEC-001's invariants — one row per distinct authority item.
- **Bind each row to its invariant.** Each row cites the SPEC-001 REQ id
  (REQ-001..012) it enforces, so a migration's audit verifies against something
  addressable (SPEC-001 NF-004).
- **Record the day-one owner.** Every item's current single owner is the Emacs
  client; the ledger is accurate before any migration (SPEC-001 "retrospective
  where already true").
- **Support transition recording.** The ledger records an owner change at the
  owning slice's audit — the shape must make a from→to transition explicit and
  greppable (the "no dual enforcement" check, SPEC-001 NF-001).
- **Closure:** the ledger exists, names exactly one owner per item, cites the
  governing REQ for each, and RFC-017 G2 is satisfied — D4.2 is unblocked.

## Non-Goals

- **Migrating any authority item.** No enforcement moves in this slice; every
  owner stays Emacs. First transition is D4.2's job.
- **The policy artifact / registry schema (ADR-018 D2, D4.2).** Out of scope.
- **The control-plane RPC surface (ADR-018 D3 / OQ-2).** Out of scope.
- **Making the ledger machine-executable / CI-gated.** A checkable format is
  desirable and a design consideration, but automated enforcement tooling is a
  follow-up, not this slice's closure bar.

## Open Questions — resolved in /design (see design.md §7)

- **Home/format** → linked companion `.doctrine/adr/017/authority-ledger.md`,
  markdown table + append-only transition log (DEC-003, accepted).
- **Row granularity** → one row per independently-ownable duty (~7 rows);
  design.md §7 D2.
- **Owner vocabulary** → fixed legend-defined tokens keyed to ADR-018 topology;
  design.md §7 D3.

Residual (do not block the slice):
- **QUE-001** — SPEC-001 has no invariant for run-lifecycle/arrival authority
  that ADR-017 §3 lists; row 7 cites ADR-002 in the interim.
- **Q2 (design.md §10 F6)** — whether the forward pointer into accepted ADR-017
  §3 is acceptable; needs a governance call before implementation.

## Verification / Closure Intent

Judged done when: (1) the ledger enumerates every ADR-017 §3 authority item;
(2) each row names exactly one current owner (all Emacs on landing); (3) each row
cites its governing SPEC-001 REQ; (4) the artifact makes an owner transition
recordable and greppable; (5) ADR-017's "authority ledger exists and is current"
verification reads as satisfiable. VA by review against ADR-017 §3 + SPEC-001.

## Summary

## Follow-Ups
