# Notes SL-023: Patch runner for the oubliette assistant room

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Pre-design research (2026-10-18)

Research artefact (gitignored, on disk): `.doctrine/slice/023/research/research.md`
+ `raw/` — five threads (governance, elisp runner, Go satan-patcher, oubliette
door, malebolge/pi-durable/pi-env) and an option-D spike. Leading candidate:
**option D** — a daemon runner hosting a pi-durable harness on the host, tools
in the room via pi-env; both existing runners retired (logic ported, not code).
Oubliette SL-005 consumes the same file (its X6/X7 cross-check is in it).

## Design triage (2026-10-18, run dr-01a14d77)

Input: research F1–F9, deltas 1–7, EVD-005. Terms: *room* = persistent
oubliette microVM; *door* = Plan F §5 ingress (agent user, runner key, relay
socket); *quarantine* = host bare repo guest commits are fetched into.

**Constraining governance**
- POL-001 — earns-the-seat (queue/dispatch/fetch: No; promotion UI: Yes);
  Rust target with workload-fit exceptions; cutover not addition; disable
  switch; ceilings hold with Emacs absent; ert corpus → acceptance fixtures.
- ADR-017 §1 (Emacs owns approval surfaces), §3 (one owner per item; ledger
  INV-1..3), §4 (fail closed client-absent).
