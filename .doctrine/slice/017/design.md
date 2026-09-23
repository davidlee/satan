<!-- doctrine:section sec-1 -->
# Intent

SATAN tells the keeper about itself in three situations:

- a run failed;
- a sensor degraded, or the model chose to notify;
- a background listener died.

In each situation the message can fail to arrive, or arrive with no record:

- **A failure that persists goes quiet.** The broker announces a failure only
  when the failure streak is exactly 1. It counts that streak across every mode
  and by directory suffix alone, so a tick or interactive run in between resets
  it. The ISS-012 outage announced once (2026-09-22 09:16) and then fell silent
  (ISS-017).
- **A sensor alert is shown but never recorded.** Pre-spawn sensor alerts use a
  synthetic tool context that has no audit handle. The intervention write
  rejects it after the D-Bus notification has already fired, so nothing records
  the action (SPEC-001 REQ-003) and the cooldown never arms: 221 unrecorded,
  repeated alerts on disk (ISS-016).
- **The test suite writes into the evidence.** Unstubbed tests reach the real
  announcer, so `just test` writes `satan[PID]` journal lines and fires real
  desktop notifications. SATAN's own diagnostics then read those lines (ISS-015).
- **The reason is lost.** The harness classifies a provider error (`auth`,
  `rate_limit`, …), but the broker drops the classification, so an expired key
  is announced as the word "failed" (IMP-005, partial).

This slice makes SATAN's self-reports **single-path, recorded, persistent and
specific**:

- every user-facing emit goes through one seam;
- an alert is recorded before it is shown;
- a failure keeps being announced on a back-off for as long as it persists;
- the harness's error class becomes the failed run's recorded reason.

SL-018 (credential policy) builds on two of these results: the per-mode outcome
streak, and the recorded `auth` reason.

## The shape

The diagram shows who emits, what each emit is recorded in, and the one path
all emits share.

```mermaid
flowchart LR
  subgraph run["a scheduled run (satan-broker--spawn)"]
    SA["sensor alerts<br/>(pre-spawn)"] -- "notify_send<br/>via satan-tool-dispatch" --> NS
    M["model tool call"] -- "notify_send" --> NS
    NS["satan-tool/notify-send"] -- "1 record" --> IR["satan-intervention-record<br/>(audit append)"]
    NS -- "2 announce" --> AN
    NS -- "3 project" --> IP["satan-intervention-project<br/>(psql)"]
  end
  F["finalize / no-child writer<br/>(run bundle = record)"] -- "outcome streak<br/>+ DEC-015 policy" --> AF["satan-broker--announce-failure"] --> AN
  L["listener death<br/>(no run, unrecorded)"] --> AN
  AN["satan-announce"] --> SINK{{"satan-announce-sink"}}
  SINK -- production --> D["D-Bus pop + logger -t satan"]
  SINK -- "test batch" --> R["recorded list"]
```

The diagram, emit by emit:

- **Every emit reaches the keeper through `satan-announce`**, and so through
  whichever sink is installed. Nothing else calls `notifications-notify` or
  `logger`.
- **Intervention emits** (sensor alerts and the model's `notify_send`) are
  written to the audit log *before* they are shown. Their Postgres row is
  written after.
- **Failure announcements** come after the run's own bundle (status,
  `final.json`, `.FAILED` rename), which is their record. The broker consults
  the per-mode outcome streak to decide whether to announce.
- **Listener deaths** happen outside any run, so there is no audit log to write
  to. They are announced as operational alarms that leave a journal line and
  no audit record, by decision (DEC-018).

## Boundary

- **In scope.** Everything above lives in the Emacs client. SPEC-001 REQ-003
  (record every action) and authority-ledger row 4 (a single audit writer, no
  third) govern it. The slice adds no authority item and no ledger row.
- **Out of scope.**
  - Credential acquisition (SL-018).
  - A typed provider-exception layer (the rest of IMP-005).
  - `message` and `display-warning`, which are Emacs-local and never reach the
    journal or D-Bus.
  - `dl-secret.el`'s own notification.

<!-- doctrine:section sec-2 -->
# The announce seam

Governed by DEC-017.

## Current behaviour

SATAN reaches the keeper from five call sites, and they share no code:

| site | channel | guarded by |
|---|---|---|
| `satan-broker.el:339` | `call-process "logger"` | `satan-failure-syslog`, `ignore-errors` |
| `satan-broker.el:346` | `notifications-notify` | `satan-failure-notify`, streak == 1 |
| `satan-tools-notify.el:56` | `notifications-notify` | `condition-case` → tool error |
| `satan-attribute-listener.el:272` | `notifications-notify` | `condition-case` → `message` |
| `satan-patch-listener.el:109` | `notifications-notify` | `condition-case` → `message` |

Tests silence these call sites with `cl-letf` stubs, one file at a time. The
stubs miss paths. The budget-denied tests (`satan-broker-test.el:427, 481,
681`) reach the real announcer.

## Target: `satan/satan-announce.el`

A new thin module. It requires only `cl-lib` and `satan-custom`, and
`notifications` loads lazily inside the production sink. Any module can depend
on it without pulling in the tool registry. It also takes over
`satan-notify-app` from `satan-tools-notify.el`, so the broker never has to
reach into a tool module for an app name.

```elisp
(defcustom satan-notify-app "SATAN"          ; moved from satan-tools-notify.el
  "Application name shown in SATAN's desktop notifications."
  :type 'string :group 'satan)

(defvar satan-announce-sink #'satan-announce-deliver
  "Function that delivers one announcement plist; returns a D-Bus id or nil.
Only ever let-bound (by the test harness and `satan-announce-with-recorder'),
never set: a global change would silence a live Emacs.")

(defvar satan-announce-recorded nil
  "Announcements captured by `satan-announce-record', newest first.")

