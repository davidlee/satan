# SL-011 Design: SATAN tick performance — observe and bound

Status: draft (pending adversarial review + lock)
Governed by: ADR-001, POL-001. Related: SL-012 (must land after — see §0).

## §0 Cross-slice constraints (SL-012)

SL-012 moves `satan/` to a standalone package and sweeps `dl-satan-*` →
`satan-*`, `my/satan-*` → `satan-*` (SL-012 design D3). Interaction assessed
decision-by-decision (2026-07-10): **decisions decoupled, execution coupled**
— same files. Consequences:

- **Serial ordering, SL-011 first.** Recorded: `SL-012 after SL-011`.
- New symbols follow current canon (`dl-satan-trace-*`); SL-012's mechanical
  sweep renames them for free. No new-prefix island, no `my/` additions.
- Trace stage-name strings and JSONL keys are **prefix-free**
  (`"evidence.git_state"`, `"kind"`) — sweep-immune; phase-3 percentile
  tooling (IMP-014) survives the rename untouched.
- Telemetry paths are `$XDG_STATE_HOME`-based defcustoms — independent of
  both the repo move and SL-012 D4's `dl-notes-paths` decoupling.
- `timeout(1)` (coreutils) becomes a runtime dependency of the future
  standalone package — SL-012 must note it in package docs/requirements.

## §1 Telemetry core — `dl-satan-trace.el` (new module)

### Decisions

- **D1 — one file, kind field.** Tick rows and subprocess ledger rows share
  one JSONL stream; rows carry `:kind "tick" | "subprocess"` and `:run_id`
  for correlation. One writer, one reader for phase-3 percentiles.
  Rejected: two files (correlation across files, two writers); per-run-dir
  trace.json (percentile queries would walk thousands of run dirs).
- **File**: `$XDG_STATE_HOME/satan/tick-trace-<YYYY-MM-DD>.jsonl` —
  day-bucketed (matches segments convention; unbounded single file rejected).
  Dir defcustom `dl-satan-trace-dir`; kill switch `dl-satan-trace-enabled`
  (default t — every new mechanism gets a disable switch, house convention).
- **Posture: telemetry never fails the tick.** Every write wrapped in
  `condition-case` → swallow + `message`. No psql, no subprocess in the
  write path — `dl-satan-jsonl-prepare` + `json-serialize` + `write-region`
  append only.
- **Write timing** (deliberate asymmetry):
  - subprocess rows: **append immediately**, one line per call. Crash/hang
    mid-tick is exactly the tick you want data for; the partial ledger shows
    which probe died. Tens of writes per tick — trivial.
  - tick row: **buffered, flushed once** in `unwind-protect` at tick end,
    so error paths still emit.

### API

```elisp
(defvar dl-satan-trace--current nil)   ; per-tick accumulator plist, let-bound

(defmacro dl-satan-trace-with-tick (run-id mode &rest body)
  "Bind accumulator (records t0), run BODY, flush tick row in unwind-protect.")

(defmacro dl-satan-trace-stage (name &rest body)
  "Time BODY; record (NAME . ms) into accumulator; return BODY's value.
No-op passthrough when no accumulator bound (MCP boot path, tests).")

(defmacro dl-satan-trace-stage-optional (name &rest body)
  "As dl-satan-trace-stage, but when the tick budget is exhausted: skip
BODY, return nil, record NAME in the accumulator's skipped list.
No accumulator / nil budget → runs BODY (passthrough).")

(defun dl-satan-trace-subprocess (argv cwd ms exit &optional timed-out)
  "Append one subprocess ledger row immediately. run_id from accumulator or nil.")

(cl-defun dl-satan-trace-call (program args &key stdin cwd timeout-secs env label)
  "Run PROGRAM ARGS bounded by timeout(1); ledger the call.
ENV is a list of \"VAR=VAL\" strings appended to `process-environment'.
STDIN string fed via `call-process-region' when non-nil.
TIMEOUT-SECS nil → unbounded (no wrapper) — long-running legit ops
(migrations) pass nil explicitly.
LABEL is a caller-supplied attribution string (e.g. \"memory-store.query\")
carried on the ledger row — argv alone cannot distinguish psql callers
(SQL is stdin, not argv).
Returns (:exit N :stdout STR :timed-out BOOL).  Exit 124 → :timed-out t;
wrapper exits 125/126/127 map honestly to :exit, never :timed-out.
Wrapper invocation is `timeout -k 2 SECS PROGRAM ARGS…' — KILL after a
2s grace so a TERM-ignoring child (hung socket/NFS) still dies.
Ledger row logs the logical PROGRAM+ARGS (wrapper stripped), LABEL, CWD,
ms, exit.")
```

`dl-satan-trace-call` lives here, not in a separate module: the runner is
useless without trace (its point is timing + ledger + timeout); "observed,
bounded subprocess" is one responsibility. Revisit if it grows.

### Row shapes

```json
{"kind":"tick","run_id":"20260710T091500-tick-pulse-ab12","mode":"tick-pulse",
 "ts":"2026-07-10T09:15:00+10:00","total_ms":4310,"budget_ms":10000,
 "budget_breached":false,
 "stages":{"evidence.focus_segments":12,"evidence.git_state":210,
           "evidence.bough_recent":890,"enrich.resonance":1400},
 "skipped":[],"outcome":"spawned"}

