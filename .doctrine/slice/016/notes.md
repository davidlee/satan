# Notes SL-016: goad as SATAN's elicitation surface

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest

**fresh-as-of:** PHASE-03 implemented, 2026-09-24 (uncommitted; orchestrator
commits). SATAN reads goad: `satan-goad.el` readers, a `:goad` evidence slice,
and canon's `goad.outstanding` rule. Inert in production until a queue exists.
PHASE-02 landed as corpus `e3ac87c` / dev `528079c`. Next: `/phase-plan
PHASE-04`.

### PHASE-03

**Orchestrator resolutions** (sheet OQs):
- OQ-1 — outstanding = record has no `:value` and `expires_at` after ctx
  `:time_now`, compared as instants; deferral does not change it; `app:goad`
  only when at least one ask is outstanding (design VT row 25, sec-2).
- OQ-2 — canon owns public `satan-memory-canon-topic-handle`; the rule lives
  in canon under the purity lint; `satan-goad-subject-topic` is a `defalias`.
  Mechanism-only departure from the plan's wording.
- OQ-3 — `:goad` skipped under `:cue_only`.
- OQ-4 — out of scope, backlogged as ISS-024 (overlaps ISS-010).

**Files** (dev repo):
- `satan/satan-goad.el` (new) — `satan-goad-local-date` (date of a parsed
  instant in `satan-goad--zone`, nil for anything but ISO-with-offset),
  `satan-goad-read-queue` (five A3 fields, bad entry dropped alone, never
  signals), `satan-goad-read-record` (record from the emit date's day file),
  `satan-goad-slice` (entry + `:record` when present, queue order, each day
  file read once), `satan-goad-subject-topic` (alias).
- `satan/satan-custom.el` — `satan-goad-queue-file` (state join),
  `satan-goad-data-dir` (corpus join).
- `satan/satan-memory-canon.el` — `satan-memory-canon-parse-instant` (strict,
  `iso8601-parse`), `satan-memory-canon-topic-handle`, rule
  `goad.outstanding`; `hint.topic` now spells topics via the handle function.
- `satan/satan-memory-evidence.el` — `:goad` via `satan-trace-stage
  "evidence.goad"`, skipped under `:cue_only`, key absent when empty; header
  updated.
- `satan/satan-jsonl.el` — `satan-jsonl-read-object-file` (promoted from the
  observer; lenient). `satan/satan-observer-classify.el` — private copy
  deleted, two call sites use it.
- `dev/satan-test.el` — harness floor binds both goad paths to nonexistent
  `temporary-file-directory` paths (`satan-custom` required first).
- Tests: `satan/test/satan-goad-fixture.el` (new, non-suite: goldens dir,
  outcome→id alist, `-with-goldens`, `-with-tmp`, `-write`, `-write-queue`,
  `-ask`), `satan/test/satan-goad-test.el` (new, 15),
  `satan-memory-canon-test.el` (+7), `satan-memory-evidence-test.el` (+5),
  `satan-jsonl-test.el` (+3). Existing tests changed only by added requires.
- `satan/test/goad-fixtures/README.md` — provenance row → `e3ac87c` (shas
  re-verified against that commit).

**Verification:**
- Baseline `just check`: exit 0, 1145 ran / 1139 expected / 6 skipped.
  After: exit 0, 1175 / 1169 / 6 (+30 tests), 0 unexpected, no LOADERR; lint
  clean; test-log warnings identical to baseline (DB-absent attribute
  snapshot noise). Python harness 54 OK.
- VT-24 — `satan-goad/local-date-*` (5 tests): GMT `…T23:30:00+00` →
  `2026-09-23` in 36000, `2026-09-22` in 0; microsecond goldens; raw psql
  space form, naive, date-only, garbage → nil; the read side normalises a
  psql cell through `satan-intervention--normalize-pg-timestamp` and finds
  the answered ask in `2026-09-23.json`.
- VT-25 — `satan-goad/after-midnight-reads-emit-date` (the 23:15 ask answered
  00:05 reads answered from `2026-09-23.json`; no `2026-09-24.json`) and
  `satan-memory-canon/goad-outstanding-after-midnight-sees-the-answer` (at
  00:10 on the 24th: no topic for it, nothing emitted).
- VT-32 — `satan-memory-evidence/goad-slice-is-pure`: `ert-fail` spies on
  `write-region write-file make-directory rename-file copy-file delete-file
  set-file-times satan-db-psql satan-attribute-enqueue
  satan-intervention-record make-process`, each checked `fboundp`;
  `satan-trace-enabled` nil. Mutation-checked: a `make-directory` injected
  into `satan-goad-slice` fails the test.
- VT-33 — `satan-memory-canon/goad-outstanding-*` (5 tests): handles =
  `app:goad` + `satan-goad-subject-topic` of later/enough-seen/enough-unseen/
  untouched at 09:35; answered and expired excluded; all well-formed and
  admitted; `artifact:~/notes/a b/c.org` → admitted topic; slug-nil subject →
  `app:goad` only; a No (`:false`) is answered; no `:goad` or bad `time_now`
  → nothing.
- Mutation checks on the readers: a substring date function fails 9 of 15
  goad tests; accepting any entry fails the drop/five-field tests.
- Canon runs without `satan-goad` loaded (checked in a bare batch Emacs).
- Scratch byte-compile of the touched modules: no new warnings.

**Decisions beyond the sheet:**
- One strict instant parser, canon-owned (`satan-memory-canon-parse-instant`);
  the date function formats its result.
- The queue reader validates `expires_at` too (mirrors `parse_ask`).
- `:record` omitted when absent: `satan-jsonl-prepare` would persist `nil` as
  `{}`.
- T3 path test reuses `satan-custom-test` helpers by `require` rather than
  editing that suite's var lists.

**Findings:**
- ISS-024 overlaps ISS-010.
- Six more hand-rolled lenient JSON-object readers (`ingest-cursor`,
  `sensor-wpm`, `sensor-content`, `sensor-curiosity`, `audit`, `run`) —
  candidates for `satan-jsonl-read-object-file`.
- `satan-memory-evidence--encode-bytes` (legacy `json-encode`) garbles lists
  of plists as alists; size estimate only, affects segment slices too.
- Pre-existing: `satan-memory-evidence--next-day` calls
  `parse-iso8601-time-string` without requiring `parse-time`.
- `satan-memory-canon-parse-instant` is the natural fix for ISS-021's
  GMT-substring `crosses_midnight`.
- Answered is asserted as "`:value` present", not `eq t`: proposed DEC-025
  makes an ask's value an `{option, values}` object, and the rule already
  tests presence only. Regenerated goldens will keep these tests green.
- Proposed DEC-027 (user-approved 2026-09-24, shapes SL-016) makes the
  state root treat an empty `XDG_STATE_HOME` as unset, contradicting OQ-4's
  "out of scope" and ISS-024's "out of scope for SL-016". Not reconciled
  here.

### PHASE-02

- **`goad/backend.py`**
  - `instant()`, the one timestamp parser (offset required); `is_deferred`
    uses it.
  - Queue: `QUEUE_FIELDS`, `Ask` (NamedTuple; `.item` =
    `("ask:<iid>", "SATAN asks", question)`, `.place` = emit date),
    `queue_path(env)` (`GOAD_SATAN_QUEUE`, else `$XDG_STATE_HOME/satan/goad/queue.json`,
    else `~/.local/state/...`; empty = unset), `parse_ask`, `read_queue`
    (never raises).
  - Record: `day_path`/`load_day`/`save_day` over whole documents;
    `save_day` is the one atomic writer and omits an empty `asks`.
    `record_path`/`load`/`save` stay as wrappers; `save` keeps the day's
    `asks`.
  - `Days`: per-exchange documents, each loaded once, saved only if changed.
    `holding_ask` searches `data/*.json` newest first (A6). `place_of` maps an
    item to its record's day/map/key.
  - `pending(items, cycle, asks=())` asks first (two-arg call unchanged);
    `waiting` applies `now < expires_at`; `view_for(item, items, still)`;
    `answer()` is the single answer path; `present` stamps `presented_at` on
    first render only; `run(request, now, data, queue=None)` resolves the
    queue per call. `main()` unchanged.
- **`goad/test_backend.py`** — 65 tests: Characterisation 12 (byte-identical
  to the start-of-phase snapshot), Record 9, Queue 9, Asks 25, Goldens 10.
  `BackendTestCase` points `GOAD_SATAN_QUEUE` at a temp path, so no test can
  read the real queue. Helpers: `write_queue`, `day`, `asks_on`, `exchange`,
  `queued` (delegates to `goldens.ask`), `morning`, `late_night`,
  `option_ids`.
- **`goad/goldens.py`** (new) + `just goldens <dir>` — fixed script (7 asks, 8
  exchanges, microsecond stamps) through `backend.run`; idempotent; refuses to
  write over the live `data/`.
- **`goad/README.md`** — "SATAN asks" (queue path, A3 schema, option ids,
  emit-date filing, A6, A5 pairing, `presented_at` vs Enough, goldens) and a
  rewritten "The record". **`goad/.gitignore`** — `__pycache__/`.
- **`satan/test/goad-fixtures/`** (this repo) — `queue.json`,
  `data/2026-09-23.json`, `README.md` (recipe, provenance, scenario table).

**PHASE-01 departure, now pinned.** PHASE-01's `save` dumps `items` as given,
so ids not in `ITEMS` survive a save (its sheet's A3 assumed they were
dropped). PHASE-02's A10 keeps that and pins it with
`Asks.test_unknown_item_id_survives_save_and_load`.

**Verification** (waived VT rows, verified here):
- VT-2 / ASM-001 — `test_yes_ask_round_trips_through_the_day_file`,
  `test_no_ask_stores_false`: `yes:ask:<iid>` lands in `"asks"` on disk,
  `items` untouched. ASM-001's plan is met; promotion is the orchestrator's.
- VT-16 — `test_nothing_renders_at_or_after_expires_at`,
  `test_expires_at_is_compared_as_an_instant`, Goldens "expired" row.
- VT-22 — the four `presented_at` tests (first stamp, never moved, stamped
  after a respond, not stamped when behind another ask).
- VT-26 — `test_ask_renders_first`.
- VT-27 — `deferred_by` tests: Later on an ask, Later on a checklist item,
  Enough across two emit-date files (unseen ask: `deferred_by: enough`, no
  `presented_at`).
- VT-30 — `test_ask_filed_under_emit_date`,
  `test_presented_ask_still_renders_after_midnight_unstamped`.
- VT-31 — `test_emit_date_is_local`.
- Live smoke evaluate after every save: identical to baseline, wrote nothing.
  Dev `just check` exit 0 (1139/1145, 6 skipped); fixtures not picked up.

**A3/A6/A7 as implemented:**
- A3 — `{"asks": [...]}`, five string fields, offset timestamps, file order.
  Bad entry dropped alone; absent/malformed file = no asks. Reader ignores
  extra fields (writer must emit exactly the five; Goldens checks it).
- **A6 — design gap, flagged.** Late answer: filed under the emit date if the
  ask is still queued (expired or not); else in the newest day file already
  holding `asks[<iid>]`; else dropped. The design requires storing late
  answers (sec-5, F-31) but does not say where to find the emit date once
  SATAN has retired the entry; this is the least-new-state reading.
- A7 — `deferred_by` on checklist items too, one `answer()` path. Yes/No
  replaces a checklist record, merges into an ask's (`presented_at`
  survives).