(cl-defun satan-announce (&key (app satan-notify-app) title body
                               (urgency 'normal) timeout journal)
  "Announce to the keeper through `satan-announce-sink'.
TITLE non-nil requests a desktop pop (BODY, URGENCY, TIMEOUT, APP apply).
JOURNAL non-nil requests one journal line.  At least one of TITLE /
JOURNAL must be given.  Returns the sink's value."
  (funcall satan-announce-sink
           (list :app app :title title :body body :urgency urgency
                 :timeout timeout :journal journal)))

(defun satan-announce-deliver (a)
  "Production sink: journal line (best effort), then the D-Bus pop."
  ...)

(defun satan-announce-record (a)
  "Test sink: push A onto `satan-announce-recorded'; return a fake id."
  ...)

(defmacro satan-announce-with-recorder (&rest body)
  "Run BODY with the recording sink and a fresh `satan-announce-recorded'."
  `(let ((satan-announce-sink #'satan-announce-record)
         (satan-announce-recorded nil))
     ,@body))
```

### Contract

- **Journal line.** It runs `logger -t satan -p user.warn JOURNAL`, with the
  same tag and priority as today, so existing `journalctl --user -t satan`
  readers still work. The text must be ASCII: `logger` receives bytes encoded
  in the locale's coding system, and a non-ASCII character does not survive a
  C locale.
- **Journal failure.** It is best effort. A missing `logger(1)` must never
  fail an emit, just as with today's `ignore-errors`.
- **Journal-only announcements** omit `:title`. The failure announcer sends
  one at every streak position where DEC-015 says no pop is due.
- **Pop failure propagates.** `satan-tool/notify-send` must know when the
  keeper did not see an alert (section 5). The broker and the listeners wrap
  their calls, as they do today.
- **`:app`** defaults to `satan-notify-app`. The listeners pass their own
  `*-notify-app`.
- **Category switches stay with their callers.** `satan-failure-notify` and
  `satan-failure-syslog` decide *whether* the broker asks for a pop or a
  journal line. The seam decides only *how* the announcement is delivered.
  The REQ-005 kill switches and the `notify` capability gate therefore stay
  where they are.

## Test hermeticity

The harness owns hermeticity, one level up from each test file.

- **The whole suite runs inside one binding.** `satan-test-run-batch`
  (`dev/satan-test.el:65`) wraps its load-and-run in
  `(let ((satan-announce-sink #'satan-announce-record)) …)`, next to the
  existing guard against the production database. Nothing the suite does can
  reach D-Bus or the journal, whatever a test forgets to stub. Because the
  binding is a `let` and not a `setq`, running the harness inside a live Emacs
  does not silence that Emacs's alerts once the run ends.
- **Tests that assert on an emit** wrap themselves in
  `satan-announce-with-recorder` and inspect `satan-announce-recorded`. The
  macro also makes such a test hermetic when it runs on its own, outside the
  harness.
- **The per-file stubs are removed.** Every `cl-letf` of `notifications-notify`
  and of `call-process "logger"` goes, so the recorder is the only mechanism.
- **The exception is `satan-announce-deliver`'s own unit tests.** They stub
  `notifications-notify` and `call-process` locally, because delivery is the
  unit under test.
- **Production code never checks `noninteractive`.** A batch-mode production
  path that silently swallowed alerts would recreate the failure this slice
  removes.

<!-- doctrine:section sec-3 -->
# Run outcomes and the streak

Governed by DEC-014. This section is the contract SL-018 consumes.

## Current behaviour

`satan-broker--failure-streak-count` (`satan-broker.el:311`) sorts every run
directory under `satan-runs-dir` newest-first. It counts leading `.FAILED`
suffixes and reads nothing inside the directories. This has three consequences:

- **It is global.** A `tick-pulse` success or an interactive MCP run between
  two `motd` failures resets the `motd` streak to zero.
- **It sees only the suffix.** A `session_blocked` run is `status=failed` but is
  deliberately left un-renamed (DEC-8). Its directory therefore *ends* the walk,
  and the next failure counts as streak 1 again. That is the opposite of the
  DEC-8 comment's intent (`satan-broker.el:535-537`).
- **It cannot count anything except failure.** SL-018 needs "N consecutive
  `credential_deferred` runs of this mode".

## Target: the outcome of a run

An **outcome** is what a finished run recorded about itself:

- its `status` file, one of `done`, `failed`, `timed-out`, `invalid-protocol`
  or `budget-exceeded` (`satan-audit.el:685-692`);
- the `reason` in its `final.json`.

No-child runs already put their cause in `reason` (`session_blocked`,
`perceive_failed`, `budget_daily_tokens`). From section 7 on, a child that
dies without a final does too, carrying its error class.

```elisp
;; satan-run.el — leaf; json-parse-buffer is built in, so no new require.

(defconst satan-run-id-regexp
  "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)-\\(.+\\)-\\([0-9a-f]\\{6\\}\\)\\'"
  "A run-id: group 1 timestamp, 2 mode name (may contain hyphens), 3 hex.")

(defun satan-run-mode-from-id (run-id)
  "Return the mode name inside RUN-ID (a leaf with or without `.FAILED'), or nil.
\"20260923T081501-tick-pulse-33ec98\" -> \"tick-pulse\"."
  ...)

(defun satan-run-outcome (dir)
  "Return DIR's recorded outcome, or nil when DIR has no `status' file.
Plist: (:run-id ID :mode MODE :status SYMBOL :reason STRING-OR-NIL :dir DIR).
A missing or unparseable `final.json' yields :reason nil."
  ...)

(defun satan-run-outcome-streak (mode counts-p &optional skips-p runs-dir)
  "Return MODE's current streak as a list of outcomes, newest first.
Walks MODE's runs in RUNS-DIR (default `satan-runs-dir') from newest
back.  A run with no outcome is stepped over; an outcome satisfying
SKIPS-P is stepped over; one satisfying COUNTS-P is collected; any
other outcome ends the walk.  SKIPS-P is tested before COUNTS-P."
  ...)
```

The function returns the outcomes themselves, not a count. The caller then has:

- the **position**, `(length streak)`;
- the **first run** of the streak, `(car (last streak))`, which the
  announcement names.

The walk is **policy-free**. Which outcomes count, and which are stepped over,
is decided by the caller.

### Who parses run-ids

`satan-run.el` owns run identity (DEC-001), yet two modules parse run-ids
themselves today:

- `satan-tank.el:90` uses an ad-hoc mode regexp;
- `satan-context.el:245` defines `satan-context--run-id-regexp`, which also
  pulls out the date and `.FAILED`.

This slice adds the third reader, so all three move onto `satan-run.el`:

- `satan-tank` calls `satan-run-mode-from-id`;
- `satan-context` builds its date and `.FAILED` groups on
  `satan-run-id-regexp`, and stops defining its own id grammar.

### The failure streak (broker policy)

The failure streak is a **same-cause** streak, per DEC-015. It counts
consecutive failures whose status and reason match the newest run's. A new
cause therefore starts again at position 1, and the announcement names that
cause's own first run.

```elisp
;; satan-broker.el
(defconst satan-broker--streak-transparent-reasons
  '("session_blocked" "credential_deferred")
  "Reasons of runs that neither extend nor break a failure streak.")

(defun satan-broker--failure-streak (mode-slug newest)
  "MODE-SLUG's same-cause failure streak ending at outcome NEWEST."
  (let ((cause (list (plist-get newest :status) (plist-get newest :reason))))
    (satan-run-outcome-streak
     mode-slug
     (lambda (o) (equal (list (plist-get o :status) (plist-get o :reason)) cause))
     (lambda (o) (member (plist-get o :reason)
                         satan-broker--streak-transparent-reasons)))))
```

`NEWEST` is the outcome of the run being announced, which the broker reads with
`satan-run-outcome` on that run's directory.

`credential_deferred` is listed now so that SL-018's outcome is transparent to
the failure streak from the day it first appears. It is only a string, so no
code in this slice depends on SL-018.

### Example

This example walks the failure streak (same cause: `failed`/`auth`) back from
`0924T0815-motd`, newest first. Runs of every other mode are never visited.

| run | status / reason | step |
|---|---|---|
| `0924T0815-motd` | failed / auth | count → 1 |
| `0923T1200-motd` | *(no `status` file: in flight, or Emacs died)* | step over |
| `0923T0830-motd` | failed / session_blocked | step over |
| `0923T0815-motd` | failed / auth | count → 2 |
| `0922T0815-motd` | failed / unknown | stop (another cause) |

Result: position 2, first run `0923T0815-motd`.

### SL-018's use (illustrative, not built here)

```elisp
(satan-run-outcome-streak
 mode (lambda (o) (equal (plist-get o :reason) "credential_deferred"))
 (lambda (o) (equal (plist-get o :reason) "session_blocked")))
```

## Properties

- **Derived, not stored.** The run bundles already on disk are the only input.
  No counter file exists and no third writer is added (ADR-018 D5; ledger
  row 4).
- **Owned by the leaf.** Run discovery (`satan-run-list-dirs`) and run identity
  belong to `satan-run.el` (DEC-001). The outcome reader sits beside them. Its
  requires stay `cl-lib`/`subr-x`/`satan-custom`.
- **Cost.** Listing all run directories costs what today's walk costs. The walk
  then reads `status` and `final.json` only until the streak ends, so the reads
  are bounded by streak length plus the runs stepped over.
- **A run with no outcome is rare, and stays rare.** Only two things leave a
  run without a `status` file: a run still in flight, and an Emacs that died
  mid-run. A spawn error before the child starts, including a manifest that
  cannot be built, now finalises as `failed`/`spawn_failed` (section 4). It is
  announced and counted, not stepped over.
- **The rename is a view.** The `.FAILED` suffix stays as a human affordance
  for `ls`, but nothing counts it any more.
- **Known limit: the walk starts at the mode's newest run,** not at the run
  being announced. If two runs of one mode overlap and the newer finishes
  first, the older run's announcement can see a shorter or different streak.
  That needs a run to outlast its mode's cadence, or a manual run to overlap a
  scheduled one. The worst case is one pop early or late. Accepted rather than
  adding a start-at parameter.
- **Timing.** The broker calls the walk *after* `satan-audit-close` and the
  rename, so the run being announced is already visible to the walk as
  position ≥ 1.

<!-- doctrine:section sec-4 -->
# One tool-ctx, and a spawn that cannot fail silently

Governed by DEC-016, with DEC-019 for `spawn_failed`.

A **tool-ctx** is the plist that tool handlers and the intervention write API
receive: run-id, mode name, frozen time, capabilities, audit handle and
percept handles. `satan-intervention--ctx-required`
(`satan-intervention.el:332`) is the single check that it carries `:id`,
`:mode-name`, `:time-now` and `:audit`.

## Current behaviour

Five functions build tool-ctx plists. Only one of them lives where DEC-001
puts tool-ctx ownership, in `satan-run.el`:

| builder | used for | problem |
|---|---|---|
| `satan-run-tool-ctx` (`satan-run.el:225`), from a `satan-run` struct | in-run tool calls, output handler, MCP | none: the canonical one |
| `satan-sensor-alerts--make-tool-ctx` (`satan-sensor-alerts.el:297`) | pre-spawn alerts | **no `:audit`**, no `:percept-handles`, and the id `pre-spawn-<mode>` joins no run. This causes ISS-016's 221 failures. |
| `satan-observer--ctx-from-run-ctx` (`satan-observer.el:328`) | pre-spawn outcome classification | a hand-built copy from the `prepare` plist |
| `satan-intervention-mark--build-ctx` (`satan-intervention-mark.el:97`) | manual `M-x` marks | duplicate of the atsatan builder below |
| `satan-tools-atsatan--intervention-ctx` (`satan-tools-atsatan.el:468`) | `@satan` outcome directives | duplicate of the mark builder above |

`satan-broker--spawn` also has a gap. It already wraps its whole body in one
`condition-case` (`:568`), but that handler only clears the DEC-8
scheduled-run lock `satan-run--spawn-running` and re-signals. The error then
dies in the timer as a `message`. Two windows leave a run with no `status`
file, and nothing announces either:

- **Before the audit exists.** `satan-broker--build-manifest` (`:611`) runs
  before `satan-audit-open`. It signals when a tool is unknown or its
  description file is missing from the corpus (`satan-tools.el:209`). The
  corpus is a separate repo, so a package deployed ahead of its corpus breaks
  every run of the affected mode. The no-child writer (`:446`) calls the same
  builder, so budget-denied and perceive-failed runs of that mode fail the
  same way.
- **After the audit, before the child.** If the context function, the bundle
  write or `make-process` throws, the run has a truncated transcript. One such
  run exists from 2026-06-21 (`20260621T090011-tick-pulse-8b31a5`).

Under a per-mode walk, a run in either window would be stepped over for ever.
The handler also leaks the stderr buffer (`:572`) on every failed launch.

## Target

Every tool-ctx is built in `satan-run.el`. A spawn that fails before its child
starts finalises like any other failed run.

```mermaid
sequenceDiagram
  participant S as satan-broker--spawn
  participant R as satan-run.el
  participant O as satan-observer-process
  participant A as satan-sensor-alerts-check
  participant F as satan-broker--finalize
  participant W as --write-no-child-run
  Note over S,W: the existing condition-case, from the lock until make-process returns
  S->>S: manifest <- build-manifest; audit <- satan-audit-open
  S->>R: run-ctx <- make-satan-run (:audit audit :prepare prepare ...)
  S->>O: process (satan-run-tool-ctx run-ctx)
  S->>S: prepare <- enrich; setf (satan-run-prepare run-ctx)
  S->>A: check ... :tool-ctx (satan-run-tool-ctx run-ctx)
  S->>S: prepare <- :pre_spawn; setf slot; bundle; proc <- make-process
  alt error, no child, audit open (run-ctx bound)
    S->>F: kill stderr; clear lock; mirror percept if no bundle; spawn_failed; finalize
    F-->>S: status, final.json, .FAILED, announce (sections 6-7)
  else error, no child, no audit yet (manifest or audit-open threw)
    S->>W: kill stderr; clear lock; failed / spawn_failed, stub manifest, rename-announce
  end
  Note over S: returns run-id; a pre-child error is not re-signalled
```

### `satan-broker--spawn`

- **The single `make-satan-run` moves up**, to immediately after
  `satan-audit-open`, and the call at `:679` is removed. Every slot value is
  bound by then: `run-id`, `dir`, `bundle-path`, `stdout-log`, `audit`,
  `prepare`.
- **Every later rebind of `prepare` is followed by
  `(setf (satan-run-prepare run-ctx) prepare)`.** There are three: the
  observer result, enrich, and `:pre_spawn`. Nothing relies on `plist-put`
  mutating a shared cons.
- **Pre-child errors finalise the run.** No second `condition-case` is added.
  The existing handler becomes the one pre-child handler. `run-ctx` and
  `proc` are bound to nil at the top of the function, so the handler can tell
  how far the spawn got.
  - **Always.** The handler clears `satan-run--spawn-running`, as it clears
    the lock today.
  - **The stderr buffer is killed only when no child exists.** Killing a live
    child's stderr buffer breaks its pipe and kills the run. The stderr-flush
    sentinel wrapper is installed right after `make-process`, so once a child
    exists its sentinel owns the buffer (RV-011 F-1; PHASE-05 OQ-A).
  - **The child exists (`proc` non-nil).** The error came from the timer or
    sentinel wiring after `make-process`. The child's sentinel owns
    finalisation, so the handler re-signals as it does today and finalises
    nothing. This prevents a double finalise, and a second close into a
    directory the `.FAILED` rename has already moved.
  - **No child, audit open (`run-ctx` non-nil).** The handler:
    1. records `(satan-audit-record audit 'broker 'spawn-failed (:error MSG))`;
    2. attaches `(:percept …)` from `prepare` as `bundle.json` if the context
       function had not yet produced a bundle (the no-child writer's
       convention), so the audit bundle checks and the observer's baseline
       still find a percept;
    3. sets the struct's `failure-reason` to `"spawn_failed"` and its status to
       `'failed`;
    4. calls `satan-broker--finalize`. Finalize writes `status`, a
       `final.json` whose reason is `spawn_failed` (section 7), the `.FAILED`
       rename and the announcement.
  - **No child, no audit yet.** The manifest build or `satan-audit-open`
    threw. The handler calls `satan-broker--write-no-child-run` with `'failed`,
    reason `"spawn_failed"`, the error message in the final's summary and
    `:rename-announce t`.
  - **Return value.** In both no-child branches the handler returns the
    run-id and does not re-signal: the failure is recorded and announced, and
    a re-signal would only add a timer `message`. This matches the
    `perceive_failed` path in `satan-broker-run`.
  - **Trace.** Both no-child branches call
    `(satan-trace-outcome "spawn_failed")`. `satan-broker-run` stamps
    `"spawned"` before calling `--spawn` (`satan-broker.el:549`), and the
    stamp is last-write-wins, so the tick trace no longer calls a failed spawn
    spawned.

  Soft-failing stages that already `condition-case` themselves (the observer,
  the probes, the sensor alerts, the ingest cursor) keep their own handling.
- **The manifest never blocks a record.** `satan-broker--manifest-or-stub`
  returns the built manifest or, when the build signals, a stub
  `(:run_id ID :mode (:name NAME) :manifest_error MSG)`. `satan-audit-open`
  only writes the manifest to `manifest.json`, so the stub is admissible. The
  no-child writer uses it, so budget-denied, perceive-failed and
  pre-audit-spawn-failed runs of a mode with a broken manifest still end with
  a `status`. `--spawn` keeps calling the strict builder: the harness needs the
  real tool schemas, so a spawn with a broken manifest must fail and be
  recorded, not proceed.
- **The probe commits and the ingest cursor are unaffected.** They run after
  the sensor alerts and before the bundle, as today. A `spawn_failed` run
  therefore commits its probes, exactly as a run that spawned and then failed
  does today.

### The other builders

- **`satan-sensor-alerts-check`** takes `:tool-ctx` instead of `:run-dir`,
  which it used only to build the synthetic context.
  `satan-sensor-alerts--make-tool-ctx` is deleted. The A17 capability gate
  still works: `satan-run-tool-ctx` copies the mode's `:capabilities`, so
  removing `notify` from a mode still yields `capability_denied`.
  `--notify-call` keeps its tool-call `:id` (`pre-spawn-<cause>`), which names
  the call, not the intervention.
- **`satan-observer-process`** takes the tool-ctx in place of the `prepare`
  plist. It checks the ctx with `satan-intervention--ctx-required`, reads
  `:time-now`, and passes the tool-ctx to the classify API.
  - `satan-observer--ctx-from-run-ctx` is deleted.
  - The wall-clock fallback for NOW (`satan-observer.el:384`) is deleted: a ctx
    without `:time-now` fails the check, so it cannot run with the wrong time.
  - The `:ctx` option is deleted from `opts`, leaving one way to pass the ctx.
    The other options are unchanged.
  - The ten direct calls in `satan-observer-test.el` move to a tool-ctx built
    with `satan-run-manual-tool-ctx` over a temporary audit handle.
- **`satan-run-manual-tool-ctx (run-id audit now)`** replaces the two identical
  manual builders. It returns `:id RUN-ID :mode-name "manual-mark" :time-now
  NOW :audit AUDIT :capabilities ()`. `satan-intervention-mark` and
  `satan-tools-atsatan` both call it.

## Consequences

- **Pre-spawn interventions mint as `<run-id>.ivNNN`** and carry
  `percept_handles`, so the observer's correlation gate can reach them
  (mem_01a0c168d5eb795387f47fc818fe2810). No earlier pre-spawn intervention
  was ever written, so no old id shape needs migrating. The IMP-001/IMP-002
  cross-checks are re-run against one in verification.
- **`:mode-name` loses its `/pre-spawn` suffix.** Nothing reads the suffix (rg,
  2026-09-23). A pre-spawn alert remains identifiable by its message
  (`SATAN sensor: <cause>`) and by the `pre_spawn` block in `actions.json`.
- **`satan-intervention--ctx-required` is unchanged.** One contract means the
  invariant is enforced at one point (REQ-009).

<!-- doctrine:section sec-5 -->
# Record before emit

Governed by DEC-018 and SPEC-001 REQ-003, which requires every enacted action
to be appended to a durable, immutable audit log.

## What counts as the record

`satan-intervention-create` writes an intervention to two places:

| store | role |
|---|---|
| `intervention.created`, appended to the run's `transcript.jsonl` by `satan-audit-record` | **the record**: canonical and append-only. This is ledger row 4's single writer. |
| a row in `satan_interventions` | a **projection**. The observer queries it, and it can be rebuilt from the transcript (`satan-intervention-rebuild`). |

The function's own docstring agrees: "The audit record is canonical; a
DB-side failure leaves the run's audit log intact"
(`satan-intervention.el:385`). REQ-003 is therefore satisfied by the audit
append, and only the append has to come before the keeper sees anything.

## Current behaviour

`satan-tool/notify-send` shows the alert first (`satan-tools-notify.el:56`)
and calls `satan-intervention-create` afterwards (`:65`). The pre-spawn path
therefore emits without a record. Even with a valid ctx, a failure in either
store reports a tool error for an alert the keeper has already seen.

## Target

Both write APIs are split the same way: a **record** half that validates and
appends to the audit log and touches no database, and a **project** half that
writes Postgres. The composed functions keep their names and contracts, for
callers that do not emit (see the end of this section).

```elisp
;; satan-intervention.el
(cl-defun satan-intervention-record
    (&key ctx kind target-surface message related-motive-id cue-handles
          expected-outcome outcome-window-minutes severity)
  "Validate, mint the id, append `intervention.created' to CTX's audit.
Returns the payload plist (carrying :intervention_id).  Signals on an
invalid ctx, a validator failure, or an append failure — and then
nothing has been recorded.")

(cl-defun satan-intervention-project
    (payload &key (db satan-memory-migrate-database))
  "INSERT PAYLOAD into the `satan_interventions' projection (idempotent,
ON CONFLICT DO NOTHING).  Signals on psql failure.")

(cl-defun satan-intervention-create
    (&key ctx kind target-surface message related-motive-id cue-handles
          expected-outcome outcome-window-minutes severity
          (db satan-memory-migrate-database))
  "Record then project; return the intervention id.  Unchanged contract."
  ...)

(cl-defun satan-intervention-project-with-verdict
    (payload verdict &key (db satan-memory-migrate-database))
  "Project PAYLOAD and its VERDICT in one transaction (undelivered pops).")

(cl-defun satan-intervention-classify-record
    (&key ctx intervention-id revision-p classification confidence evidence
          maturity next-revisit-at source classified-at marked-by notes)
  "Validate the verdict and append `intervention.outcome_classified' (or
`outcome_revised' when REVISION-P) to CTX's audit.  No database access.
Returns the payload plist.  Signals on an invalid ctx, a validator
failure or an append failure.")

(cl-defun satan-intervention-classify-project
    (payload &key (db satan-memory-migrate-database))
  "UPSERT PAYLOAD into `satan_intervention_outcomes'.  Signals on psql
failure, including a missing `satan_interventions' parent row.")

(cl-defun satan-intervention-classify (&key ctx intervention-id ... db)
  "Lookup (sets REVISION-P), classify-record, classify-project, then the
attribute enqueue.  Unchanged contract."
  ...)
```

Today `satan-intervention-classify` reads Postgres (`satan-intervention-lookup`,
`satan-intervention.el:422`) *before* it appends, and its upsert has a foreign
key to `satan_interventions` (`0006_interventions.sql:52`). An `unknown`
verdict for an alert whose projection row was never written therefore cannot
go through the composed API. The split puts the append first on this path.

`satan-tool/notify-send` becomes:

```mermaid
flowchart TD
  V["validate args"] --> REC["payload <- satan-intervention-record"]
  REC -- signals --> E1["(error ...)<br/>nothing shown, nothing recorded"]
  REC --> AN["id <- satan-announce :title :body :urgency :timeout"]
  AN --> PR["satan-intervention-project payload"]
  PR -- signals --> OK2["(ok :id ID :intervention_id IV :projection \"failed: ...\")"]
  PR --> OK1["(ok :id ID :intervention_id IV)"]
  AN -- "pop signals" --> UD["satan-tools-notify--mark-undelivered<br/>(never signals)"]
  UD --> OK3["(ok :id :null :intervention_id IV :delivered :false :error ERR)"]
```

`satan-tools-notify--mark-undelivered (ctx payload err)` runs two steps, and
each step's failure is caught and noted on the result, so the branch always
returns `ok` and the cooldown arms (see below). If step 1 fails, step 2 is
skipped: a projected intervention with no verdict would look pending, and
the observer would score an alert the keeper never saw. Step 2 writes both
rows in one transaction, so the same state cannot arise from a failed verdict
write either (RV-012 F-2).

The pop result carries `:id :null`, not `nil`: `nil` serialises as `{}`.

1. **`satan-intervention-classify-record`** with `revision-p` nil (a verdict
   minted moments after creation cannot be a revision), and:

   | field | value | why |
   |---|---|---|
   | `classification` | `unknown` | nothing was observed |
   | `confidence` | `high` | the failed pop is certain |
   | `maturity` | `mature` | final: `pending` would invite reclassification |
   | `source` | `auto` | the broker decided, not the keeper |
   | `classified-at`, `next-revisit-at` | ctx `:time-now` | no revisit is due |
   | `evidence` | JSON null | nothing was observed |
   | `notes` | `undelivered: ERR` | |

2. **`satan-intervention-project-with-verdict`** of the intervention payload
   and the verdict: both INSERTs in one transaction, intervention first, so
   the foreign key holds and either both rows land or neither does.

No attribute-outcome enqueue happens on this path: an alert the keeper never
saw teaches the attribute daemon nothing.

How each branch meets the rule:

- **Nothing is shown until the audit line exists.** REQ-003 holds by
  construction.
- **A Postgres outage cannot silence an alert.** The projection comes last,
  and its failure is only a note on an `ok` result.
- **A pop that fails after the record is marked in the record itself.** The
  verdict's audit append needs no database, so the mark lands even while
  D-Bus and Postgres are both down. It uses the existing
  `intervention.outcome_classified` event and vocabulary; nothing new is
  added.
  - Once projected, the outcome row excludes the intervention from
    `satan-intervention-pending` (`satan-intervention.el:780`), so the
    observer never scores it as seen.
  - While the projection is down, `satan-intervention-rebuild` replays both
    events, so it cannot resurrect a pending, unseen alert.
  - The result is `ok` with `:delivered :false`, because the action was
    recorded; it tells the model plainly that nothing was shown.
- **The result shape passes `satan-protocol--validate-tool-result`**
  (RV-009, verified).

## Sensor alerts and the cooldown

A sensor alert goes through the same `notify_send`, via `satan-tool-dispatch`.
`--dispatch` treats `:ok t` as dispatched and arms the per-cause cooldown
(`satan-sensor-alerts.el:368`). Because every recorded outcome returns `ok`,
**the cooldown arms on the record**, whatever happens to the pop or the
projection. With D-Bus down, that means one record per cause per cooldown
window (24 h by default), not one per run. Each such record is already
classified as undelivered.

## Emits that are not interventions: operational alarms

Two emits are not actions on the keeper's world. They report SATAN's own
state, and neither gets an intervention record. The authority-ledger row 4
standing note is revised (REV) to name both, so no future audit mistakes them
for audit writers.

- **Failure announcements** (section 6) come after `satan-audit-close` and the
  `.FAILED` rename. The run bundle is their record: `status`, `final.json`,
  the transcript and `crash-context`. That record exists before the
  announcement. The decision to pop at a given streak position is derived from
  those bundles, so it is reproducible and needs no record of its own. The
  journal line is written for every failure regardless.
- **Listener deaths** (`satan-attribute-listener--report-death`,
  `satan-patch-listener--report-death`) happen outside any run, with no audit
  handle. They call `satan-announce` with a critical pop *and* a `:journal`
  line, and the journal line is their only durable trace. Recording them in
  the audit log would need a third audit writer, which ledger row 4 forbids.

## Tests must not reach the production projection

`satan-memory-migrate-database` defaults to `satan_memory`, the production
database. The verification invocation `SATAN_DB_HOST=/run/postgresql/`
reaches the production server (mem_01a0316176b17672988b91759e145e5d). Today
the tests stub `satan-intervention-create` wholesale. After the split:

- **Tests of `notify_send` and the sensor alerts** stub
  `satan-intervention-project` and `satan-intervention-classify-project` at
  the database boundary, and assert they were called with the recorded
  payloads. The record steps run for real against a temporary audit handle,
  so ISS-016's class of defect cannot hide behind a stub again.
- **`satan-intervention-test.el` and `satan-observer-test.el`** exercise a
  real projection, each against the test database `satan_memory_test`, as
  they do today.

## Out of scope, noted

Several other intervention-creating tools also produce their side effect first
and call `create` afterwards: `sway_border_set` (`satan-tools-sway.el:135`),
`inbox_append`, `proposal_stage` and `patch_job_create`. This is the same
REQ-003 ordering question, but for effects that are not emits. They stay on
`satan-intervention-create` in this slice, and the question is captured as a
backlog item.

<!-- doctrine:section sec-6 -->
# Announce policy

Governed by DEC-015. This section uses the streak from section 3.

## Current behaviour

`satan-broker--announce-failure` (`satan-broker.el:331`) does two things:

- It writes a journal line for every failure.
- It pops a desktop notification only when the global streak is exactly 1.

The line reads `<status> <mode> <run-id> <reason>`, and for a child that died
without a final the reason is the literal word `failed`.

## Target

```elisp
(defun satan-broker--announce-due-p (outcome position)
  "Non-nil when a desktop pop is due for OUTCOME at streak POSITION.
Pure.  auth reason -> always; budget-exceeded -> only at 1;
otherwise POSITION is a power of two (1, 2, 4, 8, ...)."
  (cond ((equal (plist-get outcome :reason) "auth") t)
        ((eq (plist-get outcome :status) 'budget-exceeded) (= position 1))
        (t (zerop (logand position (1- position))))))

(defun satan-broker--announce-failure (run-id mode-slug status reason dir)
  ;; MODE-SLUG, not MODE-NAME: `mode-name' is an Emacs special variable
  ;; (RV-011 F-3).  With both switches off nothing is due, so
  ;; `satan-announce' is never called.
  ;; both call sites (finalize rename, no-child writer) pass the renamed DIR
  (let* ((newest   (or (satan-run-outcome dir)
                       (list :run-id run-id :status status :reason reason)))
         (streak   (satan-broker--failure-streak mode-slug newest)) ; section 3
         (position (max 1 (length streak)))
         (first-id (plist-get (car (last streak)) :run-id))
         (line     (satan-broker--failure-line
                    status mode-slug run-id reason position first-id))
         (pop      (and satan-failure-notify
                        (satan-broker--announce-due-p newest position)
                        (not (satan-broker--quiet-p)))))
    (when (or pop satan-failure-syslog)
      (ignore-errors
        (satan-announce
         :title (and pop (format "SATAN %s (%s) x%d" status mode-slug position))
         :body line
         :urgency (if (equal (plist-get newest :reason) "auth") 'critical 'normal)
         :journal (and satan-failure-syslog line))))))
```

### Line format

`<status> <mode> <run-id> <reason> x<position> since <first-run-id>`

The ` since …` part is omitted at position 1. An example:

```
failed motd 20260926T081501-motd-9a01c2 auth x4 since 20260923T081501-motd-33ec98
```

The first four fields are unchanged, so existing `journalctl -t satan` readers
still parse the line. The text is ASCII only (section 2).

### Policy decisions

- **The position is derived.** It is the length of the per-mode
  **same-cause** failure streak (section 3), and the broker keeps no state. A
  new cause starts again at 1 and pops immediately. So twelve budget denials
  followed by a 500 give the 500 position 1, not 13, and the line names the
  500's own first run. `(max 1 …)` guards against a walk that
  somehow misses the run being announced; that should not happen, because the
  walk runs after close and rename.
- **The policy reads the newest outcome's reason, not the display reason.**
  After section 7, a classified failure's `final.json` reason is its class, so
  `auth` is matched structurally. The `reason` argument stays display-only.
  For example, a budget denial passes `"500000/400000 tokens"`.
- **An `auth` failure pops at every position, at critical urgency.** A human
  must act on an expired key. After SL-018, an `auth` failure also evicts the
  cached reference, so a repeat means the new key is bad too.
- **`budget-exceeded` pops once per streak.** It cannot change before
  midnight, so a repeat carries no information. The journal still gets a line
  for every denied run.
  - Known limit: the ceiling is global but streaks are per mode, so a breach
    pops at most once for each scheduled mode per day (3-4 pops). That is
    accepted as bounded.
- **Quiet hours** go through `satan-tick-quiet-p`, the ledger row 7 owner, via
  a small `satan-broker--quiet-p` that uses the `declare-function` precedent
  from `satan-sensor-alerts.el:20`. `satan-tick` requires `satan-broker`, so the
  broker cannot require it back. When the function is not bound, it is not
  quiet. A position that falls inside quiet hours is not replayed later, and
  the journal line is still written. Today `satan-tick-quiet-hours` is nil, so
  this is inert until quiet hours are re-enabled.

### Noise bound

| mode cadence | persistently broken for | pops |
|---|---|---|
| tick, every 30 min, one cause | 24 h (48 runs) | 6 (positions 1, 2, 4, 8, 16, 32) |
| motd, daily, one cause | 30 days | 5 (days 1, 2, 4, 8, 16) |
| any, alternating causes | n runs | up to n (each switch is new information) |
| any, `auth` | n runs | n (by design) |

## Kill switches

`satan-failure-notify` still vetoes every failure pop, and
`satan-failure-syslog` still vetoes every failure journal line. Their
docstrings are updated to describe the back-off instead of "first failure of a
streak".

<!-- doctrine:section sec-7 -->
# Failure reason: class transport and spawn failure

Governed by DEC-019. This covers only the transport part of IMP-005; it adds
no typed exception layer.

## Current behaviour

- **How the harness classifies errors.** It classifies an exception from the
  provider with `classify_error` (`satan/harness/runloop.py:115`), using bare
  substring tests: `"rate"`, `"auth"`, `"401"` and so on. So `"generate"`
  reads as a rate limit, `"author"` reads as an auth error, and any digit run
  containing `401` reads as an auth error too.
- **How it sends the class.** The class goes out double-encoded:

  ```json
  {"type":"error","error":"{\"class\": \"auth\", \"detail\": \"Error code: 401 ... API key expired\", \"tokens_total\": 0, \"turn\": 0}"}
  ```

- **Where the class is lost.** `satan-broker--on-error`
  (`satan-broker.el:166`) records the object and sets `'failed`, and the class
  goes no further:
  - `final.json` is written as `{"status":"invalid"}` (`satan-audit.el:123`);
  - `crash-context` has no class field;
  - the announcement's reason is the word `failed`.
- **Errors that carry no class at all.** Init-path errors are plain strings,
  e.g. `init failed: OPENROUTER_API_KEY not set` (`runloop.py:178`). A
  pre-child spawn error leaves no record (section 4).

## Target

```mermaid
flowchart LR
  H["harness error line<br/>(class by status_code)"] --> OE["--on-error:<br/>parse class"]
  SF["pre-child spawn error<br/>(section 4)"] --> SLOT
  OE --> SLOT["satan-run failure-reason<br/>(first write wins)"]
  SLOT --> FIN["finalize (no final):<br/>final.json {status: invalid, reason}"]
  SLOT --> CC["crash-context :failure_reason"]
  FIN --> OUT["outcome failed/auth, failed/spawn_failed, ...<br/>(section 3 walk)"]
  FIN --> FR["--failure-reason, used in the announce line"]
  OUT --> POL["announce policy (section 6)<br/>SL-018 eviction on auth"]
```

### Harness: `classify_error`

The status code is read first. Text matching is only a fallback, and it
matches whole words.

```python
def classify_error(e: Exception) -> str:
    code = getattr(e, "status_code", None)        # openai.APIStatusError et al.
    if code == 401:                    return "auth"
    if code == 402:                    return "credits"
    if code == 429:                    return "rate_limit"
    if isinstance(code, int) and code >= 500: return "server"
    msg = str(e).lower()
    if re.search(r"\b(429|rate[ _-]?limit(ed)?|quota)\b", msg): return "rate_limit"
    if re.search(r"\b(401|unauthori[sz]ed|authentication|invalid api key|api key expired)\b", msg): return "auth"
    if re.search(r"\b(402|insufficient credits)\b", msg): return "credits"
    if re.search(r"\b(500|502|503|504)\b", msg): return "server"
    if re.search(r"\b(timeout|timed out)\b", msg): return "timeout"
    return "unknown"
```

- **403 is not `auth`.** OpenRouter answers 403 when a moderation check flags
  the input, and the key is fine. Mapping 403 to `auth` would pop critically on
  every run and, after SL-018, evict a valid key. A 403 whose text names an
  auth failure still reads as `auth` through the word match; any other 403 is
  `unknown`.
- **402 is `credits`.** OpenRouter answers 402 when the account is out of
  credits. That needs the keeper as much as an expired key does, but it is not
  a key problem, so it gets its own class, follows the ordinary back-off
  (section 6), and SL-018 must not evict on it.
- **Tests.** The existing cases in `test_gptel_harness.py:267` keep passing,
  except `test_classify_auth_403` (`"Error code: 403 - Forbidden"`), which
  now expects `unknown`. That change is the point of this rule. New cases cover
  the false positives (`"generate"`, `"author"`, `"4013 tokens"`), the
  `status_code` paths, 402 as `credits`, and a 403 moderation error reading as
  `unknown`.
- **Init-path errors stay unclassified.** They read as `unknown`. SL-018 moves
  key resolution before the spawn, so `KEY not set` should stop reaching the
  harness.
- **Deploy.** The jail runs the harness from the GitHub flake input
  (mem_01a09dd9b5bc704388093135ea89e9f2). Shipping this change therefore
  takes a push, a `nix flake update satan` in `~/flakes`, and a home-switch.
  That is a step on the slice's deploy checklist. The elisp half works either
  way; until the new harness is live, it just receives the old, noisier
  classes.

### Broker

- **A new `satan-run` slot, `failure-reason`.** It is appended last in the
  `cl-defstruct`. Two paths write it, and the first write wins:
  - **`--on-error`** stores `(satan-broker--error-class obj)`. That pure helper
    parses `(plist-get obj :error)` with
    `json-parse-string :object-type 'plist` and returns its `:class` if that
    is a string, and `"unknown"` otherwise (including when the error is not
    JSON). The protocol guarantees `:error` is a string.
  - **The pre-child spawn handler** (section 4) stores `"spawn_failed"` when
    the audit is open. Before the audit exists there is no struct, and the
    no-child writer puts `spawn_failed` in its final directly.
- **Finalize.** When the run has no final and `failure-reason` is set,
  finalize hands `satan-audit-close` a synthesised final,
  `(:status "invalid" :reason FAILURE-REASON)`. `satan-audit` stays generic;
  the broker owns what a failed run's reason is.
- **`satan-broker--crash-context`** adds `:failure_reason`.
- **`satan-broker--failure-reason`** resolves the reason in this order: the
  final's `:reason`, then `failure-reason`, then the status name.

## Resulting outcomes

| failure | `final.json` reason | outcome |
|---|---|---|
| provider 401 | `auth` | failed / auth |
| provider 402 | `credits` | failed / credits |
| provider 403 (moderation) | `unknown` | failed / unknown |
| provider 429 | `rate_limit` | failed / rate_limit |
| init `KEY not set` | `unknown` | failed / unknown (SL-018 removes this path) |
| error before the child starts | `spawn_failed` | failed / spawn_failed |
| timeout | *(none)* | timed-out / nil |
| no-child denials | unchanged (`session_blocked`, `budget_daily_tokens`, …) | unchanged |

The existing `final.json` consumers tolerate the added `reason` key
(RV-009, verified):

- `actions-partition-final` handles a missing `:actions`;
- `satan-context` reads only `:summary`;
- the `satan-audit-p/*` checks do not constrain an `invalid` final.

<!-- doctrine:section sec-8 -->
# Code impact

## Module dependencies after the change

Only the edges this slice adds or relies on are shown.

```mermaid
flowchart BT
  ANN["satan-announce (new)<br/>cl-lib, satan-custom; owns satan-notify-app"]
  RUN["satan-run (leaf)<br/>+ id regexp, mode-from-id, outcome, outcome-streak,<br/>manual-tool-ctx, failure-reason slot"]
  INT["satan-intervention<br/>record / project / create"]
  TN["satan-tools-notify"] --> INT
  TN --> ANN
  SA["satan-sensor-alerts"] -. "tool-ctx passed in" .-> RUN
  OB["satan-observer"] -. "tool-ctx passed in" .-> RUN
  BR["satan-broker"] --> ANN
  BR --> RUN
  BR -. "declare-function" .-> TICK["satan-tick-quiet-p"]
  AL["satan-attribute-listener"] --> ANN
  PL["satan-patch-listener"] --> ANN
  MK["satan-intervention-mark"] --> RUN
  AT["satan-tools-atsatan"] --> RUN
  TK["satan-tank"] --> RUN
  CX["satan-context"] --> RUN
  DEV["dev/satan-test.el"] --> ANN
```

- **`satan-announce` needs no SATAN module except `satan-custom`.** It
  cannot create a cycle.
- **`satan-run` keeps its I3 requires**, which are `cl-lib`, `subr-x` and
  `satan-custom`. JSON parsing uses built-ins.
- **`satan-tools-notify` still requires `satan-announce`**, because the
  `satan-notify-app` defcustom has moved there.

## Paths and intended changes

| path | change | section |
|---|---|---|
| `satan/satan-announce.el` | **New.** `satan-notify-app` (moved), `satan-announce`, `-sink`, `-deliver`, `-record`, `-recorded`, `-with-recorder`. | 2 |
| `satan/satan-run.el` | Adds `satan-run-id-regexp`, `-mode-from-id`, `-outcome`, `-outcome-streak` and `-manual-tool-ctx`, plus the `failure-reason` slot. | 3, 4, 7 |
| `satan/satan-broker.el` | `--announce-failure` rewritten (seam, policy, `dir` argument).<br>Adds `--announce-due-p`, `--failure-streak`, `--streak-transparent-reasons`, `--failure-line`, `--quiet-p`, `--error-class`.<br>Removes `--failure-streak-count` and the `notifications` declare-function.<br>`--spawn`: early struct, prepare sync, the existing handler extended to finalise pre-child failures.<br>Adds `--manifest-or-stub`, used by `--write-no-child-run`.<br>`--on-error`, finalize, `--crash-context`, `--failure-reason`: failure reason.<br>`--mark-failed-on-disk`, `--write-no-child-run`: pass the renamed `dir`. | 3, 4, 6, 7 |
| `satan/satan-intervention.el` | `-create` split into `-record` and `-project`; `-classify` split into `-classify-record` and `-classify-project`. The composed functions keep their contracts. | 5 |
| `satan/satan-tools-notify.el` | record → announce → project; `--mark-undelivered` on a failed pop. Drops `(require 'notifications)` and the `satan-notify-app` defcustom. | 5 |
| `satan/satan-sensor-alerts.el` | `-check` takes `:tool-ctx`; `--make-tool-ctx` deleted. | 4 |
| `satan/satan-observer.el` | `-process` takes the tool-ctx; `--ctx-from-run-ctx`, the wall-clock fallback and the `:ctx` option deleted. | 4 |
| `satan/satan-intervention-mark.el`, `satan/satan-tools-atsatan.el` | Use `satan-run-manual-tool-ctx`; own builders deleted. | 4 |
| `satan/satan-tank.el`, `satan/satan-context.el` | Parse run-ids via `satan-run.el`. | 3 |
| `satan/satan-attribute-listener.el`, `satan/satan-patch-listener.el` | `--report-death` goes through `satan-announce` (critical pop + `:journal`). | 2, 5 |
| `satan/harness/runloop.py`, `satan/harness/test_gptel_harness.py` | `classify_error` by `status_code`, then word boundaries; tests. | 7 |
| `dev/satan-test.el` | `let`-binds the recording sink around load and run. | 2 |
| `satan/test/satan-announce-test.el` | **New.** Delivery unit tests, recorder, macro, batch self-check. | 2 |
| `satan/test/satan-run-test.el` | Id regexp, outcome, streak and manual ctx. | 3, 4 |
| `satan/test/satan-broker-test.el` | Streak and announce tests rewritten over outcomes and the recorder; emit stubs removed; class, spawn-failed and early-struct tests. | 3, 4, 6, 7 |
| `satan/test/satan-sensor-alerts-test.el`, `satan-tools-notify-test.el` | Real record step against a temporary audit handle; both projections stubbed at the DB boundary; `satan-intervention-create`/`notifications-notify` stubs removed. | 4, 5 |
| `satan/test/satan-observer-test.el` | The ten `satan-observer-process` calls pass a tool-ctx; `:ctx` option uses migrated. Keeps its real test database. | 4 |
| `satan/test/satan-intervention-test.el` | Both record/project splits (test database `satan_memory_test`). | 5 |
| `satan/test/satan-{attribute,patch}-listener-test.el`, `satan-tools-test.el`, `satan-tank-test.el` | Recorder or new constructor or id parser, where they touch these. The intervention-id parser unification that would touch `satan-intervention-mark-test.el` and `satan-tools-atsatan-test.el` is IMP-022; `satan-context-test.el` needed no change (RV-011 F-9). | 2, 3, 4 |
| `docs/governance.md` | The `satan-observer.el` row names the new broker entry, `satan-observer-process TOOL-CTX` (RV-011 F-7). | 4 |

## Design-target selectors

These are declared at lock (mem_01a0adb7c4f879c38d90403906dd6ea4) and checked
with `rg` (mem_019f8fbda1ed74e39d7f558044ccf592):

- `rg -n 'notifications-notify|"logger"' satan/ dev/ -g '!satan/test/**'`
  should hit only `satan/satan-announce.el`.
- `rg -n 'notifications-notify' satan/test/ -g '!satan-announce-test.el'`
  should find nothing.
- `rg -n 'make-tool-ctx|ctx-from-run-ctx|mark--build-ctx|atsatan--intervention-ctx|failure-streak-count|satan-context--run-id-regexp' satan/ dev/`
  should find nothing. This is I6's mechanical check: the four builders
  outside `satan-run.el` are gone. A new builder added elsewhere later is a
  review concern; no grep for tool-ctx construction separates it from the
  many readers of `:mode-name` and `:id`.

<!-- doctrine:section sec-9 -->
# Invariants, risks and verification

## Invariants

- **I1. One path out.** Every desktop pop and every `satan` journal line
  leaves through `satan-announce-sink`.
- **I2. Recorded before shown.**
  - An intervention emit is shown only after its `intervention.created` audit
    line exists.
  - A failure announcement is shown only after its run's `status` and
    `final.json` exist.
- **I3. The projection never gates.** A failed `satan_interventions` insert
  never suppresses an emit and never un-arms a cooldown.
- **I4. Unseen is marked.** A recorded intervention whose pop failed carries an
  `unknown`/`undelivered` classification in the same transcript.
- **I5. Streaks are derived.** They are computed from run bundles on each call,
  per mode and per cause. No counter is stored.
- **I6. Every tool-ctx is built in `satan-run.el`,** and
  `satan-intervention--ctx-required` is its one check.
- **I7. No terminal-less run.** A scheduled run that got past the gates in
  `satan-broker-run` ends with a `status` file. That includes a run whose
  manifest cannot be built. The exceptions are an Emacs process that dies
  mid-run and a run directory that cannot be written at all.
- **I8. The leaf stays a leaf.** `satan-run.el` requires only
  `cl-lib`/`subr-x`/`satan-custom`.
- **I9. One audit writer.** No new audit writer is added (ledger row 4).
- **I10. The sink is only let-bound, never set.** Production code never
  branches on `noninteractive` to decide delivery.

## Risks

| id | risk | mitigation |
|---|---|---|
| R3 | Operational alarms (failure announcements, listener deaths) have no intervention record. | They are classified as operational alarms (section 5). REV the ledger row 4 standing note. |
| R4 | The pre-spawn intervention id shape changes. | No earlier pre-spawn ids exist. Verify the observer and the IMP-001/IMP-002 cross-checks against a `<run-id>.ivNNN` pre-spawn row. |
| R5 | Quiet-hours suppression does nothing while `satan-tick-quiet-hours` is nil. | Accepted. Unit-tested through `satan-broker--quiet-p`. |
| R6 | The harness classifier change must be deployed separately (flake input). | It is a step on the deploy checklist (section 7). The elisp side is correct with either harness. |
| R7 | The streak walk reads files for each run. | The cost is bounded by streak length. Listing costs the same as today. |
| R8 | Removing per-file stubs exposes tests that relied on emits being swallowed. | The harness binding catches every emit. A test that fails once its stub is gone was asserting nothing, and it is fixed, not re-stubbed. |
| R9 | Test code reaches the production projection (`satan_memory`). | The projection is stubbed at the DB boundary outside `satan-intervention-test.el` (section 5). |
| R10 | Hoisting the struct and wrapping the spawn changes the order in the longest function in the broker. | Early-struct and spawn-failed tests cover it. The soft-failing stages keep their own handlers. |
| R11 | A budget breach pops once per scheduled mode per day. | Accepted limit (section 6). |
| R12 | Overlapping runs of one mode can skew the older run's streak position. | Accepted limit (section 3); at worst one pop early or late. |
| R13 | Until the new harness is deployed, a 403 moderation error still arrives as `auth` and pops critically on every run. | Same as R6: a deploy-checklist step. SL-018 must not evict on `auth` before that deploy. |

Assumptions:

- **A1 (narrowed).** The `auth` class is trusted on `status_code` 401, or on
  a whole-word match. A 403 is not trusted as `auth` (section 7).
- **A2 (confirmed).** The audit handle exists before the sensor alerts run.

## Verification

Evidence names its invocation and counts
(mem_01a0316176b17672988b91759e145e5d). The Elisp suite runs with
`SATAN_DB_HOST=/run/postgresql/ just check`; grep the output for
`unexpected`. The harness tests run with `python -m unittest` in
`satan/harness`.

### Key test cases

**`satan-announce`**

- `satan-announce/deliver-pops-and-journals`
- `satan-announce/journal-only-when-no-title`
- `satan-announce/journal-failure-is-swallowed`
- `satan-announce/pop-failure-propagates`
- `satan-announce/with-recorder-captures-and-isolates`
- `satan-announce/batch-harness-binds-recorder`: a self-check that runs inside
  the suite.

**`satan-run`**

- `satan-run/mode-from-id-handles-hyphenated-modes-and-failed-suffix`
- `satan-run/outcome-nil-without-status`
- `satan-run/outcome-reads-status-and-reason`
- `satan-run/streak-is-per-mode`: another mode's `done` does not break it.
- `satan-run/streak-steps-over-skips-and-unfinished`
- `satan-run/streak-stops-at-non-counting-outcome`
- `satan-run/manual-tool-ctx-satisfies-ctx-required`

**`satan-broker`**

- `satan-broker/announce-due-at-powers-of-two`: positions 1, 2, 4 and 8 are
  due; 3, 5, 6 and 7 are not.
- `satan-broker/failure-streak-restarts-on-new-cause`: the F-3 regression.
- `satan-broker/announce-auth-always-critical`
- `satan-broker/announce-budget-once`
- `satan-broker/announce-journals-every-failure-ascii`
- `satan-broker/announce-quiet-suppresses-pop-not-journal`
- `satan-broker/session-blocked-transparent-to-failure-streak`: the DEC-8
  regression.
- `satan-broker/budget-denied-run-is-recorded-not-delivered`: the ISS-015 leak
  now lands in the recorder.
- `satan-broker/spawn-error-before-child-finalizes-spawn-failed`: the RV-009
  F-4 regression. It also asserts the lock is cleared, the stderr buffer is
  killed, `bundle.json` carries the percept, and the run-id is returned.
- `satan-broker/manifest-error-finalizes-spawn-failed`: a missing tool
  description yields a `failed`/`spawn_failed` run with a stub manifest.
- `satan-broker/no-child-run-survives-broken-manifest`: a budget-denied run
  of a mode with a broken manifest still writes `status`.
- `satan-broker/error-after-child-not-finalized-twice`: an error after
  `make-process` leaves finalisation to the sentinel.
- `satan-broker/error-class-parsed-from-harness-json`
- `satan-broker/error-class-unknown-for-plain-string`
- `satan-broker/failed-run-final-carries-failure-reason`

**`satan-intervention` and `satan-tools-notify`**

- `satan-intervention/record-appends-before-projection`
- `satan-intervention/classify-record-needs-no-database`
- `satan-intervention/classify-composition-unchanged`
- `satan-tools-notify/no-emit-when-record-fails`
- `satan-tools-notify/emits-and-notes-when-projection-fails`
- `satan-tools-notify/undelivered-pop-classified-unknown`
- `satan-tools-notify/undelivered-with-db-down-still-ok`: D-Bus and Postgres
  both fail; the verdict is in the transcript and the result is `ok`, so the
  cooldown arms (RV-009 F-2's scenario).

**`satan-sensor-alerts` and `satan-observer`**

- `satan-sensor-alerts/pre-spawn-intervention-joins-run`: the id is
  `<run-id>.ivNNN` and the audit line is present.
- `satan-sensor-alerts/cooldown-arms-on-record`
- `satan-sensor-alerts/capability-denied-still-suppresses`: the A17 regression.
- `satan-observer/process-uses-run-tool-ctx`

**Harness (Python)**

- `test_classify_by_status_code`: 401, 402, 429, 5xx.
- `test_classify_no_substring_false_positives`
- `test_classify_403_moderation_is_unknown`

### Slice-level evidence

- **V1: hermeticity.** Bracket a full `just test` run with
  `journalctl -t satan --since/--until`. No line in that window may name a
  run-id that is absent from the real `satan-runs-dir`. Test runs live in temp
  directories, so a leaked line cannot name a real run. This check works while
  the live Emacs is also emitting. `satan-announce/batch-harness-binds-recorder`
  keeps the property checked on every run afterwards. Closes ISS-015.
- **V2: selectors.** The section 8 `rg` checks produce the stated hit sets.
- **V3: REQ-003 coverage.** Record coverage for the notify path, both in-run
  and pre-spawn, per REQ-012.
- **V4: live.** After the Elisp change is loaded and the harness is deployed:
  - the next degraded-sensor run produces a `<run-id>.ivNNN`
    `intervention.created` line and a `pre_spawn` entry with `:dispatched_at`,
    and `notified.json` gains `last_notified_at` (closes ISS-016);
  - a forced failure streak on a scratch mode shows the back-off in the
    journal (closes ISS-017).

## Follow-ups (not this slice)

- Backlog: record before side effect for the other intervention-creating tools
  (sway, inbox, proposal, patch). See section 5.
- REVs:
  - the ledger row 4 standing note, naming the operational alarms and the
    journal channel;
  - optionally, a SPEC-001 REQ-003 acceptance criterion: "a side effect whose
    record fails is not enacted".
- Memory: correct the `session_blocked` streak claim in
  mem_eb8e5cff794c48bd86597f94fa50b0ac.
- IMP-005 remainder: the typed exception layer.

