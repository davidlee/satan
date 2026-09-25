# REQ-018: Components locate each other's state through named roots, never host literals

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Host facts live in the deployment (see ~/flakes/SATAN.md), not in code or architecture. Known violations: the panopticon reader in `satan-tools-activity.el` hard-codes `~/.local/state/behaviour`, and jails hard-code `/run/user/1000` and `$HOME/satan-corpus/hippocampus`.

Tracked gaps: IMP-031.