**Goldens sha256** (corpus commit pending):
- `backend.py` `0f506e01446dee9ad5c5ffb1d4a39ef762db238374f5da9e8938d3698e029965`
- `goldens.py` `595006274b44599e6e55071f3e9282b2d9f954cd8e03bc808d7c1df0602166e4`
- `queue.json` `a38c1b318da4770a0a671ac7147208289bef4a29867e01291abb0e65abc4bc34`
- `data/2026-09-23.json` `06d7c94d76f8eb24695eb4f464b293e2350f106e2c679d0395ef54aabe857653`

Reproducibility: regenerate to scratch, `diff -r -x README.md` — empty.

**Findings:**
- Empty `XDG_STATE_HOME`: backend treats it as unset; `satan-state-root`
  (`satan/satan-custom.el:105`) accepts `""`. Harmless while unset;
  PHASE-03's defcustom inherits it.
- A respond that changes nothing no longer writes a day file (PHASE-01 always
  wrote on respond).
- "still to ask" count now includes pending asks.
- The A6 search reads every day file; a corrupt old one would raise on a late
  answer (PHASE-01 already has this exposure for today's file).
- Later on an ask defers to the next 2h slot, usually past its 60-minute
  window: Later effectively retires the ask.

### PHASE-01

- **`goad/backend.py`** — guarded `main()` under `if __name__ == "__main__"`;
  extracted `run(request, now, data=DATA)` (pure over its args except the
  day-file I/O); `record_path`/`load`/`save` take a `data` param (default
  `DATA`, unchanged call sites); `save` now writes JSON atomically — tmp file
  in the same dir, `os.replace`, `tmp.unlink` on any exception before the
  replace; `record_path` returns `.json`; `tomllib` import and the TOML
  serializer are gone. Two incidental corrections while the import line was
  already touched: dropped the unused `time` import, and the module
  docstring's `data/YYYY-MM-DD.toml` reference is now `.json`.
- **`goad/test_backend.py`** (new) — `class Characterisation` (12 tests):
  `slot_start`/`next_slot` at the three boundaries in the sheet; `pending`
  order = `ITEMS` order; yes/no final across slots; `later` defers for the
  slot only then reappears; `enough` defers every currently-pending item and
  leaves an already-answered item alone; `view` = first pending item with the
  four option ids; `view: null` once nothing is pending; `next_check` = next
  slot; `is_deferred` compares instants across an offset change. `class
  Record` (5 tests): `record_path` suffix; save→load round-trip; `save`
  writes via a `.tmp` in the same dir then `os.replace`s it (asserted via a
  `mock.patch` wrapping the real `os.replace`, and no leftover `.tmp` after);
  a `json.dump` failure mid-write leaves the prior record's bytes untouched
  and no `.tmp` behind; a legacy-TOML day converts to JSON with the same
  items tomllib saw. The legacy fixture is a literal TOML string captured
  from a real day file rather than a read of `goad/data/` — that directory's
  contents are user data, live and mutating, not a stable test fixture.
- **`goad/justfile`** — `check` recipe: `python3 -m unittest -v test_backend`
  from the justfile's directory.
- **`goad/convert_toml_days.py`** (new, one-off) — `convert_one(toml_path,
  data)` reads a day file with `tomllib`, writes it through `backend.save`,
  asserts `backend.load(...) == tomllib items`, then removes the `.toml`;
  `convert_all(data)` runs it over every `*.toml` under `data`, sorted, and
  returns the count. Stays in the code commit for review; deleted in the data
  commit that records its effect (not deleted by this phase — the
  orchestrator commits).
- **`goad/README.md`** — record-format table row is `data/YYYY-MM-DD.json`; a
  `just check` line added to the recipe block; new "The record" section: JSON
  shape example, and the atomic-write rationale (SATAN may read while the
  keeper answers).

**Verification:**
- VT-39 — `class Characterisation` diffed byte-for-byte between the pre-T4
  and post-T4 snapshot: identical. Green both before and after the JSON
  switch (12/12 both times).
- VT-40 — `class Record`'s round-trip, atomic-failure, and legacy-conversion
  tests, plus the real conversion below. 5/5 green.
- EX-1 — `just check` broke on a deliberately wrong `slot_start` assertion:
  `error: recipe check failed on line 8 with exit code 1` (non-zero),
  reverted immediately after.
- EX-4 — `convert_toml_days.py`'s per-file assert (round-trip equality)
  passed for every file, in both the dry run and the real conversion.
- Live — the goad unit's live `data/` dir (7 `.toml` files: 2026-09-14, -15,
  -16, -20, -21 tracked, -22/-23 untracked user answers) was backed up to
  `/tmp/.../scratchpad/goad-data-backup/`, the conversion dry-run against a
  second scratch copy converted 7/7 with every assert passing, then the real
  `data/` dir was converted immediately after (7/7, same asserts). A
  post-conversion diff of each converted `.json` against the backed-up
  `.toml` (via `tomllib`) confirmed all 7 identical. `echo '{"type":
  "evaluate"}' | python3 backend.py` against the real (now-JSON) `data/`
  returned the same pending item, counts, and `next_check` as the pre-switch
  baseline capture (same command, run before T1's edit).

**Findings:** none — no bug surfaced during characterisation; T1's refactor
and T4's format switch were both behaviour-preserving by the tests above.

**Files changed** (corpus repo `~/satan`; code committed as `51a0f36`, the
`data/` conversion left uncommitted on purpose):
`goad/backend.py`, `goad/test_backend.py` (new), `goad/convert_toml_days.py`
(new), `goad/justfile`, `goad/README.md`, `goad/data/*.toml` → `*.json` (7
files converted in place). `goad/goad.service` (deleted) and `motd.txt`
(modified) are the user's pre-existing, unrelated changes — untouched.

### Produced

- **RV-007 round 1 (Claude raiser, 2026-09-23)** — F-1..F-19: 16 verified, F-6/
  F-9/F-10 contested; F-20..F-27 raised (F-20 blocker: goad-minted handles can
  never correlate the ask that creates them). All 11 answered `fixed`, user
  accepted every disposition; design revision 39 (`041ba2f`). Amendments
  appended to `DEC-004`, `DEC-011`, `DEC-012`. Memory
  [[mem.fact.satan.bough-deprecated]].

- **Drift revision, 2026-09-23** (run revision 37, materialised 38), against
  HEAD `1fbdc67` — 55 commits after the RV-007 rebuild. SL-017's record/project
  split (ask records → projects → rewrites queue; `undelivered` verdict on
  failure, writer moved to `satan-intervention.el`); a kind-`"ask"` branch in
  `classify-negative` so non-engagement has a writer (the rebuild named none —
  it fell through to the focus path); quiet window via `satan-tick-quiet-p`
  window arg; SL-018 `defer` gates producer enablement. Amendments appended to
  `DEC-005`, `DEC-006`, `DEC-013`. goad advanced 28 commits (slice 010, exit
  codes) — no ingress or backend-contract change. All ten sections now
  outstanding review; RV-007 awaits its raiser.

- **design.md** — ten sections, 816 lines, materialised from the run's runtime
  sections. Committed.
- **Eleven durable records.** `DEC-004` PERCEIVE route (forced, not a
  tradeoff) · `DEC-005` no new stateful layer · `DEC-006` autonomous producer in
  v1 via tick-pulse · `DEC-007` correlate by construction · `DEC-008` POL-001 No
  branch, no trigger · `DEC-009` day record becomes JSON · `DEC-010` one queue
  file · `DEC-011` answer lands in three roles · `DEC-012` both observer legs ·
  `EVD-002` refusal reaches SATAN through the ledgered tier · `ASM-001`
  backend.py can echo `intervention_id` (unvalidated, with a plan).
- **Selectors corrected** and doctor-clean: dropped `test/**` (never existed)
  and `satan/satan-sensor-*.el` (targets the probe route `DEC-004` did not
  take); added `satan-memory-{canon,evidence}.el`,
  `satan-observer-classify.el`, `satan-tick.el` as design targets.
- **Doctrine pin moved 0.25.3 → 0.44.3** (`flake.lock`). The old pin had no
  `doctrine design` run machine, which is why the research round was
  hand-stamped.
- **Research baseline re-stamped** by the CLI. The hand-stamped one had
  `slice = 16` as an integer and was unparseable to the 0.44.3 verb.

### Learned (durable sinks)

- [[mem.fact.satan.intervention-classification-gate]] — **corrected this
  round.** Three additions: the correlator reads `bundle.json` and never the
  `cue_handles` column, so `:cue-handles` is not the hook it looks like;
  `satan-motive--admitted-namespaces` is a closed allowlist so a new handle
  namespace cannot be cued on; and `:ignored` today means the keeper was
  *absent*, not that they ignored anything.
- **Five research claims corrected at point of use**, each now carried by a
  record rather than by this file: X4's stderr-discard premise (`EVD-002` —
  `call-process` with DESTINATION `t` mixes stderr in); X3's three-way cost
  framing (`DEC-004` — only the evidence route emits handles); delta 9's
  tick-pulse capabilities (`DEC-006` — it cited `self-edit-mech`'s spec);
  delta 8's fixed-TOML premise (`DEC-009` — the format is `backend.py`'s own);
  delta 7's assumption that `save()` is atomic (it uses `write_text`).
