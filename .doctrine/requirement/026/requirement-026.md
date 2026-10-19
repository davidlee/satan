# REQ-026: Patch jobs have one consumer and one state owner

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

SL-023 found two consumers of one Postgres queue, neither of which ever finished a job (ISS-039), and a two-owner table (SPEC-002 REQ-013, RSK-015). Process-private state may live in its own store (ADR-018 D3 as amended by REV-006); sharing one file with the durable conversations gives job rows and transcripts one commit order (DEC-052, DEC-054).
