# REQ-019: The harness binary resolves from one declared source per deployment

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

ISS-037: the binary used to follow the calling buffer's direnv PATH, so a buffer inside the source checkout silently ran the devshell build, with dev mounts baked in, and killed a production tick at spawn. One source per deployment is also what SPEC-002 REQ-015 (one revision per repo per deployment) needs from this container.
