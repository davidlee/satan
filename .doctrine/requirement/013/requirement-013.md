# REQ-013: Each durable store has exactly one schema owner

## Statement

<!-- The sister TOML's `description` field is the primary, normative statement.
     Prose here may elaborate, expand upon, or disambiguate it — never
     duplicate it. -->

## Rationale

<!-- Why it must hold — the force behind it, not the implementation. -->

Today `satan_memory` is migrated by the elisp runner (`schema_migrations`), satan-attrd (`_sqlx_migrations`) and satan-patcher's `just migrate`, with colliding numbers (RSK-015). Split schema ownership is split authority over the data every component shares. ADR-018 D1 resolves it structurally by absorbing attrd into the core repo.

Tracked gaps: RSK-015.
