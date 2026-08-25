# ISS-008: just check exits 0 even with unexpected test failures

Found discharging SL-015 PHASE-01 EN-1 (2026-08-26).

`just check` returns exit status 0 whether the suite passes or not. Three
separate invocations were measured; two reported unexpected failures and all
three exited 0.

Cause: `satan-test-run-batch` (`dev/satan-test.el:65`) calls
`(ert-run-tests-batch t)` — not `ert-run-tests-batch-and-exit` — and returns a
summary *string*. `emacs --batch --eval` discards the return value and exits 0,
so the recipe's `set -euo pipefail` never sees a failure.

Consequence: **exit status carries no signal.** Any CI gate, git hook, or agent
that trusts `just check`'s status is reading a constant. The only reliable check
today is grepping stdout for `unexpected`.

Fix sketch: have the `test` recipe exit non-zero when the summary reports
unexpected results or load errors — e.g. `--eval` that `kill-emacs`es with the
right status, keeping the existing summary string for humans. Note
`satan-test-run-batch` already distinguishes `LOADERR` from test failure; both
should fail the build.

Related: SL-015 design §9.3, and ISS-009 (the other trap found in the same act).