- ADR-018 D1 (one daemon repo — none exists yet; `~/dev/satan-attrd` is a
  single Rust crate), D3 (Postgres state, control plane UDS RPC; no new
  `pg_notify` control traffic, VT-3), D5 (no new stateful layer in elisp),
  OQ-2/OQ-3 open (don't front-run the global RPC shape).
- SPEC-001 REQ-003 audit, REQ-004 ceilings, REQ-005 kill switch fails closed,
  REQ-007 lifecycle is request/response, REQ-009 no dual enforcement,
  REQ-010 fail closed. SPEC-002 REQ-013 one schema owner per store (today
  `patch_jobs`: elisp 0005 + Go 0006). SPEC-003 OQ-3 (SL-023 picks the
  surviving runner and its spec). DEC-049 (no credential row), DEC-043
  (gateway budgets ≠ SATAN ceilings), oubliette DEC-031 (room stops routine).

*Superseded by the inquiry outcome: DEC-050..DEC-064 and REV-006 are
authoritative; the lists below are the pre-inquiry triage.*

**Shaping decisions (proposed)** — option D; both runners retired (logic
ported); Emacs keeps producer tool, inbox, promotion.

**Open questions** — QUE-005 (glue language/repo), QUE-006 (room down);
store layout; control socket + auth (RSK-018); replay-safe tools; per-job
ceiling; audit writer for patch jobs (row 4 forbids a third writer);
`patch_jobs` contract owner + ISS-041; who enacts promotion; ledger rows;
runner spec home.

**Assumptions** — ASM-005 (door as sketched). Door-touching decisions
(room addressing, quarantine fetch) defer to oubliette SL-005's design;
build against slot f / a stub until then.

**Risks** — pi-durable/pi-env are experimental ("changes without notice") →
pin versions; designing against a sketched door; half-extraction during
cutover (two consumers live, ISS-039).

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-18 · design locked (run dr-01a14d77 rev 44); plan written, 14 phases materialised, slice ready · e8f4012 + uncommitted

### Produced
- SL-023 scoped, linked (IDE-007/008, RFC-018, ISS-030/038/039/041, IMP-006; governed_by POL-001, ADR-017, ADR-018) — 42b2dea
- IDE-007 gateway-key wording corrected — 42b2dea
- research round + option-D spike against capsule slot f — artefact on disk, not committed
- design run inquiry complete: DEC-050..DEC-064 (shape SL-023); inq-14 deferred on ASM-005 — uncommitted
- REV-006 applied: ADR-018 D1/D3 scope amendment, POL-001 IMP-006 destination — uncommitted
- IMP-041 (malebolge lint → typescript-eslint, before runner code) — uncommitted
- slice scope aligned to the decisions (objective 7 added) — uncommitted
- design.md drafted: 14 sections materialised, design-target selectors recorded; user rulings on §6 OQ-1..OQ-6 and pre-ready fixes 1-6 applied; DEC-052 (ordered creation) and DEC-058 (ack op, failure resend) amended with revision notes; `drafting-ready` recorded — uncommitted
- DEC-056 amended (recovery before resume); run advanced to reviewing; Codex (gpt-6-sol) pass on RV-025: 14 findings (4 blocker, 9 major, 1 minor), all accepted fix-now and integrated; F-1/F-2 routed demonstrate (model gate, env-boundary failure typing), rest review; DEC-055 and DEC-057 amended — uncommitted
- RV-025 third pass: F-4, F-8, F-13, F-15..F-19 verified; F-19 raised; DEC-057 note (warning placement via submission record) — uncommitted
- design locked 2026-10-18: section attestations, review-disposed (conducted RV-025), design-accepted; slice-023.md risks/closure reconciled — uncommitted
- plan.toml + plan.md (PHASE-01..14), phase sheets materialised, slice status ready — uncommitted
- slot f left running; its volume holds `~/sl023-spike` and the pi-env daemon in `~/.pi`

### Learned
- pi-durable: no hook can deny a request (throwing hooks are skipped); tool/env exceptions are converted before afterTool; submit/abort/compact/wait start the task scheduler
- doctrine orders design sections by id *lexically* (sec-10 before sec-2) and has no section delete; bodies were rebound so reading order holds
- pi-durable 1.3.0 `beforeRequest` rewrites messages only — no per-request maxTokens hook (design §6 OQ-1)
- EVD-005 — pi-env drives a slot through its relay; dropped connection fails one tool call, run recovers
- mem.pattern.satan.pi-env-oubliette-gateway — recipe: pi-env via relay ProxyCommand, pi-ai via the gateway
- pi-durable: one SQLite file may hold pi tables (prefix) and host tables via one adapter; built-in tools declare no replay (unsafe) — cited in DEC-052/054
- Biome 2.5 lacks tsc-backed unsafe-any / strict-boolean / assertion rules — IMP-041

### Open
- design §6 OQ-1 — model gate; PHASE-01/EX-2 demonstrates it; on failure /consult and amend DEC-057 (weaker guarantee, user ruling)
- RV-025 — concluded and disposed conducted; F-1/F-2 (BLOCKER, demonstrate) answered, transcribed into PHASE-01/EX-2 and EX-3; verify on RV-025 after the spike
- Further review passes (2026-10-18, after RV-025 concluded): none before lock. Three Codex passes converged; the last rounds found only wording and one crash-window edge. What remains unproven is empirical, not textual: the model gate (F-1, OQ-1), pi-env failure typing and the wrapper's host write (F-2, F-17), steer placement mid-run and status() leaving scheduling paused. The first-phase spike is the next probe; a re-review is warranted only if the spike fails and DEC-057/DEC-055 are amended.
- ASM-005 — oubliette SL-005 pins the door as Plan F §5 sketches (room adapter, door config, promotion verb wait on it)
- QUE-005, QUE-006 — answered (DEC-051, DEC-055)

## PHASE-01 spike — offline half (2026-10-18, worker)

### Produced
- malebolge: pi-env 1.3.0 pinned exact; spike tests `test/runner/{model-gate,steer-status,env-pause}.test.ts`, fixtures `test/runner/{runner,gate,env}-fixture.ts`, `openFauxHarness` in `test/harness-fixture.ts`; live spike `test/runner/room-stop-spike.ts` + `just spike-room-stop` (results in gitignored `spike-results/`) — uncommitted
- EVD-006 (model gate in every provider path), EVD-007 (steer placement, passive status), EVD-008 (pause mark on shared adapter, durable before afterTool), EVD-009 (pi-env exec erases the lost type)

### Learned
- OQ-1 holds at pi-durable 1.3.0: a Proxy Models view over `streamSimple`/`completeSimple` gates generation, retry (generation re-entry) and compaction (manual and threshold); counter on the shared adapter survives reopen (EVD-006). DEC-057 needs no amendment on that ground.
- The view does NOT gate: `fetchDeferred`/`cancelDeferred` (poll/cancel of an admitted deferred request), and the ungated `complete`/`stream`/`classify`/`generateImages` that tools reach through `api.models` (the same view object). Coding tools never call models; codemode does. DEC-057 "every provider call" wording is the orchestrator's/user's call.
- Gate refusal text must avoid pi-ai's retryable pattern (`overloaded`, `5xx`, `connection.?lost`, …) or the retry policy re-asks a refused gate.
- pi-env 1.3.0 `exec()` drops the RemoteError (ExecutionError `unknown`, no cause); file ops keep it as `FileError.cause`. The type survives at a `Connection` subclass — which must observe `info()`/`session()` as well as `request()` (a file op can lose the connection resolving its path). DEC-055's `ExecutionEnv` placement cannot recognise a lost room on `bash` by type (EVD-009) — placement decision is open (S2), pending the live run.
- Host writes on the shared adapter from the env seam and reads in `afterTool` settle: both run outside pi storage transactions (EVD-008).

### Open
- EX-3 live: human runs `capsule f start` (if stopped) → `just spike-room-stop` in ~/dev/malebolge → `capsule f stop` at the IN FLIGHT marker → `capsule f start`; then an EVD from the results file.
- DEC-055 placement (Connection seam vs ExecutionEnv) — to the user via the orchestrator.
- RV-025 F-1/F-2 verdicts — orchestrator.

## PHASE-01 close (2026-10-18, orchestrator)

### Produced
- EVD-010 — live room stop (`capsule f stop` mid-exec, slot f): Connection seam saw two typed lost RemoteErrors (codes `unknown`, `spawn_error`), durable mark settled <=5 ms; ExecutionEnv seam saw a plain ExecutionError (isConnectionLost false); a same-message ordinary error was not recognised. Results: `~/dev/malebolge/spike-results/room-stop-2026-10-18T07-38-01.165Z.json` (gitignored).
- RV-025 F-2 verified as raiser against EVD-010 + EVD-009 (F-1 verified earlier against EVD-006).

### Exit criteria
- EX-1 pi-env 1.3.0 pinned (malebolge c3fa08e). EX-2 EVD-006. EX-4 EVD-008 + EVD-010 (markSettledMs). EX-5 EVD-007.
- EX-3 met at the Connection seam, not literally at an `ExecutionEnv` wrapper: EVD-009/EVD-010 show the type is erased there. DEC-055 amended by user ruling (2c01639): per-job Connection subclass over info()/session()/request(), idempotent mark. Recorded class/code: RemoteError, `unknown` and `spawn_error`, lost true.
- EX-6 evidence EVD-006..010; F-1, F-2 verified; DEC-055 and DEC-057 amended.

### Drift (for /audit -> /reconcile; locked design not edited)
- design.md §5.4, and any section naming the ExecutionEnv wrapper as the recognition point or the gate as streamSimple/completeSimple only, drifts from amended DEC-055 / DEC-057. The DECs govern.
- plan.toml criteria worded on the pre-amendment DECs (left unrewritten; ids immutable — phase planners for 07-09 plan to the amended DECs):
  - PHASE-07/EX-3: env.ts must also pass the per-job Connection subclass (RemoteExecutionEnvOptions.connection).
  - PHASE-08/EX-1, VT-1: gate names only streamSimple/completeSimple; DEC-057 now also gates fetchDeferred, cancelDeferred and runtime.models complete/stream/classify/generateImages/streamDeferred; refusal avoids pi-ai retryable wording.
  - PHASE-09/EX-1: "env wrapper ... before rethrow" becomes the Connection subclass with an idempotent mark (one stop raised two lost failures).

## PHASE-02 quality gates (2026-10-18, worker)

### Produced
- malebolge (uncommitted, for the orchestrator): `eslint.config.js` (typescript-eslint strictTypeChecked + stylisticTypeChecked, projectService, IMP-041 rule list), `tsconfig.json` (DEC-053 flags), `vitest.config.ts` (V8, `src/**`, `src/*-main.ts` excluded, lines >= 85), `justfile`/`package.json` (`fmt-check` = `biome format .`, `lint` = `eslint . --max-warnings 0`, `check: fmt-check lint typecheck test`), typescript pinned 6.0.3 (T0 option A; CHR-015 covers TS 7).
- `src/json.ts` `isRecord` — the one narrowing guard for parsed JSON (protocol, models store, render wire decode, test fixtures, spike).
- `src/render.ts` dispatches through an exhaustive `Handlers` table keyed by event type (a new AgentEvent type fails to compile); `toPrintable` decodes a wire line (discriminant check only, the daemon is a trusted peer). Answer-text tracking across message_start/update/end unchanged; render tests now go through `toPrintable`.
- 0 inline eslint-disable. 86 -> 103 tests. Coverage baseline (ratchet start): lines 94.96%, statements 94.42%, branches 83.22%.

### Learned
- `import-x/no-duplicates` autofix (default `prefer-inline: false`) merged `import type {A}` into `import {type B, c}` as `import type {A, type B, c}` — invalid, and vitest/oxc refuses to parse it. Config now sets `prefer-inline: true`; one file needed a manual repair.
- `complexity: 8` counts every `case` label, so a switch over pi-durable's 25-member `AgentEvent` cannot pass; a mapped `Handlers` table (`{ [E in Printable as E["type"]]: E }`) plus a generic `dispatch(handlers, type, event)` passes both complexity and exhaustiveness without an assertion.
- `switch-exhaustiveness-check` at defaults flags a `default:` that hides union members; use `"block" in change` narrowing or enumerate the members.
- Hoisted function declarations lose a top-level `const` narrowing (spike `slot`): pass the narrowed value in.
- Biome's `files.includes` (in the user's dirty `biome.json`) covers `src/**`, `test/**`, `*.json` only — root `eslint.config.js` / `vitest.config.ts` are not format-checked.

