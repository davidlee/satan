# Hermetic test DB with pinned satan-attrd schema

## Context

The broker (this repo) reads and writes tables owned by **satan-attrd** (the
attribute daemon, `~/dev/satan-attrd`, Rust, sqlx migrations). SATAN's test
suite has never seen those tables, so every broker path that touches them fails
in tests and the failure is swallowed. Separately, the test DB fixtures are
duplicated per suite, and each copy rebinds a different subset of the
database-name settings, so some tests reach for the *production* DB name.

State as of 2026-09-23 (commits `90a2e12`, `ed922a6`; ISS-008, ISS-009
resolved):

- `just test` targets the local Supabase Postgres (127.0.0.1:54322) via
  `PG*` + `SATAN_DB_HOST` exported from the justfile; fails if a test DB is
  unreachable; exits non-zero on failure. See memory
  `mem.fact.satan.green-is-not-green`.
- Baseline: 1091 ran / 1085 expected / 0 unexpected / 6 skipped; the output
  carries ~37 `database "satan_memory" does not exist` warnings — the leaks
  below, now harmless only because the host is the test host.

### Production schema layout (verified against the system Postgres)

```
satan_memory  (one DB)
 ├─ satan migrations 0001–0007   ledger schema_migrations   elisp runner (satan-memory-migrate)
 └─ attrd migrations 0007–0012   ledger _sqlx_migrations    `satan-attrd migrate` (manual, nix/module.nix:21)
```

Broker dependencies on attrd-owned DDL:

| Table | Broker use | Code |
|---|---|---|
| `satan_outcome_inbox` | INSERT + `pg_notify` | `satan-attribute-enqueue` (`satan/satan-attribute.el:131`) |
| `satan_attributes` | snapshot SELECT for capsule | `satan-attribute-snapshot` (`satan/satan-attribute-render.el`) |
| `satan_attribute_settings` | UPSERT on toggle | `satan-attribute--write-enabled-setting` |
| `satan_audit_inbox` / `satan_audit_replies` | LISTEN consumer | `satan/satan-attribute-listener.el` |

The wire payload (v1.0) is pinned only in prose: `docs/attributes/design-contract.md` §17.3.

### Leak inventory (ISS-019)

Four DB-name defcustoms all default to `"satan_memory"`:
`satan-attribute-database`, `satan-memory-store-database`,
`satan-patch-store-database`, `satan-memory-migrate-database`.

- **Writes:** ~24 observer / pattern / intervention tests reach
  `satan-attribute-enqueue` via `satan-intervention-classify`;
  `satan-intervention-test--with-db` rebinds only `satan-memory-migrate-database`.
- **Reads:** ~13 capsule tests (context, percept, resonance, motive,
  self-edit) call `satan-attribute-snapshot`; they use no DB fixture at all.
- Map produced by attributing each warning to the test that follows it in
  `just check` output — repeat that to verify the fix.

### Duplicated fixtures

`reset-and-migrate` is byte-identical (DROP list + `satan-memory-migrate-apply`)
in 7+ suites: memory-store, intervention, memory-renormalize, pattern,
tools-memory, observer, tools-hippocampus (patch-store has its own `with-db`).
The `with-db` macros differ only in which DB-name vars they bind. All use
`"satan_memory_test"` by per-file defconst.

### ISS-007

`satan/test/satan-memory-grammar-test.el:22` uses
`(or (getenv "SATAN_MEMORY_TEST_DB") "satan_memory")` and a private psql
helper, so its three `db-sync-*` tests (the only elisp-constants vs SQL drift
check) always skip. Pointing it at `satan_memory_test` alone would make it
order-dependent (siblings drop/re-migrate) — it needs its own migrate step.

## Scope & Objectives

1. **Pin satan-attrd's schema via the flake (user-endorsed direction).** Add
   `satan-attrd` as a flake input of this repo; expose the `satan-attrd` binary
   in the devshell. The test DB gets attrd's real migrations by running
   `satan-attrd migrate` (DATABASE_URL at `satan_memory_test` on the test host)
   after satan's own migrations — same two ledgers in one DB as production.
   `flake.lock` becomes the schema-version contract: bumping attrd re-runs
   satan's suite against the new DDL.
