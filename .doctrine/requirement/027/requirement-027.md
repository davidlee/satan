# REQ-027: The control socket is unjailed, validated and never writes a real repo

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Same-uid plus never-jailed is the whole authentication story (DEC-058): a jail that could reach the socket could submit or dispose jobs. Full-schema validation is SPEC-001 REQ-001 on the runner's own surface (ledger row 8).
