# REQ-014: The repo composition graph is acyclic

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

satan's `agents` input is the nix-config repo that ~/flakes lives in, while ~/flakes consumes satan; goad resolves a second copy of the jail library. A cycle makes the build order depend on `follows` overrides and lets standalone builds diverge from deployed ones.

Tracked gaps: IMP-030.
