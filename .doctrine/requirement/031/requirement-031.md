# REQ-031: A room outage pauses a job without spending

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Oubliette stops rooms routinely (its DEC-031). Letting the model retry would burn turns and budget while the room is down (DEC-055); treating a trust failure as downtime would park a job on a healthy, possibly impersonated, room (DEC-065).
