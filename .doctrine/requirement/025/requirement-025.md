# REQ-025: The harness jail profile is declared by root and asserted by test

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Concretises SPEC-002 REQ-016 for the harness consumer class, in root terms; host paths stay in ~/flakes/SATAN.md (SPEC-002 D2). Gaps today: the source tree is bound read-write (ISS-028), and JAIL_WORKSPACE_DEPS can inject mounts into impure builds (ISS-037 option A). SL-022 closed ISS-029 for the harness: the key travels by fd, and SATAN_MAX_BUDGET_TOKENS is forwarded; the `harness-jail-profile` flake check asserts both.
