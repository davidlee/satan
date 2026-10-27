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

check: lint test forms-suite shell-suite

gate: check

# Nix: assert the built jail launchers (flake checks, Linux).
# Separate from `check`, which stays Nix-free.
check-jails: malebolge-unbound
    nix build --no-link -L .#checks.x86_64-linux.harness-jail-profile
    nix build --no-link -L .#checks.x86_64-linux.runner-socket-unjailed
    nix build --no-link -L .#checks.x86_64-linux.op-unjailed
    nix build --no-link -L .#checks.x86_64-linux.malebolge-jail-profile
    nix build --no-link -L .#checks.x86_64-linux.quotient-forms

# RV-035 F-1: the jailed-malebolge an impure devshell builds binds no
# /workspace/ path, even with JAIL_WORKSPACE_DEPS set. `nix flake check` is
# pure, so it never sees the env merge; this builds it impure.
malebolge-unbound:
    #!/usr/bin/env bash
    set -euo pipefail
    out=$(JAIL_WORKSPACE_DEPS="$HOME/notes/" \
      nix build --impure --no-link --print-out-paths .#jailed-malebolge)
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

# The offline flake-form suites (TS, run by node's type stripping — no build
# step). No test database and no network, so `check` covers them without the DB
# gate.
forms-suite:
    node --test test/flake/*.test.ts

# The offline shell-script suites: every `scripts/**/*-test.sh`, each exit 0 = pass.
shell-suite:
    for t in scripts/*-test.sh scripts/lib/*-test.sh; do [ -e "$t" ] || continue; bash "$t" || exit 1; done

# Build the quotient forms and bin to fixed, GC-rooted links. The operator
# policy names `<state>/forms/<capability>/bin/quotient-<capability>`, and
# `<state>/bin/quotient` is the stable server path: a rebuild is picked up
# without editing either, and a garbage collection cannot delete them.
quotient-forms state=(env("XDG_STATE_HOME", env("HOME") / ".local/state") / "quotient"):
    mkdir -p {{state}}/forms {{state}}/bin
    nix build -o {{state}}/forms/read .#quotient-read
    nix build -o {{state}}/forms/write .#quotient-write
    nix build -o {{state}}/pkg .#quotient
    ln -sfn ../pkg/bin/quotient {{state}}/bin/quotient

# Quotient's write-denial probe against both built forms. Calls a model through
# the LLM gateway, so it is not part of `check`. Exit 77 = prerequisite missing.
quotient-hostile-audit state=(env("XDG_STATE_HOME", env("HOME") / ".local/state") / "quotient"): (quotient-forms state)
    #!/usr/bin/env bash
    set -euo pipefail
    # The forms run under the gateway (profile specDev, network) and their
    # wrapper refuses to launch without both.
    gateway_run_dir=/run/llm-gateway
    gateway_key="$HOME/.config/llm-gateway/keys/pi"
    if [ ! -d "$gateway_run_dir" ]; then
      echo "quotient-hostile-audit: the LLM gateway is not running (no $gateway_run_dir); just system-switch, or systemctl status llm-gateway" >&2
      exit 77
    fi
    if [ ! -r "$gateway_key" ] || [ ! -s "$gateway_key" ]; then
      echo "quotient-hostile-audit: no gateway key at $gateway_key; llm-gateway issue pi --models <a,b> --budget <usd> --out \"$gateway_key\"" >&2
      exit 77
    fi
    audit=$(nix build --no-link --print-out-paths .#quotient-hostile-audit)/bin/quotient-hostile-audit
    base={{state}}/hostile-audit
    mkdir -p "$base"
    status=0
    for capability in read write; do
      dir=$(mktemp -d "$base/$capability-XXXXXX")
      mkdir "$dir/root" "$dir/session-home" "$dir/run"
      echo "quotient-hostile-audit: $capability evidence under $dir"
      # No exposure: the form writes only the call's root and session
      # directory, and its private temp.
      "$audit" --form {{state}}/forms/$capability/bin/quotient-$capability \
        --capability "$capability" --model llm-gateway/deepseek-flash \
        "$dir/root" "$dir/session-home" "$dir/run" || status=1
    done
    exit "$status"

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