{"kind":"subprocess","run_id":"20260710T091500-tick-pulse-ab12","ts":"…",
 "argv":["git","status","--porcelain"],"label":"evidence.git_state",
 "cwd":"~/dev/foo","ms":180,"exit":0,"timed_out":false}
```

**Stage nesting caveat**: stages may nest (`spawn.bundle` contains the
optional `recent_runs` work) — stage ms overlap, so Σ stages ≠ total_ms.
Percentile tooling (IMP-014) must treat stages independently, never sum.

`outcome`: `spawned | budget_denied | session_blocked | perceive_failed`.
Denied ticks perceive (ISSUE-001 / DR-010 §3), so they trace too —
`with-tick` wraps `dl-satan-broker-run`'s whole body, not just spawn.

## §2 Choke points — bounded, ledgered subprocess execution

### Decisions

- **D2 — timeout mechanism: `timeout(1)` prefix** at choke points.
  Exit 124 → degrade. Zero restructuring of sync call sites; kills the child
  for real. Rejected: `with-timeout` (does not kill the child);
  `make-process` + sync wait (rewrites 4 choke points' IO plumbing, more
  bug surface, still blocks main thread); hybrid (two mechanisms to test).
- Ledger `argv` is the **logical** command — wrapper prefix stripped before
  logging; `timed_out` carries the wrapper's verdict.
- **Non-goal held: no async.** `trace-call` blocks; boundedness comes from
  the timeout, not concurrency. Async perception is ADR-001/DE-010 territory.

### Choke-point edits

All four route through `dl-satan-trace-call`; each keeps its own
return-shape contract:

| Site | Edit | Timeout defcustom | Degrade path |
|---|---|---|---|
| `dl-satan-db-query` / `-psql` | `call-process[-region]` → `trace-call :stdin sql :label CALLER` | `dl-satan-db-timeout-seconds` (5) | existing `(error . msg)`; timeout msg explicit |
| `evidence--git-output` + `--git-state` rev-parse | `trace-call :env '("GIT_OPTIONAL_LOCKS=0") :cwd default-directory` | `dl-satan-memory-evidence-git-timeout-seconds` (3) | nil-on-nonzero as today; additionally `git_state` gains `:timed_out t` when any sub-call hit the deadline — a timeout must not read as a clean repo |
| `dl-satan-bough--invoke` (tools-bough.el) | `trace-call` — combined stdout+stderr | `dl-satan-bough-timeout-seconds` (5) | existing attempt/ok counters → `bough_status` degraded |
| `dl-satan-sway--swaymsg` (tools-sway.el) | `trace-call` | `dl-satan-sway-timeout-seconds` (2) | existing tool error return |

**Timeout scope consequences (owned explicitly):**
- The db timeout applies to **every** `dl-satan-db` caller, including
  model-facing memory tools mid-run — a >5s resonance/store query now
  degrades to an error result instead of stalling the editor. Intended.
- `dl-satan-memory-migrate` (and any `--single-transaction` op) passes
  `:timeout-secs nil` — migrations are legitimately long; never killed.

