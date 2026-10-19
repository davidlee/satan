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
fresh-as-of: 2026-10-19 · reconcile (RV-029 outcome, REV-007 done, RV-027 concluded) · satan 0affb18+audit, malebolge 8c93902

### Produced
- design amended and re-locked twice: rev 56 (room adapter, RV-026) — 5bbc0fc; rev 63 (probe = job collect; DEC-057 gate rulings) — 15662ba
- DEC-065; DEC-055, DEC-057, DEC-060, DEC-061 amended; EVD-006..010; ASM-005 validated; CON-003, CON-004
- runner live as `satan-runner` (room `assistant`, repo goad-walk); PHASE-12 smokes and closure run (P promoted, R rejected); one consumer deployed
- audit RV-029: 26 findings (8 design-wrong items in the Reconciliation Brief, 3 governance/spec groups); ADR-017 ledger rows 4b/5b/6b/8/9 → `patch-runner` with transition lines (DEC-062); closed ISS-030, ISS-038, ISS-039, ISS-041, CHR-003, IDE-007, IMP-006
- minted: ISS-047 — rejoin wedges the seat when a held job's repo leaves config; CHR-019 — code/comment/doc residue
- earlier follow-ups: IMP-042, IMP-043, CHR-016 (closed), CHR-017, CHR-018, ISS-046

### Learned
- mem.fact.pi-env.type-survives-only-at-connection — where runner failures stay typed in pi-env/pi-durable 1.3.0
- mem.fact.git.fetch-auto-maintenance-races-temp-repo-cleanup — `maintenance.auto=false` for temp-repo tests
- `capsule <room> ssh … true` is the human door, never a probe (oubliette RV-018); agents cannot restart user units
- EVD-006..010 — PHASE-01 spike evidence

