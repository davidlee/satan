# Verifying green in SATAN: just check needs DB env, just lint is paren-balance only

`just check` aborts from a bare shell without SATAN_DB_HOST/SATAN_FAILOVER_TO_SYSTEM_DB; `just lint` is only paren balance, and ~130 tests skip-and-pass without the test DBs.

## The three traps

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

## Consequence

A load-time defect — the classic being a module that references
`satan-custom.el`'s roots without requiring it — passes lint, and passes the
suite too if the DB env is missing enough tests. It then fails only in a fresh
interactive Emacs.

So: any plan gate, phase criterion, or PR claim of the form "`just check`
green" must name the invocation it was green under. Tests run interpreted via
`emacs --batch`, never byte-compiled (project governance), which removes the
other channel that would have caught it.

Related: [[mem.signpost.satan.orientation]].
