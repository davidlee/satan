# REQ-029: Promotion is a human act enacted in Emacs and verified by the runner

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

ADR-017 §1 keeps human approval surfaces in Emacs. Keeping the enactment there means nothing reachable over the runner's socket writes a real repo (DEC-061); the runner's read-back keeps promoted meaning verified.
