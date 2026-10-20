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
