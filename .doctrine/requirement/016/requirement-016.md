# REQ-016: Every jail holding model output has a declared, test-asserted profile with no protocol bypass

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Elaborates SPEC-001 REQ-011 (surface-agnostic invariants) at the deployment layer: the protocol is only as strong as the channels a jail can reach around it. Observed gaps on 2026-09-25: MCP dev jails bind the Emacs server socket; the harness binds its launcher's cwd (probably `~`) and `~/dev/satan` read-write; keys forwarded via `try-fwd-env` land on bwrap argv; `SATAN_MAX_BUDGET_TOKENS` is not forwarded.

Status 2026-10-18: closed since — the harness cwd (ISS-037, SPEC-003 REQ-021); keys on argv and the unforwarded ceiling for satan's jails (SL-022: gateway key by fd, `harness-jail-profile` flake check). Open — the MCP dev jails' editor-socket bind and the harness's rw `~/dev/satan` bind (ISS-028); satan-attrd forwarding keys on argv (ISS-043). Tracked gaps: ISS-028, ISS-043.

Status 2026-10-20 (SL-027): the interactive daemon's room-profile jail (`jailed-malebolge`) is a consumer class of its own. It binds the room's door, its own state and runtime directories read-write, and its read-only inputs (code, corpus, gateway key and catalog, the SATAN MCP socket); it has no network and no launch directory. The `malebolge-jail-profile` flake check asserts its binds and absences; the paths live in that check and `~/flakes/SATAN.md` (SPEC-002 D2).

Status 2026-10-21 (SL-029): the `pi-mcp` per-call forms (`pi-mcp-read`,
`pi-mcp-write`) are a consumer class of their own. Each is one generator call
(`piMcpJail` in `flake.nix`) adding exactly the call's root (read-only for
`read`, writable for `write`) and its active session directory. The
`pi-mcp-forms` flake check asserts that residue over a derived generator
baseline, plus the absences (`/workspace/`, the session home, the run directory,
the policy path). It ran on 2026-10-21 against the built forms, and an injected
bind turns it red. A confinement probe under both real forms found the run's
audit unreachable from the child (SL-029 notes, PHASE-09 evidence). The write
root is the call's own allowlisted root, never the user's home by default; but
DEC-095 lets an operator allowlist `$HOME`, and the child-view check refuses
such a root only where it contains a protected store. Open for this class: a
policy's `child_binds` is not yet checked against the generator baseline, and it
cannot declare a read-only bind (IMP-048). Tracked gaps: ISS-028, ISS-043,
IMP-048.