### Open
- RV-029 brief reconciled 2026-10-19 (see RV-029 `## Reconciliation Outcome`); SPEC-004 + REQ-026..033 via REV-007 await the user's read
- CHR-017 — user ruling: must land before SL-023 closes (runner runs malebolge's live tree)
- ISS-046 — producer lanes other than fix/goad-walk refused
- prompt `~/satan-corpus/prompts/patch-agent.md` swept into corpus 21b64ea by the daily commit; PHASE-12 batch B's 6 review points unconfirmed by the user

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

## PHASE-08 batch A (worker, opus)

### Produced
- malebolge (uncommitted on 281ee3f):
  - `src/runner/model-gate.ts`: `REFUSALS` (fixed text, each ends "(out of budget)" so pi-ai's non-retryable pattern matches first) and `GateRefused { reason }`; `gatedModels(real, gate)` — an explicit object literal typed `Models` (no Proxy). Nine request members each admit then call the *same-named* real method: `stream`/`streamSimple`/`streamDeferred` via `lazyStream` (refusal = error event); `complete`/`completeSimple`/`fetchDeferred` resolve pi-ai's own setup-error message (`lazyStream(...).result()` of the rejection); `cancelDeferred` rejects `GateRefused`; `generateImages`/`classify` resolve pi-ai's `imageErrorResult`/`classifierErrorResult` (never reject). `maxTokens` = min(caller's, gate's) on the four chat entry points. `getProviders → []`, `getProvider → undefined` (OQ-B ruling). `createModelGate({ seated, jobs, now, usageOf })` with the sheet's binding order; `modelLimits` (AS-3; non-chat models get `maxOutputTokens 0`, see Learned); `spendOf` (Σ `models` + `tools` buckets, AS-2); `harnessUsage()` → `{ usageOf, bind }` (late-bound harness; unbound = unreadable, I10).
  - `src/runner/store.ts`: `JobStore.admitModelRequest(id, now, judge)` + `RequestVerdict`: one transaction; admit → `model_requests + 1`, no event; refuse → one `ceiling` event per job (payload `{ reason, source: "gate", entryPoint }`), no count.
  - `src/runner/ceiling-latch.ts`: first trip wins; `signal` + `reason()`.
  - `src/runner/tenancy.ts`: `Tenant extends GuardedJob, GateJob` (`meter`); `seated()`.
  - `src/runner/run.ts`: per-run `Stops { control, latch }`; tenant seated with `meter.refused = latch.trip`, `warnDue` no-op; `settleSubmission` waits on `AbortSignal.any([cancel, latch])`, then `conversation.abort` from the run loop; `toCollecting`: cancel wins, else the latch's reason is `end_reason` and `{ ceiling: reason }` joins the payload.
  - `src/runner/start.ts`: gate built before `Harness.open`, catalog wrapped in `gatedModels`, `usage.bind(harness)` after open.
  - Tests: `test/runner/model-gate.test.ts` rewritten (44: refusal text, 9-entry-point table over `test/runner/models-fixture.ts` — `createModels` + `createProvider` recording every provider method incl. images/classifiers — and the harness-level VT-1/VT-3 cases); `store.test.ts` (+3), `tenancy.test.ts` (+1), `ceiling-latch.test.ts` (2), `run.test.ts` (+2, EX-4 gate path; `runWorld` now wires the gate as start.ts does, `RunWorldOptions.ceilings` = submit ceilings, `usageOf` override), `runner-main.test.ts` (`result.usage.modelRequests = 1`). `test/runner/gate-fixture.ts` deleted.
- `just check`: fmt clean, lint 0, tsc clean, 42 files / 910 tests, lines 98.22% (model-gate.ts 100% lines, run.ts 100%).

### Learned
- `capped(options)` cannot be typed against `ModelsApiStreamOptions<TApi>` for a free `TApi` without `as`; typing it at `StreamOptions` and calling `real.stream<Api>` / `real.complete<Api>` passes tsc. A non-generic member signature does not (the `Models` method type is not bivariant there).
- The usage read `harness.snapshot(UsageDoc, conversationId, context)` from inside the generation task settles (no hang): `streamResponse` runs outside any `runtime.commit`.
- A refused generation already ends the submission `unanswered: model_error`; the latch is what turns `end_reason` from `error` into `ceiling_exceeded`/`usage_unavailable`.
- `NEW_JOB` carries submit ceilings (`model_requests: 5`), which override config layers; tests lower a ceiling through the submission, not `[defaults]`.
- Non-chat models have no output limit: `maxOutputTokens = 0` keeps `shouldWarn`'s "under one request's allowance" from firing on every classify/image call (with ∞ it always would). AS-4 (cap < 1 refuses) applies only to the four capped entry points; deferred/images/classify are count-only.
- `prefer-const` flags a `let` assigned once later; the late-bound harness is a `{ usageOf, bind }` object instead.

### Deviations from the sheet
- A store failure inside `admitModelRequest` is not caught: it surfaces as a request error (no provider call, no latch trip), so the run ends `end_reason = error`, not `usage_unavailable`. Judged more honest than relabelling a bug; flag if the orchestrator wants fail-closed relabelling.
- `harnessUsage()` returns `{ usageOf, bind }` rather than closing over a `let harness` in start.ts (lint).
- `RunWorldOptions.ceilings` sets submit ceilings (see Learned), not a policy override.
- TDD order: for A1/A2 and the latch the implementation preceded the first test run; the tests were then mutation-checked (dropping AS-4; bypassing the gate on `cancelDeferred`) and each mutation failed them.

### Open
- **OQ-A consequence (escalated to the human):** per DEC-057 `cancelDeferred` is refused when the budget is exhausted — exactly when a ceiling abort runs. An already-admitted deferred request is then left running at the provider, possibly still billing. Latent: the runner never enables `settings.stream.deferred`.
- The `cancelDeferred` harness test waits 200 ms after the first provider call for the poll checkpoint to commit before aborting (no public read of `LiveDoc`); stable over 5 runs, but timing-based.
- `warnDue` is wired as a no-op; batch B consumes it (and must schedule the steer outside the gate's task).
- No seated job → refusal `no_job` with no count, no event, no signal (AS-1); nothing ends the generation's run except the error result.

## PHASE-08 batch B (worker, opus)

### Produced
- malebolge (uncommitted on df435a8):
  - `src/runner/deadline.ts`: `Timer` port `(ms, fire) => { cancel }`, `systemTimer`; `armCeilingTimers({ job, ceilings, softThreshold, now, timer, expire, warn })` arms the deadline (`active_wall_clock_s`) and the soft timer (`softThreshold ×` it) from the row's `activeMs` + open segment (`activeWallClockMs`); a passed moment fires during the call; past the deadline only `expire` fires (warning moot); `stop()` cancels both and guards callbacks already in hand.
  - `src/runner/warning.ts`: `WARNING_TEXT` (runner constant, OQ-C), `warningRequestId` (the one `warn-` spelling; `jobs.ts` recovery uses it), `submitWarning` (submit steer, then `warning` event `{ requestId, submissionId, trigger }`), `warningPlaced(harness, submissionId)` (`submission(id).status().entry`), `runWarning` — once per run, given from a microtask (never on the gate's stack), skipped if a `warning` event exists, withheld once closed or the run is stopping; failures go to `failed` (logged), never thrown.
  - `src/runner/store.ts`: `recordCeiling(id, now, payload)`; it and `admitModelRequest` share `appendCeilingOnce` — one `ceiling` event per job, first source wins.
  - `src/runner/run.ts`: `RunDeps.timer`, `RunDeps.log`; `runStops` (latch + one `signal` for cancel-or-ceiling + deadline `expire` = trip at once, then record `{ reason, source: "deadline" }`); warning built before seating (gate `warnDue` → `due("usage")`); timers armed right after the `running` commit from the returned row (soft → `due("wall_clock")`); `settleRun`: settle, then in `finally` stop timers, close the warning, abort a stray warning run, await the deadline's event — all before `toCollecting`.
  - `src/runner/start.ts`: `timer: systemTimer`, `log: options.log`.
  - Tests: `test/runner/run-fixture.ts` (promoted `runWorld` etc.; `manualTimer`, `RunWorld.timers`; fixture `log` throws), `test/runner/ceilings-harness.test.ts` (16), `store.test.ts` (+1).
- `just check`: fmt clean, lint 0, tsc clean, 43 files / 927 tests, lines 98.12% (deadline.ts, warning.ts, store.ts 100% lines; run.ts 96.7% — the three log-only catch arms).

### Learned
- A steer submitted to an **idle** conversation is placed and starts a new run (`admitSubmission`). A warning racing the run's end therefore starts a stray run after `settle`; `settleRun` closes the warning, reads its status, and aborts the conversation when it is `queued`/`placed`. Tested by holding the warning's submit until the initial submission settles.
- A faux response step that blocks on `options.signal` must check `signal.aborted` first: an abort before the step runs never fires the listener (hang).
- `close()` withholds a `due` made in the same tick (the give runs a microtask later and re-checks after its last await). Tests that want a warning given wait for its receipt before closing.
- The deadline's event write lands before `collecting` in practice even without the `await stops.expired()`; the await is defensive (a mutation removing it is not caught).

### Deviations from the sheet
- One `armCeilingTimers` for both timers (the seam PHASE-09/10 stop/re-arm as a unit), not a separate `armDeadline`.
- `RunDeps.log` added (warning/deadline-event failures the run outlives, I12).
- Stray-warning abort in `settleRun` — not in the sheet; needed for "nothing fires into collection".
- `warningPlaced` false is tested on a queued steer mid-run (active harness), not on a `resume: false` harness.
- `submitWarning(deps, trigger)` takes `WarningDeps { conversation, jobs, jobId, now }` (not the job row).

### Open
- Gate-vs-deadline race: the deadline trips the latch first, then writes its event; a gate refusal inside that window writes `source: "gate"` first. One event either way; the recorded source may name the gate.
- `warningPlaced` takes a branded `SubmissionId`; the receipt stores its text. PHASE-10 recovery must recover the id, e.g. `tx.submissionByRequest(conversationId, warningRequestId(jobId))`, not parse the text.
- If `admit` throws after the prompt is submitted (e.g. the `running` transition fails), the warning is never closed; benign (no timers yet) but unaudited.
- Forward notes:
  - **PHASE-09 (pause):** a pause must `timers.stop()` (deadline + soft) and re-arm via `armCeilingTimers` from the fresh row on resume. The resume message carries `WARNING_TEXT` when the threshold passed and `warningPlaced` is false or there is no receipt — reuse `warning.ts`. Keep the pause abort separate from the ceiling latch (a pause is not an exhaustion); note `runWarning`'s `stop` signal is cancel-or-ceiling today — a pause must also close/withhold the run's warning. `settle` still waits on the initial submission only.
  - **PHASE-10 (recovery):** re-arm from `active_ms` + (now − `running_since`) after the DEC-065 `parked_at` re-base; `armCeilingTimers` takes only the row. The "running, threshold passed, no receipt" row calls `submitWarning` (same `requestId` → existing submission) then writes the receipt. `model_requests` survives restart (A3).
  - **PHASE-15 (room adapter):** the timers' `stop` and the warning close live in `settleRun`, not `runJob`'s `finally`; moving connection lifetime past `collectJob` must not drag them.

## PHASE-09 batch A (worker, opus)

### Produced
- malebolge (uncommitted on 9dab8e5):
  - `src/runner/pause.ts`: `pausingObserver({ jobs, now }, jobId)`, the running job's `ConnectionObserver`: `lost` → `jobs.markPause(jobId, now, { ...failure })`, awaited before the rethrow. `env.ts` untouched (`RUNNING_OBSERVER` removed from run.ts).
  - `src/runner/guard.ts`: `GuardedJob.paused` (the trigger); `GuardDeps.jobs` += `get`; `PAUSED_RESULT_TEXT` = "environment unavailable; paused"; `pausedJob(api)` reads the row's `pause_requested`, never a result; `afterTool` (ToolTask) replaces the result `{ isError: true, output: [PAUSED_RESULT_TEXT] }`; `afterTools` (GenerationTask) signals `paused()`. See Deviations.
  - `src/runner/tenancy.ts`: `guarded()` passes `paused` through.
  - `src/runner/run.ts`: `Admitted.pause: AbortController` (per segment, AS-5; never the latch); tenant `paused` aborts it; `meterOf(...)` extracted from `admit` (max-lines) with `pausePending`; `settleSubmission` waits on cancel | ceiling | pause, then `conversation.abort`; `afterSegment`: cancel, then ceiling → `toCollecting` as before; else the durable row's `pause_requested` → `transition(running → waiting_room, <settlement payload>)`, no end reason; else `toCollecting`. `runJob` returns a `waiting_room` job without `collectJob` (seat held by the row; tenant unseated and connection closed in `finally` as before).
  - `src/runner/model-gate.ts` (STOP-1 ruling 1): `Refusal` += `paused`; `REFUSALS.paused` = "model gate refused the request: job paused while its room is down"; `Meter.pausePending()`; the signal checked right after the seated job (before the usage read); `judge` declines when the row has `pause_requested`; both throw `GateRefused("paused")` without `meter.refused`, count or event.
  - `src/runner/store.ts`: `RequestVerdict` += `{ kind: "decline" }`, which `admitModelRequest` enacts as nothing.
  - Tests: `test/runner/pause.test.ts` (11: VT-2 info/session/exec each mark durable before the rethrow; two concurrent lost failures → one mark, one event; same text as `Error` / non-lost `RemoteError` → no mark; VT-1 pause half on `runWorld`; STOP-1 race with `abort` held until the submission settles; cancel and ceiling each win over a pending pause; EX-4 same-text bash failure → no pause, second model call). `guard.test.ts` +4 (afterTool replaces + signals; row not result; no job → nothing; text not retryable). `model-gate.test.ts` +2 (paused marked / signalled: no provider call, no count, no ceiling event, no latch) and `paused` in the refusal-text table. `store.test.ts` +1 (decline writes nothing). `tenancy.test.ts` updated.
  - Fixtures: `env-fixture.ts` gains `FailingConnection(failWhen, inner?)` (promoted from env-pause's spike class, now delegating), `lostError(code)`, `LOST_TEXT`; env-pause.test uses them. `run-fixture.ts`: `RunWorldOptions.connection` (wrap the local daemon), `until` promoted from ceilings-harness.test.
- `just check`: fmt clean, lint 0, tsc clean, 44 files / 947 tests, lines 98.14% (pause.ts, guard.ts, model-gate.ts 100% lines; run.ts uncovered lines are the three pre-existing log-only arms).
- Mutation-checked, each fails a test: idempotency guard dropped (`markPauseRequested`); `afterTool` reading the result text; latch tripped on pause; signal fired from `afterTool`; gate pause check removed; precedence ignored in `afterSegment`.

### Learned
- **STOP-1 observed order.** Signalled from `afterTool` (the sheet's A2), the run's `conversation.abort()` lands *before* the tool task commits its result: the transcript shows `<harness> [error] Tool bash was aborted`, never the replaced result (6/6 runs). No second provider call in that arrangement.
- Signalled from `afterTools` (every call of the round terminal and committed; before `finishToolRound`'s commit hands over to the next generation), the replaced result lands and the plain path shows one provider call (8/8). But that is a microtask race: delaying `abort` by one macrotask (`setTimeout` 0, 1, 5, 20, 100 ms) gives a second provider request every time (`callCount` 2, `model_requests` 2). Not guaranteed by construction, so ruling 1's gate refusal is in.
- pi-ai's `isRetryableAssistantError` is false unless the retryable pattern matches; "out of budget" only matters to override a retryable match. The `paused` text matches neither, so it is not retryable.
- `afterTools` runs outside pi transactions (its store read settles on the shared handle), like `beforeTool`/`afterTool`.
- pi-durable has `ToolControl.terminate` (end the run at the round's final boundary, no next generation) — but only when *every* call of the round asks. Not used: the design's mechanism is the runner's abort.
- A cancel or ceiling winning over a pending pause leaves `pause_requested = 1` on a `collecting`/terminal row. It is inert: `markPauseRequested` no-ops outside `running`, and recovery's `running, pause_requested = 1` row only matches `running`.

### Deviations from the sheet
- The trigger is split. `afterTool` still replaces the result; the signal fires from `afterTools`, because from `afterTool` the abort discards the replaced result (binding order steps 5 and 6 would run in reverse).
- STOP-1: gate refusal `paused` (ruling 1), checked on the in-memory signal and on the durable mark inside the gate's transaction. That needed a store verdict `decline` (a no-op), a small vocabulary addition to `RequestVerdict`, not to `vocab.ts`.
- `waiting_room` vs `collecting` is decided by the durable row after the settle, not by which signal woke the run (AS-1: the mark is the record). A run whose submission settled `done` with the mark set still goes to `waiting_room`.
- The `waiting_room` transition payload is the segment's settlement (`submission`, `submissionReason`), not a `{ pause: … }` field.
- A0: the spike's `PAUSE_SCHEMA`/`markPause`/`pauseRequested` stay in `env-fixture.ts`, because the live PHASE-01 harness `room-stop-spike.ts` still uses them. env-pause.test is not folded into pause.test (it holds the real-daemon-kill and ExecutionEnv-seam evidence).
- Added cancel/ceiling-over-pause precedence tests (sheet A3 named the precedence, no test).

### Open
- Batch B forward:
  - Per-segment state lives in `Admitted`: `pause`, `warning`, `timers`. The tenant's `paused` and `meter.pausePending` close over that segment's `pause`, so a resume must re-seat (`tenancy.enter`) or rebind. While the old segment's signal stays fired the gate refuses `paused`, which covers the waiting episode for free if the tenant stays seated.
  - `runJob`'s `finally` unseats the tenant and closes the connection before the job is returned in `waiting_room`. AS-4 moves both past the waiting episode.
  - The paused segment's settlement may be `unanswered: aborted` or `unanswered: model_error` (a racing request the gate declined). The settle re-target must read neither as an end reason.
  - AS-3 ruling: the carried warning is recorded as a standard `warning` event `{ requestId, submissionId, trigger: "resume" }`. The resumed segment's `runWarning` already skips when a `warning` event exists.
  - Signal latency: `afterTools` waits for every call of the round, so a long parallel call that is not lost delays the abort to the round's end. With the room down, the round's other env calls fail fast.
- PHASE-10 forward: the durable mark is set before any abort. A mark set with no tool round to signal it (e.g. pi's own env use) is still acted on when the segment settles (`afterSegment` reads the row). Recovery's `running, pause_requested = 1` row matches this state.
- PHASE-15 forward: `host_key_alias` is required for the slot kind (I13); `room.ts` currently derives `pi-env-<slot>` (batch C moved here).

## PHASE-09 batch B (worker, opus)

### Produced
- malebolge (uncommitted on 1a0e411):
  - `src/runner/pause.ts`: the waiting episode and the resume, exported for PHASE-10. `awaitRoom({ channel, config, now, sleep }, { stateEnteredAt }, signal)` → `"reachable" | "timed_out" | "cancelled"`: probe first, then `roomRetryDelay` backoff cut at the bound; the bound is `max_room_wait` from the row's `state_entered_at`. `roomWaitedOut(deps, id)`: `waiting_room → pending_collection`, payload `{ reason: "room_unavailable" }`, `end_reason = room_unavailable`. `RESUME_TEXT` (the design's sentence). `resumeRequestId(jobId, pauseCount)` is the one spelling of `resume-<id>-<n>`, and jobs.ts's recovery row now uses it. `submitResume(deps, { pauseCount, withWarning })` submits `{ type: "input", content, requestId }`, where content is `RESUME_TEXT`, plus `"\n\n" + WARNING_TEXT` when the warning is owed. A carried warning then gets the standard receipt through warning.ts (ruling 1). `running` stays the caller's to record.
  - `src/runner/warning.ts`: `DueTrigger` (`usage | wall_clock`); `WarningTrigger` += `resume`. `recordWarning(deps, requestId, submission, trigger)` is the receipt path, extracted from `submitWarning`. `placed(submission)` (`warningPlaced` now uses it). `warningOwed(thresholdPassed, receipt?)` is the one predicate (ruling 2). jobs.ts's `warningUnplaced` is replaced by it. `RunWarning.wasDue()` is true once `due` was called, even if the warning was withheld.
  - `src/runner/backoff.ts`: `roomWaitDeadline(since, maxRoomWaitS)` and `pausedForRetry(deps, attempt, deadline, signal)` (false once the bound has passed). Shared by `readyRoom` and `awaitRoom` (refactor).
  - `src/runner/run.ts`: the segment loop. `Run` holds what segments share: the conversation, policy, stops, and `seat()`, which seats the tenant over a fresh `pause` + `RunWarning` with one env on the job's connection. `Admitted` is one segment, built by `armed(...)`, which arms timers from the `running` row. `runSegments`: `settleSegment` (stop the timers, close the warning, end a stray, await `expired`) → `afterSegment` → on `waiting_room`, `awaitResume`. That probes; timed out → `roomWaitedOut`; cancel → `recordCancel`; reachable → re-seat, `submitResume` (owed from the `WarningTrail`), `transition(waiting_room → running, { submissionId, requestId: resume-… })`, re-arm → next segment, whose own submission is the one awaited. `runJob`'s `finally` (unseat, close the connection) now runs after the waiting episode (AS-4). It collects only a `collecting` result; `pending_collection` is left to the scheduler's retry. `recordCancel` is shared by `endUnrun`, `toCollecting` and the wait.
  - Tests (`test/runner/pause.test.ts`, +21): `awaitRoom` unit tests (backoff 1/2/4 s; bound from `state_entered_at` → one 500 ms sleep then `timed_out`; aborted → `cancelled`). `submitResume` tests (stable id → same submission; warning carried with a `trigger: "resume"` receipt). A `warningOwed` table. Run-level: resume after a pause (`resume-<id>-1`, `RESUME_TEXT` last, the `unanswered/aborted` settlement only in the `waiting_room` payload, completed → needs_review); the gate-declined (`model_error`) race resumes and completes; two pauses (`resume-<id>-2`, `pause_count` 2); waiting not charged (7 s slept, `active_ms` < 1 s, resumed deadline < first by < 1 s); deadline / cancel in the resumed segment; warning withdrawn → carried once; carried by a placed resume → a second resume does not repeat it; placed before the pause → not carried, and the resumed segment's due gives none; `max_room_wait` passed → `pending_collection/room_unavailable` → collected → needs_review `partial`; cancel while waiting → `pending_collection/cancelled` → collected → `cancelled`. The batch A run tests now read the pause half at the first probe (`noteAtProbe`). `ceilings-harness.test`: `wasDue` assertions.
  - Fixtures: `run-fixture.ts` gains `slept` (every backoff asked of `sleep`). `writeAndCommit`, `userText`/`userTexts`, `warningEvents` and `warned` were promoted from ceilings-harness/run.test; the duplicates were removed.
- `just check`: fmt clean, lint 0, tsc clean, 44 files / 968 tests (baseline 947), lines 98.21%. pause.ts, warning.ts and backoff.ts are fully covered. run.ts's uncovered lines are the three log-only arms.
- Mutation-checked, each fails a test: resume id from a stale count; warning always carried; warning never carried; timers not re-armed; waiting counted as active; the loop awaiting the old submission; the carried resume not tracked as the carrier.

### Learned
- In-process placement is read from the held `Submission` (`placed`): the warning steer that `close()` returns, or the resume message that carried it. No `SubmissionId` parse is needed. Recovery has only the receipt's `submissionId` text, and `SubmissionId` is branded, with no public parser.
- Over about 12 runs (9 of pause.test.ts alone, 3 in the full suite) the steer queued during the paused round was withdrawn, never placed. The pause's abort lands before the round's generation boundary places a steer. As with batch A, this is observed order, not order by construction. If the steer were ever placed, the resume would correctly not carry it, but the "withdrawn → carried" test would fail rather than pass the other way.
- The tenant must be re-seated **before** the resume submit. The old segment's fired pause signal makes the gate refuse `paused`, which also covers the waiting episode for free.

### Deviations from the sheet
- No `resume` event is written. The `waiting_room → running` transition (`{ requestId: resume-…, submissionId }`) is the resume's audit record, as `running` is for the initial prompt. The `resume` kind in vocab.ts stays unused.
- The warning-owed input in process: `thresholdPassed = due in any segment (wasDue) || a carrier exists`; receipt = placement of the last carrier. "A warning event exists" is read as "this run gave one". An event from an earlier process is PHASE-10's case.
- B1's "extract the shared bounded wait with `readyRoom`" was done as two small helpers in backoff.ts, not a generic retry loop.

### Open
- **PHASE-10 seam.** Recovery calls:
  - `awaitRoom(deps, row, signal)`: the bound is from `state_entered_at`, so a restart does not reset it.
  - `roomWaitedOut(deps, id)`.
  - `warningOwed(thresholdPassed, receipt)`: the same predicate the recovery table uses.
  - `submitResume({ conversation, jobs, jobId, now }, { pauseCount: row.pauseCount, withWarning })`, then `transition(waiting_room → running, { submissionId, requestId: resumeRequestId(id, pauseCount) })`, then `armCeilingTimers` from that row.
  - Receipt forms to read: `warning` events `{ requestId: "warn-<id>", submissionId, trigger: "usage" | "wall_clock" }` and `{ requestId: "resume-<id>-<n>", submissionId, trigger: "resume" }`. Placement means the record of any receipt's submission has an `entry`; recovery must parse `submissionId` text back to a branded id.
  - Re-calling `submitResume` with `withWarning` after a crash between its receipt and `running` writes a second `trigger: "resume"` receipt for the same submission. That is harmless to `warningOwed`, but dedupe by `requestId` if it matters.
  - Paused-row shapes left behind:
    - (a) `running, pause_requested = 1` with a `pause` event: a crash before the abort/transition.
    - (b) `waiting_room, pause_requested = 0, pause_count = n`, with a `transition:waiting_room` payload carrying the settlement (`submission`, `submissionReason`).
    - (c) `waiting_room` with the resume admitted but no `running`: same id on resubmit.
    - (d) `pending_collection` with `end_reason = room_unavailable | cancelled`, from the wait.
    - (e) a leftover `pause_requested = 1` on a `collecting`/terminal row: inert (batch A).
- Runner shutdown does not reach a waiting episode. The scheduler's `stop` is not the run's signal, and `close()` does not await the run, so a probe sleep can hold the process for up to 60 s. `readyRoom` already behaves this way; the restart then recovers `waiting_room`.
- A `submitResume` or transition that throws mid-episode propagates out of `runJob` (the drain logs and stops) and leaves `waiting_room` for recovery, like any other unexpected run error.
- Mutation survivor: dropping `segment.warning.wasDue()` from the trail is caught only at unit level (`RunWarning.wasDue`). No deterministic run-level way was found to make the warning due but never given before a pause.
- The two open user questions (`cancelDeferred` under an exhausted budget; the gated view's `getAuth`/`login`/`logout`) are untouched.

## PHASE-10 batch A (worker, opus)

### Produced
- malebolge (uncommitted on ae787a8):
  - `src/runner/store.ts`: migration V2 `ALTER TABLE jobs ADD COLUMN parked_at TEXT` (V1 untouched). `JobStore.parkAll(now)` / `unparkAll(now)`: one transaction each over every job, through a private `#changeAll` that shares `writeChange` with `change` (refactor). `JobUpdate.parkedAt` (`null` clears); `applyUpdate` clears `runningSince` and `parkedAt` on `null`.
  - `src/runner/rows.ts` `parkedAt` codec (last column); `vocab.ts` `EVENT_KINDS` += `parked`, `unparked`.
  - `src/runner/jobs.ts`: pure `park(job, now)` and `rebase(job, now)` → `{ update, parkedAt, shiftedMs }`. Table: `RecoverySnapshot.initialSubmission`; the `preparing, base_oid set` row split in place (no record → `ensure_job_branch` + `submit_initial_prompt`, with the PHASE-15 checks seam as a comment; record → phase B `record_running`, new `HarnessAction`). `ENABLED_ONLY` (room actions + `rearm_deadline`) filtered from phase A when disabled. `STARTUP_ACTIONS` (`to_collecting`) and `splitPhaseA(plan)` → `{ atStartup, inRejoin }` state R1's split.
  - `src/runner/recover.ts` (new): `RecoverDeps` (harness typed `Pick<Harness, "commit" | "snapshot">`, so phase A cannot call a progress-asking member), `readSnapshot(deps, job)` → `JobRecovery { snapshot, segment? }`, `recoverHost(deps, enabled)`.
  - `src/runner/durable-ids.ts`: `submissionRecordOf(session, conversationId, requestId)`. `pause.ts`: `segmentRequestId(job)`. `policy.ts`: `recordedPolicy(record)` (AS-2 decoder; `config.ts` exports `isThinkingLevel`). `model-gate.ts`: `catalogLimits(models)(ref)`. `run.ts`: exports `Ending`, `settledEnding`, `ceilingEnding(ending, ceiling?)` (now takes the reason, not the latch), and `enterCollecting` (the run's and recovery's one `collecting` write).
  - `src/runner/start.ts`: `recoverHost` after `usage.bind`, before `serveControl` and `wake`; header comment updated. `closingOnFailure(harness, step)` replaces the two inline catch-and-close blocks (max-lines).
  - Tests: `test/runner/recovery.test.ts` (new, 13): VT-2/EX-6 disabled matrix, 7 states each reached by a real run that crashes at its write boundary (`preparing` ×3, `running` + pause, `waiting_room`, `collecting`, `pending_collection`): clock past every bound, no channel verb, no connect, row unchanged except `parked_at`, `harness.inspect().scheduling === "paused"`, faux `callCount` 0. EX-3 pause kept. Row 7 disabled → `collecting/completed`, payload `reason: "recovered"`; with a gate `ceiling` event → `ceiling_exceeded` (AS-3). EX-7 parked once over two disabled restarts. VT-3 park half: `pending_collection` parked 10 days, enabled restart → retried and collected (`needs_review`), one `unparked`, parked span not charged. `readSnapshot` `initialSubmission` false/true. `store.test` +7 (v1 → v2 migration, v2 refuses v1's list, park/unpark incl. one-tx rollback and state-entered-while-parked). `jobs.test`: recovery rows rewritten (row numbers, disabled column per row: the old "disabled keeps phase A" test was wrong under EX-6), EX-8 no branch judgement, R1 disjointness, `splitPhaseA`, `park`/`rebase` units. `policy.test` +2, `model-gate.test` +1.
  - Fixtures (`run-fixture.ts`): `runWorld` split into `openProcess(shared, { enabled, resume, crashAt })`. `RunWorldOptions.path` / `crashAt`; `storeFile()`; `restart(world, { enabled })` (close without awaiting the run, reopen passive on the same file/room/clock, `recoverHost`, `wake`). `CrashingJobStore` (subclass, not Proxy: `#db` private fields break a Proxy `this`): the write labelled `crashAt` (`eventLabel`: kind or `transition:<to>`; `prompt` = the prompt read before submit) and every later write throw `Crash`, and its `dead` signal is the scheduler's `stop`. `world.crash()`, `world.advance(ms)`, `world.close()`, `world.recoverDeps`. `ROOM_DOWN`, `roomGoesDown`, `lostBash` promoted from pause.test; `kinds` now uses `eventLabel`.
- `just check`: fmt clean, lint 0, tsc clean, 45 files / 1001 tests (baseline 44 / 968), lines 98.15%. recover.ts 90.24% lines: uncovered are the unreadable-usage arm, two guard throws and the per-row log.
- Mutation-checked, each fails a test: rebase without clearing `parked_at` (re-base twice); `running_since` not shifted; room action kept when disabled; `harness.resume()` in `recoverHost` (progress call while disabled: 9 tests); row 7 before row 6; park instead of unpark on enabled; ceiling reason ignored.

### Learned
- `harness.inspect(context).scheduling` is `"paused" | "running" | "closing"`: a direct, non-mocking check that nothing asked pi for progress. Verified in pi-durable's js: `commit`, `snapshot`, `submission(id)`, `inspect` never call `tasks.resume()`; `submit`, `abort`, `compact`, `waitForIdle`, `waitForTask`, `Submission.wait` do.
- A `JobStore` Proxy cannot intercept writes: methods touch `#db`, which throws on a Proxy receiver. A subclass overriding `change`/`appendEvent` catches every row write (`transition`, `cancel`, `markPause` go through `this.change`).
- Re-base rule: a bound's start moves by its own parked time, `since + (now − max(parkedAt, since))`. A state entered while parked (a control-socket cancel on a disabled runner moves `waiting_room` → `pending_collection`) starts at unpark; a flat `+ (now − parkedAt)` would put `state_entered_at` in the future.
- A crash point needs the scheduler stopped too: the fixture's fake `sleep` advances the clock, so a still-draining dead process "waits out" `max_pending_collection` before the restart. The crashed store's `dead` signal is the scheduler's `stop`.

### Deviations from the sheet
- A4/A5 code was written before its integration tests (recovery.test.ts needed the fixture first); A1-A3 were red first. Each A4/A5 invariant was then mutation-checked instead.
- `readSnapshot` returns `JobRecovery { snapshot, segment? }`, not a bare snapshot: row 7 needs the settled record for `settledEnding`, and batch B needs `segment.id` to reacquire the `Submission`.
- The usage half of AS-4 uses the gate's own `shouldWarn` over `pi.usage` with the model's limits (`limitsOf` = `catalogLimits` in start.ts). A model the catalog lacks gets zero limits (only the soft fractions and `model_requests` apply). Unreadable usage → wall-clock only.
- Row 7's `collecting` payload gains `reason: "recovered"`.
- `recoverHost` logs and skips a job whose views cannot be read, and returns nothing. Batch B recomputes the plan at rejoin.
- `rearm_deadline` sits in `ENABLED_ONLY` and outside `STARTUP_ACTIONS`: it runs in the rejoined run (settled assumption).

### Open
- **Batch B seam.**
  - `readSnapshot(recoverDeps, job)` → `{ snapshot, segment? }`. `segment` is the running segment's `SubmissionRecord`: `harness.submission(segment.id)` reacquires it.
  - `recoveryPlan(snapshot, true)` + `splitPhaseA(plan).inRejoin`: the room actions and `rearm_deadline`, to run in the rejoin before phase B. The startup part is already done.
  - `HarnessAction` `record_running` (row 5) → `transition(preparing → running, { submissionId: String(segment.id), requestId: job.id })`.
  - `recordedPolicy(job.policy)` (AS-2). `segmentRequestId`, `submissionRecordOf`.
  - `ceilingEnding` / `enterCollecting` / `settledEnding` exported from run.ts.
  - Fixture: `restart(world, { enabled: true })` already calls `recoverHost` then `wake()`. B adds the rejoin to `SchedulerDeps`, and `restart` picks it up through `openProcess`. `crashAt` labels, `world.crash()`, `storeFile()`.
- Batch B must give the rejoin `RecoverDeps` plus `RunDeps`, widening `RunDeps.harness` with `resume`/`submission` (sheet B2). `RecoverDeps.harness` stays read-only.
- Not tested in A: the R3 warn-record arm of `warningThresholdPassed` (it needs a crash on `appendEvent("warning")` after the steer's admission: batch B row 9 exercises it); `startRunner` running `recoverHost` (covered by the fixture's mirror, not by runner-main.test).
- A job submitted on a disabled runner after startup is not parked until the next disabled restart. Harmless: `queued` has no bound.
- The two open user questions (`cancelDeferred` under an exhausted budget; the gated view's `getAuth`/`login`/`logout`) are untouched, as is `host_key_alias`.

## PHASE-10 batch B (worker, opus)

### Produced
- malebolge (uncommitted on a0faedf):
  - `src/runner/rejoin.ts` (new): `rejoinJob(deps, held, control)`, restart recovery's phase B. It re-reads the job (`readSnapshot`), plans with `recoveryPlan(…, true)`, and maps the plan's action kinds to entries (`ENTRIES`, first match): `redo_refresh` / `ensure_job_branch` → `prepareAndAdmit` (rows 3, 4); `record_running` → `transition(preparing → running, { submissionId, requestId: job id })`, then the reopened segment armed (row 5); `abort_then_waiting_room` → `conversation.abort`, then an unarmed segment that settles to `waiting_room` (row 6); `rearm_deadline` → the reopened segment armed, plus, on `resubmit_warning`, the segment's own warning made due and awaited (rows 8, 9); `resume_probing` → `awaitResume` with the plan's `withWarning` (rows 10, 11). `redo_collect` → `collectJob` (row 12). Order inside `superviseRun`'s enter: room work, then the act, then `harness.resume()`, only when a segment was entered (R1, R2). `RejoinDeps` = `RunDeps` with the harness widened by `snapshot | submission | resume`, plus `limitsOf`. The `Submission` is reopened with `harness.submission(record.id)`.
  - `src/runner/run.ts`: `superviseRun(deps, job, resolved, control, enter)` owns the connection, stops, tenancy and collection, so `runJob` and the rejoin share them. `Entered = { segment, trail } | { ended }`. `runSegments` starts from an `Entered`. `awaitResume(…, withWarning?)` returns an `Entered`. `prepareAndAdmit`, `unarmed`, and the `NO_TRAIL` constant are new. The `openRun`, `armed`, `endUnrun`, `Resolved`, `Run`, `Admitted`, `Seated`, `Stops` and `WarningTrail` exports are new. Also new: `RunDeps.stopping`, the runner shutting down. `settle` and `prepareAndAdmit` rethrow while it is aborted, so they write no `settle_failed` or `failed` row (see Deviations).
  - `src/runner/ending.ts` (new): `Ending`, `endReasonOf`, `settledEnding`, `ceilingEnding` and `enterCollecting`, moved out of run.ts. This breaks the run ↔ recover import cycle.
  - `src/runner/recover.ts`: `JobRecovery` += `carrier` (the last receipt's submission record) and `dueTrigger`. `dueTrigger` replaces `thresholdPassed`: `wall_clock` when the clock alone passes, else `usage`, else, when a `warn-<id>` record exists (R3), `usage`.
  - `src/runner/scheduler.ts`: `SchedulerDeps.rejoin`. `pick()` seats a held job that is not `pending_collection` once per process through `rejoin` (`rejoinClaims`). A job still held after its rejoin rests the drain, logged. Wake, drain and idle moved to `drainer()` (max-lines). Disabled still never drains, so it never rejoins.
  - `src/runner/warning.ts`: `recordWarning` writes once per `requestId` (the PHASE-09 double `trigger: "resume"` receipt). `WarningDeps.jobs` += `events`. `RunWarning.given()` awaits the warning in progress without closing it.
  - `src/runner/start.ts`: `runDeps: RejoinDeps` (`limitsOf`, `stopping: stop.signal`), and `rejoin` passed to the scheduler.
  - Tests: `recovery.test.ts` +21:
    - Rows 1, 3, 4, 4-moved, 5, 6, 7→12, 8, 8 VT-3 (parked), 9 usage, 9 R3, 10, 11 shape b (R1: `inspect().scheduling === "paused"` at the rejoin's probe), 11 shape c (resume once), and 11 waited out (R2: paused, no resume).
    - Rows 3, 8 and 12 with `close` as the fault, shape (e), and the EX-5 Go fixtures.
  - Other test files:
    - `scheduler.test.ts` +5: rejoined not run, once only, `pending_collection` never rejoined, disabled, cancel routed.
    - `runner-main.test.ts` +1: `startRunner` rejoins a `preparing` row. The disabled test now asserts `parked_at` (phase A at startup).
    - `pause.test.ts` +1: receipt dedupe.
  - Fixtures (`run-fixture.ts`): `rejoin` wired through `openProcess` (`rejoinHarness`). `restart(w, { enabled, script })`. The fixture's `close` aborts `stopping` first, as start.ts does. A dead or stopping process's logs are dropped. In `recovery.test.ts`: `started` / `crashedAt` / `inFlight`, the `Room.before(verb)` hook (`dieAtProbe`, `closingAt`), `stoppedAfterSubmit(prefix)` (closes pi right after an admission), `recordOf`, `heard`.
- `just check`: fmt clean, lint 0, tsc clean, 45 files / 1029 tests (baseline 1001). Coverage: lines 97.98%, branches 93.69%. rejoin.ts has 89.65% lines; the uncovered lines are the missing-conversation/segment guards, "nothing to rejoin", and the policy-resolve failure.
- Mutation-checked, each fails a test:
  - resume sent from a fresh count (sent twice);
  - `resume()` before the rejoin's room work;
  - the scheduler draining while disabled;
  - row 9's act dropped;
  - row 9 awaited with `close` (withholds it);
  - row 5 entered through `prepare` (re-judges the branch);
  - row 8 unarmed;
  - the `stopping` guard in `settle` removed;
  - the once-per-job claim removed (hot loop: hangs).

### Learned
- A reopened `Submission` (`harness.submission(record.id)`) in a new passive harness can be waited on. `resume()` continues its run, and pi gives the interrupted `wait` tool's result as "interrupted and may have partially run". The sheet's STOP did not trigger.
- **`close` did not leave in-flight rows the way a crash does.** `Session.close` lets admitted work settle before the storage closes. The seated run's `submission.wait` failed ("Harness is closed") while the database was still open, so the run wrote `collecting / settle_failed / error` and then collected, and the job ended `failed`. Before this batch, a runner stop failed every running job. PHASE-07 B2 Open's claim ("the next write fails; the row stays") held only for writes after the database closed.
- In the fixture, a crash with `crashAt` stops only runner writes. pi in the "dead" process goes on, and the gate refuses its model calls once the tenant leaves. To freeze pi at a boundary, close the harness right after the admission (`stoppedAfterSubmit`). The close is idempotent (`Session.#closing`).
- `RunWarning.close()` sets `closed` synchronously, so `due(); close()` withholds the warning it just made due. A `given()` that does not close was needed.
- A type predicate on a claim function (`held is Job`) narrows the false branch to `undefined`. That made the "no held job" check an unnecessary condition. The claim now returns a plain boolean.

### Deviations from the sheet
- `RunDeps.harness` is not widened. `RejoinDeps` narrows `harness` to `RunDeps["harness"] & Pick<Harness, "snapshot" | "submission" | "resume">`. `runJob` needs none of these, and the three test harness wrappers stay as they are. `RecoverDeps.harness` is unchanged (read-only).
- **`RunDeps.stopping` is new, and changes shutdown behaviour.** A run whose runner is shutting down rethrows instead of writing `settle_failed` (`settle`) or `failed` (`prepareAndAdmit` → `endUnrun`). The row stays as a crash leaves it. This was needed for the sheet's close-as-fault matrix rows. Survivor: the `prepareAndAdmit` guard, because "row 3 by close" waits for the full close and its writes fail anyway.
- Row 6's act is an explicit `conversation.abort`. Its segment has no timers, since the table does not re-arm on row 6. `settleSubmission` may abort again, which is harmless.
- Row 9: the act goes through the rejoined segment's `RunWarning` (`due(trigger)` + `given()`), not a bare `submitWarning`. A soft timer that is already past fires during the re-arm (phase A, before the act) and would otherwise race a second receipt. The trigger is `wall_clock` when the clock alone passes, else `usage`. When only the R3 record proves the threshold, the trigger is `usage` by elimination, because active wall-clock only grows. The R3 test fires the soft timer early, so its receipt says `usage` where the run had `wall_clock`. No real run reaches that.
- No `resume()` for row 12 (collecting), or for an entry that ended before a segment (row 4 `job_branch_moved`, row 11 waited out or cancelled). This extends R2: nothing of the conversation continues.
- Row 1 has no rejoin entry. `queued` is never held, and `runJob`'s `ensureConversation` is the act (AS-5). Row 13 has no new test: batch A's VT-3 test is the enabled row-13 path.
- The receipt dedupe reads the events, then appends (not one transaction). The run is the job's only writer.
- `rejoinClaims` has no `enabled` check: `wake` is the single disabled gate (never drains), and the disabled scheduler test pins it.
- EX-5: `TestReconcile_FailsCrashedRunner` → "a crashed running row is recovered (continued and collected), not failed" (the deliberate DEC-054 change). `TestReconcile_IgnoresNonRunningStates` → `recoverHost` leaves queued and terminal rows' events unchanged. `LeavesLiveRunnerAlone` and `IgnoresOtherHost` are N/A: there is one runner, one host and one store file.

### Open
- A rejoin of a non-`preparing` row whose recorded policy or repo no longer resolves throws. The scheduler logs it and rests; the job stays held until the next restart, and no test covers this. A `preparing` row fails as `runJob` would.
- PHASE-11+ forward: `stopping` is the run's shutdown signal now. `awaitRoom` and `readyRoom` sleeps could take it, so that a stop does not hold the process for up to 60 s (PHASE-09 B Open). It is not done here.
- PHASE-11+ forward: a cancel that arrives after startup but before the rejoin seats the job goes through the store (`jobs.cancel`), as for any unseated job.
- PHASE-15 forward: the row-4 checks seam is the `prepare` entry (`readyRoom`). Row 5 never reaches it, and `ensure_job_branch` is only on the no-record branch. `host_key_alias` is untouched.
- The two open user questions are untouched: `cancelDeferred` under an exhausted budget, and the gated view's `getAuth`/`login`/`logout`. `biome.json` is untouched.

## PHASE-15 batch A (worker, opus)

### Produced
- Uncommitted delta in malebolge on `b82fa19`:
  - `src/runner/config.ts`: `[door] kind` is required, `"slot"` or `"room"`. `DoorConfig = SlotDoorConfig | RoomDoorConfig`. `[door]` keys are closed per kind: shared `kind`, `user`, `known_hosts`, `host_key_alias`; slot adds `slot`, `quarantine`, `host`, `profile`, `ssh_config`, `identity`; room adds `room`, `ssh_config`, `identity`, `session_path`, `probe_timeout_s`. Every key a kind needs is required at parse, and `host_key_alias` is required for both kinds (I13). `session_path` is kept verbatim (no `~` expansion). The door is read before the repos. `[repo.*]` takes `quarantine` and `transfer_timeout_s` only under a room door and requires them there, so a slot door or no door refuses them. `RepoConfig` gains `name` (the `[repo.*]` key) and the optional `quarantine` / `transferTimeoutS`.
  - `src/runner/exec.ts`: `runProgram` now runs over `spawn`, with one output path for bounded and unbounded runs. stdin is `/dev/null`. Output is decoded once at the end. Overflow at 64 MiB kills the program and rejects. With `timeoutMs`, the program is spawned `detached` (its own session and process group). Past the bound: TERM to `-pgid`, poll `kill(-pgid, 0)` until the group is empty or `killGraceMs` (default 5 s) passes, then KILL to the group and poll again. It then awaits the leader's `exit` and rejects `TimedOut`. `execFile`'s timeout is not used. Git calls stay unbounded.
  - `src/runner/room.ts`:
    - `SlotCli` is renamed `CapsuleCli` and now takes `(args, ProgramOptions)`. `execCapsule` is still the one production implementation.
    - `ChannelUnavailable.reason` is `channel_unavailable | channel_timeout`. `ChannelFailed.reason` is `channel_failed | channel_refusal`.
    - Shared helpers: `collectedJobRef(name, id)` (slot or room), `baseTip` (`base_ref_invalid`), `landed` (resolves the ref in the quarantine).
    - New `roomChannel(door, cli, reader)` with pure `roomPushArgs`, `roomCollectArgs`, `roomProbeArgs` and `roomVerbError`.
    - `refresh`: check `refs/heads/<base_ref>`, then `push`. Push's stdout must be a 40- or 64-hex oid, and that oid is returned. A push exit 2 re-checks the branch: absent → `base_ref_invalid`, else a refusal.
    - `collect`: runs the verb, then resolves `refs/capsule/<room>/heads/job/<id>` in the repo's `quarantine` (`landed`). stdout is ignored (orchestrator ruling on S1).
    - `reachable`: `capsule <room> ssh <user> true`, bounded by `probe_timeout_s`.
    - Exit codes: 75 → `ChannelUnavailable` (no probe); 2 → `ChannelFailed` `channel_refusal`; any other non-zero → `ChannelFailed`. `TimedOut` → `ChannelUnavailable` `channel_timeout`.
    - `channelFromConfig` dispatches on kind. `roomConnection` reads the union: host is the slot's `host` or the room's name, and `hostKeyAlias` comes from config. The `pi-env-${slot}` derivation and the `lacking` helper are deleted (config refuses missing keys now).
  - `src/runner/prepare.ts`: `ChannelFailed` records `failure.reason = error.reason`, so a refusal is `channel_refusal`. The `room_unavailable` failure carries `channel: error.reason`.
  - `src/runner/collect.ts`: the `pending_collection` transition's reason is `error.reason` (`channel_timeout` for a timeout). The `collection_failed` payload carries `channel: error.reason` for a `ChannelFailed`. No new writer.
- Tests (baseline 1029 → 1095; 45 files):
  - `config.test.ts` (VT-4): room parse, kind missing/unknown/non-string, room keys under slot (door and repo), repo room keys with no door, slot keys under room, each kind's required keys missing, timeout validation, `session_path` verbatim.
  - `exec.test.ts` (VT-3): bounded resolve, process group plus grandchild dead before the reject, KILL after the grace when the leader or the grandchild ignores TERM, output overflow.
  - `room.test.ts` (VT-1, VT-2 adapter half, EX-9): refresh, collect, exit-code typing, bounds passed (600 000 / 15 000 ms), a fake timeout and a real never-exiting `sleep` killed at its bound, reachable, `channelFromConfig` room, `roomConnection` both kinds and the configured alias, the EX-9 `result` quarantine and ref, and collection audit (`channel_timeout` → `pending_collection` then retried; exit 2 → `collection_failed` `channel: channel_refusal`).
  - `prepare.test.ts`: refusal → `channel_refusal`; a timeout retried within `max_room_wait`, then `room_unavailable` with `channel: channel_timeout`.
- Fixtures:
  - `config-fixture.ts`: `EXAMPLE_TOML` gains `kind = "slot"` and `host_key_alias = "pi-env-f"`. New `ROOM_TOML` (room `assistant`, `/work/satan`, `/var/lib/capsule/collect/assistant/satan.git`), `roomVariant`, `roomConfig`.
  - `room-fixture.ts`: `fakeRoom` and `roomKindWorld()`. The guest clone is unborn (`git init -b work`), and the quarantine is made by collect. `ROOM_DOOR`, `roomKindCollectWorld`. `collectWorld` is generalised to `collectWorldOver(world, config, …)`. The header records "follows oubliette SL-006 design sec-4/5/6 at 73ec574; re-check at SL-006's lock (CHR-016)" (EX-11).
  - `git-fixture.ts`: `tempUnbornRepo`, and `ISOLATED_ENV` sets `maintenance.auto=false` (see Learned).
- `just check` green: fmt, lint 0, tsc, 1095 tests. Coverage vs baseline: lines 98.08% (97.98), statements 97.86% (97.75), branches 93.95% (93.69), functions 98.12% (98.05). room.ts lines 100%.
- Mutation-checked, each fails a test:
  - exec: signalling `pgid` instead of `-pgid`; no KILL after the grace.
  - room: 75 typed as failed; push exit-2 re-check removed; refresh returning the locally resolved oid; collect reading `refs/capsule/<repo>/…`; probe unbounded.

### Learned
- **git 2.55 `fetch` starts auto-maintenance detached.** It can still be writing in a temp bare repo when `onTestFinished` removes it, giving `ENOTEMPTY` from `rmSync`. This was a pre-existing flake, about 1 in 15 runs of "a job branch moved after reviewed_oid …". `maintenance.auto=false` in `ISOLATED_ENV` fixed it: 0 failures in 40 runs. Memory candidate.
- Node `detached: true` calls `setsid()`, so the bounded program leads its own group and `kill(-pid)` reaches every descendant that stays in it. A descendant that calls `setsid` itself escapes; out of scope.
- The group check `kill(-pgid, 0)` counts zombies, so "group empty" means reaped. That is the guarantee the retry needs ("no orphaned git holding a ref lock").
- A mutant that drops the bound leaves `sleep` orphaned under init (ppid 1, pgid of the vitest group). The real-hang stub is now `sleep 60`, not `sleep 1000`.

### Deviations from the sheet
- **`RepoConfig.name` is new.** The port passes `RepoConfig`, and the room argv needs `<repo>` (the `[repo.*]` key). Batch B's room launch needs it too (`<session_path> <repo> -- <daemon>`). Two test literals were updated.
- Room repo keys are flat optional fields on `RepoConfig` (as the sheet suggests). The room adapter guards them (`roomRepo` → `ChannelFailed`), though config already guarantees them.
- Config refuses missing door keys at parse, not in `channelFromConfig` / `roomConnection` (StartRefused). runner-main's "refuses a [door] … naming the missing key" still passes, through the parse error.
- S1 is resolved per the orchestrator: collect stdout is not parsed. The fake still prints `<ref> <oid>` with a comment that the format is unpinned.
- The fake room's exit codes for front-end usage refusals (unknown room or target) are 2, and the probe on a down room is 255 (ssh's own failure). SL-006 sec-5 does not pin these. The adapter types only 75/2/other.
- Audit by reason. `pending_collection` transition `reason` is now `channel_timeout` for a timeout; the slot keeps `channel_unavailable`. `collection_failed` gains a `channel` field, and `room_unavailable` (preparing) gains a `channel` field.
- `runProgram` stdin is now `/dev/null` (`execFile` left an open pipe). No caller writes stdin.

### Open
- **Batch B:**
  - `roomConnection` gives a room door's host as the room name, but `start.ts`'s `connect` still uses pi-env's `sshConnection` with the daemon-path launch and accept-new. Until B lands, a room-kind config starts and would run the wrong daemon command. Only fixtures use the room kind, so nothing live is affected.
  - Use `repo.name` for the launch's `<repo>`.
  - The `DOOR_WORDS` structural test still passes unchanged: prepare.ts and collect.ts mention no door words. C7 splits it.
- **Batch C:** VT-2's `max_room_wait` keyword is not yet in `room.test.ts`. The preparing-timeout retry is tested in `prepare.test.ts` (`readyRoom` with a `channel_timeout` `ChannelUnavailable`). C should add the VT-2 preparing-half test in `room.test.ts`, or move it there.
- PHASE-12 deploy fact (carry-forward 2): the runner unit runs as the oubliette module owner (CON-003), for the slot deploy too. Nothing in config implies otherwise.
- S2 (host-key policy drift vs SL-006 sec-5 accept-new) is still a relay item. S1's unpinned collect stdout is moot for the runner, but worth relaying.
- Untouched: `cancelDeferred` under an exhausted budget; the gated view's `getAuth`/`login`/`logout`; `biome.json`.

## PHASE-15 batch B (worker, opus)

### Produced
- Uncommitted delta in malebolge on `ba4f0d3`:
  - `src/runner/env.ts`: `roomDaemon` (pi-env `sshConnection`) is replaced by:
    - `daemonCommand(room, launch, helpers)`: pi-env's `sshConnectionFor` recipe. `detectPlatform` once per connection, `deployDaemon` every start, then `[ssh, ...sshArguments(target, true), <launch words, each POSIX-quoted, space-joined>]`. `DaemonHelpers` (`ssh`, `detectPlatform`, `deployDaemon`) is the test seam; production uses pi-env's own (strict by default). The quoter is local to env.ts.
    - `DaemonConnection extends Connection`: wraps the command and keeps a trust record. A start that throws `HostKeyChangedError`/`HostKeyUnknownError` is recorded (by `instanceof`) before the rethrow. Only a start whose command is built (host key checked) clears it, so the rule fails closed: a later non-trust failure, or a concurrent start racing the reader, leaves `untrusted`.
    - `daemonConnection(room, launch, helpers?)`.
    - `ConnectionObserver.untrusted(failure, trust)` (required member). `JobConnection` reads the inner `DaemonConnection`'s record at every lost failure and calls `untrusted` instead of `lost`. A non-daemon inner (test fixtures) has no record.
  - `src/runner/room.ts`: `Launch` type and `daemonLaunch(config, repo)`. The slot launch is `[daemon]`; the room launch is `[session_path, repo.name, "--", daemon]`, with `session_path` verbatim. `ChannelFailed.reason` gains `host_key`.
  - `src/runner/start.ts`: `connect(repo)` = `daemonConnection(roomConnection(config), daemonLaunch(config, repo))`. Each call makes a new connection, so each job gets its own trust record (A3).
  - `src/runner/prepare.ts`: `roomShell`'s counting observer collects trust failures. An exec failing after one throws `ChannelFailed` `host_key`, so `readyRoom` does not retry and `preparingFailure` records `failed(error)` with reason `host_key`. Nothing marks a pause.
  - `src/runner/pause.ts`: `pausingObserver(deps, jobId, untrusted)`. Its `untrusted` marks nothing.
  - `src/runner/run.ts`: `openRun` passes `() => stops.latch.trip("host_key")`, the existing abort machinery. No second mechanism. `toCollecting` uses `latchedEnding`.
  - `src/runner/ceiling-latch.ts`: `LatchReason = Exhaustion | "host_key"`.
  - `src/runner/ending.ts`: `latchedEnding`. `host_key` → `end_reason = error`, payload `reason: "host_key"`; otherwise `ceilingEnding`.
- Tests (1095 → 1117; 45 files):
  - `env.test.ts` (VT-5):
    - Room command = `ssh <sshArguments(target, true)> '<session_path>' '<repo>' '--' '<daemon>'`, with the room name as host and the alias and `known_hosts` from config. `session_path` is verbatim (a `'` in it is quoted) and the repo is the job's.
    - Slot command = the daemon path alone.
    - `StrictHostKeyChecking=yes`.
    - `detectPlatform` is called once and `deployDaemon` every start, both on the configured target.
    - A lost failure through either kind's `daemonConnection` reaches `lost`.
    - Both `HostKey*Error`s reach `untrusted`, never `lost`.
    - The fail-closed rule, and the rule that a start past the key check clears the record.
    - A non-daemon connection's loss is `lost`.
  - `pause.test.ts` (VT-6):
    - Running, for each `HostKey*Error`: the room's restart fails trust. The job ends `failed`/class `error` after `collected`, with `endReason: error`, collecting payload `reason: host_key`, no `pause` event, no `waiting_room`, `pauseRequested` false.
    - Preparing, for each: `failed`, reason `host_key`, no sleep (not retried), no model call.
    - A plain failure of the same restart still pauses (`waiting_room`).
  - `recovery.test.ts`: row 8 restart redo with the host key changed meanwhile. The rejoined run aborts to collecting (`host_key`), never `waiting_room` (EX-5's "restart redo included").
  - `prepare.test.ts` (EX-8 / carry-forward 5, preparing half): `roomShell` over each kind's `daemonConnection`. A lost start is `ChannelUnavailable`; each `HostKey*Error` is `ChannelFailed` `host_key` → `failed`/`error`.
- Fixtures:
  - `env-fixture.ts`: `REMOTE`, `DAEMON`, `fakeHelpers(ssh, failure?)`, `doorFacts(config)`, and `RebuiltRoom` (a `DaemonConnection` that delegates to the local daemon until a `ROOM-DOWN` exec, then fails every start with the given error through the production trust record).
  - `run-fixture.ts`: `roomRebuilt(failure)` and `roomUntrusted(failure)`.
- `just check` green: fmt, lint 0, tsc, 1117 tests. Coverage vs `ba4f0d3`: lines 98.07% (98.08), statements 97.90% (97.86), branches 94.04% (93.95), functions 98.16% (98.12). The 0.01 drop in lines is `start.ts`'s production `connect` lambda, now on its own line and never called in tests (as before; its old one-liner counted as covered).
- Mutation-checked, each fails a test:
  - `JobConnection` ignoring the record.
  - The record cleared at start, and the record never cleared.
  - `sshArguments(target, false)`.
  - `detectPlatform` on every start.
  - `latchedEnding` without the `host_key` branch.
  - `roomShell` without the `host_key` branch.
  - `openRun` not tripping the latch.
  - The room launch with a fixed repo, and without `session_path`.
- Each mutant was restored from the in-memory original, not by git. No stray processes were left behind.
- `grep`: nothing in `src` calls `acceptHostKey`/`forgetHostKey`/`scanHostKey`, uses `accept-new`, or passes `sshArguments(…, false)`.

### Learned
- pi-env's `HostKeyChangedError`/`HostKeyUnknownError` do not set `name`; it stays `Error`. Tell them apart by `instanceof` or `constructor.name`, never by `.name`.
- `Connection.#start` calls the command function synchronously inside its own try. A rejection becomes `RemoteError{spawn_error, lost: true}` with only the message, so the type survives only in a record the command keeps.
- `typescript-eslint` `no-unnecessary-condition` flags a closure-assigned `let x: T | undefined` read after a reset (TS narrows it to `undefined`). `roomShell` keeps the trust failures in an array, read with `.at(before)`.

### Deviations from the sheet
- **The trust record lives on the connection (`DaemonConnection`), not as a `JobConnection` constructor option (B4).** `JobConnection` reads it from its inner by `instanceof`. This keeps `RunDeps.connect: (repo) => Connection` and every `enter`/`openRun`/`admit` signature unchanged, and the record cannot be wired to the wrong connection. A connection that is not a `DaemonConnection` has no record (its losses are `lost`).
- **The record is cleared only by a start that passes the key check (fail closed),** not reset at every start. This closes a race in which a concurrent start cleared the record before `JobConnection` read it, turning a changed key into a pause.
- **Preparing's trust failure is `ChannelFailed` `host_key`, not `PrepareFailed` (B4).** `failureReason` already maps `ChannelFailed.reason`, and the design classes a changed key as `ChannelFailed`. It also suits batch C's clean, which uses `roomShell` outside preparing.
- The launch is words (`Launch = (daemon) => readonly string[]`), computed in room.ts. env.ts quotes and joins them, so room.ts knows no shell quoting. `daemonLaunch` reads `door.kind` in room.ts only (EX-10).
- `ConnectionObserver.untrusted` is required, not optional. An observer without it must not silently fall back to `lost` (a pause).
- No `vocab.ts` change: failure and payload reasons are free strings, not a closed vocabulary.

### Open
- **The gate does not refuse a model request that races the `host_key` abort.** The pause has STOP-1 (`pausePending`); the latch has no equivalent for `host_key`. One raced request costs one model turn, then the abort lands, and `end_reason` is still `error`/`host_key` (`latchedEnding` overrides). The design does not ask for it, so nothing was built. If wanted, the meter could refuse on `latch.reason() === "host_key"` with its own refusal text.
- **The latch is still named `CeilingLatch`/`ceilingLatch`,** though it now carries `host_key`. Renaming it (e.g. `RunLatch`) touches run.ts and `ceiling-latch.test.ts` only. Not done, to keep B's diff focused.
- `daemonCommand` does not refuse a Windows remote; its launch quoting is POSIX. Rooms and slots are Linux. Such a start would fail as `lost` (a pause), not trust.
- **Batch C:**
  - Carry-forward 5's clean half (the clean through `roomShell` in `collectJob`) is C's. `roomShell` gives `ChannelFailed` `host_key` there, so C's audit of a failed clean should record `reason`.
  - C7's structural test: env.ts now names no door words. The header was reworded to "kind of room". `daemonLaunch` (the kind read) is in room.ts.
  - `CollectDeps.connect` (A4) can reuse `start.ts`'s `connect(repo)` lambda (`RoomAccess.connect`).
- PHASE-12 deploy fact (carry-forward 2, unchanged): the runner runs as the oubliette module owner (CON-003), slot deploy included.
- S2 relay (strict vs SL-006 sec-5 `accept-new`) is still outstanding. This batch builds strict.
- `biome.json` was already modified in the tree before batch B and is left as found.

## PHASE-15 batch C (worker, opus)

### Produced
- Uncommitted delta in malebolge on `c495a49`:
  - `src/runner/room.ts`: `GitChannel` gains `checkClone(shell, repo, signal) → CloneDefect | undefined` and `cleanClone(shell, signal)` (A1). `ShellOutput`/`RoomShell` move here from prepare.ts (the port's types); `RoomShell` takes an optional `cwd`. `succeeded` moves here too (shared by `ensureJobBranch` and the clean). Slot: both no-ops. Room: exported `checkRoomClone` (`test -d <guest_path>/.git` run from `/`, then `git status --porcelain --untracked-files=normal`; defect `guest_path_invalid {guestPath}` or `dirty_clone {paths}`) and `cleanRoomClone` (`git reset --quiet --hard`, `git clean -ffd --quiet`).
  - `src/runner/shell.ts` (new): `roomShell`, moved unchanged from prepare.ts except the per-call `cwd`. Used by preparing and by collection, so it no longer lives in prepare.ts.
  - `src/runner/prepare.ts`: `readyRoom` runs `channel.checkClone` every attempt, after the base and before `ensureJobBranch`; a defect is `PrepareFailed(defect)` → `failed(error)`. A `ChannelUnavailable` from the check retries as before. Row 5 (`recordRunning`) never reaches `readyRoom` (carry-forward 4).
  - `src/runner/collect.ts`: `CollectDeps.connect` (moved from `RunDeps`, which inherits it). `checkAndClassify`: inspect → `recordCollected` (durable) → `cleanAfterCollect` → mismatch/check/classify. The clean opens its own connection (pi-env `Connection` starts at its first request, so the slot's no-op never starts one), runs through `roomShell` (counting), closes it in `finally`. A failure appends `clean_failed {reason, message}` (reason = the channel error's `reason`, e.g. `channel_unavailable`, `channel_failed`, `host_key`) and changes nothing else.
  - `src/runner/vocab.ts`: `EVENT_KINDS` appends `clean_failed`.
  - `src/runner/start.ts`: the scheduler's `CollectDeps` gets `connect: room.connect` (one lambda for runs, pending-collection retries and rejoin row 12); `runDeps` inherits it.
- Tests (1117 → 1142; 46 files):
  - `prepare.test.ts` (VT-7): fresh unborn clone takes `git switch -c job/<id> <oid>`; guest_path without `.git` and absent → `guest_path_invalid`; untracked file + untracked dir → `dirty_clone` with paths, tree and branch left as found; ignored-only passes. Fake-channel: check runs every attempt after the base; a defect fails with no branch work, no sleep.
  - `recovery.test.ts`: the `watched` channel now runs the room's real hygiene in the slot clone and records `check`/`clean`, so the whole matrix exercises it. New: row 4 with residue → `dirty_clone`, no switch, no model call; row 5 with the agent's files → no `check`, records `running` once, `needs_review` (VT-7 fault injection); row 12 crash at `collected` with residue → rejoin collects then cleans, residue gone (VT-8, R1). The disabled matrix's "no env command" assertion now also covers check/clean (R1 disabled half).
  - `collect.test.ts` (new, VT-8): reset + `clean -ffd` (tracked edit reset, untracked file and nested repo removed, ignored kept); idempotent; failed collect (exit 1) and room down (exit 75) leave the tree untouched; stale `index.lock` → `clean_failed channel_failed`, outcome unchanged; per kind (slot/room `daemonConnection`): lost start → no `pause_requested`, no pause event, `clean_failed channel_unavailable`; `HostKeyChangedError` → `clean_failed host_key`; crash before the clean → still `collecting` with `reviewed_oid`, re-collect cleans, `collected` once.
  - `room.test.ts`: VT-2 preparing half (`readyRoom` over the real room adapter: hung push retried within `max_room_wait`, then past it `room_unavailable` / `channel_timeout`); slot hygiene never touches the shell; EX-10 structural test split (below).
  - `room-fixture.ts`: `roomKindWorld({ guestAtClone })`; `roomKindCollectWorld` uses it (clean runs for real); `collectWorldOver` gives `connect: localConnection`; new `readying(world)` (a preparing job + `readyRoom` through a local daemon).
- EX-10 regexes: door words `/\bcapsule|\bslot|\bdoor/i` → files ⊆ {room.ts, config.ts, env.ts}, ⊇ {room.ts, config.ts}; kind words `/["'](?:slot|room)["']|\bsession_?path|\b(?:probe|transfer)_?timeout_?s\b|\b(?:slot|room)Door(?:Config)?\b/i` → exactly {room.ts, config.ts}. Mutation: a `transferTimeoutS` read in collect.ts fails the kind test; `// the slot` in prepare.ts fails the door test.
- `just check` green: fmt, lint 0, tsc, 1142 tests. Coverage vs `c495a49`: lines 98.14% (98.07), statements 97.97% (97.90), branches 94.11% (94.04), functions 98.17% (98.16).
- Mutation-checked (each fails a test; restored from copies, `cmp`-verified): check without `cwd /`; `clean -fd`; clean before `recordCollected`; clean failure rethrown. Red shown before green for the check (5 failing) and the clean (8 failing) by removing each call site.

### Learned
- pi-env `Connection` is lazy: the constructor stores options; `#connect` starts on the first request. A connection that is never used costs nothing and `close()` on it is safe.
- An exec whose `cwd` does not exist fails on a live connection (ChannelFailed), so "guest_path absent" needs the check run from `/` to be `guest_path_invalid`. `RemoteExecutionEnv.exec` takes a per-call `cwd`.
- The run fixture's agent commits with `git add -A`, so planted agent files outside `allowed_paths` become a `path_violation`; plant under `src/`.

### Deviations from the sheet
- Clean placed after `recordCollected`, not between `channel.collect` and `checkAndClassify` (A4): design §5.4 step 2 says "Record `reviewed_oid` … then clean". Still before classification, so a crash leaves `collecting`. Covers all three `collectJob` callers.
- Clean also runs when the recorded oid mismatches or the quarantine read fails: the collect itself succeeded, and the clean discards only working-tree residue (commits stay on the job branch).
- `checkClone` returns the defect instead of throwing (no new error class; prepare.ts wraps it in `PrepareFailed`, kind-blind).
- `RoomShell` gained an optional `cwd` (for the check from `/`).
- New `shell.ts` for `roomShell` (A1 left it to the worker); `succeeded` moved to room.ts.
- `clean_failed` is a new event kind (audit vocab append).
- The row-5 "agent's files → running" VT-7 case lives in `recovery.test.ts` (needs the restart harness); prepare.test.ts holds VT-7's other cases and keywords. Same split as VT-2 (adapter in room.test.ts by A; preparing half added there by C, A's unit test kept in prepare.test.ts).

### Open
- The clean's signal is never aborted (`CollectDeps` has no `stopping`); a hung git in a live room would hold collection. Same as preparing's shell; out of scope with the `stopping`-into-sleeps item.
- `clean_failed`'s non-channel fallback reason (`clean_failed`) is not covered by a test.
- PHASE-12 deploy fact (carry-forward 2, unchanged): the runner runs as the oubliette module owner (CON-003), slot deploy included.
- PHASE-11/12: a `dirty_clone` wedge needs the operator remedy (design §5.2); worth a line in the runbook. `clean_failed` events are the signal to watch.
- Relays to oubliette still open: S2 (strict vs sec-5 `accept-new`), S1 (collect stdout format). EX-11: fixtures follow SL-006 at `73ec574`; re-check at SL-006 lock (CHR-016).
- Carried from B, untouched: `CeilingLatch` rename; the `host_key` model-gate race; `cancelDeferred`; gated view's `getAuth`/`login`/`logout`; `biome.json` (pre-existing `!.mcp.json` edit, left as found).

## PHASE-11 (worker, sonnet)

### Produced
- T1 pre-fence: non-terminal `patch_jobs` query returned zero rows; all rows `failed|21`; `systemctl --user is-active satan-patcher` = `active`.
- `satan/satan-tools-patch.el`: unconditional fence clause before the success `t` branch of `satan-tool/patch-job-create` -> `(error . "patch runner migration in progress (SL-023 cutover): patch_job_create is fenced")`; docstring updated. PHASE-13 deletes it.
- `satan/test/satan-tools-patch-test.el`: new `create-refused-migration-in-progress` (no DB; store-insert stubbed to fail). Removed `create-success` / `create-emits-intervention-args`, the intervention stub and ctx const; setup now via fixture.
- `satan/test/satan-patch-fixture.el` (new, not a suite file): `satan-patch-fixture-enqueue` inserts a queued job via the store plus the `queued` transition event. Used by tools-patch and patch-runner tests (DRY).
- `satan/test/satan-patch-runner-test.el`: `--enqueue` and the real-pi test use the fixture (they went through the fenced handler; the sheet missed this).
- `~/.config/emacs/apps/dl-satan.el`: `satan-patch-runner-enabled` -> nil with comment.
- `~/flakes/features/satan/patcher.nix`: `enable = false` with comment; `~/flakes/SATAN.md` satan-patcher row Role -> disabled (fenced).

### Learned
- Plan path `modules/home/linux/satan-patcher.nix` is stale; real file is `features/satan/patcher.nix`.
- Ad-hoc `emacs --batch -l` picks stale `.elc` ("newer than byte-compiled file; using older file") and shows the old handler; `just check` runner sets `load-prefer-newer`. Use `--eval '(setq load-prefer-newer t)'` for ad-hoc runs.
- Red evidence: new test failed ("store insert reached") before the clause; green after.
- `just check`: 1347 tests, 0 unexpected, 6 skipped (none are patch-tool tests; all 11 `satan-tools-patch/*` ran and passed, DB reachable). Skips: patch-listener integration, runner real-pi, 3 memory-grammar db-sync, integration morning.

### Deviations
- Touched `satan-patch-runner-test.el` and added `satan-patch-fixture.el` (outside the sheet's listed test file) because runner tests called the fenced handler.

### Open
- Human steps (EX-3/VH-1), not done:
  1. `cd ~/flakes && just home-switch` (runs `home-manager switch --flake '.#david@Sleipnir' <local overrides>`).
  2. Emacs: restart, or `M-x eval-buffer` in dl-satan.el, or `emacsclient -e '(setq satan-patch-runner-enabled nil)'`; reload satan checkout so the fence is live.
- Post-deploy verification (agent): `systemctl --user is-active satan-patcher` -> `inactive`/unit not found; `systemctl --user is-enabled satan-patcher` -> not `enabled`; `pgrep -a satan-patcher` -> nothing; `emacsclient -e 'satan-patch-runner-enabled'` -> `nil`; `psql -d satan_memory -Atc "select state,count(*) from patch_jobs where state not in ('needs_review','failed','cancelled','accepted_external','stale') group by 1"` -> no rows; `emacsclient -e '(satan-tool/patch-job-create (list :directive "x" :mode "self-edit-mech" :repo "/tmp" :allowed_paths (list "a") :start nil) nil)'` -> `(error . "patch runner migration in progress ...")`.

## PHASE-16 batch A (worker, sonnet)

### A0: EX-5 precondition (recorded before the refusal was built)
- `@earendil-works/pi-durable` 1.3.0 (installed, pinned beside pi-env 1.3.0). Re-run at malebolge `3eef85a`: `grep -rnwE "login|logout|getAuth" node_modules/@earendil-works/pi-durable/dist` returns 0 lines. pi-durable never calls or destructures `getAuth`/`login`/`logout` on the job's `Models` view.
- `models.<member>` uses in pi-durable: `harness/generation.js` `streamSimple` (:315), `fetchDeferred` (:151), `cancelDeferred` (:183); `harness/compaction.js` `completeSimple` (:128), `getModel` (:64); `codemode/models.js` `classify`, `generateImages`, `getModelsOfType`, `getAvailableOfType`, `getModelOfType`. None is an auth member.
- pi-ai resolves auth internally (`applyAuth` calls `this.getAuth` on the real `Models`); `gatedModels` delegates to `real` bound, so refusing the view's auth members cannot affect generation.
- `generation.js:183` calls `cancelDeferred` on abort: the old gate refused it when exhausted (the bug DEC-057's 2026-10-19 ruling fixes).

### Batch A produced (malebolge, uncommitted on baseline 3eef85a)
- `src/runner/model-gate.ts`: `cancelDeferred` removed from `ENTRY_POINTS` and delegated bound to `real` (never consulted, never counted, never refused; DEC-057 2026-10-19). `getAuth`/`login`/`logout` now reject `GateRefused("credentials")` via one shared `refuseCredentials`; new `Refusal` member `"credentials"` with fixed text (contains no retryable wording; the EX-6 word-scan test covers it). `rethrow` deleted (unused). Doc comments updated.
- `test/runner/model-gate.test.ts`: `credentials` added to `REFUSAL_REASONS`; `cancelDeferred` row dropped from `ENTRY_ROWS` and the refusal filter removed; unit tests for cancelDeferred-always-passes and for getAuth/login/logout refused (spies prove `real` untouched); harness test inverted: exhausted `model_requests: 1`, abort reaches the provider (`cancelledDeferred` non-empty), `model_requests` stays 1, no ceiling event, `seen == ["streamSimple"]`. fetchDeferred (exhausted refused) and runtime.models-from-a-tool tests unchanged and green.
- Red evidence: 4 tests failed before the source change (credentials wording, cancelDeferred unit, auth unit, cancelDeferred harness); 47 passed.
- Result: model-gate.test.ts 51 tests green; `just check` green (see hand-back for totals).
- OQ-4 ruling applied: `GateRefused` with reason `credentials`.

## PHASE-16 batch B (worker, opus)

Malebolge, uncommitted on `0824e56` (batch A). Rulings applied: OQ-1 (a)
`reachable(repo: RepoConfig, jobId)`, both adapters (the slot ignores the
arguments); OQ-2 the probe IS the collect, so a `capsule` that cannot spawn is
`ChannelFailed` (a deploy fault fails loud); OQ-3 the sheet's defaults.

### What changed, by EX / VT
- **EX-1 / VT-6** (`config.ts`): `probe_timeout_s` gone from `DOOR_KEYS.room`,
  `RoomDoorConfig` and the parse, so `onlyKeys` refuses it under either kind.
  Test: one `it.each` "probe_timeout_s under kind = %s refuses start: the probe
  is a collect" (slot + room). Superseded rows deleted (parsed `probeTimeoutS`,
  missing-key row, 0 / fractional rows, the old slot row); fixture line removed.
- **EX-1, EX-2 / VT-1** (`room.ts`): port member is
  `reachable(repo, jobId)`, doc per rev 63. Room `reachable` = `collect` with
  `ChannelUnavailable` → false, everything else rethrown; it inherits the
  `transfer_timeout_s` bound, the exit mapping and the VT-2 cross-check (no
  second implementation). `roomProbeArgs` deleted; `RoomDoor` narrowed to
  `room`. Slot: the private probe is renamed `probe` (still used by `step()`),
  exported as `reachable`. Tests: describe "reachable(repo, job) over a room is
  this job's collect (DEC-060, VT-1)" — 0 → true with the collect argv and the
  quarantine ref written; 75 → false; hang → false at 600_000; 1 → ChannelFailed
  `channel_failed`; 2 → `channel_refusal`; bad stdout → ChannelFailed; spawn
  failure → ChannelFailed (OQ-2). Timeout describe renamed "room verbs past
  their bound: transfer_timeout_s (no probe_timeout_s: the probe is a
  collect)", bounds `[600_000 ×3]`; real `sleep 60` test now calls
  `reachable(repo, JOB)` with `transferTimeoutS: 1`. "channel from config"
  room case answers 75 and expects `["assistant","collect","satan","job/pj-1"]`.
- **EX-3 / VT-2** (`room.ts`): room `collect` compares stdout (one trailing
  `\n` allowed) with `lsRemoteLine(landed)` = `<oid>\t<ref>`; any difference is
  `ChannelFailed` naming both. The "no pinned format" comment is gone. Fake
  room: prints `<oid>\t<ref>\n`; new knob `collectStdout`. Test: it.each over
  another oid, another ref (`refs/capsule/<room>/heads/job/other`), ref first,
  space for the tab, two lines, empty.
- **EX-4 / VT-3** (`jobs.ts`, `pause.ts`, `run.ts`, `collect.ts`):
  `TRANSITIONS.waiting_room` gains `collecting` (LEGAL updated; a unit test
  shows the edge charges no `active_ms`). `awaitRoom(deps, repo, job, signal)`
  rethrows a probe `ChannelFailed`; `awaitResume` catches only `instanceof
  ChannelFailed` → `roomProbeFailed` (`collecting`, `end_reason = error`,
  payload `{ reason: error.reason, message }`), returned as `{ ended }` so the
  existing `superviseRun` tail collects it. `Run` gains `repo` (set in
  `openRun` from `Resolved`), so the waiting episode reuses the run's resolved
  repo, no new lookup. `retryPendingCollection` passes the job's repo
  (`config.repos.get`, as `collectJob` does) and maps a probe `ChannelFailed`
  to `failOutright` with `collectionFailed(error)` = `{ reason:
  "collection_failed", channel, message }`, now shared with `collectJob`'s
  catch. Tests (pause.test.ts, "a probe ChannelFailed ends the job, never
  parked (VT-3, EX-4)"): waiting half — transitions after `waiting_room` are
  exactly `collecting, failed`, class `error`, no resume (2 provider calls);
  pending half — `roomKindCollectWorld`, exit 1 on retry → `failed`, class
  `error`, `channel: channel_failed`, last transitions `pending_collection,
  failed`. Recovery (rejoin → awaitResume): "row 11, the rejoined probe
  ChannelFailed: collecting with end_reason error, no resume".

### Red evidence
- VT-6: room row failed (config parsed) before the config change.
- VT-2: all 6 rows failed (collect resolved) before the cross-check.
- VT-1: 9 room tests failed before the adapter change ("exit 75" passed in red
  only because the old ssh probe had been removed from the fake: not
  discriminating in red, discriminating after).
- VT-3: waiting half stayed `waiting_room`; pending half threw ChannelFailed.
  jobs.test: 3 failed (edge missing). Recovery row 11 written after green;
  checked by disabling the `awaitResume` catch: it and the VT-3 waiting test
  both failed, then the catch was restored.

### Result
- `just check` green: 46 files, 1157 tests, lint zero warnings, typecheck and
  format clean, coverage gate met.
- Flake check: room/pause/recovery/collect tests (179) run 5× green. The fake
  channels' git (slot and room `gitStep`) runs with `ISOLATED_ENV`
  (`maintenance.auto=false`), so the extra per-probe fetch cannot start
  detached maintenance. Agent commits in run worlds use their own env
  (`GIT_CONFIG_GLOBAL=/dev/null`), unchanged and unaffected by this phase.

### SL-006 sec-6 revision followed
Oubliette `ad2dd7d` (last change to SL-006 design): collect prints one line
`<oid>\t<ref>` in `ls-remote` order (sec-6 and the GitChannel row). This closes
PHASE-15 relay item S1. Source and fixture header comments now cite it.

### Judgement calls (for /audit)
- **Cross-check is an exact line compare, not a parse.** The sheet suggested a
  parse function reusing `OID`; comparing stdout with the expected line built
  from the quarantine needs no parse and rejects every malformed shape. `OID`
  is not reused here (the quarantine's oid needs no validation).
- **Unconfigured repo in `retryPendingCollection`:** the probe is skipped and
  the job goes to `collecting`, where `collectJob` fails it
  `repo_not_configured`, as before this phase.
- **`awaitRoom` takes the repo positionally** from `run.repo` (new `Run`
  field) rather than resolving config itself; pause.ts stays door-free.
- `prepare.test.ts`'s zero-argument stub still type-checks against the new
  member, so it is unchanged.
- The rejoined-probe recovery test ends class `no_changes`, not `error` (the
  job never committed; the class table ranks `no_changes` first). It asserts
  `end_reason = error`, class `no_changes` and the `waiting_room → collecting`
  edge.

### Friction
- vitest does not typecheck, so a red run with a changed signature exercises
  runtime behaviour only; `npx tsc --noEmit` was the guide for callers.
- Lint caught `expect.stringMatching` in a `toMatchObject` as unsafe `any`
  assignment, and a default destructured parameter tipping `complexity` past 8
  in the fake; both reshaped.

## PHASE-12 batch B (EX-2)

Model: sonnet. Argument: additive negative assertions in two files that already have the helper pattern, plus a read-only sweep; no design judgement.

**T-B1** `~/flakes/agents/jailed-agents-test.nix`: the `/run/user/1000` refute now loops spec/research/offline (was spec only). New loop after the gateway launches refutes `satan-runner` in 10 launchers (spec, research, offline, op-run inner, gw outer+inner, research gw inner, claude-pi gw inner, eca outer+inner), `test -f` first so the refute is not vacuous.
Red: temporary `try-ro-bind` in `hostDoctrineOptions` (all profiles). `try-readwrite "/run/user/1000/satan-runner"` failed on the (extended) `/run/user/1000` refute; `try-readwrite "/xdg/satan-runner"` failed on the new satan-runner refute (`grep -Fq -- satan-runner .../jailed-zsh`). First attempt in `postgresOptions` stayed green: that option set is not in any test profile (not a bug; wrong place for the red). Reverted; green: `nix build path:/home/david/flakes/agents#checks.x86_64-linux.jailed-agents --no-link --no-write-lock-file` rc=0.

**T-B2** `~/dev/satan/flake.nix`: new sibling check `runner-socket-unjailed` (`runnerSocketUnjailed`), iterating `lib.attrValues jailPkgs`, every `bin/*` launcher plus the inner it execs (`exec /nix/store/...-jailed-*`), asserting absence of `satan-runner` and ` /run/user/1000 ` (whole runtime dir as a bind arg; written literally). Broader `XDG_RUNTIME_DIR` / `/run/user` probes rejected: jailed-claude legitimately has `--bind-try /run/user/1000/satan/mcp/...` and `--setenv XDG_RUNTIME_DIR`. `justfile` `check-jails` gains the second `nix build` line (needed to run it). Red (temp raw bind in `satanJailOptions`, reverted): `--bind-try /run/user/1000/satan-runner /x` and `--bind-try /run/user/1000 /run/user/1000 --x` each failed with `jailed-satan-fake-harness must not contain ...`. Green: `just check-jails` rc=0; `just check` rc=0 (55 tests OK).

**T-B3 sweep** (read-only): `satan-runner` appears in none of ~/satan-corpus, ~/dev/satan-attrd, ~/dev/goad, ~/notes, ~/.config/emacs; in ~/flakes only in `agents/jailed-agents-test.nix` (the new assertion). No `/run/user/1000"`, `/run/user/1000 ` or `"$XDG_RUNTIME_DIR"` bind/jail lines in any of the five. satan-attrd and goad flakes define jails (flake.nix mentions jail) but have no profile tests; not added (open question 3). Note: `grep --dereference-recursive` over all of ~/flakes timed out; used plain `-r` there.

## PHASE-17

- malebolge `ef470b8`; `just check` green, 1186 tests, lint 0; worker model
  sonnet; EX-1..5 and VT-1..4 met.
- Catalog fixture `test/gateway-catalog.json` hand-written from
  `agents/gateway.nix`'s `deepseek-flash` pi block at flakes HEAD
  `add489ed`, plus cost `{0.3, 1.2, 0.006, 0}` (the sheet had cited
  `28c0cf53`).
- Audit items: (1) daemon (`src/daemon-main.ts`) not wired to the gateway
  provider (E2; design §5.1/§10 say both binaries); (2) zero cost accepted
  when present; (3) `thinkingLevelMap`/`compat` passed through,
  shape-checked only; (4) the runner catalog is gateway-only (the built-ins
  + coding-agent store default is gone from the runner); (5)
  `requiredEnv`/`Env` moved to `src/runner/errors.ts`.
- Fact: pi-ai 1.3.0 `createProvider` + `openAICompletionsApi()` sends `POST
  <baseUrl>/chat/completions` with `Authorization: Bearer <key>`.

## PHASE-12 (re-plan, room)

### Batch A (worker, opus)

Model: opus. Argument (orchestrator): wires a secret (`LoadCredential=`) into a
user unit, refactors the shared `piGatewayConfig`, sets a price feeding the
DEC-057 cost ceiling, and writes host-key / trust-boundary scripts; mistakes are
silent and security-relevant, and home-manager is unfamiliar ground.

Bases: malebolge `ef470b8`, satan `b0a37a1`, home `28c0cf53`, fleet `b3011a7`.

**E1 re-read (read-only):** `/srv/fleet` HEAD `b3011a7`, tree clean;
`targetNames` lists `goad-walk`; `rooms.assistant.repos.targets = targetNames`.
The removal the planner saw is gone. goad-walk stays the smoke repo.

**T-A1 `piGatewayConfig` moved** to `~/flakes/agents/pi-gateway.nix`
(`{lib}: url: models: …`, body and comment verbatim); `jailed-agents.nix`
imports it and still re-exports it. Guard: jailed-agents check out path
`bj2ph1qj…-jailed-agents-policy-tests` before and after: identical
derivation, so no behaviour change.

**T-A2 cost** on `models.deepseek-flash.pi`: `{input 0.3, output 1.2,
cacheRead 0.006, cacheWrite 0}` USD/Mtok. Sources agree: (a) pi-ai 1.3.0
`dist/providers/data/deepseek.json` id `deepseek-flash`; (b) LiteLLM 1.102.1
`model_prices_and_context_window_backup.json` `deepseek/deepseek-flash`
(3e-7, 1.2e-6, 6e-9, 0 per token); the gateway unit sets
`LITELLM_LOCAL_MODEL_COST_MAP=True`, so (b) is what it bills. No other model
has a `pi` block. No test pins the JSON (`expectedPiModels` derives from
`gatewayData`); check rc=0, new out path (models file changed, intended F7).

**T-A3 `features/satan/runner.nix`** + registry (`features/satan.nix`),
`feature.satan.runner.enable = mkDefault true` (`features/profiles/personal-linux.nix`),
`features-test.nix` wants `satan.runner#homeManager` (red with the profile
line removed: `features-test.nix failed`, rc=1; green restored, rc=0),
README feature-tree line. Judgement calls:
- **Absolute paths in the unit, not `%h`.** EX-8 names the absolute path;
  A2 wants one rule. Also found: `systemd-run --user -p
  LoadCredential=x:%h/…` is refused ("Credential source is invalid") and `-E
  X=%S` is passed literally: transient properties expand no specifiers. The
  host-key script therefore passes absolute paths.
- **`StateDirectory=satan/runner` + `StateDirectoryMode=0700`** over
  `ExecStartPre install -d`: declarative; `man systemd.exec` gives
  `$XDG_STATE_HOME` as the user root, and the user manager sets no
  `XDG_STATE_HOME` (`systemctl --user show-environment`), so `%S` =
  `~/.local/state`, matching the explicit `XDG_STATE_HOME`. M's own `mkdir`
  would make it 0755.
- `[mode.fix]` rendered (empty): submit refuses an unconfigured mode
  (`protocol.ts` `knownMode`), and the smoke submits `fix`.
- `[maxima]` design §5.3 example, `cost_usd = 0.50`; `transfer_timeout_s =
  600` (A4, orchestrator-accepted).
- **E4 gap:** the fleet exposes no room data (outputs: devShells,
  nixosConfigurations, nixosModules, packages; home-manager is standalone, no
  osConfig). Room/repo values are literals, commented with their fleet source.
  Design §5.3's one-source claim is unmet: /audit item.
- `nodejs_24` = 24.21.0 at `~/flakes`' pin (`--inputs-from .`); the built
  unit's node is `nodejs-24.21.0`.

**T-A4 verify (no switch):**
1. `just home-build` rc=0.
2. `result/home-files/.config/systemd/user/satan-runner.service`: ExecStart
   `/nix/store/…-nodejs-24.21.0/bin/node /home/david/dev/malebolge/src/runner-main.ts`;
   Environment = config path, XDG_STATE_HOME, PATH (no key);
   `LoadCredential=satan-runner:/home/david/.config/llm-gateway/keys/satan-runner`;
   RuntimeDirectory/StateDirectory 0700; StartLimit* in `[Unit]`;
   `default.target.wants` link present. `systemd-analyze --user verify` rc=0
   (one unrelated warning from `~/.config/environment.d/10-home-manager.conf`).
   Catalog `…-satan-runner-gateway.json`: one provider, `deepseek-flash`
   with cost.
3. M's real parser, parked start, scratch dirs, **temporary config copy with
   `prompt_file` → a scratch file** (Batch B's draft not on disk yet):
   store/control lines logged, no refusal, ran to `timeout` (rc 124); runtime
   dir 700. Unmodified rendered config: `refusing to start: prompt_file
   …/patch-agent.md: ENOENT`, rc=1, as expected until Batch B.
4. `just gate` rc=0 (features, factories, host-meta, workarounds,
   llm-gateway, jailed-agents, treefmt). `flake.lock` untouched (user's dirt,
   mtime before this batch). statix W20 on `personal-linux.nix` pre-exists at
   HEAD; treefmt passes.

**T-A5 `~/flakes/SATAN.md`:** Units row, Storage rows, Secrets paragraph,
Jails paragraph (which tests assert the socket/credentials dirs are unbound;
none names `credentials` itself, covered by the whole-dir refute), new
`## satan-runner` section: Switches (the one-line enable), Room values,
Host keys, `dirty_clone` remedy, Watching `clean_failed` (sqlite query),
Live checks, First deploy steps 0-10 with agent checks.

**T-A6/T-A7 malebolge:** `test/runner/live-smoke.ts`, `live-host-key.ts`,
shared `live-fixture.ts` (+ `live-fixture.test.ts`, 17 tests; outside the
sheet's file list: the scripts' testable parts, one copy for both),
`justfile` recipes `smoke-runner *args`, `smoke-runner-host-key`. Red: test
file before module (no tests ran), then `answered`/`deployedPaths` (3
failing); green. Follow is `status` polling every 2 s (watch frames carry no
events). Job events are read from the store with `node:sqlite` `readOnly`.
The host-key verdict reads the scratch store's `transition` events: failed
from `preparing`, reason `host_key`, no `waiting_room`. Tamper changes one
base64 character 10 from the end of the alias line's key (the type prefix
untouched). Only the refusal paths were run (no `SATAN_RUNNER_LIVE`: refuse;
with it, the host-key script stops at the missing deployed config).
`just check` rc=0: 47 files, 1203 tests, coverage lines 97.93%, lint 0.

### Friction (Batch A)
- `systemd-run` properties expand no specifiers, unlike unit files; a
  planning probe with a literal path could not show it.
- The `~/flakes` gate output is dominated by lock-diff noise from the dev
  overrides; rc is the only reliable signal.

### Batch B (worker, sonnet)

Prose against a checklist, plus a read-only sweep. Edits: the prompt draft only
(and this section). Nothing committed, no tests added, nothing fixed.

**Prompt draft.** `/home/david/satan-corpus/prompts/patch-agent.md` — new,
**uncommitted, for the user's review** (the runner refuses to start without the
file, `prompt_file` is checked before `enabled`). Written against design §5.2
(Job contract, Policy ladder and prompt, Execution environment, Tools offered),
§5.4 (collection and classification) and `src/runner/prompt.ts` (the job block
it appends). It explains, and does not restate, the job-block values or the
commit-footer template. The old `patch-agent/prompt.md` is untouched.

Departures from the old prompt: dropped the bubblewrap jail framing (now an
isolated VM room; no network uplink); the worktree (now a clone at `cwd`); the
`checks` list (the runner runs none, DEC-059; agent runs the repo's checks if
asked); `.satan-patch-manifest.json`; the "one commit" rule and cherry-pick
review (now: commit as you go on `job/<id>`, only that branch is collected);
the inline commit footer/subject template (the job block supplies it). Added:
collection semantics (uncommitted work discarded), allowlist checked at
collection (`path_violation`, never promotable), pauses invisible, ceilings may
end the job, human promotes in Emacs, repo-relative paths only (`~`/absolute
match nothing), tools `read`/`write`/`edit`/`bash` in the clone with the repo's
tool set on `PATH`.

**Jail sweep (EX-12).** Pattern: `grep -rIl --dereference-recursive -e
satan-runner -e credentials -e /run/user/1000 -e XDG_RUNTIME_DIR` over each
repo (`.direnv/flake-inputs` copies are cached upstream sources, ignored), plus
a grep of the built launchers (`nix build .#jailed-pi --no-link --offline`
works for both; outer `op run` wrapper and the inner bwrap launcher both
scanned).

| repo | `satan-runner` | `/run/user/1000` whole | `/run/user/1000/credentials` | verdict |
|---|---|---|---|---|
| satan-attrd | none | no | none | not exposed |
| goad | none | no | none | not exposed |

- satan-attrd `flake.nix:70`: `(try-readwrite "/run/user/1000/docker.sock")`, one
  socket file only. Built inner launcher: two occurrences of
  `/run/user/1000/docker.sock`, nothing else under `/run/user`. (The
  `tests/common/mod.rs:67` hit is the word "credentials" in a URL-parsing
  comment.)
- goad `flake.nix:48,190-192`: comments say the host `/run/user/1000` is
  deliberately kept out; `:59-60` and `:192` set `XDG_RUNTIME_DIR` to
  `/tmp/xdg-runtime` (inside the jail's tmpfs) rather than binding or
  forwarding the host's. Built inner launcher: one `XDG_RUNTIME_DIR`
  occurrence (the set-env), no `/run/user/1000`.
- Neither flake has any `satan-runner` reference, and neither is covered by a
  `runner-socket-unjailed` check (see table).

**Drift report.** References: `~/dev/satan/flake.nix` (S) and
`~/dev/doctrine/flake.nix` (D). All four lock the same `agents` rev
(`ea3cf561bc`, lastModified 1792329380); S also carries a second `agents_2`
node (`4869e4fb8a`, via a transitive input). So the library version is not
drift today; the differences are in how each flake uses it.

| feature | satan (S) | doctrine (D) | satan-attrd | goad |
|---|---|---|---|---|
| `agents` pin | ea3cf561bc | ea3cf561bc | ea3cf561bc | ea3cf561bc |
| gateway client | `gatewayClient "pi"` on every jail, `"satan"` on harness (`:51-52`) | `gatewayClient "pi"` via `mkJail` (`:186`) | **none**: launcher is `op run --env-file ...api-keys.env` (built output) | **none**: same `op run` wrapper |
| provider keys | via gateway key on FD 22 | via gateway key on FD 22 | stock env forwarding (`try-fwd-env "OPENROUTER_API_KEY"`, `:67`) | own `apiKeysViaFd` on fd 21, `passApiKeysFromEnv = false` (`:119-140`) |
| bound pi `models.json` / `piGatewayConfig` | via gateway client | via gateway client | absent | absent |
| shared `mkJail` helper | no (each jail spelled out) | yes (`:177-190`) | no | yes (`mkJail`, `:196`) |
| profiles | specDev, research, offline (harness) | specDev, research | specDev, research | specDev (research absent) |
| jails exported | jailed-pi, -pi-research, -claude, -shell, SATAN harnesses; codex commented out | pi, pi-research, claude, codex, shell | pi, pi-research, claude, codex (opencode/gemini commented) | claude, codex, pi |
| `subagents` | `["pi" "claude"]` | claude/codex/shell take lists | none | claude `["codex"]`, codex `["claude" "codex"]` |
| `try-fwd-env` | MCP/DB/DOCKER vars (`:84-100`) | `DOCTRINE_BIN` | `DATABASE_URL`, keys, `DOCKER_HOST` | none (set-env only) |
| runtime-dir binds | `/run/user/1000/satan/mcp/mcp.sock`, `emacs/server`, `podman/podman.sock`; forwards `XDG_RUNTIME_DIR` (`:84-95`) | none | `docker.sock` only | none; `XDG_RUNTIME_DIR=/tmp/xdg-runtime` |
| MCP / harness socket | yes (MCP, emacs server) | no | no | no |
| `exposePostgres` | via `supabaseJailOptions` env | no | `exposePostgres = true` on jailed-pi | no |
| profile / jail checks in flake | `harness-jail-profile`, `runner-socket-unjailed` (`:405-406`) | none | none | none |
| `workspaceDeps` | explicit list | `JAIL_WORKSPACE_DEPS` env (`--impure`) | `["/home/david/.emacs.d/"]` (stale) | none (devshell-relative) |
| `CLAUDE_CODE_SHELL` pin | no | yes | no | yes |
| network profile | specDev (host loopback shared) | specDev | specDev | specDev |

One-line observations (no recommendations beyond these):
- Neither attrd nor goad uses the gateway, so a gateway-era `piGatewayConfig`
  change (PHASE-12 Batch A's `cost`) does not reach them; they still hold
  provider keys in the jail.
- Neither has a `runner-socket-unjailed`-style check: exposure is true today
  only by absence of a bind, and nothing would catch a future one.
- attrd's `workspaceDeps` still names `~/.emacs.d/`, a frozen corpus path
  (project governance note).
- goad has no `research` jail; attrd has no `subagents` and no shared `mkJail`.

### Live evidence (VA-1, VA-2, VH-2) 2026-10-19

**VH-2 basis.** The user ran every human step; the coordinator relayed the results. The enable flip is home commit 0796c480 (`runner.nix` only), made by the coordinator on the user's "enable".

**VA-1 (orchestrator-run).**

- `satan-runner`: ActiveState=active/running, MainPID 3068325, started 10:05:45 AEDT.
- ExecStart: nodejs-24.21.0 `node /home/david/dev/malebolge/src/runner-main.ts`.
- Unit Environment holds `SATAN_RUNNER_CONFIG`, `XDG_STATE_HOME` and `PATH` only. `LoadCredential` is set (systemctl prints it as unprintable) and the process env has `CREDENTIALS_DIRECTORY`.
- The gateway key string occurs 0 times in `ps -o args`, in `/proc/<pid>/environ` and in the unit's Environment.
- The journal has 0 `refusing to start`. It shows `store …/runner.sqlite` and `control …/control.sock`.
- Config has `enabled = true` (unparked; jobs scheduled).
- `/run/user/1000/satan-runner` is 700 david; `control.sock` is 600 david.
- `satan-patcher` is inactive.

**VA-2.**

- EX-6 smoke (`/tmp/runner-smoke.txt`): job pj-01M58KY5GCAV5RSCK8BN47TCDV reached needs_review, class complete. Collected into `/var/lib/capsule/collect/assistant/goad-walk.git` at ref `refs/capsule/assistant/heads/job/pj-01M58KY5GCAV5RSCK8BN47TCDV`, reviewedOid 669249f705c34cf9666e1f70c29769413f705c4e ("fix: add runner smoke marker file", 1 file +1). Not promoted.
- EX-10a reconnect (`/tmp/runner-smoke-reconnect.txt`): job pj-01M58KYQJ2AF6YXD2HYTX5KRM3 went running -> waiting_room (submission unanswered, reason aborted) on `capsule assistant stop`. After start, requestId resume-pj-01M58KYQJ2AF6YXD2HYTX5KRM3-1 took it waiting_room -> running -> collected, reviewedOid 339fcf9177aa3e3a2832c6d5434fd3ee76a2304a -> needs_review complete.
- EX-10b: push, collect and probe ran non-interactively as the runner user (both smokes, unit-run).
- EX-10c (`/tmp/runner-host-key.txt`): the scratch instance failed from preparing with reason host_key ("The host key of assistant changed"), endReason error, no waiting_room. The real known_hosts sha256 (6c9d7ea1…8ec73) was unchanged before and after.

**Verdict.** EX-6, EX-10 and VH-2 met. The runner is left running and enabled (user ruling 5). The prompt draft `~/satan-corpus/prompts/patch-agent.md` is still uncommitted, awaiting user review (the deployed runner reads it). The WAL read-only store read worked in practice (judgement call 7 resolved).

## PHASE-13 (cutover step 3: Emacs client)

### Batch C: deletion, migration, corpus, sweep (sonnet worker)

**Produced.**

- EX-4. Deleted `satan/satan-patch-{runner,worktree,adapter,adapter-pi,prompt,classify,store,listener}.el` and `satan/test/satan-patch-{runner,worktree,adapter,classify,store,listener}-test.el`. `satan-patch.el` now requires rpc, tools, inbox, promote only. `satan-custom-test.el` inventories updated (corpus vars 11 / 13 call sites; state vars 8; require-all and segment allowlist drop the patch modules; "one live path" wording). Comment-only rewords in `satan-db.el`, `satan-attribute.el`, `satan-attribute-listener-test.el`.
- Stale gitignored `.elc` deleted: `satan-patch{,-adapter,-adapter-pi,-classify,-inbox,-listener,-prompt,-runner,-store,-worktree}.elc` and `satan-tools-patch.elc` (changed module, was stale).
- EX-5. `satan/memory/migrations/0009_drop_patch_jobs.sql`: DO-block RAISE while any row is outside {needs_review, failed, cancelled, accepted_external, stale}; then drops `patch_job_events`, `patch_jobs`, `patch_jobs_set_updated_at()`. VT-4 in `satan-memory-migrate-test.el`: `0009-refuses-while-a-job-is-non-terminal` (running row -> user-error, tables remain, max(version) stays 8), `0009-drops-tables-when-all-jobs-are-terminal`; `applies-real-migrations` now (1..9). Red first (3 failures), green after the SQL. Production apply (`M-x satan-memory-migrate` against `satan_memory`) remains a deploy step; PHASE-11 found 21 rows, all `failed`.
- EX-6. `~/satan-corpus/tools/patch_job_{create,status,result,cancel}.md` rewritten; `patch_job_cleanup.md` removed with `git rm` (staged). NOT committed (E3): `just commit` would sweep `prompts/patch-agent.md` and runtime dirt. The user or orchestrator commits by path: `git -C ~/satan-corpus add tools/patch_job_*.md` (plus the staged deletion).
- Docs: `docs/governance.md` module/test/migration/tool rows updated; `docs/INDEX.md` marks the Patch agent docs superseded. `docs/patch/*`, `docs/review/*`, `docs/attributes/*` left as historical.
- E4: `~/.config/emacs/lisp/dl-sleipnir-doctor.el` (clean in git beforehand) — the four store/runner/worktree patch checks collapsed to one `patch-runner` check reporting `satan-patch-inbox-running-p`. `apps/dl-satan.el` untouched (`satan-patch-runner-enabled nil`, PHASE-14).

**Rulings applied (batches A-C).** E1 `result.repoPath` (M2) plus M1 `failure` on the summary; E2 mode enum from `satan-tools-patch-modes` (default `("fix")`), repo a plain config name, corpus producer prompts (`self-edit-*`, `tick/agent`) not edited (gap to backlog, orchestrator); E3 corpus edits by path, no `just commit`; E4 doctor check replaced; E5 directive stays off the wire.

**EX-7.** `just check` green: 1307 ran, 1303 as expected, 0 unexpected, 4 skipped (integration/morning-end-to-end, three satan-memory-grammar db-sync); luau and python suites ok.

**Open: live steps (orchestrator/user).**

- Restart Emacs or reload `satan-mode.el`, `satan-tick.el`, `satan-patch.el`; `patch_job_cleanup` must be gone from the live `satan-tools` and its description file is deleted, otherwise spawn fails (mem_01a1388a77bb78e1a70066cb0cdf0bbb). Stale `.elc` removed above, but a long-lived Emacs holds the old definitions.
- Runner redeploy needed for M1/M2 (`failure` on summary, `repoPath` on result) to be live.
- Corpus commit by path (above); apply migration 0009 to `satan_memory`.
- Then start the inbox watch and confirm the two goad-walk `needs_review` jobs land once each; PHASE-14 does closure promote/reject and the `dl-satan.el` / flake `satan-patcher` removal.

## PHASE-18 (2026-10-19): interactive daemon on the gateway provider

- Code: malebolge `8c93902` (one loader `loadGatewayModels(catalogPath, keyPath)` in `src/models.ts`; `src/runner/gateway.ts` is a `CREDENTIALS_DIRECTORY` + `StartRefused` adapter over it; `src/message-of.ts` shared; models-store built-in catalog code deleted; daemon config `gatewayCatalog` / `gatewayKeyFile`, env overrides `MALEBOLGE_GATEWAY_CATALOG` / `MALEBOLGE_GATEWAY_KEY_FILE`, defaults `~/.config/malebolge/gateway-models.json` / `~/.config/llm-gateway/keys/malebolge`; default model `gateway/deepseek-flash`). `just check` rc 0, 1206 tests, coverage 97.81/93.91/98.2/97.96.
- flakes: `~` `58c908a2` (`features/satan/runner.nix` links the runner's catalog render to `~/.config/malebolge/gateway-models.json`; `SATAN.md` daemon catalog + key).
- Runner runs the live tree: its next restart loads the refactored loader (behaviour unchanged; PHASE-17 tests pinned).
- Pending (VA-1): user issues key `malebolge`, `just home-switch`, runs `just daemon` + `just attach` on the host; agent checks key absent from `/proc/<pid>/{environ,cmdline}`.
- Known break: jailed `just hello-durable` (`~/notes`, `gateway = null`) will not start until the other agent's jail migration binds the key file and catalog read-only and sets the two env vars. `gatewayClient` passes `LLM_GATEWAY_KEY` as env, which this daemon does not read (file-only custody).

### PHASE-18 VA-1 (orchestrator-run, 2026-10-19)

- Prereqs (seat-verified): key `~/.config/llm-gateway/keys/malebolge` mode 600 david; `~/.config/malebolge/gateway-models.json` -> `/nix/store/s3fjiq8q…-home-manager-files/.config/malebolge/gateway-models.json` (H2 applied).
- Host run: `cd ~/dev/malebolge && setsid nohup just daemon` (user's justfile: `satan-mcp-start` -> `/run/user/1000/satan/mcp/mcp.sock`, then `node src/daemon-main.ts`). Stderr: `malebolge: gateway/deepseek-flash · 37 SATAN tools`, session `~/.local/state/satan/durable/session.sqlite`, attach `/run/user/1000/satan/durable.sock`.
- Key custody (pid 3596604, compared by `grep -cF` without printing): key text occurs 0 times in `/proc/<pid>/environ` and 0 times in `/proc/<pid>/cmdline` (cmdline is `node src/daemon-main.ts`). The process env does carry `DEEPSEEK_API_KEY`, inherited from the launching shell; the daemon no longer reads it (the gateway provider is the only one registered).
- One message via `node src/attach-main.ts` (stdin held open 75 s, then `/quit`): attach replayed the durable history, then the model answered `pong`. Since `gateway` is the only provider and the key file is `keys/malebolge`, the gateway accepted that key.
- Stop: SIGTERM -> exit, `durable.sock` removed, log ends `satan-mcp connection closed; reconnecting on next SATAN tool call` (no `stop failed`).
- Spend corroboration: `llm-gateway list` needs sudo (re-execs as the `llm-gateway` user, DEC-050), so agents cannot run it. The user ran it and relayed this row (2026-10-19):
```
satan-runner    deepseek-flash  30.0000 0.0053  -
malebolge       deepseek-flash  30.0000 0.0220  -
```
  `malebolge` spend is 0.0220 (> 0); `satan-runner` 0.0053.
- Side effect: the ping and `pong` are now turns in SATAN's real durable session (the host daemon has no scratch session).
- Verdict: VA-1 met, including spend corroboration (user-relayed row above).

## PHASE-14 batch B (orchestrator-run, 2026-10-19): closure run to needs_review

**Human block 1 agent checks (H3/H4), run 11:5x AEDT.**
- H3: `schema_migrations` max 9; `pg_tables like 'patch_job%'` 0; `pg_proc patch_jobs_set_updated_at` 0 (all psql rc 0).
- H4: `systemctl --user cat satan-patcher` "No files found"; `list-unit-files | grep -c satan-patcher` 0; `~/.config/systemd/user` has no patcher entry; `pgrep -x satan-patcher` rc 1; `~/.nix-profile/bin | grep -c satan-patcher` 0 (a loose `-i patcher` grep matches only `nerd-font-patcher` / `speech-dispatcher`); flake lock nodes have no `patcher`.
- satan-runner: MainPID 3347729, active since 10:53:47 AEDT (the H1 restart, per journal). No later start, so the ~11:44 home-switch did not bounce it.

**B1.** Runner config `enabled = true`, `[door] kind = "room"`, room `assistant`. Room up (`microvm@assistant` active/running; ssh relay answers). `~/dev/goad-walk` clean on `main` 6fe3a49, no `satan/*` branches. R4 pre-check: the quarantine `/var/lib/capsule/collect/assistant/goad-walk.git` is `drwxr-xr-x david users`; Emacs (`--fg-daemon` pid 3347959) runs as david; `git -C ~/dev/goad-walk ls-remote <quarantine>` rc 0 lists both closure refs. No ownership or `safe.directory` barrier is expected.

**B2 (create path, ruling 2).** `emacsclient -e '(satan-tool/patch-job-create (list :directive … :mode "fix" :repo "goad-walk" :allowed_paths (list "CLOSURE-<X>.md")) nil)'` at 11:57:22 AEDT:
- P = `pj-01M58TKGY59Y8C10ZTWJ8V1D46` (CLOSURE-PROMOTE.md), `queued`
- R = `pj-01M58TKGYN2G6HPJ9DM5763XD8` (CLOSURE-REJECT.md), `queued`
- Both return `:intervention_error "satan-intervention: tool-ctx missing :id/:mode-name/:time-now/:audit"` (sheet R3). Building a ctx would require reopening an unrelated run's audit (`satan-run-manual-tool-ctx`), which is false provenance, so nil was kept. Consequence: there is no `patch_job` intervention row for the closure jobs, and B6's intervention query will return the older rows or none.

**B3.** Both `needs_review` within 15 s (job_events seq 22-39): submitted -> conversation -> policy (`gateway/deepseek-flash`, ceilings 200 req / $0.5 / 2M tok / 3600 s) -> preparing -> refreshed (base 6fe3a49) -> running -> collecting -> collected -> needs_review, class `complete`, flagged false, offending [].
- P: reviewed_oid 374309736f13ddede82e77bacb4afc2aa638a933, 5 model requests, active 7.3 s. One commit "fix: add CLOSURE-PROMOTE.md for SL-023 closure run", parent 6fe3a49; only `CLOSURE-PROMOTE.md` (+1: "SL-023 closure run, promote.").
- R: reviewed_oid 203bf2380080efcec8b49c126a1a661380aa63a2, 4 model requests, active 4.5 s. Commit "fix: add CLOSURE-REJECT.md", parent 6fe3a49; only `CLOSURE-REJECT.md` (+1).
- R queued behind P (one job per repo), as the sheet predicted.
- `satan-tool/patch-job-result` P returns class complete, `:quarantine_ref`, `:commits`, diffstat 1/+1/-0.

**B4.** Inbox: each id has exactly one entry (`SATAN_PATCH_JOB:` count 1), `:STATE: needs_review` (inbox.org property lines 88 and 104). The PHASE-12 jobs still have one entry each.

**Pre-review state.** Live Emacs: `satan-patch-inbox-running-p` t, `satan-tools-patch-modes` ("fix"), `(featurep 'satan-patch-runner)` nil, `(boundp 'satan-patch-runner-enabled)` nil, `satan-patch-inbox-enabled` t, `satan-patch-rpc-socket` nil (default resolution). goad-walk: no `satan/*` branch, `refs/satan/incoming` empty, `main` = 6fe3a49.

**Pending: B5 (VH-1, user), then B6 agent checks.** PHASE-14 stays in_progress.

## PHASE-14 batch B6 + C (2026-10-19): VH-1, VA-1 evidence, EX ledger

Model: sonnet worker (evidence assembly from the orchestrator's verified checks). Ids below are runner job ids; P = `pj-01M58TKGY59Y8C10ZTWJ8V1D46`, R = `pj-01M58TKGYN2G6HPJ9DM5763XD8`.

### Human steps and commits
- Batch A: `~` `605447d8` "feat(flakes): remove satan-patcher (SL-023 PHASE-14, DEC-063 step 4)"; `~/.config/emacs` `e6cea06` "chore(satan): drop satan-patch-runner-enabled; the elisp runner is gone (SL-023 PHASE-14)".
- H1: runner restarted, MainPID 3347729, active since 10:53:47 AEDT. H2: Emacs restarted (`--fg-daemon` pid 3347959). H3/H4: see "PHASE-14 batch B" above.
- H5 (user): `gh repo view davidlee/sloptower --json isArchived` -> true; remote main = local HEAD 4637fda "docs: archive banner; superseded by the malebolge patch-job runner (satan SL-023)" (README links davidlee/Malebolge); `~/dev/satan-patcher` clean, in sync; `~/dev/sloptower` symlink and `~/.config/satan-patcher/policy.toml` absent (ruling 3 done). Go migration 0006 retired with the archived repo; its columns dropped by satan 0009.

### VH-1 (user, in the Emacs inbox via `satan-patch-promote` / `satan-patch-reject`)
- P promoted; R rejected. Per ruling (4) both PHASE-12 smokes, `pj-01M58KY5GCAV5RSCK8BN47TCDV` and `pj-01M58KYQJ2AF6YXD2HYTX5KRM3`, rejected (not evidence).
- Verdict: VH-1 met.

### B6 / VA-1 evidence (orchestrator-run, all rc 0)
- sqlite `jobs`: P `promoted`, R `rejected`, both smokes `rejected`.
- `job_events` after needs_review: seq 40 `2026-10-19T01:06:41.764Z` P transition `{"disposition":"promoted","branch":"satan/patch/pj-01M58TKGY59Y8C10ZTWJ8V1D46","verifiedOid":"374309736f13ddede82e77bacb4afc2aa638a933","from":"needs_review","to":"promoted"}`; seq 41 `2026-10-19T01:07:05.137Z` R transition `{"disposition":"rejected","from":"needs_review","to":"rejected"}`. Each job has 10 events (P seq 22-40, R seq 26-41).
- goad-walk: `rev-parse satan/patch/<P>` = 374309736f13ddede82e77bacb4afc2aa638a933 (= reviewed_oid = verifiedOid); `show --stat` parent 6fe3a49, only `CLOSURE-PROMOTE.md | 1 +`; `main` = 6fe3a49 unmoved (`main...origin/main` in sync); `refs/satan/incoming` empty; R's branch absent; the only satan head is P's.
- Quarantine `/var/lib/capsule/collect/assistant/goad-walk.git`: `refs/capsule/assistant/heads/job/<P>` = 374309736f…; `<R>` = 203bf2380080efcec8b49c126a1a661380aa63a2 (left in quarantine).
- `satan-tool/patch-job-result` P: `:state "promoted" :class "complete" :end_reason "completed" :reviewed_oid 374309… :base_oid 6fe3a49322154f66c65eb15974084ec753359bc9 :quarantine_ref refs/capsule/assistant/heads/job/<P> :diffstat (:files 1 :insertions 1 :deletions 0) :model_requests 5`. The tool plist does NOT carry repoPath; the raw RPC `(satan-patch-rpc-call "result" …)` does: `:repoPath "/home/david/dev/goad-walk"` (H1's M2, live). Audit item: the tool result surface omits the repo path.
- Inbox `~/satan-corpus/inbox.org`: one entry per id (`SATAN_PATCH_JOB:` lines 85, 101, 53, 69); `:STATE:` promoted (P), rejected (R and both smokes).
- One consumer (deployed): `satan-runner` active, MainPID 3347729, since 10:53:47 AEDT; `systemctl --user cat satan-patcher` "No files found"; `pgrep -x satan-patcher` rc 1; Emacs `(featurep 'satan-patch-runner)` nil, `(boundp 'satan-patch-runner-enabled)` nil, `satan-patch-inbox-enabled` t, `(satan-patch-inbox-running-p)` t, `satan-tools-patch-modes` ("fix"), `satan-patch-rpc-socket` nil (default resolution); `satan_memory` `pg_tables like 'patch_job%'` = 0.
- Intervention: the table is `satan_interventions` (the sheet's `interventions` was wrong). Latest `kind='patch_job'` rows are 2026-10-14 / 10-01 Go-era jobs; none for P/R. **User ruling 2026-10-19 (binding):** "no intervention record, by construction of the ruled create path (handler called via emacsclient with nil tool-ctx)" is accepted as EX-2's intervention evidence.
- Verdict: VA-1 met.

### Batch C: EX-3 rows (evidence only; ledger edits and transition lines are audit's job, INV-3)

Anchors are malebolge `src/runner/` at HEAD `8c93902` (the deployed tree).

| Item | Where the authority / evidence now lives |
|---|---|
| DEC-062 row: job lifecycle / queue consumer | `satan-runner` is the sole consumer (one-consumer block above); lifecycle is `jobs` transitions in `store.ts` (every write in one transaction with its `job_events` row, `store.ts:185`); `scheduler.ts`; satan-patcher unit absent (H4), Go repo archived (H5) |
| row: per-job path allowlist | validated at submit: `protocol.ts:125` (`normaliseAllowedEntry`, `classify.ts:19`) and `control.ts:86` `admit`; enforced in-run by `guard.ts:102` (`pathAllowed`); enforced at collection: `classify.ts:55` `disallowedPaths`, `classify.ts:95` -> `path_violation`, called from `collect.ts:232`. Live: P/R `offending []`, class `complete` (batch B) |
| row 4: patch-job audit | `job_events` append-only (`store.ts:81-91`, UPDATE/DELETE triggers abort); rows in B6 above (seq 22-41); transcript is the job's pi-durable conversation (`conversations.ts`) |
| row 5: per-job ceiling | request ceilings checked against maxima at submit (`protocol.ts:272` `ceilingsWithinMaxima`, `SUBMIT_CHECKS` `protocol.ts:276`); enforced in run (`ceilings.ts:84` `ceiling_exceeded`); config `~/.config/satan-runner/config.toml` `[maxima]`: `active_wall_clock_s = 3600`, `cost_usd = 0.5`, `model_requests = 200`, `tokens = 2000000`, `soft_threshold = 0.8`; closure policy event showed 200 req / $0.5 / 2M tok / 3600 s |
| row 6: runner `enabled` | `config.ts:137`, `config.ts:388` (required boolean); submit refused with `runner_disabled` (`control.ts:114`); disabled startup parks, enabled un-parks (`start.ts:161`, `recover.ts:216`); config `enabled = true`. `satan-patch-runner-enabled` is gone: `(boundp …)` nil (B6), `dl-satan.el` edit `e6cea06` |
| legend `satan-patcher` -> `patch-runner` | audit edit; evidence: satan-patcher removed (`605447d8`, H4, H5) |
| ISS-030 (patcher never completed a job) | Superseded: satan-patcher removed (`605447d8`, H4); closure job P reached `needs_review` and `promoted` through the runner (B6) |
| ISS-038 (elisp adapter resolved `jailed-pi` from caller PATH) | Superseded: `satan-patch-adapter-pi.el` deleted (satan `01dab54`); the runner runs pi in the room via its own unit PATH (PHASE-12 VA-1) |
| ISS-039 (two `patch_jobs` consumers) | Superseded: one consumer (B6 block); `patch_jobs` dropped (H3, 0009 applied) |
| ISS-041 (`--branch HEAD` clone failure) | Superseded: no `HEAD` default; the submit sends `baseRef` only when given, the runner falls back to `default_branch = "main"` (`protocol.ts:287`); P/R `base_oid` 6fe3a49 from `job_events` |
| CHR-003 (retarget satan-patcher prompt default) | Superseded: module and repo retired; runner reads `~/satan-corpus/prompts/patch-agent.md` (config `prompt_file`) |
| IDE-007 (owned microVM for proposals) | Resolved into SL-023: runner jobs run in oubliette room `assistant`, collected host-side into the quarantine, promoted from Emacs (B6 quarantine + branch rows); gateway-held keys (PHASE-12 VA-1, PHASE-18 VA-1 key custody) |
| EX-4 / DEC-065 | `cd ~/dev/malebolge && just check` rc 0 at HEAD `8c93902`: 47 files, 1206 tests, coverage 97.81/93.91/98.2/97.96 (working tree dirty only in the user's `biome.json`, `justfile`, untouched). `test/runner/{room,exec,config,env,pause,prepare,collect}.test.ts` rerun alone: 7 files, 295 tests, green. SL-006 sec-6 revision followed (PHASE-16 batch B: oubliette `ad2dd7d`, collect prints `<oid>\t<ref>` in `ls-remote` order; closes PHASE-15 relay item S1) |
| CHR-016 | Closed per user ruling (1); see below |

### CHR-016 (user ruling 2026-10-19 (1))
Closed with `doctrine backlog edit CHR-016 --status closed --resolution done`; body section appended. The closure run (P/R) plus PHASE-12 cover the live room rung. Waived by the ruling: silence limit, oubliette verbs' host-key refusal, agent home writable/exec. Still OPEN (audit item): the re-check of the room adapter at oubliette SL-006's lock (Harvest `### Open`).

### PHASE-14 criteria ledger
| Criterion | Status | Evidence |
|---|---|---|
| EN-1 (PHASE-13 deployed in Emacs) | met | H2 checks (batch B pre-review state); migration 0009 applied (H3) |
| EX-1 (flakes, Go repo, dl-satan.el) | met | `605447d8`, `e6cea06`; H4 checks; H5 `isArchived` true, symlink and policy.toml gone |
| EX-2 (closure run, one consumer) | met | P/R from `patch_job_create` handler via emacsclient (ruling 2), `needs_review` -> promoted/rejected; one-consumer block. Intervention: none, by construction of the ruled create path (nil tool-ctx), accepted by user ruling 2026-10-19. "Against the slot" superseded by EX-5 |
| EX-3 (ledger + issue evidence) | met (evidence recorded; edits are audit's) | Batch C table |
| EX-4 (PHASE-15 fixtures green; CHR-016 deferred) | met, CHR-016 clause superseded | fixtures green (row above); CHR-016 closed per ruling (1), not deferred |
| EX-5 (appended: closure ran against the deployed door) | met | closure ran against room `assistant` (`[door] kind = "room"`), repo goad-walk |
| VH-1 (user promotes one, rejects one) | met | VH-1 section |
| VA-1 (deployed state, `job_events`, real-repo branch) | met | B6 section |

### Reconcile items (for audit; locked design, DEC-065, plan.toml not edited)
- DEC-065 and design §9 "the slot is the live rung" / "live room rung is not closure evidence" are stale against ruling (1) (the closure run and PHASE-12 are live room evidence).
- PHASE-14 EX-4 text ("CHR-016 deferred") is stale against ruling (1); EX-2's "against the slot" is superseded by EX-5.
- Sheet B6's intervention query named table `interventions`; the table is `satan_interventions`.
- SATAN.md drift E5 (inputs row said `path:`) was fixed by row deletion in `605447d8`.

### Friction
- `llm-gateway list` needs sudo; agents cannot corroborate spend (user relayed).
- `satan-tool/patch-job-result` omits `repoPath`; only the raw RPC carries it.
- `patch_job_create` called with nil tool-ctx yields `:intervention_error` (sheet R3); no ctx exists outside a run.

## Audit (RV-029, 2026-10-19)

Conformance self-audit; findings, Synthesis and Reconciliation Brief live in
`doctrine review show RV-029 --full`. Phase-sheet sweep (the sheets are
disposable; lifted here):

- **Rulings that changed canon, held by the brief:** PHASE-09 STOP-1 ruling 1
  (gate `paused` refusal); PHASE-10 R1–R4 (room work in the rejoin, no
  `resume()` without a segment, R3 `warn-` record as threshold proof, row 7 on
  disabled start); PHASE-13 E1 (`result.repoPath`), E2 (mode enum defcustom),
  E3 (corpus commit by path); PHASE-16 OQ-1 (`reachable(repo, jobId)`), OQ-2
  (a probe that cannot spawn is `ChannelFailed`); PHASE-14 rulings (1)–(5)
  (closure on the deployed room; nil-ctx create path; sloptower archived; smokes
  rejected; runner left enabled).
- **Standing risks:** live-tree deploy (CHR-017); seat wedge on an
  unrejoinable job (ISS-047); room config literals (RV-029 F-8); one raced model
  request on a `host_key` abort (F-22, tolerated); shutdown can wait one backoff
  delay (ISS-047).
- **Check note:** malebolge `just check` fails at lint on untracked
  `.pi/extensions/doctrine/*.ts` (not SL-023's; not in the tsconfig project).
  Over the committed tree: eslint 0, tsc clean, 1206 tests, coverage
  97.81/93.91/98.2/97.96.
- **Ledger:** the first authority migration in this repo; anchors are malebolge
  symbols, verified at `8c93902`.


## Reconcile (2026-10-19)

Outcome recorded in RV-029 (`## Reconciliation Outcome`); REV-007 done
(SPEC-004 new; SPEC-002, REQ-013, SPEC-003). Delegated pass, no user in the
session: design edits not confirmed by the user beforehand.

### Evidence: oubliette SL-007 relay
- Relay (oubliette `.doctrine/slice/007/notes.md:371`, evidence): `session`
  supplies the room's base tools (`git bash coreutils-full which` + declared
  extras, `/etc/room/base/bin`), behind the repo's `tools/bin`, ahead of the
  caller's PATH; keep calling it by absolute path.
- Checked: malebolge `src/runner/room.ts:476` launches `door.sessionPath`
  (absolute; `~/flakes/features/satan/runner.nix` `session_path`); the runner
  sets no guest PATH; the unit's `PATH=` is for host programs (capsule, git,
  ssh, socat, coreutils) and never reaches the guest. No simplification owed;
  no backlog item. Design §5.2 states the new base-tools behaviour.

### Friction
- `doctrine slice record-delta --commit` refuses to narrow an existing range
  without `--force`; the brief's premise (ranges span to HEAD) was wrong — the
  foreign commit sat in PHASE-09's recorded range.
- REV cannot target DEC records; DEC revision notes go through `knowledge edit`.
- `revision new` / `spec new` try a remote reservation fetch (denied) and fall
  back to local ids.
