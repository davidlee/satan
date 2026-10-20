Used for SL-028 PHASE-02 (2026-10-20), malebolge 460b7c6..298fcd0. Worked well.

Shape:
- Run from the code repo (`cd ~/dev/malebolge`): the jail binds `$PWD` as
  `/workspace/<basename>`. `~/dev/satan` is NOT bound unless it is `$PWD`, so
  the worker cannot read the slice; paste the design section into the brief.
- Brief file inside the bound tree (gitignored), e.g.
  `.doctrine/state/sl028/brief.md`: rules (one chunk then stop; TDD; no git
  commit/stash/checkout; no doctrine verbs; files in scope), a fixed report
  format (CHANGED / TESTS red seen / CHECKS / DEVIATIONS / QUESTIONS), the
  plan-level choices, and the design text.
- Each chunk: `nohup jailed-pi -p --session-id satan-a --append-system-prompt
  <brief> "$(cat cN.md)" > cN.out 2> cN.err < /dev/null &`, poll for a
  non-empty `cN.out`. Re-using `--session-id` resumes the session (stderr warns
  "creating" only the first time). Chunks took 3-8 min.
- Reviewer: a second session id with its own brief pointing at the doctrine
  `code-review` skill (`.agents/skills/code-review/SKILL.md`); it writes
  findings as text, the orchestrator records them on the RV ledger
  (`--as <raiser label>`). Reviewer pi ran node probes against the real
  modules and bite-checked tests against pre-fix commits — high value
  (found 3 real defects in round 1).

Jail gotchas (inside jailed-pi):
- `npx biome` fails: glibc binary in node_modules on NixOS. Run biome on the host.
- malebolge `test/runner/*` fail (git-guard refuses `git reset --hard`; some
  probe timeouts). Run only the named test files inside; full `just check` on host.
- malebolge's doctrine pi extension (`.doctrine/state/pi/extensions/index.ts`)
  shells out to a host `/nix/store/...doctrine` path absent in the jail: the
  doctrine boot fails (non-fatal). The jail has doctrine at `/run/doctrine-bin`.

Worker behaviour: deepseek-flash pushed back with evidence when the
orchestrator's prescription was wrong (twice, correctly) — keep a QUESTIONS
field and read DEVIATIONS closely; its fixes occasionally regress an
adjacent path (F-8), so review each chunk's logic, not just its report.
