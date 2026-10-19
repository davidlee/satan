# REQ-033: Everything door-specific sits behind one port chosen by config

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

The room interface was built against fixtures while oubliette SL-006 was unshipped (DEC-060, DEC-065); keeping the door behind a port made SL-006 shipping a config change. Derived values hide drift; configured ones fail at the first check (the preparing guest_path check, the push oid gate).
