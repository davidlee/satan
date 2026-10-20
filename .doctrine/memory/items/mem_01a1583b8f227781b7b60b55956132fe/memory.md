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

Update, SL-028 PHASE-03 (2026-10-20, malebolge c0d3264..f44240e). Worked well; same shape, new transport:
- **Never background jailed-pi.** bwrap runs `--die-with-parent`: a `nohup … &` launch is killed the
  moment the launching shell exits (seen: the event stream stopped mid-thought at the record count it
  had when the Bash call returned). Run each chunk in the foreground: `timeout 570 jailed-pi …`.
  A cut-off chunk continues with the same `--session-id`.
- **Prefer `--mode json` + `bin/pi-run-reduce` over `-p`:**
  `jailed-pi --mode json --model llm-gateway/deepseek-flash --tools … --no-extensions --no-skills
  --approve --offline --session-dir <bound path> --session-id <id> --append-system-prompt <brief>
  "<chunk>" > cN.jsonl 2> cN.err < /dev/null`, then `pi-run-reduce cN.jsonl -q` → `status.json`
  (state/turns/cost) + `transcript.md` (the `## Result` section is the worker's report).
  `--no-extensions` also stops the doctrine pi extension rewriting boot.md with a jail path.
- **Model:** only `llm-gateway/deepseek-flash` resolves inside the jail (the gateway's models.json);
  host `pi` has no gateway key. For `scripts/pi-scout`/`pi-research` from the host:
  `PI_BIN=jailed-pi PI_MODEL=llm-gateway/deepseek-flash`, prompt paths as `/workspace/<repo>`.
- **Session dir under the bound cwd** (jail `/tmp` is a fresh tmpfs per run); then follow-on turns
  resume across runs — used to have the reviewer verify its own findings (8 turns, $0.015).
- Reviewer: tools `read,grep,find,ls,bash` (no write/edit), `--thinking medium`: 55 turns, $0.11,
  8 mutation bite-checks, 1 real major (watch leak). Worker chunks: $0.03–0.13 each.
- Worker "red seen" can mean only "module did not exist"; bite-check the important tests yourself
  (mutate a cp-backed copy, run the file, restore — never git checkout).
