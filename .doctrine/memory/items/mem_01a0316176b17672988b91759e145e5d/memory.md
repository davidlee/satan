# Verifying green in SATAN: what `just check` does and doesn't prove

## How the suite reaches a database (fixed 2026-09-23, ISS-008 + ISS-009)

- The justfile exports one test target to every recipe: `PGHOST=127.0.0.1`,
  `PGPORT=54322`, `PGUSER`/`PGPASSWORD=postgres`, `SATAN_DB_HOST=$PGHOST` —
  the local Supabase Postgres, same as the dev jail's `supabaseJailOptions`.
  Override with `SATAN_TEST_PG{HOST,PORT,USER,PASSWORD}`.
- Deliberately **not** in the devshell env: direnv applies it to Emacs buffers
  and the broker merges `satan-direnv-dir`'s env into spawns, so a `PGPORT`
  there could redirect the live broker.
- `SATAN_DB_HOST` is a `psql -h` host (hostname or socket dir), **not** a
  URL. Port/user/password come from `PG*`.
- Setup: `just db-start` (outside the jail — `supabase start` fails inside),
  then `just db-setup` (idempotent).
- `just test` refuses (exit 1) if any test DB is unreachable;
  `SATAN_TEST_ALLOW_NO_DB=1` opts out (~142 DB tests then skip).
- The production-host guard (`satan-db-production-host-p`) compares canonical
  paths, so `/run/postgresql/` or `/var/run/postgresql` no longer slip past.
  The old invocation `SATAN_DB_HOST=/run/postgresql/ just check` is dead.
- Exit status is real: `satan-test-run-batch-and-exit` exits 1 unless PASS.

Baseline (2026-09-23): `just check` → 1091 ran, 1085 expected, 0 unexpected,
6 skipped (3 grammar drift = ISS-007, jail integration, 2 patch); 54 Python
harness tests OK.

## Remaining traps

1. **`just lint` is not a linter** — paren balance only, no byte-compile. It
   can't see a missing `require`, `void-function`, or unused binding.
2. **Two runs at once corrupt each other** (ISS-013): fixed DB names, each
   suite `reset-and-migrate`s at setup, no lock. Run serially.
3. **Some tests reach for production DB names** (ISS-007 grammar drift,
   ISS-019 outcome inbox). On the test host those DBs don't exist, so they
   log `database "satan_memory" does not exist` noise rather than touching
   real data — against the system socket they would hit production.
4. **Tests run interpreted** (project governance), so load-time defects that
   byte-compilation would catch surface only in a fresh interactive Emacs.

So a claim of "`just check` green" should still name the counts it saw.

Related: [[mem.signpost.satan.orientation]].
