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
