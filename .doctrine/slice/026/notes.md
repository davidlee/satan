# Notes SL-026: malebolge coding layer: project context, cwd, ripgrep grep

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-19 · ready (plan 8 phases, none started) · 8c5bcb3

### Produced
- scope + research round done; scope reshaped on research (commits d911161, 8256d4a), then rewritten against design decisions (slice-026.md, uncommitted)
- RFC-019 D7 table corrected: pi-durable bash already has `timeout`
- minted: CHR-020 (related, independent); DEC-070, DEC-071, DEC-072, DEC-073 (accepted, shape SL-026); IDE-012 (room setup step, deferred); REV-008 (SPEC-004 draft, apply at reconcile)
- design.md locked (run dr-01a152b2 rev 44) after RV-033; selectors `.doctrine/spec/tech/004/*`, `flake.nix`
- plan.toml / plan.md: PHASE-01..08 (commits 83018c0, 3179933, 8c5bcb3); phase sheets materialised

### Learned
- mem.pattern.doctrine.cross-corpus-id-collision — qualify foreign ids (oubliette DEC-052 ≠ satan DEC-052)
- mem.pattern.satan.research-jail-snapshot — research jail sees no sibling repos; launch over a snapshot
- doctrine verify checks in design runs need `doctrine` on PATH (else "no result produced"); not yet a memory
- pi-env reports a missing argv binary as `spawn_error`, not exit 127 (design §4.3); candidate memory at harvest
- rg `--json` ignores `--max-columns` and exits 2 after matches on any file error (RV-033 F-2, F-7); candidate memory
- the oubliette room floor is `git bash coreutils-full which` — no `find` (design §4.2); candidate memory
- cross-repo VT test_file paths are absolute (SL-023 convention); verify-vt FAILs until files exist

### Open
- ASM-006 — validated (live probe), closed
- RV-033 F-1 (probe) answered: transcription onto PHASE-03 EX-3/VT-2 repaired after the raiser's check; raiser re-verify pending. F-2 verified.

## Design triage (2026-10-19, explore stage, run dr-01a152b2)

### Findings that reshape the open questions
- **The runner has no system prompt sections.** Its extensions are
  `[JobTools, jobGuard]` (`malebolge/src/runner/start.ts:147`); the corpus
  prompt + policy fragments + job block go in as the conversation's first
  *input message* (`run.ts:348-354`, `composePrompt`). Context composed into
  that message lands in the durable transcript: fixed for the job's life,
  survives restart, needs no job-row field.
- **Runner cwd is the clone root** (`/work/goad-walk`, has `.git`), so a walk
  that stops at the nearest git root reads one directory there.
- **`~/notes` has `.git` and no `AGENTS.md`/`CLAUDE.md`**: under the same walk
  rule the daemon finds nothing until CHR-020 moves its cwd; CHR-020 need not
  land first.
