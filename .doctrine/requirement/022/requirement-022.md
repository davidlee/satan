# REQ-022: The harness reads only its run directory and its spawn environment

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Model-facing text belongs to the corpus and policy belongs to the broker (SPEC-001 REQ-006: surfaces read policy, none restate it). A harness that reads only what it was handed is replaceable and auditable: the run directory is the complete record of its input.
