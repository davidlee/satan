# REQ-030: Per-job ceilings hold at the provider boundary without Emacs

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

No pi-durable hook can deny a request or set its options, so denial sits at the provider boundary (DEC-057, EVD-006). Gateway budgets are deployment caps, not SATAN ceilings (DEC-043). Ledger row 5b; SPEC-001 REQ-004, REQ-010.