- **goad-walk has no `AGENTS.md`/`CLAUDE.md`**: the slice's VH needs one added
  to that repo (the user's) before the live job.
- **Context files may carry harness-specific syntax** (malebolge's own
  `AGENTS.md` is a Claude `@`-import stub); pi renders them verbatim, and so
  will we.
- **ASM-006 validated** (live probe; record body has the evidence).
- **pi-env FileSystem ops exist** (`readTextFile`, `listDir`), but a room loss
  is classified only at the Connection seam; `roomShell` already does that for
  `exec` (mem.fact.pi-env.type-survives-only-at-connection).

### Constraining governance
SPEC-004 §Components (pure composition), §Job contract ("the repo itself
authors no policy"), §Execution environment (tool list); REQ-030 (deadline is
the wall-clock authority); DEC-056 (no default prompt text in malebolge);
DEC-067 (read-once constant section); ADR-017 §4 (degrade, not fail);
POL-001 (cutover, not copy); SPEC-002 NF-004 (jail probes), NF-005 (notes
read-only).

### Risks
- pi-durable API churn (pinned 1.3.0).
- A context file in a repo is untrusted text in the job's input; the DEC
  bounds what it can mean, not what the model does with it.

## Review passes (design, 2026-10-19)

RV-033 concluded: adversarial lane, three rounds, 22 findings (ledger holds them).
A further pass would probe only what the ledger leaves to instruments: F-1
(preparing bounds against hostile room binaries and FIFOs) and F-2 (grep
host-side memory bound) are routed `probe`; their adversary and criterion are
on RV-033 and `/plan` must transcribe them onto phase VTs, where the probe
itself runs. No further prose pass is needed: every other finding is verified,
and the two user decisions (F-16 no clean, fail `dirty_clone`; F-17 limits on
all `preparing` execs) are integrated. Residual: an independent GPT design
review was not run (codex MCP failed to connect this session).


## PHASE-01 — shared project-context module (2026-10-19, malebolge 4ac55fe)

Transcribed from the phase's progress notes (`phase-01.toml`).

- `just check` green.
- BOM stripped in `capSource` only: one strip point; `nodeSourceReader`'s
  `readCapped` does not strip separately.
- Empty sources are dropped in `readSources` (resolves the sheet's open
  empty-file question: a readable but empty file renders no block; pi would
  render an empty one).
- The `project_context` section is tagged, per design §4.6.

## PHASE-02 — room shell limits; preparing execs bounded (2026-10-19, malebolge 0c294ae)

Transcribed from the phase's progress notes and commit body.

- `just check` green.
- `OVERFLOW_EXIT_CODE = -1` (`src/runner/shell.ts`): the exit code of an exec
  the shell stopped for overflowing; meaningless, never branched on.
- Outcome precedence is a pure `settle`: exit → host_key → lost → caller
  abort → own abort (= `overflowed`) → else `ChannelFailed`. Loss stays ahead
  of the new mappings; a caller abort beats the shell's own overflow abort.
- Overflow on a non-status preparing exec (`test -d`, `rev-parse`,
  `switch`) fails closed as `ChannelFailed` (`notOverflowed`, `room.ts`);
  design §4.2 was silent on these. An overflowed `git status` is
  `dirty_clone`, complete lines only.
- `PREPARE_LIMITS` lives in `room.ts` beside `ShellLimits`.
- Finding: pi-env's exec timeout reaps a process blocked opening a FIFO
  (ENXIO probe).
- Finding (orchestrator): closing a local pi-env `Connection` does not kill
  its running children; a failing never-exit test leaks processes. Fakes use
  `exec sleep 30`, not `sleep infinity`; check leaks with `pgrep -x`, not
  `pgrep -f`. Candidate memory.
- Friction: `doctrine slice verify-vt 26` shows every malebolge VT as
  `UNATTRIBUTABLE` (it diffs the satan repo); expected for a cross-repo
  slice (observation `01a1535b`).

## PHASE-03 — runner fetch, doctrine step, classification (2026-10-19, malebolge a0efde5 Part A, 594a07f Part B)

Transcribed from the phase's progress notes and commit bodies. Run as two
worker passes (A: fixture, `readyRoom` `FinalStep`, room reader, probes
P1-P11; B: doctrine step, probes P12-P15), one commit each.

### Rulings
- **D-1 — PENDING USER DECISION (design deviation, flag at reconcile).**
  `regularFiles` runs one `stat -L --printf '%f %n\n'` from the clone root
  over absolute paths, matched back by full path, instead of design §4.2's
  "one `stat` per directory, with that directory as cwd". Reason: pi-env
  refuses an exec whose cwd does not exist (`spawn_error`), so per-directory
  cwd would degrade APPEND_SYSTEM (`missing`) on every repo without `.pi/`.
  Same exec count; still never opens a file. Accepted by the orchestrator and
  implemented; the user has not yet ruled. Design §4.2 needs amending at
  reconcile if accepted.
- D-7 accepted by the orchestrator: probe timeouts are time-scaled ×1/20 in
  tests by a wrapper over the real `roomShell` that asserts the production
  limits were requested; honest-binary FIFO cases run unscaled.
- D-3, D-4, D-5, D-8, D-9 sheet defaults accepted, except: the clone
  re-check rethrows a non-channel error (a bug) per D-5 rather than mapping
  it to `dirty_clone` per D-9 — still fail closed, never cleans.
- D-6: `admit` passes a no-op final step until PHASE-04 composes the result.

### Decisions in the code
- A-1: the test fixture's `readying.ready()` keeps returning the base oid;
  `readyWith(step)` was added for the final-step variant.
- A-2: the failure classifier takes the code from the `ExecutionError`
  cause, else from the error's `reason`.
- A whitespace-only (or whitespace-only overflowed) doctrine boot is `empty`.
- In `Fetched.degraded`, the doctrine degradation precedes reader
  degradations.

### Findings
- Probes while planning (local pi-env daemon): an exec with a nonexistent
  cwd → `spawn_error` ("Working directory does not exist"); a missing argv
  binary → `spawn_error`; `Connection({ command: ["env", "PATH=…",
  localDaemon()] })` makes execs resolve from that PATH; `git status
  --porcelain` lists no FIFOs; symlinks are tracked, so symlinked fixtures
  are committed in the base repo. Candidate memories.
- RV-033 F-1 raiser gaps covered: P4 (FIFO and `/dev/zero` symlink at
  `.pi/APPEND_SYSTEM.md`), P10/P14 (hostile `test`), P1-P4 assert < 3 s and no
  `head` argv.
- Tests: 1404 after A, 1458 after B; `just check` green after each.
- Friction: a single-file vitest run fails the global coverage gate; iterate
  with `--coverage.enabled=false` (observation `01a1537d`). An editor or
  formatter rewrote malebolge files between worker edits; one edit silently
  failed until `tsc` (observation `01a15372`).

## PHASE-04 (2026-10-19) — Composition and admission

Malebolge delta uncommitted (base 594a07f). `composePrompt` takes
`projectInstructions` as a required fourth input (rendered via
`renderProjectContext`, between fragments and job block); `PromptJob.cwd` adds
`Working directory:` after `Job branch:`. `EVENT_KINDS += context_degraded`.
`admit` passes `fetchProjectContext(repo)` as `readyRoom`'s final step, writes
one `context_degraded` per degradation via `appendEvent` (not `jobs.change`;
`Change.update` is required, nothing on the row changes) plus a `deps.log`
line, after the ready loop and before `openRun`. Prompt tests moved to
`test/runner/prompt.test.ts`; run-fixture gained `allowLog` / `logs`.
`just check` green, 1466 tests, lines 98.17%. verify-vt: PHASE-04 VT-1/2
UNATTRIBUTABLE (expected); PHASE-05/06 missing-file FAILs expected.
Accepted gap: a crash between the degradation writes and the submit redoes
`admit` on restart and writes that attempt's degradations again.

## PHASE-05 (2026-10-19) — grep tool

Malebolge delta uncommitted (base fb902de). New `src/grep.ts`: `grepArgv`,
`contextLines`/`matchLimit` clamps, `grepCollector` (bounded splitter at
`MAX_MESSAGE_BYTES` = 1 MiB, parse-time 500-char truncation, stderr
`headKeeper` at 4 KiB, stops at limit or the 50 KB budget), `runGrep` (the
testable seam over `Pick<ExecutionEnv,"cwd"|"exec">`), `grepTool`
(`replay: "safe"`) and `grepExtension`. `src/ndjson.ts`:
`boundedLineSplitter`; `lineSplitter` is now its `maxBytes: Infinity` case
(index scan, no per-line re-slice). `src/truncate.ts`: `headKeeper`;
`shell.ts outputCollector` rebuilt on two of them. `JobTools` = coding tools
+ `grepTool` (five; read and grep replay-safe).

Decisions: 50 KB by reservation (lines stop at 50 KB − 5 KiB so notices
always fit); notice order limit, 50 KB, pi's line-truncated, oversize,
stderr; `REPLAY_SAFE` unchanged; `requireEnv` not public, inlined; abort via
`withAbortSignal(own.signal, context)`. No flake touched (R1 rejected).

EX-2 evidence: VT-2 asserts structurally through `grepCollector.stats()`
(peak carry ≤ 1 MiB, kept ≤ 50 KB, stderr ≤ 4 KiB, result ≤ 50 KB) over lazy
generators (64 MiB line, 200k submatches, binary/malformed, 1000 × 100 KB,
8 MiB stderr, no-newline stream ended by caller abort). Negative control:
the same probe over an uncapped splitter exceeds 1 MiB; mutation (collector
cap → Infinity) fails three VT-2 cases.

Findings: rg ignores `.gitignore` outside a git repo (VT-3 `git init`s);
embedded newlines in hostile `lines.text` are not sanitised (bounded).
`just check` green, 1512 tests, lines 98.16%.

## 2026-10-19 PHASE-06 — Daemon wiring

`src/cwd.ts` `cwdExtension` (untagged `cwd`, `Current working directory: <path>`,
D-2 ruling); `src/daemon-extensions.ts` `daemonExtensions(parts)` holds the
ordered list [persona, projectContext, skills, cwd, CodingTools, grep, satan]
(D-1; a plan addition beyond design §5, flag at reconcile); `daemon-main.ts`
reads context once (`renderProjectContext(readSources(cwd, gitRootDirs, nodeSourceReader))`),
and its startup log says whether project context was found.
`test/daemon-sections.test.ts` (4 tests): fresh order, omission, and the
existing-conversation case, which shows exactly pi-durable's remove-all/re-add-all
pair as derived from `planSections`.

Findings: `harness.close` closes MemoryStorage, so the reopen case uses temp sqlite.
`systemPromptSections` returns entries newest first (doc comment says oldest);
test reverses it. `just check` green, 1516 tests, lines 98.24%. Delta uncommitted
in malebolge. Phase status not flipped.

## 2026-10-19 PHASE-07 — Corpus, fleet, docs

Done (all uncommitted; orchestrator commits): malebolge `flake.nix` +
`flake.lock` (doctrine input), `docs/internals.md` (components diagram,
Sections, Project context (sources), grep notes); satan `flake.nix`
(probe + comment). **Corpus T1 NOT done**: the worker's one Bash call to edit
`~/satan-corpus/prompts/patch-agent.md` and `interactive.txt` was denied by
the auto-mode classifier, and the denial bars retrying the outcome by another
tool. Left for the orchestrator/user (EX-1 open).

Decisions: corpus commit must stage the two prompt files by path, never
`just commit` (orchestrator ruling). doctrine input in malebolge has a system
guard (`doctrine.packages ? ${system}`), no `follows`: doctrine publishes only
x86_64-linux and aarch64-darwin, malebolge also lists aarch64-linux. The
guard sits in `devToolPkgs`, so `dev-tools` and the devshell both carry it.

Ripgrep reconciliation: no package added. `ripgrep` is already in the jail
PATH twice (devToolPkgs, and the jail library base profile), and the room
supplies `rg` from its base. The satan probe `${pkgs.ripgrep}/bin` asserts
availability, not which list supplies it; removing it from `devToolPkgs`
would not turn the probe red.

Evidence: `nix flake lock` in malebolge added only the doctrine node and its
transitive inputs (flake.lock: sole removal is the root's inputs line).
`nix build .#dev-tools` has `bin/doctrine`. malebolge `just check` exit 0 and
`nix flake check` green; satan `nix flake check` green. VT-1 negative control:
probe changed to `${pkgs.ripgrep}/binX` -> `malebolge-jail-profile` failed
with "launcher must contain '/nix/store/...-ripgrep-15.2.0/binX'"; reverted,
green again. No elisp touched, so satan `just check` not run.

Docs describe what is implemented: runner chain is clone-root only, via one
`stat -L` (PHASE-03 D-1); daemon wiring includes `daemon-extensions.ts`
(PHASE-06 D-1). Neither pending decision reworked.
