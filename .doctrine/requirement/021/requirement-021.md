# REQ-021: The harness starts in its own run directory

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

The jail library binds the launcher's working directory read-write. Before ISS-037 that was the calling buffer's directory: from a notes buffer the notes root became writable despite its read-only bind; from the home directory, all of home (ISS-028).