### `GIT_OPTIONAL_LOCKS=0` scope

- Applied at the `--git-output` choke — covers all evidence git reads
  including the offending `status --porcelain` — plus the bare
  `rev-parse --git-dir` in `--git-state` (also routed).
- `dl-satan-tools-vcs.el` read-only git calls: same env. The rule is
  *every* read-only SATAN git invocation.
- `dl-satan-patch-worktree.el`: intentionally-writing ops in satan-owned
  trees — **exempt** from the env var; §4 confinement instead. They DO
  route through `trace-call` for ledger visibility
  (`dl-satan-patch-worktree-timeout-seconds`, 30).

## §3 Stage map + tick wall budget

### Decisions

- **D3 — instrumentation: inline macros at call sites** (not advice-add —
  hidden control flow, load-order/byte-comp coupling, weak ert story; not
  ledger-only — misses file-read + elisp stages).
- **D4 — budget: tiered core/optional.** Budget checked before each
  optional stage; no mid-stage abort (per-call timeouts bound stage
  internals). `dl-satan-trace-tick-budget-seconds` defcustom (default 10;
  nil = unbounded). Rejected: observe-only (slice promises truncation);
  hard abort (loses the percept; fights ISSUE-001 perceive-unconditionally).
- **Worst-case arithmetic (honest):** the wall budget bounds only the
  optional tail. The true ceiling is Σ core per-probe timeouts ≈
  git 3s×5 + psql 5s×~5 + bough 5s ≈ 40s pathological (every probe at its
  deadline simultaneously). The budget's job is that a *typically* slow
  tick sheds its fat optional stages early; the per-probe deadlines are
  what make the pathological case finite at all (today it is unbounded).
  Tightening defaults is a data-driven follow-up once trace rows exist.

### Stage names (stable strings — phase-3 keys)

| Stage | Kind | Tier |
|---|---|---|
| `evidence.current_window` | file read | core |
| `evidence.focus_segments` / `.browser_segments` | file reads | core |
| `evidence.git_feed` | file read | core |
| `evidence.content_probe` | file scan | **optional** |
| `evidence.bough_recent` | subprocess | **optional** |
| `evidence.bough_active` | subprocess | core (drives attention block; single call) |
| `evidence.bough_day` | subprocess | **optional** |
| `evidence.git_state` | subprocess ×5 | core (timeout-bounded) |
| `evidence.fs_state` / `evidence.truncate` | elisp | core |
| `perceive.persist` | write | core |
| `probes.read.{curiosity,content,wpm}` | psql | core (watermark integrity) |
| `spawn.audit_open` | write | core |
| `spawn.observer` | psql | core (already error-soft) |
| `enrich.resonance` | psql | **optional** |
| `enrich.motive` | file parse | core |
| `spawn.sensor_alerts` / `probes.commit.*` / `spawn.ingest_cursor` | | core (state advance — never skip half) |
| `spawn.bundle` (context-fn; `recent_runs` inside it **optional**) | | core |
| `spawn.exec` (make-process) | | core |

Probe commits / ingest cursor stay core: skipping a *commit* after its
*read* desyncs watermarks (cf. `mem.pattern.satan.sensor-watermark-format`
bug class). Budget savings come from the fat optional stages (bough ×2,
content, resonance) — the slow ones in practice.

### Degrade surfaces (honest percept)

- `evidence.bough_recent/day`, `content_probe` skip → slot nil;
  `sensor_status` content slot → `"budget_skipped"`; trace `skipped` names
  every skip precisely. Renderers already self-suppress nil blocks.
- `enrich.resonance` skip → `(:status budget-skipped :cue nil :matches nil)`
  — mirrors the existing `memory-unreachable` shape; render path tolerant.
- Tick row: `"skipped":[…]`, `"budget_breached":true`.

Coupling: evidence/context modules gain `(require 'dl-satan-trace)` and
macro wraps only — no broker knowledge; budget state lives entirely in the
accumulator dynamic binding. MCP interactive path binds no accumulator →
macros pass through free, no trace, no budget.

## §4 Worktree confinement assertion

