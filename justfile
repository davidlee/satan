check: lint test

lint:
    #!/usr/bin/env bash
    set -euo pipefail
    for f in satan/*.el; do
        bin/elisp-locate-paren-error "$f"
    done

test:
    #!/usr/bin/env bash
    set -euo pipefail
    emacs --batch -L ./satan -L ./dev -L ./satan/test \
      -l satan-test --eval "(satan-test-run-batch)"
    (cd satan/harness && python3 -m unittest -q test_gptel_harness)

# Create the isolated test databases. Idempotent.
#
# The DB suites drop and re-migrate their own TABLES per test, but they never
# create the DATABASE — they `skip-unless` it is reachable. So a fresh checkout
# silently skips ~130 tests and reports green. PGHOST/PGPORT/PGUSER/PGPASSWORD
# come from the devshell.
db-setup:
    #!/usr/bin/env bash
    set -euo pipefail
    for db in satan_memory_test trace_test patch_live_test; do
        if createdb "$db" 2>/dev/null; then
            echo "created  $db"
        else
            echo "exists   $db"
        fi
    done
