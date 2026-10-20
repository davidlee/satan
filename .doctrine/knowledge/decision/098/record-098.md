## Decision

A profile declares `filesystem: read | write` as an explicit capability. It is **not** derived from the tool list: every profile carries `bash`, which writes, so tool names cannot carry the safety claim.

The capability selects which wrapped form the server executes (`wrapper_read` / `wrapper_write`, named in the policy artefact). The server maps capability to an authorised form; it never assembles a jail argv and never decides what is bound.

- `tools` arguments may only narrow the profile's set; they never widen it, and they never grant filesystem authority.
- A missing required wrapper is `wrapper-unavailable`, refused before any spawn.
- The read-only form binds the root read-only (the `pi-review.sh` posture: rw only `~/.pi` and the session/artefact paths). `bash` then cannot write the target tree — an OS guarantee, not a prompt instruction.

## Delivery dependency, not follow-up

The flake's read-only wrapped form is **part of SL-029's delivery**, not a later nicety: the advertised read-only default is false without it. If it is not built, the server has no read-only capability and must say so rather than downgrade.

## Amendment to DEC-092

DEC-092 settled the profile *identifier* boundary and said a wider `tools` argument may only narrow. That stands, but it was not a filesystem control and this decision supersedes that implication: authority now comes from the capability, and the profile file is where the capability is declared. `.pi` being gitignored still argues for tracked profile documents (DEC-092).


## RV-043 F-7: the launcher has the executable baked in

`makeJailedAgent { agent = … }` builds a launcher for a *fixed* executable and
forwards pi's arguments to it (`jailed-agents.nix:343-346`). It is not a generic
command-prefix wrapper. The corrected argv is therefore:

```
<launcher> --mode json --model … --system-prompt … --tools … --thinking … \
           [--session-id … --session-dir …] \
           --no-extensions --no-skills --no-themes --no-context-files --offline --approve
```

No executable word, no `--`. A literal `pi` would arrive as a message and `--`
would terminate pi's option parsing.

Static mode has the mirror requirement: its launch closure and `PATH` must
contain the pi executable and the provider configuration, because
`makeJailedAgent`'s `piInJail` is false for `agent = pi-mcp`. The policy names
the executable, and a launcher probe asserts it is reachable inside the jail.

## RV-043 F-2: the child sees one session, not the home

The child-visible bind is `<PI_MCP_SESSION_HOME>/<session-id>/` — the active
session only — with binding and lock metadata held server-side, outside every
bind. Static mode inherits the broader view by construction and its policy may
declare a single session; that restriction is stated in sec-3 rather than
implied.
