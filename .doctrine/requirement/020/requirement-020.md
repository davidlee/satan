# REQ-020: The child environment has one base, shared with credential lookup

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

SL-018 RV-013 N5: credential lookup must read exactly the environment the child receives, or a key can be resolved from one env and spawned with another. ISS-037 showed N5 needs one base, not the direnv merge that used to supply it. The scrub is SPEC-001 REQ-010 (fail closed) at this surface.