2. **One shared DB fixture** (e.g. `satan/test/satan-test-db.el`, not matched
   by suite discovery — `satan-test--file-p` wants `*-test.el` / `test-*`):
   the test DB constant, reachability predicate, `reset-and-migrate` (satan +
   attrd, and the DROP list extended to attrd's tables + `_sqlx_migrations`),
   and a `with-db` macro binding **all four** DB-name vars. Remove the copies.
3. **Harness floor** (ISS-019): `satan-test-run-batch` (`dev/satan-test.el`)
   let-binds all four DB-name defcustoms to the test DB for the whole run —
   same pattern as the existing `satan-announce-sink` binding (SL-017 design
   "Test hermeticity": the harness owns hermeticity; `let`, never `setq`).
4. **ISS-007:** grammar suite uses the shared fixture and migrates its own DB;
   drop the `SATAN_MEMORY_TEST_DB` escape hatch and private psql helper.
5. Fix the enqueue/snapshot/settings tests that currently pass *because* the
   call fails, if any start failing once the tables exist.

## Non-Goals

- **Payload contract fixtures** (golden §17.3 payloads checked by broker
  builder and attrd validator, cf. `satan/protocol/fixtures.json`). ADR-018 D3
  retires the inbox + `pg_notify` transport for UDS RPC, and D1 absorbs attrd
  into the daemon-core repo. Do this when the RPC lands, specified in SPEC-001 (trust-boundary protocol tech spec)
  with fixtures from day one — not for the transitional queue.
- Renumbering / consolidating migration ledgers (RSK-015).
- Concurrency of test runs (ISS-013), live-root writes (ISS-018).
- Anything in `~/dev/satan-attrd` beyond consuming it (see Follow-Ups).

## Summary

Affected surface: `flake.nix`, `flake.lock`, `justfile` (`db-setup`, test
reset), `dev/satan-test.el`, new `satan/test/satan-test-db.el`, the ~8 DB
suites under `satan/test/`, `satan/test/satan-memory-grammar-test.el`.
No production elisp change expected.

Open questions for design:

- **OQ-1 Where attrd migrations run.** Per-test reset (inside the shared
  `reset-and-migrate`, spawning `satan-attrd migrate` each time — cost?) vs
  once in `just db-setup` with the per-test reset leaving attrd tables alone
  (then do broker tests need attrd rows truncated between tests?). Measure
  `satan-attrd migrate` latency.
- **OQ-2 FK/CASCADE interplay.** Does any attrd table reference satan tables
  (or vice versa), so satan's `DROP ... CASCADE` takes attrd objects with it?
  Read attrd `migrations/0007–0012`.
- **OQ-3 Flake input form.** `github:davidlee/satan-attrd` (matches how
  `~/flakes` consumes satan) vs `path:`; `inputs.*.follows` to avoid a second
  nixpkgs. `flake.nix:107` already bind-mounts `~/dev/satan-attrd/` into the
  dev jail — reconcile.
- **OQ-4 Runtime jail.** Tests run inside the dev jail too; the binary must be
  on PATH there and reach 127.0.0.1:54322.
- **OQ-5 DATABASE_URL.** `satan-attrd migrate` reads `DATABASE_URL`; derive it
  from the justfile's `PG*` target, never a default.

Risks: attrd migrations may assume production-only state (e.g. seed rows,
`0012` seeds `attribute_updates_enabled`); `satan-attribute--on-enabled-change`
is a variable watcher that writes on `set` — watch for it firing at load.

## Verification / closure intent

- `just check` green with the counts named; **zero** `satan_memory`
  warnings in the output (grep it), and the ISS-007 `db-sync-*` tests run
  (not skipped).
- A test proving the harness floor: inside the batch run, all four DB-name
  vars equal the test DB.
- Enqueue / snapshot paths exercised against the real attrd DDL at least once.
- Bumping or breaking attrd's schema (e.g. rename a column locally via a
  `path:` override) makes a satan test fail — demonstrate once, record in notes.
- ISS-007 and ISS-019 resolved; memory `mem.fact.satan.green-is-not-green`
  updated.

## Follow-Ups

- **RSK-015 is stale:** says attrd lives in a separate `satan_attributes` DB;
  production has both ledgers in `satan_memory`, overlapping at 0007. Correct it.
- **~40 orphaned `satan_attrd_test_*` DBs** on the system Postgres
  (`/run/postgresql`), leaked by satan-attrd's test harness
  (`tests/common/mod.rs` provisions one per test). Clean up; file in attrd.
- `satan-tools-notes--exclude` still excludes a `satan/` subtree of `~/notes`
  — dead since SL-015 moved the corpus out.
- Payload contract fixtures — with the ADR-018 D3 RPC, in SPEC-001.