### Open
- `biome.json`: add root `*.ts`/`*.js` to `files.includes` and set `linter.enabled: false` (user's file; not touched).
- Behaviour edges taken while removing assertions (judged non-functional, listed for audit): `withMissingModels` now adds only chat models to `getModels()` (all to `getAllModels()`; new test); `readModelsStore` returns `{}` for a non-object store and drops entries lacking string `id`/`provider`; `attach` throws "not an event" on a non-object line (was a TypeError); daemon-main logs and exits 1 on a failed signal-stop (was an unhandled rejection); `persona` render extracted as `readPersona`, plus an integration test reading the rendered section from a turn's system entry.

## PHASE-03 batch A (2026-10-18, worker)

### Produced
- malebolge (uncommitted): `src/fields.ts` (shared untrusted-JSON readers incl. `onlyKeys`, `required`, `setDefined`; `src/protocol.ts` now reuses them), `src/runner/{errors,vocab,config,classify,protocol}.ts`, tests `test/fields.test.ts`, `test/runner/{config,classify,protocol}.test.ts`, fixture `test/runner/config-fixture.ts`; `smol-toml` 1.9.1 dependency. 151 -> 292 tests; lines 96.44%.
- config: closed tables at every level; ladder layers are `PolicyLayer`; repos/modes/tags are `Map`s. classify: allowlist + table. protocol: 8 ops via a `Handlers` table, `checkSubmit` with a `SUBMIT_CHECKS` seam for the ceiling-maximum check (batch B).

### Learned
- `no-misused-spread` forbids `[...string]`; a regex table is the lint-clean and clearer form for the `check-ref-format` shape rules.
- `explicit-function-return-type` does not exempt arrows inside tuple-typed arrays; use data (regexes) instead of predicate tables.
- Plain-object lookups by user-chosen names (repo, mode) must use `Map`: `toString`/`__proto__` otherwise resolve.

### Open
- Cancelled-with-clean-commits class is `partial` (design table says only "class recorded"); confirm at audit.
- `base_ref` existence (refs/heads) is the git layer's, PHASE-05/06.

## PHASE-03 batch B (2026-10-18, worker, opus)

### Produced
- malebolge (uncommitted): `src/runner/policy.ts` (ladder, `pickTagRule`, `checkCeilingsWithinMaxima`, `configEntry`), `src/runner/prompt.ts` (`composePrompt`), `src/runner/ceilings.ts` (`closeSegment`, `activeWallClockMs`, `remaining`, `exhausted`, `maxTokens`, `shouldWarn`), `src/runner/jobs.ts` (`TRANSITIONS`, `TERMINAL`, `transition`, `cancel`, `markPauseRequested`, `parseJobState`, `recoveryPlan` + `RECOVERY_TABLE`); tests `test/runner/{policy,ceilings,jobs}.test.ts`. Touched batch A: `protocol.ts` (`SUBMIT_CHECKS` = knownMode + ceilingsWithinMaxima; repo/mode via `configEntry`), `config.ts` (`ceilingsFrom`), `vocab.ts` (`isJobState`). 539 tests; lines 97.15%.

### Learned
- `unicorn/no-array-reduce` is on: fold layers with a `for` loop.
- Arrow members of an interface-typed object array (`RECOVERY_TABLE: readonly RecoveryRow[]`) pass `explicit-function-return-type`; arrows in a function-typed tuple array (`SUBMIT_CHECKS`) do not. Named functions there.
- `exactOptionalPropertyTypes` makes "row with a null column" fixtures awkward: build the minimal record as a constant and spread the optional field in, rather than passing `undefined`.

### Open (for /audit to reconcile)
- Settled-beats-pause ordering in the `running` recovery rows: reverted by orchestrator: pause precedes settled, per design §5.4 order and the crash-after-abort window.
- `resolvePolicy` refuses an unknown mode/repo at preparing (config changed since submit) — not stated in design; fail-closed reading of I13.
- Pure model uses epoch ms and booleans; PHASE-04 store maps to TEXT timestamps and INTEGER flags.
- `cancel` stamps `end_reason = cancelled` on queued/preparing too (design only implies it after a run).
- `exhausted` order: `ceiling_exceeded` before `usage_unavailable`.
- Prompt "notes" convention wording is the worker's; corpus prompt may restate it.
- Cancelled-with-clean-commits class `partial` (from batch A) still open.

## PHASE-04 (worker, opus)

### Produced
- malebolge (uncommitted, for the orchestrator): `src/runner/store.ts` (`MIGRATIONS` [v1], `migrate(db, migrations)`, `JobStore` with `submit` / `change` / `transition` / `cancel` / `markPause` / `appendEvent` / `get` / `bySubmission` / `list` / `events`, `openRunnerStore(path, { newId })`, `PI_PREFIX`), `src/runner/rows.ts` (`Job`, `NewJob`, `JobEvent`, the column codec table `JOB_CODECS`, `encodeJob` / `decodeJob` / `encodeEvent` / `decodeEvent` / `decodeSchemaVersion`, `columnOf`, `JOB_FIELDS`), `src/runner/ids.ts` (`newJobId(now, random)` hand-rolled ULID, `systemJobIds`); `vocab.ts` gains `EVENT_KINDS`, `isEndReason`, `isJobClass`, `isEventKind` over one `memberOf` guard (`isJobState` now uses it); `fields.ts` exports `isStringArray`. Tests `test/runner/{store,rows,ids}.test.ts`, fixture `test/runner/store-fixture.ts` (`openTestStore`, `NEW_JOB`, `sequentialIds`, `T0`). 539 -> 600 tests; lines 97.15% -> 97.77%. 0 inline eslint-disable.
- OQ-A ruled (a): v1 `jobs` carries `ceilings TEXT NOT NULL DEFAULT '{}'` after `source`; otherwise the §5.3 DDL verbatim (comments included) plus the two append-only triggers. `job_schema` is created by the migrator (`IF NOT EXISTS`, seeded 0).
- `change(id, now, decide)` is the one read-modify-write path: read, `decide(job)` (jobs.ts patch), write only the patched columns + `updated_at`, append the event, all on the `tx` handle in one `BEGIN IMMEDIATE`. Later phases add callers by widening `JobUpdate` (today `Partial<JobPatch>`).

### Learned
- `sqlite_master` holds `sqlite_autoindex_*` objects for PRIMARY KEY/UNIQUE columns, including `sqlite_autoindex_pi_document_revisions_1` for pi: partition host vs pi objects by `tbl_name`, not by name prefix.
- No-`as` codec: a non-homomorphic mapped type `{ [K in JobField]: Codec<Job[K]> }` (keeps `undefined` in optional fields' types, unlike `-?`) plus a generic `<K>(job: Pick<Job, K>, field: K)` indexes the table without assertions; decode still lists fields once (required in the base, optional via `setDefined`) because building a typed object from a loop needs a cast.
- `explicit-function-return-type` flags arrows inside an object literal returned from a generic arrow; use a function declaration with a typed `const codec: Codec<T>`.
- vitest `%j` in a test name throws on `bigint` (JSON); use `%s`.

### Open (for /audit to reconcile)
- Drift: `jobs.ceilings` column (OQ-A) is not in design §5.3.
- Timestamps are ISO-8601 UTC ms text limited to years 1970-9999 (A1; keeps lexical = time order). Equal-ms `created_at` ties: `list` orders by `created_at, id`; the scheduler (PHASE-07) should do the same or use `rowid`.
- Submit is SELECT-by-`submission_id` then INSERT inside the one `BEGIN IMMEDIATE` (the sheet sketched `INSERT … ON CONFLICT DO NOTHING`); the UNIQUE constraint remains the backstop.
- `submitted` event payload is the `NewJob` as passed (validated request without `op`/`requestId`). Transition payload is `{ ...caller, from, to }` plus `endReason` when the patch sets it (cancel, A3).
- `openRunnerStore` does not close the database when `migrate` refuses (runner start refuses and exits); revisit if a long-lived process ever retries opens.
- I2 "no other process opens the file" is operational (PHASE-12 unit); in code `migrate` is called only by `openRunnerStore`.

## PHASE-05 (worker, opus)

### Produced
- malebolge (uncommitted): `src/unix-socket.ts` `serveUnix` + `UnixServer` (generic half of the daemon's `serve`; `daemon.ts` now only `attach`/`act`, `Daemon = UnixServer`); `src/runner/git.ts` (`runGit` exec helper, read-only `RepoReader` = `checkBranchName` + `resolveBranch`, `checkBaseRef`); `src/runner/views.ts` (`summary`, `resultBody`, `jobChangedFrame`, `REPLAY_STATES`, `isReplayed`); `src/runner/control.ts` (`serveControl`, `ControlDeps`, `Conversations`/`harnessConversations`, `CancelJob` port; ops via a mapped `{ [K in Op]: Operation<K> }` table); `src/runner/start.ts` (`runnerPaths`, `startRunner`); `src/runner-main.ts` + `package.json` bin `satan-runner` + `just runner`. Store: `JobUpdate` widened with `conversationId`/`announcedAt`; `JobStore.observe` (after commit; a throwing listener is skipped); `cancel(id, now, payload?)`. `vocab.EVENT_KINDS` += `conversation`, `announced`. `rows.isoTime` exported (time codec encodes through it). `errors.StartRefused`. `config.modelsStorePath(home)` shared by daemon and runner.
- Tests: `test/runner/{control,runner-main,git,views}.test.ts`, fixtures `control-fixture.ts` (NDJSON client), `git-fixture.ts` (isolated real git), `refusal-fixture.ts` (`codeOf`/`rejectionCode`, replacing five copies in policy/jobs/protocol/store/git tests). 600 -> 662 tests; lines 97.77% -> 97.69%. 0 inline eslint-disable.

### Learned
- pi-durable `ConversationId` is a branded **number**, not a string; `jobs.conversation_id` is TEXT, so the id is stored as `String(id)`. No public constructor turns text back into a `ConversationId` (and `as` is banned): PHASE-07 must find another way to reopen a job's conversation (a query by id, or a codec column change).
- Watch needs more than subscribe-before-read: transitions observed while the replay set is being read must be held and sent after the replay, or a stale replayed state (`needs_review`) can follow a newer live one (`promoted`). Both properties are mutation-tested (`RacingStore` in control.test.ts).
- An observer lives on one `JobStore` instance: the scheduler (PHASE-07) and control server must share the instance `openRunnerStore` returns, or watch misses the scheduler's transitions.
- `git check-ref-format --branch` exits 128 on refusal; `rev-parse --verify --quiet` exits 1 on absence and 128 outside a repo. `@` is accepted by git but refused by the shape check (expected direction).
- typescript-eslint `no-unused-vars` does not ignore rest siblings here: build `NewJob` field by field rather than `{ op: _op, ...rest }`.

### Deviations from the sheet
- `RepoReader` has no `branchExists`: existence is `resolveBranch(...) !== undefined` (one verb fewer, same `refs/heads/<b>^{commit}` read).
- `controlSocketPath` lives in `start.ts` as `runnerPaths(env).socket` with the store and config paths (env resolution in one place).
- `result` body also carries `jobId` and `state` (additive), so a client can tell an uncollected answer.
- A refused promotion (`receipt_mismatch`) is audited: `disposition` event `{disposition, branch, outcome: "receipt_mismatch", message}`; a verified promotion stays a `transition` event carrying `{disposition, branch, verifiedOid}` as the sheet said.

### Open (for /audit to reconcile)
- ConversationId text round-trip (above) — PHASE-07 blocker-in-waiting.
- Submit's conversation creation failing after the insert leaves a queued job with `conversation_id` null and drops the connection (S11); a resubmit returns that job. PHASE-07's recovery row for "queued, no conversation" must create it.
- S11 as ruled: non-RunnerError → logged to stderr, no response, connection destroyed; tested with a throwing `RepoReader`.
- `checkSubmit`'s default branch (config `default_branch`) is not shape-checked before reaching `git check-ref-format --branch`; git refuses option-like names itself (`-x` → 128), so it fails closed.
- `ack` is per job (S10): all ids and states are checked before any write, but the writes are separate transactions.
- R6: `lineSplitter` buffers unbounded per connection (same-uid only).
- `openRunnerStore`/`Harness.open` failures in `startRunner` leave the database open; the process exits on refusal.

## PHASE-06 (worker, opus)

### Produced
- malebolge (uncommitted): `src/runner/room.ts` (port `GitChannel` {refresh, collect → `{ quarantine, ref, oid }`, reachable}; `ChannelUnavailable` / `ChannelFailed`; `jobBranch`; slot adapter `slotChannel(door, cli, reader)` over a `SlotCli` port with `execCapsule`; one-function argv builders `provisionArgs` / `collectArgs` / `probeArgs` / `returnToWorkArgs` (PROVISIONAL) and `collectedJobRef`; `channelFromConfig` and `roomConnection` (Q3: PHASE-07's env.ts calls it), both `StartRefused` without the door keys); `src/runner/collect.ts` (`collectJob`, `retryPendingCollection`, `CollectDeps` = {jobs, channel, quarantine, config}); `src/runner/exec.ts` (`runProgram`: the one subprocess helper, 64 MiB maxBuffer; `runGit` now sits on it); `src/runner/git.ts` (`resolveCommit`; `resolveBranch` delegates; `QuarantineReader` / `gitQuarantineReader.inspect` → ancestry, all-commit paths (`log -z --reverse --name-only --format= -m --no-renames`), commits oldest first, shortstat diffstat); `jobs.ts` (`recordReviewed` I7, `pendingCollectionExpired`); `errors.ts` += `reviewed_oid_mismatch`; `store.ts` `JobUpdate` += `baseOid`, `reviewedOid`, `quarantineRef`, `class`, `failure`, and `transition(id, to, now, payload?, fields?)`; `config.ts` `[door]` += `slot`, `quarantine` (~-expanded), `profile`; `views.resultBody(job, collected?)` adds `quarantine`, `commits`, `diffstat`; `control.ts` `result` reads the latest `collected` event.
- Tests: `test/runner/room.test.ts` (VT-1, 45 cases incl. EX-3 structural test), `room-fixture.ts` (`roomWorld`, `fakeSlot`, `collectWorld`), `exec.test.ts`; `git-fixture.ts` gains `tempDir`, `gitIn`, `tempBareRepo`, `tempClone`, nested-path `commit`; extended git/config/jobs/store/views/control tests. 662 -> 730 tests; lines 97.69% -> 97.82%. 0 inline eslint-disable.

### Learned
- Oubliette's provision source repo is `${CAPSULE_REPO:-$profile_path}` (host/git-channel.nix `src=`), not the cwd; `<ref>` is any commit-ish there. The adapter passes the resolved **oid** with `CAPSULE_REPO = repo.path`, so the guest gets exactly the oid refresh returns (closes Q4's resolve/push race without a guest recheck). The push is unforced: a guest `work` ahead of the new base refuses (→ ChannelFailed).
- `capsule <slot> <verb>` supplies `--capsule` and `--profile` itself (README); `--profile` in `provisionArgs` is only used when `[door] profile` is set.
- Node's `ExecFileException` is `Omit<ErrnoException, "code">`, so `prefer-promise-reject-errors` refuses rejecting it directly; wrap in a new `Error` with `cause`. A signal kill has a non-numeric `code` and says nothing of the signal in `message`.
- `git log -m` lists a merge's paths against each parent; without `--reverse` paths and commits come newest first.
- Subclassing `JobStore` (`override transition`) is a clean crash-injection seam for the two-write window.

### Deviations from the sheet
- `SlotCli` is `(args, env?)`, not `(args, cwd?)`: the source repo travels in `CAPSULE_REPO` (above).
- Exec: new `exec.ts` `runProgram` shared by `runGit` and `execCapsule` (no second exec path); maxBuffer 64 MiB (R6).
- T4: `pendingCollectionExpired(job, now, maxMs): boolean` instead of a 3-valued decision taking `reachable`; the probe stays in `retryPendingCollection` (abandon at the bound without probing, Q6).
- Store: `transition` gains an optional `fields` argument (the outcome columns ride the transition's one event) rather than collect.ts rebuilding the transition change; `JobUpdate` also gains `baseOid` (fixture, and PHASE-07's refresh).
- Error outcomes go through `classify({ collection: { ok: false } })`, so a cancelled job whose collection fails ends `cancelled` (class `error`), not `failed`. Rows that cannot be collected at all (repo gone from config: `repo_not_configured`; no `base_oid`/`end_reason`: `corrupt_job`) and `collection_abandoned` go straight to `failed`, class `error`.
- `failure` reasons used: `<class>` (+ `offending`), `collection_failed`, `check_failed` (inspect threw; `reviewed_oid` still recorded, collected event without commits), `reviewed_oid_mismatch` (+ `recorded`, `collected`), `collection_abandoned` (+ `pendingSince` ISO), `repo_not_configured`, `corrupt_job`.
- EX-3 structural pattern is `/\bcapsule|\bslot|\bdoor/i` over every `src/` file; owners `runner/room.ts`, `runner/config.ts`. Exports other modules import (`channelFromConfig`, `roomConnection`, `GitChannel`, `ChannelUnavailable`) are named door-free so importing them passes.

### Open (for /audit to reconcile)
- Q1 drift (EX-1 wording): the slot's collect transfers every guest head; the adapter only reads and records `refs/capsule/<slot>/heads/job/<id>`. Narrowing the transfer belongs to the room adapter (SL-005). Commented at the collect site.
- Q2 port drift (/reconcile): `collect` returns `{ quarantine, ref, oid }` (design §5.2 says `{ ref, oid }`); result details live in the `collected` event payload, not columns.
- Q4 PROVISIONAL: `refresh` runs `capsule <slot> ssh git -C <guestPath> switch work` before provision (`returnToWorkArgs`, citing host/git-channel.nix:272, pending H1). A dirty guest worktree then fails provision (ChannelFailed), fail closed.
- `reviewed_oid_mismatch` was appended to `ERROR_CODES`, the control socket's code set, though it never reaches the socket (design §5.2 lists the wire codes).
- `execCapsule` itself is untested (no real `capsule` in tests by rule); H1 covers it.
- H1 (human, slot f) — commands verbatim from the sheet; note the provision source is `CAPSULE_REPO` / the profile's path, not the cwd, so the `cd` alone may not select the repo:
  ```
  cd ~/dev/satan && capsule f provision main          # add --profile <name> if refused
  capsule f ssh 'git -C <slot clone> switch -c job/h1-test work && \
    git -C <slot clone> commit --allow-empty -m h1'
  capsule f collect; echo "exit $?"
  git -C /var/lib/capsule/collect/f.git for-each-ref refs/capsule/f/heads/
  capsule f stop; capsule f collect; echo "exit $?"; capsule f ssh true; echo "probe $?"
  capsule f start
  ```
  Expect: `refs/capsule/f/heads/job/h1-test` present; collect exits 1 while stopped and the probe is non-zero. Also confirm the quarantine is readable by the runner's user (R4), and what `provision` does when guest HEAD is `job/h1-test` (Q4).

## PHASE-07 batch A (worker, opus)

### Produced
- malebolge (uncommitted): `src/runner/durable-ids.ts` (`conversationText(id)`, the one place a `ConversationId` becomes row text; `conversationIdOf(session, text)` recovers the branded id from `tx.scanConversations` records, newest first, pages of 64, read-only commit); `src/runner/env.ts` (`JobConnection extends Connection`, promoted from the env-fixture spike's `ObservedConnection`, with `ConnectionObserver` / `LostFailure`; `jobEnv({ jobId, cwd, connection, observer })` → `RemoteExecutionEnv` id `pi-env:job-<id>`; `sshTarget(room)` → pi-env `SshTarget`; `roomDaemon(room)` = lazy `sshConnection`); `src/runner/tools.ts` (`JobTools`: CodingTools' read/write/edit/bash, `read` with `replay: "safe"`); `src/runner/guard.ts` (`jobGuard({ currentJob, jobs, now })` → extension `job-guard` with a `ToolTask` `beforeTool`; `repoPath(argument, root)`). `config.ts` `[door]` += `host`, `user` (OQ-2 approved); `room.ts` `RoomConnection` = `{ host, user, hostKeyAlias: "pi-env-<slot>", knownHosts, sshConfig?, identity? }`, `roomConnection` refuses (StartRefused) naming the missing keys (`slot`, `host`, `user`, `known_hosts`); door refusals share `lacking(keys)`. `control.ts` writes ids through `conversationText`. env-fixture keeps only the pause table spike; env-pause.test and room-stop-spike use the promoted class, env-pause builds its env through `jobEnv`.
- Tests: `test/runner/{durable-ids,env,tools,guard}.test.ts`; env.test registers pi-durable's `registerEnvConformance` (with `listFiles`) over a local pi-env daemon through `jobEnv` (VT-2). 730 -> 799 tests; lines 97.82% -> 97.93%. 0 inline eslint-disable, no `as`.

### Learned
- §0 surfaces exist at pi-durable 1.3.0: `Harness extends Session`, `Session.commit` gives `tx.scanConversations(query, limit, cursor?)`, records type `id: ConversationId`, `Page = { items, next? }`. Observed cost on SQLite: 0.7 ms to find the oldest of 1000 conversations (16 pages), 0.3 ms for the newest.
- STOP 4 cleared: `beforeTool` runs in the tool task's `call` phase before the intent `runtime.commit` (dist/harness/tool.js:61-86), not inside a storage transaction. guard.test runs the hook on a harness over the runner store's own SQLite file and its `appendEvent` settles (bounded by `within`).
- A blocked call's tool result is `Tool call blocked: <block>` with harness error code `blocked`; a throw from `beforeTool` also blocks (its message becomes the text).
- The replay field is `ToolRegistration.replay?: "safe" | "unsafe"` (default `unsafe`); recovery reruns only when both the stored intent and the current registration say `safe`. CodingTools' registrations are plain objects, so a spread copy is exact.
- pi's file tools strip one leading `@` and turn unicode spaces into spaces before resolving (tools/path-utils.js); the remote env resolves `~` against the remote home and `file:` URLs. The guard mirrors the first two and fails closed (blocks) on `~` and `file:`.
- pi-env `sshArguments` quotes paths: `UserKnownHostsFile="<path>"`, `IdentityFile="<path>"`; user goes as `-l`, host after `--`.
- pi-ai's retryable classifier matches bare status digits (`429`, `500`, `502`…): a refusal echoing a model-chosen path containing them would match. Harmless for a tool result (the classifier reads assistant errors), but PHASE-08's gate text must never embed model-chosen text.

### Deviations from the sheet
- A3: the job's tool set is one extension holding copies of CodingTools' registrations with `read` marked `replay: "safe"`, not CodingTools plus a `wrapTool` extension. Same registration effect; one extension to select instead of two that must travel together. Tested by registration (`replay`), identity of everything else, and the tool list.
- A4 port: `currentJob(conversationIdText) → GuardedJob | undefined` where `GuardedJob = Pick<Job, "id" | "allowedPaths"> & { root }` (root = the repo's guest path, the conversation's cwd), not `Job`: the guard needs the guest path to resolve absolute paths and has no config. A write/edit in a conversation no job owns is blocked, unaudited (no job to attach the event to). The `blocked_tool` payload is `{ tool, path, repoPath? }` (`path` as the model gave it; `repoPath` when resolvable).
- A2: `jobEnv` takes an options object `{ jobId, cwd, connection, observer }`; the ssh builder is split into pure `sshTarget` (unit-tested via pi-env's own `sshArguments`) and `roomDaemon`.

### Open (for batch B / audit)
- `HarnessOptions.env` is called at each use, so batch B's env factory must keep one daemon connection per job (build `roomDaemon` once at prepare, close it at the job's end) rather than per call; `jobEnv` itself is cheap (a wrapper).
- `RemoteExecutionEnv` id is per job (`pi-env:job-<id>`) as the sheet says, though every job sees the same room files; equal ids are what pi uses to share file namespaces.
- Host key trust: `roomDaemon` needs the room's key already in `known_hosts` under `pi-env-<slot>` (pi-env `scanHostKey`/`acceptHostKey`); no runner verb does that yet — an operator step for PHASE-12/H-steps.
- Settlement API (STOP 2) and pending_collection (OQ-1) untouched here.

## PHASE-07 batch B1 (worker, opus)

### Produced
- malebolge (uncommitted, kept the interrupted batch-B work and completed it):
  - B1.0 green-up: formatted `prepare.ts`, `run.ts`, `conversations.test.ts` (named files only); 9 lint errors fixed — `preparingFailure`'s nested ternary → `failureReason`; `readyRoom` calls `signal.throwIfAborted()` at the top of each attempt (post-sleep check dropped); scheduler drain is `while (takeDirty()) { while (await step()) {} }`; tenancy/scheduler/test object-literal arrows → function declarations.
  - B1.1 VT-3 in `scheduler.test.ts` `describe("the seat (EX-8) …")`: a left-over `collecting` job and a `pending_collection` job (held mid-backoff) each keep queued B `queued` until A is terminal; a live run blocked inside its collecting step keeps B out until it returns. **These passed on the existing code** (EX-8 already met by `IN_FLIGHT`): they are the regression pin.
  - B1.2 `src/runner/backoff.ts` (`Sleep`, `abortableSleep`, `roomRetryDelay`, moved from prepare.ts; tested in `backoff.test.ts`). Scheduler: `SchedulerDeps` += `sleep: Sleep`, `stop: AbortSignal`. A held `pending_collection` job is retried from the drain (`pendingRetries`: `retryPending`, then `sleep(roomRetryDelay(n), stop)` while it stays; count per job), no wake needed; the bound stays `retryPendingCollection`'s (`collection_abandoned`). Other held states still rest the drain. `stop` aborted → no pick/retry, a pause ends, `wake` is a no-op. `turns()` (the cancel/pick serialiser) extracted to module level.
  - B1.3 `test/runner/prepare.test.ts` (17 tests, one `describe` per function): `roomShell` exit/stdout/stderr over a local daemon, lost daemon → `ChannelUnavailable`, exec in a missing cwd → `ChannelFailed`; `ensureJobBranch` through real git in `roomWorld({ guestAtClone: true })` (absent → made and checked out; at base → switched; moved → `job_branch_moved` with both oids, branch untouched, HEAD still `work`); `readyRoom` (refresh once + `refreshed` event; recorded `base_oid` kept; down at refresh or shell retried with asserted delays; past `max_room_wait` → `room_unavailable`, pauses capped by time left `[1000, 1500]`; `ChannelFailed` not retried; abort stops before the next attempt); `preparingFailure` table. Mutation-checked (3 mutations in prepare.ts → 4 failures).
  - `localConnection` / `lostConnection` promoted to `env-fixture.ts`; `env.test.ts` and `env-pause.test.ts` import them (two copies of `localConnection` removed; no third lost-daemon construction).
  - B1.4 run.ts: `RunDeps.connect: (repo: RepoConfig) => Connection`; `startPreparing` resolves `{ policy, repo }` (`Resolved`) once and `admit` takes it. I12: `settle` never throws — a settlement failure (not a cancel) is an `Ending` `{ reason: "settle_failed", message }`, `end_reason = error`, so the job still reaches `collecting` and is collected.
- `just check` green: fmt-check clean (102 files; biome.json not flagged), lint 0, tsc clean, 40 files / 852 tests, lines 93.66% (run.ts at 0% until B2.1's VT-1).

### Learned
- `max-lines-per-function` (80) bit `createScheduler` once the retry loop landed; extracting `turns()` and `pendingRetries()` as module functions and taking `stop` as a dep signal (the sheet's alternative to a `stop()` method) kept it under without hiding state.
- The pre-existing `settledPayload` spread `record.reason` (e.g. `aborted`) after the cancel's `reason`, overwriting the user's cancel reason in the event. Now the submission's reason is `submissionReason`; a payload's `reason` names why the job moved.
- A `Sleep` that returns immediately makes a never-leaving `pending_collection` spin the drain forever in tests — scheduler tests that leave a job pending must block their sleep or terminate the job.

### Deviations from the sheet
- B1.2: `stop` is a `SchedulerDeps.stop: AbortSignal`, not a `Scheduler.stop()` method (sheet allowed either). B2.2's `close` aborts the controller it passed in.
- B1.4: `settledPayload` key `reason` → `submissionReason` (collision fix above). Settlement failure under a cancel keeps the cancel's `reason` and adds `message`.
- B1.3 touched `env-fixture.ts`, `env.test.ts`, `env-pause.test.ts` (not in §5's list) to share the connection constructions, as the sheet's "do not write a third" asks.

### Open
- `retryPending` throwing (e.g. the row left `pending_collection` concurrently) stops the drain with a log until the next wake — same policy as a run's unexpected failure.
- A backoff pause may overshoot `max_pending_collection` by up to one delay (≤ 60 s); the bound is enforced at the next probe, not by the sleep.
- If `toCollecting`'s own store write fails, the row stays `running` (drain stops, logged); PHASE-10 recovery covers it.
- Six identical `messageOf(error)` helpers in `src/runner/` (collect, prepare, room, run, scheduler, start): candidate for one export from `errors.ts` (outside this batch's file set).
- run.ts untested until B2.1; VT-1 case 7 (settle failure → `collecting`, `end_reason = error`) pins B1.4.

## PHASE-07 batch B2 (worker, opus)

### Produced
- malebolge (uncommitted on b2136a0):
  - B2.1 `test/runner/run.test.ts` (VT-1, 14 tests). World: faux provider, runner store and pi on **one** `:memory:` SQLite handle (production shape, so EVD-008 is exercised, not MemoryStorage), `JobTools` + `jobGuard({ currentJob: tenancy.guarded })` + a `blockingTool`, `env: tenancy.env`, `connect` = local pi-env daemon, `roomWorld({ guestAtClone: true })`'s fake slot channel, a real scheduler seating each job. Scenarios: write + bash commit → `needs_review` with the event order `submitted, conversation, policy, →preparing, refreshed, →running, →collecting, collected, →needs_review`; initial prompt `requestId` = job id (read back via `tx.submissionByRequest`, matches the `running` payload's `submissionId`); out-of-allowlist `write` → `Tool call blocked`, `blocked_tool`, no file; same change via `bash` → `path_violation` → `failed`; room down past `max_room_wait` → `failed(room_unavailable)`, zero provider calls, no collect; `job/<id>` at another oid → `job_branch_moved`, branch untouched, no call; policy unresolvable → `preparing` → `failed`, no `policy` event; recorded conversation unknown to pi → `conversation_missing`; faux `stopReason: "error"` → `collecting` `end_reason = error`, `submissionReason: model_error` (STOP 2 pin); settle failure (Proxy whose `wait` rejects) → `collecting` `settle_failed`, collected (I12); cancel: seated-before-preparing, while preparing (refresh gated), just before submit (cancel inside `readPrompt`), while running (`conversation.abort`, answered at `collecting`/`cancelled`, then collected → `cancelled`). Mutation-checked: `endReasonOf` constant, `conversation.abort` removed, `toCollecting` ignoring the cancel — each fails a test.
  - B2.2 `start.ts`: door checked at start (`channelFromConfig` + `roomConnection` → `StartRefused`, I13); `roomTenancy`; harness opened with `registry: registryOf([JobTools, guard])`, `env: tenancy.env`, `models` unwrapped (PHASE-08's seam); one `store.jobs` for control, scheduler and run; `ControlDeps.wake/cancel` = the scheduler's; `scheduler.wake()` once after serve; `close`: server → `stop.abort()` → harness. `StartOptions.room?: RoomAccess { channel, connect }` is the test seam (named without door words: room.test's structural check). runner-main tests: enabled start drains a job queued before start (faux, one provider call, `failed/no_changes`); `enabled = false` leaves it `queued`, no conversation, zero provider calls; a `[door]` lacking `host` refuses start.
  - B2.3 `messageOf` exported once from `errors.ts`; the six named copies plus five inline/renamed ones (protocol, control, git, rows `errorMessage`, config) use it. `toolResults(harness, conversation?)` in `test/harness-fixture.ts` reads a job's conversation.
- `just check`: fmt-check clean (103 files), lint 0, tsc clean, 41 files / 869 tests, lines 98.09% (run.ts 100% lines, start.ts 97.9%).

### Learned
- `Harness` doc: `submit`, `abort`, `compact`, `Submission.wait`, `waitForTask` each enable scheduling on a passive harness. start.ts never calls `resume()`; I14 rests entirely on the scheduler making none of those calls when disabled (now tested).
- The fake slot's `provision` refuses unless the guest HEAD is `work`; a test that pre-makes `job/<id>` (`guestJob`) must `switch work` again or refresh fails `ChannelFailed`.
- The agent's `bash` runs in the test process environment through the local daemon: a commit needs `GIT_CONFIG_GLOBAL=/dev/null` and an explicit identity, or the user's git config leaks in.
- A cancel while preparing is answered only once `refresh` returns: `GitChannel.refresh` takes no signal, so `base_oid` and `refreshed` are recorded before the cancel lands.

### Deviations from the sheet
- Storage: shared SQLite (`openRunnerStore(":memory:")`) instead of pi `MemoryStorage`, to run the EVD-008 shape.
- `connect` builds `roomConnection(config)` once at start, not per call (fail closed at start).
- `messageOf` consolidation reached five files beyond the six named (same expression, inline).

### Open
- `close` does not wait for a seated run: the harness and db close under it; its next write fails and is logged, the row stays in flight for PHASE-10 recovery. Awaiting `scheduler.idle()` would let a long run block shutdown. Orchestrator to rule.
- The door is now required at start even with `enabled = false` (I13 read strictly).
- **PHASE-09 forward:** `settle` waits on the *initial* submission. A pause settles it `unanswered: aborted` and the resume is a new submission, so PHASE-09 must re-target the wait (and not read that `aborted` as a cancel — `RunControl` decides cancel, `endReasonOf` would say `error`).
- **PHASE-15 forward:** `runJob` closes the job's connection in its `finally`, *before* `collectJob`. The post-collect clean needs a room shell after collection: extend the connection's life past `collectJob` (or open a second one); the seam is `runJob`'s `finally`.
