`(called-interactively-p 'interactive)` returns nil whenever Emacs runs with
`--batch`, even for `call-interactively` or `funcall-interactively`, because
the `interactive` kind also requires a non-batch session. `just check` runs
ERT in batch, so a test cannot reach an interactive-only branch by invoking
the command interactively.

SATAN's case: `satan-run` binds `satan-run-attended` to
`(called-interactively-p 'interactive)` (SL-018 design sec-8). The attended
test (VT-8) therefore stubs `called-interactively-p` with `cl-letf` for the
positive case. The negative case (VT-17) needs no stub.

**How to apply:** to test interactive-only behaviour, stub the predicate, or
use `(called-interactively-p 'any)` where the batch distinction doesn't
matter. Don't conclude that the code is broken because the branch never
fires under batch.
