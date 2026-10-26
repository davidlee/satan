# Notes SL-032: MCP run identity per conversation, not per connection

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-26, exploring → inquiring)

Superseded in detail by the design run. Evidence: `research/research.md`.
Settled: DEC-121..DEC-125 (design B, amended after an informal Codex review
the same day). inq-4 and inq-7 non-durable; inq-6 deferred to malebolge
IDE-002. Scope: `slice-032.md`.

Codex review (gpt-6.1-sol, informal, no ledger), findings and outcome:
1 close during nested wait → DEC-122 (deferred finalisation, interrupted
calls); 2 non-dispatch writers → DEC-123; 3 status `completed` fails the
verifier → DEC-122; 4 pool lifetime → DEC-125; 5 refresh coupling →
DEC-125; 6 initialize state → DEC-121/122; 7 kind per activity → pool key
(conversation, kind); 8 ADR-017 §4 / REQ-007 → DEC-122 rationale and the
SPEC-001 revision; 9 upstream `_meta` instead → declined (user kept B).

Drafting settled the open items: all four emitter callers are listed in
design sec-4; the observer passes its broker run, and manual counter-memories
pass none.

## Review pass plan (2026-10-26, reviewing)

RV-060 pass conducted (Codex gpt-6.1-sol, raiser; three rounds): 7 findings,
F-4..F-7 verified; F-1..F-3 (major) answered with design repairs the raiser
accepted, their probe/demonstrate obligations deferred to `/plan` (route
criteria read from the RV ledger).

A further design pass is not needed: the remaining risk is in mechanism that
only an implementation can settle. If one ran, it would probe:

- the settle/admission rules (sec-3) under a real nested
  `satan-patch-rpc` wait — that is the F-1/F-2 probe, owned by the plan;
- the pool's new-entry refresh against a restarted live server — the F-3
  demonstration, owned by the plan;
- whether closing the transport on `quit` is the right user-facing response
  (a design judgement the user may revisit at section review).

## Execution log

### PHASE-01 (2026-10-26)

- EN-1: `just check` at `eaf7d4f` in a clean worktree: 1340 tests, 2
  unexpected — `satan-pattern/{real-eld-parses-all-seeds,editor-commit-is-matchable}`,
  which read gitignored `satan/patterns.eld` (absent in a fresh worktree; pass in
  the main tree). Worktree artefact, not a red baseline. They do depend on a
  private file — a tests-independent-of-prod-data smell, outside SL-032.
- Test DB had to be rebuilt first: `.envrc` points `DOCKER_HOST` at a podman
  socket this host does not have; rootless docker's store had a corrupt shared
  base layer (`exec /usr/bin/tini: no such file`); fixed by
  `docker system prune -a` with user assent, then `supabase start` + `just db-setup`.
- Pass A — pi `implement` (deepseek-flash), tests only: 7 tests across 5 files,
  6 red for the right reason, 1 negative control green by construction
  (no-run-id ⇒ no emit). $0.071, 39 requests. Wrong: reported 3
  `satan-motive/capsule-*` failures as "pre-existing" — sandbox artefact
  (no `SATAN_DB_HOST` in the form), not red on the host.
- Pass B — pi `implement`, code: all callers per design sec-2; also dropped
  the dead `run-id` local in `satan-mcp--tools-call`. $0.048, 51 requests.
  Self-corrected: `satan-tools-memory` must read `tool-ctx :id`, not the
  canonical `ctx` (which carries `:run_id`) — the VT caught it.
- VA-1: `grep -rn satan-memory-store--current-run-id satan/` → no hits (exit 1);
  positive control `grep -rn satan-memory-store--emit-trace-marked satan/` →
  2 hits (exit 0).
- Gate (orchestrator): `just check` exit 0 — 1347 tests, 0 unexpected, 4
  skipped; lint clean. 19 `Warning (satan-attribute)` log lines are identical
  at baseline (test-run noise, not lint).
- Not caught by VT: an impl keeping the dynamic var as a fallback — VA-1 covers it.

### PHASE-02 (2026-10-26)

