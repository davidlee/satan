A `pkgs.runCommand` check that greps a built launcher's text (e.g. satan's
`harness-jail-profile`, `flake.nix` `jailProbes`) can go green while
asserting nothing. Four traps, each seen in SL-022 PHASE-02:

1. **`! grep …` under `set -e` never fails** — bash exempts negated
   pipelines from errexit. Write every assertion as
   `if grep -Fq -- "$s" "$f"; then fail …; fi`.
2. **Empty extraction.** If the `sed` that finds the inner launcher matches
   nothing, every `must_not` against `""` passes. `test -n "$inner" && test -f "$inner"`
   first, with a message.
3. **Probe strings derived from the thing under test.** If the probe list is
   built from the same binding as the jail's forward list, dropping a forward
   drops its probe too. Write probes literally in their own binding.
4. **Nix escaping.** Inside `''…''` a bash `${` is `''${`; inside `"…"` it is
   `\${`. The loud failure is an eval error; the quiet one is a probe string
   that no longer matches. Pass probes through `lib.escapeShellArg`.

**How to apply:** after writing or changing such a check, run a negative
control — add a forbidden token (e.g. `try-fwd-env "OPENROUTER_API_KEY"`) and
remove a required one, confirm each goes red with its own message, revert.
SL-022 PHASE-02 notes record the control for `harness-jail-profile`.
