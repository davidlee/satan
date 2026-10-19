# REQ-032: Restart follows a written recovery table

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Job rows and pi-durable commits are separate but ordered writes; the table covers every gap between them instead of reconcile-and-guess (DEC-054). Disabled-means-parked is the runner's kill switch (ledger row 6b, SPEC-001 REQ-005).