- Pass A — pi `implement`, tests: VT-2 inverted the two MCP refusal tests
  (`dec124-{connection,startup}-succeeds-while-spawn-running`); VT-1
  `tick-spawns-while-mcp-call-mid-dispatch` drives a real
  `satan-mcp--tools-call` whose tool runs `satan-broker-run` (a bare
  `--spawn` inside the call would pass vacuously — `--spawn` has no gate).
  Deleted the ISS-058 counter tests and the session-stamps-session_blocked
  tick-row test. $0.062, 43 requests. Registries are alists rebuilt by
  `setq`, so its `let`-scoped stub registration does not leak (checked).
- Pass B — pi `implement`, code: sites per design sec-5; DEC-8 comments that
  justified `spawn-running` rewritten to DEC-023 (including the run_busy
  rationale that cited the global PHASE-01 deleted); `session_blocked` kept
  as a historical streak reason. $0.045, 52 requests. Wrote its own notes
  entry (doctrine state is the orchestrator's) — replaced by this one.
- VA-1: `satan-run--interactive-calls` → no hits (exit 1); `session_blocked` →
  only `satan-broker.el:317,319` (streak reason + comment), its streak test
  (`satan-broker-test.el:279,290`), the VT-1 prose (`:701,750`) and the
  `satan-run-test.el:396,401` historical fixture; positive control
  `defvar satan-run--spawn-running` → 1 hit.
- Gate: `just check` exit 0 — 1344 tests, 0 unexpected, 4 skipped; lint clean.

### PHASE-03 (2026-10-26)

- Research advisory reported drift (plan.md/plan.toml added since the
  baseline) — plan files, not research content; no refresh.
- Pass A — pi `implement`, tests: 9 new `lazy-mint-*`/`mint-failure-*`/
  `request-error-*` tests; `session-creates-run-dir` and
  `session-disconnect-closes-audit` replaced; prepare test moved to
  `ensure-run`. Added a bounded `--request-response` (the old `--request`
  could hang), a fail-on-Nth `satan-audit--write-json` macro, and
  `(require 'satan-context)` at file top (a lazy require clobbered stubs).
  $0.103, 60 requests. 10 red for the right reason (host-confirmed).
- Orchestrator test review: `--run-dirs` counted only manifest-bearing
  dirs, so a cleanup that emptied the run dir but left it would pass —
  widened to any dir.
- Pass B — pi `implement`, code: `satan-mcp--ensure-run` (+ pure
  `--interactive-manifest`/`--interactive-bundle`), bare session at accept,
  -32603 wrapper in `--handle-message`, close finalises nothing without a
  run, status `done`, line buffer → `satan-mcp-buf` process property.
  $0.035, 20 requests. Wrong: cleanup in `condition-case error` (misses
  `quit`), and a filter comment claiming only decoding was guarded while it
  still wrapped dispatch. Orchestrator replaced the cleanup with
  `unwind-protect` + published flag; fixed comment and log text.
- Negative control: cleanup replaced by `(ignore run-dir)` → both
  `mint-failure-*` tests fail; restored.
- Gate: `just check` exit 0 — 1351 tests, 0 unexpected, 4 skipped; lint clean.

### PHASE-04 (2026-10-26)

- Pass A — pi `implement`, tests: 9 `identity-*` tests (parse table, wire
  -32602/-32600, two-identity V1, legacy JSON null on the raw file text,
  final summary) plus `--initialize`/`--connect-session` helpers.
  $0.075, 38 requests. `identity-trace-marked-carries-session-run-id` is
  green by construction (PHASE-01 landed explicit attribution) — kept as
  the V1 trace_marked guard.
- Pass B — pi `implement`, code: `--parse-identity`, `--initialize`,
  `--identity-fields` (nil → `:null`), `--final-summary`, header I1-I5.
  $0.031, 21 requests. It caught a pass-A test bug: `"7\x7f8"` reads as
  U+07F8, not DEL — and "fixed" it by narrowing conversations to printable
  ASCII, contrary to design sec-2 ("opaque", no control chars). Orchestrator
  fixed the test (`(string ?7 127 ?8)`), added a non-ASCII positive row, and
  restored the design predicate (< 32 or 127).
- Negative control: predicate without the 127 check → parse-table fails;
  restored.
- Gate: `just check` exit 0 — 1360 tests, 0 unexpected, 4 skipped; lint clean.

### PHASE-05 (2026-10-26)

- EN-2: RV-060 F-2 re-read (settle on error and quit; quit → delete-process
  then re-signal; tool-result carries :id).
- Phase decisions (runtime sheet, flagged for reconcile): D1 — the verifier
  has no event registry and already ignores non-call/result events, so EX-3
  "knows call-interrupted" = a `calls-match-results` docstring line + VT-2
  pinning both halves, no new predicate. D2 — a non-local exit that is
  neither error nor quit (a `throw`) settles with reason `"exit"`, outside
  the design's error|quit enum.
- Pass A — pi `implement`, tests: 4 `settle-*` tests + 2 verifier tests
  (green by D1). $0.105, 58 requests. Found: a `quit` re-signalled from a
  real process filter is caught by `read_process_output`'s handler and kills
  batch Emacs, so the quit test hands the two-line chunk to
  `satan-mcp--filter` directly over a live socket pair. V15's "quit
  propagates to the caller's wait" is not observable in batch — reconcile
  note.
- Pass B — pi `implement`, code: `in-flight` slot; `--tools-call` with
  `condition-case` around dispatch only, `unwind-protect` cleanup that
  settles (`--record-interrupted`) then decrements; quit → delete-process
  then re-signal; `--send-tool-result` extracted. $0.066, 45 requests. No
  defects found in review.
- VA-1 (orchestrator probe, live half): error outside the guard and quit
  with a sibling in the same chunk — covered by the settle tests (pair,
  sibling never starts, close, verifies). Extra probe: `throw` through the
  live filter with a sibling in the same chunk → tool-call 21, tool-result
  21 "interrupted: exit", call-interrupted 21 "exit"; in-flight 0; sibling
  not run; verify t. BUT the transport stays open, so 21 and 22 are never
  answered — an I2 gap for non-error, non-quit exits (e.g. a
  `while-no-input` throw in an enclosing wait). Raised with the user.
  User chose: close on any non-error exit → DEC-126, lands in PHASE-06.
  Closing-session half → PHASE-06/VA-1.
- VA-2: removed the interrupted tool-result write → `settle-escaped-error-live`,
  `settle-quit-closes-transport`, `settle-throw-to-outer-catch-direct` fail;
  restored.
- Gate: `just check` exit 0 — 1366 tests, 0 unexpected, 4 skipped; lint clean.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-26 · PHASE-02 completed, PHASE-03 next · 7ca34df

### Produced

research/research.md; DEC-121, DEC-122, DEC-123 (amended, RV-060 F-5),
DEC-124, DEC-125; design.md (locked, run rev 35); 9 design-target selectors;
RV-060 (pass conducted, 7 findings); plan.toml / plan.md (PHASE-01..08).
- PHASE-01 explicit attribution (49b144d); PHASE-02 DEC-8 retired (7ca34df).
- ISS-059 (pattern tests read gitignored patterns.eld), ISS-060 (.envrc
  DOCKER_HOST drift); malebolge IMP-012 (own quotient forms, before PHASE-07).
- mem.fact.satan.pi-worker-sandbox-lacks-test-db-host,
  mem.fact.satan.test-db-on-rootless-docker.

### Learned

- pi/MCP tie identity to the connection; pi-mcp passes
  `capabilities.experimental` (research Thread 3; DEC-121).
- MCP close status `completed` fails `satan-audit-verify-run` (pre-existing;
  DEC-122).
- `satan-patch-rpc.el:137` permits nested dispatch (DEC-123).
- `@satan` directives run as a broker-tick tool and emit `trace_marked`
  against the consuming run today (DEC-123 amendment).
- quotient pi workers see only their `cwd` root: malebolge work needs
  `cwd: ~/dev/malebolge` (a satan-rooted worker reports it empty).
- pi worker DB-test claims are not evidence
  (mem.fact.satan.pi-worker-sandbox-lacks-test-db-host); per-phase log in
  `## Execution log`.

### Open

- RV-060 F-1/F-2 (probe), F-3 (demonstrate): answered; discharged by
  PHASE-05/06/07 VA rows.
- At reconcile: SPEC-001 REQ-007 and QUE-001, SPEC-002 transports row,
  memory mem_eb8e5cff…, malebolge IDE-002 note (design sec-91).
