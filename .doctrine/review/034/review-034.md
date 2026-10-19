# Review RV-034 — reconciliation of SL-026

Adversarial-review ledger. Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

Conformance audit of SL-026 against design.md (locked, run dr-01a152b2),
plan.toml EX/VT, DEC-070..073 and RV-033's probe obligations. Surface: the
main worktrees — malebolge 4ac55fe..fe7030a (+ 55f4a68 fix-now), satan
53da640, satan-corpus 9868f4c. Not a dispatched slice.

Lines of attack:
- every VT maps to a test that exercises its expectation, not just its keywords;
- implementation vs design §4.1–§4.7 and §5: every divergence named;
- RV-033 F-1 (hostile repo in preparing) and F-2 (grep host memory) met by
  real-shell tests;
- DEC-073: repo text never reaches runner policy; the job block stays last
  and byte-identical;
- abort, overflow and timeout ordering in the room shell; untrusted reads
  bounded in memory and time.

Evidence: malebolge `just check` green (1516 → 1523 tests after fix-now,
lines 98.24%); satan `doctrine check gate` green; `nix flake check` green in
both repos (PHASE-07 notes, with a VT-1 negative control); live VH-1 probe
job pj-01M59WZMDH8063J8RA97TSBMVF accepted by the user. `slice conformance`
is blind to cross-repo code (F-14), so the VT mapping below was done by
reading malebolge.

## Synthesis

SL-026 delivers what the design set out: both malebolge agents now carry the
repo's project instructions (AGENTS/CLAUDE chain, `.pi/APPEND_SYSTEM.md`, and
for the runner a doctrine boot), a working-directory line, and a bounded
ripgrep `grep` tool. The live probe showed all three sources in the patch
agent's first message, in design order, `grep` running in the room, and no
attempt at the doctrine workflow — the precedence paragraph worked on
deepseek-flash.

VT mapping: every PHASE-01..07 VT maps to a test that exercises it
(project-context, truncate, shell over a real local daemon, prepare,
runner project-context + 16 probe cases, prompt, run, grep incl. six hostile
F-2 inputs, tools, daemon-sections; satan jail probe with negative control).
Three §6/EX items were weak (F-10) and are now covered.

Trust boundary: DEC-073 holds — `resolvePolicy` takes no context (checked by
type), the job block depends only on the job and comes last. A hostile
source can still print a fake job block inside its own element; the design
accepts it (rendered as is), and collection's path check is unaffected.

Closure story: no blocker. One major (F-1, D-1 stat mechanism) and seven
spec-text drifts are design-wrong — the code is the better truth and the
design must catch up at reconcile. Five code/doc/test items were fixed now
(malebolge 55f4a68, satan ef5cd28). Two tolerated with rationale.

Standing risks:
- grep has no exec timeout (F-13): fine under the job deadline and an
  attended daemon; revisit if grep gains unattended daemon use.
- degradation events are at-least-once (F-3).
- doctrine's tool cannot see cross-repo code (F-14); audits of malebolge
  slices must read the repo directly.
- room clones have no git author identity (ISS-049); bun has no DNS in the
  room (ISS-048). Both outside this slice.
- the model miscounted its own grep results in the probe — model quality,
  not mechanism; worth watching if grep summaries feed decisions.

Tradeoffs accepted: D-1 over the per-directory stat; appendEvent over
jobs.change; pi parity for notices and cwd wording; doctrine input guarded
and unfollowed at the cost of a second nixpkgs in malebolge's lock.

## Reconciliation Brief

### Per-slice (direct edit)
- design.md §4.2 (F-1): replace the per-directory `stat` (directory as cwd)
  with one `stat -L` per directory run from the clone root over absolute
  paths, output matched by full path; state why (absent `.pi/` must not read
  as `missing`). Pending the user's ruling on D-1.
- design.md §4.3 (F-2): `context_degraded` is written with the store's
  `appendEvent`, not `jobs.change`.
- design.md §4.2 (F-3): at-most-once holds for the fetch per admitted prompt;
  its `context_degraded` events are at-least-once (a crash before submit
  re-writes them; a cancel before admission leaves them).
- design.md §4.2/§4.3 (F-7): overflow on existing preparing execs →
  `ChannelFailed`; non-channel re-check errors rethrown; a re-check
  `test -d` failure → `guest_path_invalid`; `Degradation.source` may name a
  directory.
- design.md §4.5 (F-4): add the 500-char truncation notice; the 50 KB cap is
  a reservation stop (~45 KB of matches), notices never cut.
- design.md §4.6 (F-8): cwd section text is `Current working directory:
  <path>`, untagged; check DEC-056 (`doctrine show DEC-056`) and raise if it
  conflicts.
- design.md §4.7 (F-6): doctrine input is `lib.optional (doctrine.packages ?
  system)`, no `follows`; lock gains a second nixpkgs.
- design.md §5 (F-5): add `src/daemon-extensions.ts`, `ndjson.ts`
  `boundedLineSplitter`, `truncate.ts` `headKeeper`/`GREP_MAX_LINE_LENGTH`,
  shell `settle`/`outputCollector`/`OVERFLOW_EXIT_CODE`, the
  FETCH/HEAD/DOCTRINE limits, grep's `spawn_error` → tool error, and
  `fetchProjectContext(repo, checkClone)` taking the channel seam (F-12).

### Governance/spec (REV)
- SPEC-004 (design §4.7, planned): §Components (composition input), §Job
  contract (DEC-073; `preparing` reads context per DEC-071/DEC-072, with the
  D-1 mechanism), §Execution environment (tools read, write, edit, bash,
  grep; read and grep replay-safe), audit vocabulary (`context_degraded`,
  at-least-once). Applying it delivers the `.doctrine/spec/tech/004/*`
  selector (F-14).
