# Project-Specific Governance

<!-- Project governance pointers — YOURS to edit. Loaded into system prompt by `doctrine boot`. keep it tight. -->
<!-- Short, stable guidance an agent needs every session. One line each. -->

## Tooling

- `just check` = lint + test; tests run interpreted (`emacs --batch`), never byte-compiled.

## Rules & Conventions

- Governance corpus imported from `.emacs.d` on 2026-07-22; that corpus is **frozen for SATAN**. Ids cited in imported prose resolve there unless they also exist here. `IMPR-NNN`/`ISSUE-NNN` are pre-doctrine prefixes for `IMP-NNN`/`ISS-NNN`; `DE-`/`DR-` have no doctrine equivalent.
- Module extraction is gated by POL-001 (earns-the-seat test); its destination is ADR-017 (Emacs is a client), its topology and order ADR-018.

## Behaviours

