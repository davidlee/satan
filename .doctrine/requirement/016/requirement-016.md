# REQ-016: Every jail holding model output has a declared, test-asserted profile with no protocol bypass

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Elaborates SPEC-001 REQ-011 (surface-agnostic invariants) at the deployment layer: the protocol is only as strong as the channels a jail can reach around it. Observed gaps on 2026-09-25: MCP dev jails bind the Emacs server socket; the harness binds its launcher's cwd (probably `~`) and `~/dev/satan` read-write; keys forwarded via `try-fwd-env` land on bwrap argv; `SATAN_MAX_BUDGET_TOKENS` is not forwarded.

Tracked gaps: ISS-028, ISS-029.