Current confinement is *incidental* (path construction under the state
root), not asserted. Add one guard, called by every mutating op in
patch-worktree + runner:

```elisp
(defun dl-satan-patch-worktree--assert-owned (path)
  "Signal unless PATH is under `dl-satan-patch-worktree-root'.
Every mutating git op (worktree add/remove, checkout, commit) calls this
with its target before running.  Read-only ops exempt.
Compares `file-truename' of both sides (symlink-escape proof).")
```

Signal = hard `error`, not degrade — writing to a user tree is corruption,
not a slow probe.

## §5 Code impact summary

| File | Change |
|---|---|
| `satan/dl-satan-trace.el` | **new** — accumulator, 3 macros, subprocess ledger, `trace-call`, budget check, JSONL append |
| `satan/dl-satan-db.el` | `-query`/`-psql` → `trace-call`; timeout defcustom |
| `satan/dl-satan-memory-evidence.el` | `--git-output`/`--git-state` → `trace-call` + `GIT_OPTIONAL_LOCKS=0`; stage macros in `assemble-with-bounds`; optional-stage macro on bough_recent/day + content |
| `satan/dl-satan-tools-bough.el` | `dl-satan-bough--invoke` → `trace-call` (combined stdout+stderr) |
| `satan/dl-satan-tools-sway.el` | swaymsg → `trace-call` |
| `satan/dl-satan-tools-vcs.el` | read-only git → `GIT_OPTIONAL_LOCKS=0` env |
| `satan/dl-satan-broker.el` | `broker-run` body in `with-tick`; spawn-side stage macros; outcome stamping |
| `satan/dl-satan-context.el` | `enrich.resonance` optional; `recent_runs` optional; `enrich.motive` stage |
| `satan/dl-satan-patch-worktree.el` | `--assert-owned` guard + `trace-call` routing. patch-runner needs no change — its git routes through `--git` |
| `satan/test/…` | new suites: trace, trace-call, budget-skip, confinement; touched: db, evidence |

~25 new ert tests; all pure/subprocess-mock except `trace-call` integration
(`sh`/`sleep`, no DB).

## §6 Verification alignment

| Slice closure intent | Design cover | Mode |
|---|---|---|
| Choke-point env injection (`GIT_OPTIONAL_LOCKS=0` present) | `trace-call` env visible to child (`sh -c 'echo $GIT_OPTIONAL_LOCKS'`); evidence choke passes it | VT |
| Probe-timeout degradation | exit-124 → `:timed-out t`; db → `(error . …)`; git-output → nil + `git_state :timed_out t`; `sleep 10` with 1s deadline returns fast; TERM-ignoring child killed by `-k` grace; `:timeout-secs nil` runs unwrapped (migrate path); ledger row carries `:label` | VT |
| Budget-breach truncation | optional macro skips on exhausted fake accumulator; assemble under breach → nil slots + honest `sensor_status`, shape valid through `--truncate` + canon | VT |
| Trace row shape | tick row (stages map, skipped, outcome, budget flags); ledger row (logical argv, no wrapper) | VT |
| Worktree confinement | guard accepts owned, rejects `~/dev/foo`, rejects symlink escape | VT |
| Run a tick; inspect trace + ledger; `git status` loop in user repo during tick → zero index.lock collisions | behavioural | VH (/audit) |
| Zero byte-compile warnings; `just check` green | gate | VT |

## Open questions — resolved

- OQ-1 (trace destination): new day-bucketed JSONL under XDG state, one
  file with kind field (§1 D1). Audit log stays semantic.
- OQ-2 (ledger sampling): every call — volume is tens per tick (§1).

## Follow-ups (out of scope, recorded)

- Trace-file retention/cleanup — day-bucketed files grow unbounded; fold
  into IMP-014 (phase-3 reporting) which owns the read side.

## Slice-scope drift to reconcile at /plan

- Slice context says "one 185-line let* in broker--spawn"; pipeline is now
  the DR-010 perceive/spawn split (perceive runs pre-gate in
  `dl-satan-broker-run`). Observability covers both halves; denied ticks
  trace. Reconcile slice-011.md wording.
- Memory `mem.fact.git.optional-locks` cites the fix as applied — it is
  prospective. Verify/correct memory at close.
