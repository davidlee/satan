# Project-Specific Governance

<!-- Project governance pointers — YOURS to edit. Loaded into system prompt by `doctrine boot`. keep it tight. -->
<!-- Short, stable guidance an agent needs every session. One line each. -->

## Tooling

- `just check` = lint + test; tests run interpreted (`emacs --batch`), never byte-compiled.

## Rules & Conventions

- Governance corpus imported from `.emacs.d` on 2026-07-22; that corpus is **frozen for SATAN**. Ids cited in imported prose resolve there unless they also exist here. `IMPR-NNN`/`ISSUE-NNN` are pre-doctrine prefixes for `IMP-NNN`/`ISS-NNN`; `DE-`/`DR-` have no doctrine equivalent.
- Module extraction is gated by POL-001 (earns-the-seat test); its destination is ADR-017 (Emacs is a client), its topology and order ADR-018. Both accepted 2026-07-22; POL-001's seat lists were amended in the same act.
- **The trust boundary is a protocol, not a process** (ADR-017). Each authority item — allowlists, ceilings, audit append, kill switches, permission profiles — has exactly one owner at a time, recorded in the ADR-017 §3 ledger. Emacs is the privileged client and owns the human approval surfaces permanently.
- ADR-017's migration gate has both artefacts: the protocol spec SPEC-001 (draft; requirements all `pending`) and the authority ledger `.doctrine/adr/017/authority-ledger.md` (since 2026-07-24, every item owned by `emacs-client`).
- Whole-system map: SPEC-002 (context spec: containers, transports, composition invariants). Host-specific facts (paths, units, jails, pins): `~/flakes/SATAN.md`.

for small pieces of work, an agreed design sketch + working directly off backlog is ok, with user acceptance.

## Behaviours

