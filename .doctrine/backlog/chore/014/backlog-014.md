# CHR-014: docs/governance.md Tick mode family states stale defaults (3000 tokens / 4 calls / 30 s, three tools); satan-tick.el registers 100000 / 10 / 120 s

## Drift, checked 2026-11-06

Four claims in the same section, not one. `docs/governance.md`:

| Line | Doc says | Code says |
|---|---|---|
| 499-500 | `tick-pulse` / `tick-agent` at 3000 / 4 / 30s | `satan-tick.el:94,97,98` → 100000 / 10 / 120s; tick-agent `satan-tick.el:130-132` → 100000 / 15 / 120s |
| 704 | `satan-budget-daily-tokens` default 400000 | `satan-budget.el:14` → 2500000 |
| 507-512 | pool default `(("tick-pulse" . 1))`; `pulse` registered in `satan-tick.el`, `agent` in `satan-tools-atsatan.el` | `satan-tick.el:18` → `(("tick-pulse" . 5) ("tick-agent" . 3))`; both registered in `satan-tick.el` (pulse :107, agent :117) |
| 499 | tick-pulse allows `patch_job_create` / `patch_job_status` / `patch_job_cancel` | `satan-tick.el:83-88` tool list has none of them |

Also missing from the doc: `satan-tick-quiet-hours` now defaults to `nil`
(disabled, `satan-tick.el:24`), which is why ticks run around the clock.

## Why it earns a chore

An agent-authored improvement card (2026-11-06, since deleted) took this table
for ground truth and built a spend argument on numbers no longer in the tree.
Stale governance prose is not cosmetic here; it is a false premise generator for
every automated reader of the repo.

The drift is not confined to the tick rows: `morning` is documented at
20000 / 8 / 90s against a registered 340000 / 100 / 1800s, `motd` at
10000 / 4 / 45s against 100000 / 100 / 1800s, and both `self-edit-*` at
50000 / 20 / 180s against 400000 / 100 / 1800s (`satan-mode.el:95-205`). Fix the
table whole — preferably by deriving it from the registrations at build time, so
it cannot drift again.
