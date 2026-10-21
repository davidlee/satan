# Pi-tiered capsule execution: Claude orchestrates, jailed pi plans/works/reviews each phase

Used for SL-030 (2026-10-21, 8 phases, malebolge 71f1bed..). The /capsule-driver shape with
pi in place of Claude subagents. Cost ≈ $0.15–0.45 per phase (planner+worker+reviewer+fixes on
`llm-gateway/deepseek-flash`); Claude context ≈ one hand-back + gate + findings per phase.

Loop per phase (Claude = sole verifier, committer, doctrine writer):
1. pi planner fills `.doctrine/state/slice/NNN/phases/phase-NN.md` (tools read,grep,find,ls,bash,write).
   It distils memories into the sheet and ends with open questions — answer them from the design
   in the worker's prompt; they are usually real (drifted lines, unpinned messages, test shape).
2. pi worker (read,edit,write,bash; thinking high, xhigh for the core phase) implements TDD,
   no commits, writes `handback.md`.
3. Host gate (format + lint + tsc + tests), read the src diff against EX criteria, commit, flip phase.
4. pi reviewer (read,grep,find,ls,bash) reviews the COMMIT (`git show`), writes `findings.md`.
   Raise valid findings on one slice RV (`--as pi-reviewer`), dispose, resume the WORKER's
   session (`--session-id`) with the fixes, gate, fix-up commit, `review verify`.
   Flash reviewers found real gaps (an unasserted stream-stop on departure; a re-bind test that
   could not see a re-bind) — not rubber stamps.

Mechanics:
- Launch from the doctrine repo (satan): cwd `/workspace/satan` + sibling `/workspace/malebolge`
  rw. Launched from malebolge, satan is not mounted (phase sheets unreachable).
- Helper/prompt dir `.capsule-runs/` in `.git/info/exclude`; session dir under it (jail `/tmp`
  is per-run tmpfs). `jailed-pi --mode json … --session-dir .capsule-runs/sessions --session-id
  sl030-<label>`, then `bin/pi-run-reduce`; verdict = `status.json` state.
- Claude's Bash call caps at 10 min and kills a foreground pi. Detach:
  `setsid nohup ./run-pi.sh … > run.log 2>&1 < /dev/null & disown`, then poll with
  `timeout 580 bash -c 'until grep -q "reduce rc" run.log; do sleep 20; done'` (cd first — a
  backgrounded `cd … && … &` does not change the foreground shell's cwd).
- A killed or errored run resumes from its session ("you were interrupted; re-orient with git
  status and continue").
- Planner of phase N+1 and reviewer of phase N can run concurrently (both read-only on code).
- Diff only slice paths (`git diff -- src test`): the tree has unrelated dirty files.
- `state: failed` + `last_stop_reason: error` → grep `errorMessage` in events: a `402
  Insufficient Balance` is the gateway's DeepSeek balance — the user must top up; halt.

Jail gotchas: see [[mem_01a1583b8f227781b7b60b55956132fe]] (biome, test/runner/* jail-only
failures; host gate authoritative). malebolge's untracked `_pi/` breaks `eslint .` — ignore it
with `--ignore-pattern '_pi/**'`.

## Outcome (SL-030 complete, 2026-10-21)

All 8 phases in one session, ≈ $2.2 of pi total; Claude context stayed small. Worked well — reuse.
- Review value: 23 findings (1 major, 9 minor); real test gaps every time a phase looked clean to the
  worker (untested post-attach typing; an abort test that could not see a mis-scoped abort; docs
  stale singulars). Have the reviewer try concrete regressions ("would this test fail if…").
- Ask workers to prove a test is meaningful by temporarily breaking the src it guards, seeing red,
  restoring byte-exactly (`git diff -- src` empty). Essential for test-only phases.
- Planner-of-N+1 alongside reviewer-of-N is safe; never two writers' gates at once.
- Tweak next time: snapshot the list of unrelated untracked dirs at start (`git status --short`
  to a file) and diff it at each gate — the gate filter hid that an unrelated `_pi/` vanished.


## Audit lessons (RV-057)

- A design claim that a removed test was "replaced, not deleted" needs the replacement to assert
  the same property; check both halves (RV-057 F-1).
- pi audit lanes earn their keep on negative findings ("no test for X") only when the prompt
  demands a positive control for each claim.
