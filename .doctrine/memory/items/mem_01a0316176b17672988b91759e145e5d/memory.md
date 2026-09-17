# Verifying green in SATAN: five ways the suite reports a false result

`just check` will not run bare (needs SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB); `just lint` is paren balance only; ~130 tests skip-and-pass without the test DBs; the exit status is always 0 (ISS-008); and concurrent runs corrupt the shared test databases (ISS-013).

## The five traps

1. **`just check` will not run bare.** The test step exits 255 with:

   ```
   satan-test: refusing to run batch tests against production socket;
   set SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB
   ```

   The devshell sets neither. `SATAN_DB_HOST` appears only at `flake.nix:85`,
   inside `supabaseJailOptions` — so it reaches jailed processes, not your
   shell. Set one of the two explicitly.

2. **`just lint` is not a linter.** `justfile:3-8` runs only
   `bin/elisp-locate-paren-error` per file — paren balance, no byte-compile.
   It cannot see a missing `(require ...)`, a `void-function`, an unused
   binding, or any other load-time or semantic breakage. "Zero warnings" from
   `just lint` means "the parens close".

3. **Green can be empty.** `justfile:18-20` warns that without the test
   databases roughly 130 tests `skip-unless` out and the run still reports
   success.

4. **The exit status is a constant.** `satan-test-run-batch` calls
   `ert-run-tests-batch`, not `…-and-exit`, and `emacs --batch --eval`
   discards the return value, so the recipe exits **0** with any number of
   failures. `set -euo pipefail` never sees a non-zero. Never trust `$?` —
   grep stdout for `unexpected`. Filed **ISS-008**.

5. **Two runs at once corrupt each other.** The DB suites target fixed
   database names by defconst (`satan_memory_test`, `trace_test`,
   `patch_live_test`) and each runs `reset-and-migrate` at setup. No
   namespacing, no lock. Overlapping invocations produce phantom failures —
   observed 14, all `satan-memory-store/*` and `satan-memory-renormalize/*`,
   with `duplicate key … (typname)=(schema_migrations)` and
   `relation "satan_interventions" does not exist`. A serial re-run of the
   same command was clean. Filed **ISS-013**. Run the suite serially; if you
   backgrounded one, wait for it.

## Consequence

A load-time defect — the classic being a module that references
`satan-custom.el`'s roots without requiring it — passes lint, and passes the
suite too if the DB env is missing enough tests. It then fails only in a fresh
interactive Emacs.

So: any plan gate, phase criterion, or PR claim of the form "`just check`
green" must name the invocation it was green under **and the counts it saw**.
The working invocation on this machine is `SATAN_DB_HOST=/run/postgresql/ just
check` (1044 ran / 1040 expected / 1 unexpected / 3 skipped; the one unexpected
is the environment-dependent `satan-db/test-db-available-p-probes-test-host`).
The trailing slash is what slips past the production-socket guard, which is
itself a defect — **ISS-009** — so fixing that guard invalidates this
invocation; they move together. Tests run interpreted via
`emacs --batch`, never byte-compiled (project governance), which removes the
other channel that would have caught it.

Related: [[mem.signpost.satan.orientation]].
