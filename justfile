# Test database target, exported to every recipe: this project's dev-db, a
# throwaway Postgres on a socket (`dev-db help`), which `just test` starts.
# Override with SATAN_TEST_PG*; that server is then yours to start.
# Nothing here falls back to the libpq default (the system socket).
export DEV_DB_NAME := "satan"
export PGHOST := env("SATAN_TEST_PGHOST", "/tmp/satan/db/run")
export PGPORT := env("SATAN_TEST_PGPORT", "5432")
export PGUSER := env("SATAN_TEST_PGUSER", "postgres")
export PGPASSWORD := env("SATAN_TEST_PGPASSWORD", "")
export SATAN_DB_HOST := PGHOST
export SATAN_MEMORY_TEST_DB := "satan_memory_test"

# The DB suites drop and re-migrate their own TABLES per test, but never
# create the DATABASE. Must match the suites' defconsts.
test_dbs := "satan_memory_test trace_test patch_live_test"

check: lint test shell-suite

gate: check

# Nix: assert the built jail launchers (flake checks, Linux).
# Separate from `check`, which stays Nix-free.
check-jails: malebolge-unbound
    nix build --no-link -L .#checks.x86_64-linux.harness-jail-profile
    nix build --no-link -L .#checks.x86_64-linux.runner-socket-unjailed
    nix build --no-link -L .#checks.x86_64-linux.op-unjailed
    nix build --no-link -L .#checks.x86_64-linux.malebolge-jail-profile

# RV-035 F-1: the jailed-malebolge an impure devshell builds binds no
# /workspace/ path, even with JAIL_WORKSPACE_DEPS set. `nix flake check` is
# pure, so it never sees the env merge; this builds it impure.
malebolge-unbound:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(JAIL_WORKSPACE_DEPS="$HOME/notes/" \
      nix build --impure --no-link --print-out-paths .#jailed-malebolge-probe)
    launcher=$out/bin/jailed-malebolge
    test -f "$launcher" || { echo "no launcher at $launcher" >&2; exit 1; }
    if grep -Fq -- /workspace/ "$launcher"; then
      echo "$launcher binds /workspace/:" >&2
      grep -Eo -- '"?/workspace/[^ ]*' "$launcher" | sort -u >&2 || true
      exit 1
    fi

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in satan/*.el; do
        bin/elisp-locate-paren-error "$f"
    done
    # Entry scripts need Noctalia's globals, which luau-analyze can't load.
    luau-analyze noctalia/*/lib/*.luau noctalia/*/test/*.luau

# Fails unless every test DB is reachable: the DB suites `skip-unless` it, so
# without this a missing DB reports green. SATAN_TEST_ALLOW_NO_DB=1 opts out.
test: _require-test-dbs
    #!/usr/bin/env bash
    set -euo pipefail
    emacs --batch -L ./satan -L ./dev -L ./satan/test \
      -l satan-test -f satan-test-run-batch-and-exit
    for t in noctalia/*/test/*_test.luau; do luau "$t"; done
    (cd satan/harness && python3 -m unittest -q test_gptel_harness)

# The offline shell-script suites: every `scripts/**/*-test.sh`, each exit 0 = pass.
shell-suite:
    for t in scripts/*-test.sh scripts/lib/*-test.sh; do [ -e "$t" ] || continue; bash "$t" || exit 1; done

_require-test-dbs:
    #!/usr/bin/env bash
    set -euo pipefail
    [[ -n "${SATAN_TEST_ALLOW_NO_DB:-}" ]] && exit 0
    {{just_executable()}} db-setup >/dev/null
    for db in {{test_dbs}}; do
        if ! psql -d "$db" -Atqc 'SELECT 1' >/dev/null 2>&1; then
            echo "test DB '$db' unreachable at $PGHOST:$PGPORT." >&2
            echo "Set SATAN_TEST_ALLOW_NO_DB=1 to skip the DB suites." >&2
            exit 1
        fi
    done

# Create the test databases on the target above. Idempotent.
db-setup: db-up
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

# Start the dev-db, unless SATAN_TEST_PGHOST names another server. Idempotent.
db-up:
  @test -n "${SATAN_TEST_PGHOST:-}" || dev-db up

db-down:
  dev-db down

db-status:
  dev-db status
