# REQ-028: Work returns only as collected git, judged at collection

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

bash in the room can write any path, so a per-tool-call check is early feedback only (DEC-060). Judging what actually travels is the only check the agent cannot route around (ledger row 9, SPEC-001 REQ-002).
