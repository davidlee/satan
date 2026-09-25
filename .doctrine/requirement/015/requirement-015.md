# REQ-015: A deployment runs one revision of each repo

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Today the harness comes from the `github:davidlee/satan` pin while elisp and `bin/` scripts come from the live working tree, so a protocol change can be half-deployed without any error.

Tracked gaps: RSK-016.