- Not yet sunk, still only here — harvest at close if they survive contact
  with implementation:
  - `satan-tick-quiet-hours` is `nil` (`satan/satan-tick.el:24`, *"was '(22 . 7);
    disabled while iterating"*) and the tick fires ~30min around the clock. Safe
    only while every tick surface is ambient.
  - `satan/satan-tools-*.el` does **not** match `satan-tools.el` — the glob
    requires the hyphen. Bit the selector list.

### Open

- **Design locked 2026-09-23** (user: "lock it"). `review-disposed` recorded
  `waived`: RV-006 (the run's pass ledger) empty and stale; the adversarial pass
  ran on RV-007 — three rounds, 36 findings, all answered. **Round-3 answers
  (F-33..F-36) were not independently verified** — RV-007 sits at
  await=raiser; the plan should re-read sec-2 (emit date) and sec-5 (window-end
  judgement) with that in mind. `design-accepted` + adversarial attestations for
  all ten sections.
- **RV-007 rounds 2–3 outcome** (`aa776b6`, `e1cd05a`): asks credit the emit-time
  motive (F-28, DEC-007 amended); a SATAN ask's events file under its local emit
  date, read per ask by percept and observer (F-29, F-33, F-34; DEC-009
  amended; backend change 6); ask exempt from `crosses_midnight`;
  `satan-goad-quiet-hours` default `(22 . 9)`; `presented_at` first render only
  (F-30); the record is judged as it stood at window end, so a late answer
  classifies `untouched` (F-31, F-35 — user choice); bulk `Enough` stays
  `:ignored :medium dismissed` (user choice).
- **[[ISS-021]]** (new): the observer's `crosses_midnight` guard slices dates
  from GMT-rendered `ts`, tripping for every intervention emitted 00:00–09:59
  local. Pre-existing, all kinds; SL-016 avoids it for asks by construction.
- ~~Unverified: whether goad re-evaluates when an `engaged` exchange ends~~ —
  **resolved at plan**: yes, the `engaged` exchange is itself the evaluation
  (plan.md § Resolved during planning).
- **Corpus working tree is dirty with the user's changes** (2026-09-23:
  `goad/data/*` modified/untracked, `goad/goad.service` deleted, `motd.txt`).
  PHASE-01 must not sweep them into its commits.
- **Risks carried** — design sec-9's table is current.
- **[[IMP-025]]** (new, 2026-09-23): SATAN perceives no checklist answers
  and no past goad days — the design narrowed scope item 1 to outstanding
  asks. Two options backlogged (`goad_read` tool / compact percept), decision
  deferred. Reconcile the scope document's PERCEIVE item against it at close.
- **Revision candidates for `/reconcile` at close** (none caused by this slice):
  POL-001's seat rationale does not contemplate a non-editor human surface;
  `.doctrine/state/boot.md` "not written yet" for the protocol tech spec and
  authority ledger; RFC-017 D1 rows G1/G2 "not written".
- **Scope document deliberately uncorrected** — per-slice artefacts are
  `/reconcile`'s to write at close.

### Tooling defects hit (doctrine 0.44.3, not SATAN)

- The design runbook's `explore.research` check shells out to a top-level
  `doctrine verify`, which does not exist — the step cannot be *attested*
  however completely it is performed. Discharged `skipped` with the substance
  recorded.
- `review.passes` carries the literal reason `probe`: a placeholder submitted
  while probing whether the step was gated. It discharged rather than refusing,
  and re-discharge is refused because the runbook is complete. The correction
  is recorded in the review-policy acceptance basis.
- `adversarial-then-human` and `human-then-adversarial` are 22 bytes against a
  16-byte payload-label bound, so neither two-lane policy is submittable. Only
  `human-only` and `adversarial-only` are reachable.
- `design materialise` orders sections **lexically**, so `sec-10` renders
  second. Section bodies are assigned to lexical slots as a workaround, so the
  ids are slots rather than reading positions. Sections cannot be pruned
  (`lifecycle` is inert on a `sec-` subject), so padded ids would have left ten
  orphans.
