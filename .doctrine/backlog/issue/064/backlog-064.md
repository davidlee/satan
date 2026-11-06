# ISS-064: retention_json policy vocabulary is enforced nowhere: memory traces are never pruned

## Observed (2026-11-06)

`traces.retention_json` carries a `policy` restricted to
`normal | ephemeral | pinned | audit` (`0001_init.sql:58-61`). Nothing in the
package reads it: no pruner, no expiry, no read filter. `grep -rn ephemeral` over
`satan/`, `scripts/` and `flake.nix` returns exactly the CHECK constraint.

## Consequences

- The vocabulary is decorative: a caller asking for `ephemeral` gets permanent.
- `memory_resonate` filters on handles and an optional `kinds` array only — no
  retention floor (`0003_memory_functions.sql:112-135`) — and the auto-resonance
  path passes no `kinds` (`satan-resonance.el:88`). Any high-volume trace write
  therefore becomes retrievable prompt context on the next tick that shares a
  handle.
- This is the specific reason a discarded proposal to write one observation trace
  per tick (~17.5k rows/year) was unshippable as designed: it would have grown
  `traces` without bound and then been recalled as SATAN's own past.

## Wanted

Decide the contract before any new high-volume writer is admitted:

- **implement it** — a pruner keyed by `policy` (`ephemeral` ages out in days,
  `audit` never), plus a read-side floor or partial index so `memory_resonate` is
  not scanning dead ephemera; or
- **shrink it** — reduce the vocabulary to what is actually enforced and retarget
  the callers that already pass `:retention-json` (`satan-memory-store.el:188`).
