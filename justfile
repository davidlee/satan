# Test database target, exported to every recipe. Defaults match the dev
# jail (`supabaseJailOptions` in flake.nix): the local Supabase Postgres
# (`just db-start`, run outside the jail). Override with SATAN_TEST_PG*.
# Nothing here falls back to the libpq default (the system socket).
export PGHOST := env("SATAN_TEST_PGHOST", "127.0.0.1")
export PGPORT := env("SATAN_TEST_PGPORT", "54322")
export PGUSER := env("SATAN_TEST_PGUSER", "postgres")
export PGPASSWORD := env("SATAN_TEST_PGPASSWORD", "postgres")
export SATAN_DB_HOST := PGHOST

# The DB suites drop and re-migrate their own TABLES per test, but never
# create the DATABASE. Must match the suites' defconsts.
test_dbs := "satan_memory_test trace_test patch_live_test"

check: lint test

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in satan/*.el; do
        bin/elisp-locate-paren-error "$f"
    done

# Fails unless every test DB is reachable: the DB suites `skip-unless` it, so
# without this a missing DB reports green. SATAN_TEST_ALLOW_NO_DB=1 opts out.
test: _require-test-dbs
    #!/usr/bin/env bash
    set -euo pipefail
    emacs --batch -L ./satan -L ./dev -L ./satan/test \
      -l satan-test -f satan-test-run-batch-and-exit
    (cd satan/harness && python3 -m unittest -q test_gptel_harness)

_require-test-dbs:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -n "${SATAN_TEST_ALLOW_NO_DB:-}" ]] && exit 0
    for db in {{test_dbs}}; do
        if ! psql -d "$db" -Atqc 'SELECT 1' >/dev/null 2>&1; then
            echo "test DB '$db' unreachable at $PGHOST:$PGPORT." >&2
            echo "Run 'just db-start' (outside the jail), then 'just db-setup';" >&2
            echo "or set SATAN_TEST_ALLOW_NO_DB=1 to skip the DB suites." >&2
            exit 1
        fi
    done

# Create the test databases on the target above. Idempotent.
db-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    for db in {{test_dbs}}; do
        exists=$(psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname = '$db'")
        if [[ -n "$exists" ]]; then
            echo "exists   $db"
        else
            createdb "$db"
            echo "created  $db"
        fi
    done

# Supabase must run outside the jail (inside it, `supabase start` fails).
db-start:
  supabase start

db-stop:
  supabase stop

db-status:
  supabase status
