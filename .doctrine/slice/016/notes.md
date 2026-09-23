# Notes SL-016: goad as SATAN's elicitation surface

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest

**fresh-as-of:** PHASE-11 implemented, 2026-09-24 (uncommitted; orchestrator
commits). SATAN's goad readers now carry an ask's answer form on its queue
entry, read the ask's answer as goad's `{option, values}` object without
interpreting it, and truncate string values over 1 KiB in the `:goad`
evidence slice (`satan-goad-truncate-value`, reused by PHASE-09's trace). No
boolean ask fixture remains. PHASE-10 (corpus answer forms, goldens with a
`form` ask) landed as dev `a6eca02`, corpus `ab00411`. Next: `/phase-plan` the
next phase.

### Design revision — answer forms (2026-09-24)

User-approved. SATAN's questions can carry a goad-protocol answer form, not
Yes / No only. Decisions DEC-024 (the form, stored on the intervention record
via migration 0008), DEC-025 (`opt:` option ids; the answer is an
`{option, values}` object), DEC-026 (one validator, at emit), DEC-027 (empty
`XDG_STATE_HOME`, with one shared helper) and DEC-028 (intervention rows read as
JSON, plus an open-asks query). Adversarial review RV-015 raised 10 findings;
all were verified and integrated.

**Consequence for the plan:** PHASE-02 (corpus `e3ac87c`) and PHASE-03
(`d036427`) are built on boolean answers and `yes:ask:` ids. Rework phases are
appended; phase ids never change. ISS-024 duplicates ISS-010, and DEC-027 fixes
both. `goad/convert_toml_days.py` is still tracked, although corpus `e0a3c9b`'s
message says it was retired.

**A further review pass would probe:**
- whether a form of goad kinds can express what SATAN actually wants to ask, by
  drafting 3–4 real questions against the tool description;
- whether the JSON row read keeps `satan-intervention-lookup`/`-recent`
  callers' plist shapes identical (the same pipe-split pattern elsewhere is
  ISS-025);
- how `enough:` interacts with a form whose option id happens to be `enough`.
  That is harmless under `opt:` namespacing, but should be pinned by a test.

None of these blocks the lock. They are verification or plan-time checks.

### PHASE-04

Shared seams: the undelivered writer moved, `satan-tick-quiet-p` grew a
window argument, four goad defcustoms, and the DEC-027 state-home helper.
Refactor and plumbing only — no kind's behaviour changed. Model: sonnet
(the orchestrator's rationale — mechanical plumbing with a fully-resolved
design, checked by existing tests plus VT-34/35/50).

**What moved and where (T3, design sec-3):**
`satan-tools-notify--mark-undelivered` → `satan-intervention-mark-undelivered`
`(ctx payload err)`, in `satan-intervention.el` after
`satan-intervention-project-with-verdict`. Its two helpers moved with it
(A4): `satan-tools-notify--project` → `satan-intervention-try-project`
(public — PHASE-06's ask handler needs it too), `satan-tools-notify--failed`
→ `satan-intervention--failed` (private). `notify_send` calls the three new
names; nothing else in `satan-tools-notify.el` changed. Moving into
`satan-intervention.el` rather than requiring `satan-tools-notify` back
avoids the require cycle (notify already requires intervention).
`satan/test/satan-tools-notify-test.el` is byte-for-byte unchanged
(`git diff --stat` empty) — the suite drives `notify_send` end to end and
never names the private symbols, so STOP-1 never triggered.

**Quiet window (T2, design sec-7):** `satan-tick-quiet-p` is now
`(&optional time window)`, WINDOW defaulting to `satan-tick-quiet-hours`.
No-arg behaviour is unchanged (EX-2); the three existing callers
(`satan-tick.el:129`, `satan-broker.el:452`'s `--quiet-p`,
`satan-sensor-alerts.el:331`) pass no window and are untouched. The two
`declare-function` arglists (`satan-broker.el`, `satan-sensor-alerts.el`)
now read `(&optional time window)`. `satan-tick-quiet-hours` itself stays
`nil` — global quiet hours remain out of scope.

**Goad defcustoms (T4, `satan-custom.el`'s goad block):**
`satan-goad-enabled` (nil — "the governed kill switch", design sec-7 ledger
row 6), `satan-goad-quiet-hours` (`(22 . 9)`, same `:type` as
`satan-tick-quiet-hours` — no ask 22:00–08:59), `satan-goad-emit-program`
(`"goad-emit"`, resolved on `PATH`) and `satan-goad-emit-timeout` (`10`,
seconds — `satan-trace-call`'s `TIMEOUT-SECS` unit, read from its
signature). The program/timeout defaults are OQ-2's proposal (A5),
unopposed by the orchestrator; both cited in their docstrings against
design sec-5 "The timeout is mandatory".

**OQ-1 resolution (T5, `goad-ask` token):** no code this phase. Capability
tokens are bare symbols compared against a tool spec's `:capability`
(`satan-tool--capability-denied-p`, `satan-tools.el:143-150`) — there is
no registry to seed. The token comes into existence when PHASE-06
registers `goad_ask` with `:capability 'goad-ask` and adds it to
`tick-pulse`'s `:capabilities`. Confirmed by the orchestrator's ruling on
OQ-1.

**State-home helper (T1, DEC-027 amended RV-015 F-9):** `satan-state-home`
in `satan-custom.el`, defined before `satan-state-root` — a pure function
of the environment (no `satan-*` state, no new require; STOP-2 never
triggered): `XDG_STATE_HOME` when non-empty (`expand-file-name`d), else
`~/.local/state`. All three readers now go through it:
`satan-state-root`'s default, `satan-sensor-curiosity-segments-dir`
(`satan-sensor-curiosity.el`, already required `satan-custom`) and
`satan-tools-content-dir` (`satan-tools-content.el`, gained
`(require 'satan-custom)`). The helper reads the environment directly, not
`satan-state-root`'s value, so the pre-existing
`satan-custom-behaviour-class-is-not-a-satan-root` test (rebinding
`satan-state-root`/`satan-corpus-root` and asserting these two dirs don't
follow either) needed no change — they never coupled to the root variable.
`satan-goad-queue-file` still derives from `satan-state-root` at load
(unchanged), so its own test has to rebind `satan-state-root` to its
re-evaluated default before re-evaluating the queue file's default (R1) —
skipping that step tests the developer's actual environment, not the fixed
one. The `:91-99` comment on the falls-back-below-home test was rewritten:
unset was never the divergent case; it was always empty, and empty is now
unset too (DEC-027), not the residual defect ISS-010 named.

**T6 — ISS-024 closed, ISS-010 untouched:**
```
doctrine backlog edit ISS-024 --status resolved --resolution fixed
doctrine link ISS-024 references --role concerns --descriptor "fixed by DEC-027 (SL-016 PHASE-04)" DEC-027
```
`resolved`/`fixed` matches house convention — `doctrine backlog list --all
--status resolved` carries nine issues/improvements/chores this way;
`closed` has exactly one precedent (a chore). The sheet's optional
"consider a dup-label link to ISS-010" was skipped: no `duplicate` relation
label exists in the schema (the closest, `references --role concerns`, was
already spent on DEC-027), and OQ-3's ruling was explicit — "do not touch
ISS-010" — so no edge touches it in either direction.
`doctrine backlog inspect ISS-010` confirms it is unchanged (`open`, no
relationships).

**Verify (T7):**
- `just lint`: clean (paren-balance only, per `mem.fact.satan.green-is-not-green`).
- Scratch byte-compile of the eight touched modules, before (HEAD's copies,
  compiled from a scratch dir) and after: identical four pre-existing
  warnings in both (`satan--root`/`satan-notify-intervention-window-minutes`
  docstring width, two unused-lexical-variable warnings in
  `satan-tools-content.el` unrelated to this phase's edit). No new warning.
  `.elc` files deleted after (`find satan -name '*.elc' -delete`); confirmed
  none remain (`git status --short satan/` shows no `.elc`).
- `just check`, serially, `SATAN_DB_HOST=127.0.0.1`: **1199 ran / 1193
  expected / 0 unexpected / 6 skipped**, same six names as the T0 baseline
  (`satan-integration/morning-end-to-end`,
  `satan-memory-grammar/db-sync-{aliases,current-version,default-weights}`,
  `satan-patch-listener/integration-fires-from-real-pg`,
  `satan-patch-runner/real-pi-edits-and-commits`). T0 baseline was 1186/1180/0/6
  with the identical skip set; the 13 new tests are all this phase's (4
  `satan-custom-test.el`, 3 `satan-tick-test.el`, 4
  `satan-intervention-test.el` DB-backed `mark-undelivered` cases — the
  fourth is real-DB, confirmed it *ran* rather than skipped by executing it
  with `SATAN_DB_HOST` set before the full run, per R2).
- EX-1: `rg -n 'defun satan-tools-notify--(mark-undelivered|project|failed)' satan`
  and `rg -n 'satan-tools-notify--mark-undelivered' satan` both zero hits.
- EX-4: `rg -n 'getenv "XDG_STATE_HOME"' satan` → one hit, `satan-custom.el`'s
  `satan-state-home`.

**Deviation from strict red-first order:** T1's helper (`satan-state-home`)
and the `satan-state-root`/curiosity/content wiring were written before
their new tests, rather than after watching the tests fail against the old
code. The new tests were confirmed failing-for-the-right-reason cannot be
re-created without reverting (never used, per the no-`git checkout`
constraint), so this is reported as a deviation rather than demonstrated.
T2, T3 and T4 all followed strict red→green (each new test was run and
shown failing — `wrong-number-of-arguments` / `void-function` /
`void-variable` — before its implementation landed).

**Files changed:** `satan/satan-custom.el`, `satan/satan-tick.el`,
`satan/satan-intervention.el`, `satan/satan-tools-notify.el`,
`satan/satan-sensor-curiosity.el`, `satan/satan-tools-content.el`,
`satan/satan-broker.el`, `satan/satan-sensor-alerts.el`,
`satan/test/satan-custom-test.el`, `satan/test/satan-tick-test.el`,
`satan/test/satan-intervention-test.el`,
`.doctrine/backlog/issue/024/backlog-024.toml` (via CLI, T6). Next:
`/phase-plan` PHASE-12.

**Review fix — explicit nil WINDOW (post-PHASE-06 defect):** the T2 quiet
window predicate defaulted an explicit `nil` WINDOW back to the global
`satan-tick-quiet-hours`, contradicting its own docstring and breaking a
user-disabled (`nil`) `satan-goad-quiet-hours` for PHASE-06's ask path —
it would inherit the tick window instead of never being quiet.
`satan-tick-quiet-p` is now `cl-defun` with a supplied-p parameter
(`(&optional time (window nil window-given))`): an *omitted* WINDOW still
defaults to `satan-tick-quiet-hours` (no-arg/one-arg callers unchanged,
EX-2), but an *explicit* WINDOW — including nil — is used as given.
New test `satan-tick/quiet-p-explicit-nil-window-never-quiet`
(`satan/test/satan-tick-test.el`), red→green. `declare-function` arglists
in `satan-broker.el`/`satan-sensor-alerts.el` unchanged (still
`(&optional time window)` — a correct description of the calling
convention). Verified: scratch byte-compile of `satan-tick.el`,
`satan-broker.el`, `satan-sensor-alerts.el` quiet, `.elc` deleted after;
`just check` serially with `SATAN_DB_HOST=127.0.0.1`: 1200/1194/0/6, same
six skips as before.

### PHASE-11

PERCEIVE rework of PHASE-03 onto the revised record (DEC-024 the form,
DEC-025 the answer object). Dev only; the corpus was not touched
(`git -C ~/satan status --short` before and after: the user's own
` D goad/goad.service`, ` M motd.txt`, nothing else).

**Files:**
- `satan/satan-goad.el` — `satan-goad--form-p` (mirrors backend `is_form`);
  `satan-goad--queue-entry` appends `:form` verbatim when present and
  well-formed, returns nil when present and malformed; truncation:
  `satan-goad-truncate-bytes` (1024), `satan-goad-truncate-marker`
  (`"…[truncated from %d bytes]"`), `satan-goad--utf8-bytes`,
  `satan-goad--prefix-within`, `satan-goad--truncate-string`, public
  `satan-goad-truncate-value`; `satan-goad--evidence-record` maps each slice
  record's `:value` through it. Header comment and docstrings updated.
- `satan/satan-memory-canon.el` — docstring only
  (`satan-memory-canon--goad-outstanding-p`: the stale "a No is `:false`" is
  now "no `:value` … an answer is DEC-025's `{option, values}`, never
  inspected here"). No code change; purity lint green.
- `satan/test/satan-goad-fixture.el` — golden direct-decode accessors
  (`satan-goad-fixture-day`, `-golden-entry`, `-golden-record`), `-keys`,
  `-answer`, `-iids`; `-with-golden-copy` (built on `-with-tmp`) and
  `-replace` (errors when FROM is absent). `-with-tmp` made hygienic: it
  now uses an uninterned symbol for the dir, so a `_dir` binding is
  genuinely unused (cleared 5 pre-existing + 2 new byte-compile warnings).
- `satan/test/satan-goad-test.el` — new/updated tests below; the malformed
  form cases build their entry from `satan-goad-fixture-ask` plus raw form
  JSON (`satan-goad-test--ask-json-with-form`).
- `satan/test/satan-memory-canon-test.el` — boolean
  `goad-outstanding-a-no-answer-is-an-answer` replaced by
  `goad-outstanding-a-form-answer-is-an-answer`.

**A1–A6 as landed:**
- A1 — `:form` rides the entry as decoded, after the five fields; absent
  (no key) on a formless entry.
- A2 (orchestrator-approved) — a `form` key present but malformed drops the
  whole entry, `null`/`[]`/`{}` included (detected with `plist-member`). The
  ordering matters: `plist-member` on a non-list signals, so the entry's
  plist check runs first (caught by the existing
  `read-queue-drops-a-bad-entry-alone`, whose queue holds a bare `7`). R3
  holds: `[false, true]` decodes to `(:false t)` and is dropped, because
  each *option* must be a plist with string `:id`/`:label`.
- A3 — bytes are UTF-8 (`encode-coding-string … 'utf-8`), not
  `string-bytes` of the internal form; marker counted against the cap; cut
  on a character boundary; idempotent.
- A4 — structural walk: string → maybe cut; cons → `mapcar` itself; else
  unchanged. Fresh lists, input never mutated.
- A5 — applied to the record's `:value` only, in `satan-goad-slice`;
  `satan-goad-read-record` stays whole.
- A6 (orchestrator-approved) — VT-55's long string is one golden value
  (`"steady after lunch"`) replaced in a temp copy of the goldens.

**VT evidence** (`satan/test/satan-goad-test.el`):
- VT-54 — `satan-goad/queue-entry-keeps-form`,
  `satan-goad/answer-is-option-and-values`; also
  `read-queue-reads-the-goldens-in-file-order` (keys = five + `:form` iff the
  golden entry has one), `read-queue-drops-a-malformed-form` (13 bad forms,
  each between two good entries; a well-formed one-option form kept),
  `read-record-matches-the-scenario-table` (now includes `form`).
- VT-55 — `satan-goad-truncate-value/{keeps-strings-within-the-cap,
  cuts-a-long-string-to-the-cap, cuts-on-a-character-boundary, is-idempotent,
  passes-non-strings-unchanged, walks-a-value-without-mutating-it}`,
  `satan-goad/long-string-truncated`. Short values passing unchanged over the
  goldens is pinned by the existing `slice-pairs-every-entry-with-its-record`
  (slice `:record` `equal` to `satan-goad-read-record`'s).
- T6 wire — `satan-goad/slice-survives-json`: persists the golden slice
  through the real writer `satan-percept-persist` and reads it back `equal`
  (no existing `:goad` wire test to extend).
- VT-32 — `satan-memory-evidence/goad-slice-is-pure` untouched, green.

**EX-1 sweep:** `rg -n '\\"value\\": *(true|false)|:value (t|:false)' satan/test`
— before T3: 2 hits (`satan-goad-test.el:175`, `satan-memory-canon-test.el:429`);
after: no output, exit 1. A wider `rg -n '\\"value\\"|:value '` over the goad,
canon and evidence suites and the fixture finds only the key-list assertion
`'(:presented_at :value :at)`.

**Counts** (dev `just check`, serial, `SATAN_DB_HOST` from the justfile):
- T0: 1175 ran / 1169 expected / 0 unexpected / 6 skipped.
- T7: 1186 ran / 1180 expected / 0 unexpected / 6 skipped (+11: goad
  suite 38 → 49; canon test replaced one for one). Harness 54 OK.
- Skip set, both runs: `satan-integration/morning-end-to-end`,
  `satan-memory-grammar/db-sync-{aliases,current-version,default-weights}`,
  `satan-patch-listener/integration-fires-from-real-pg`,
  `satan-patch-runner/real-pi-edits-and-commits`.
- `just lint` clean. Scratch byte-compile of `satan-goad.el`,
  `satan-memory-canon.el`, `satan-goad-fixture.el`, `satan-goad-test.el`,
  `satan-memory-canon-test.el`, `satan-memory-evidence-test.el`: HEAD's four
  gave 5 warnings (all `_dir` not left unused); now 0 in touched files. One
  pre-existing, untouched: `satan-memory-evidence-test.el:471` unused
  `git-start-iso`.

**R1 observed:** the golden form serialises to 330 bytes; the whole golden
`:goad` slice to 3068 bytes.

**Deviations from the sheet:**
- `read-record-without-a-usable-day-file-is-nil`'s positive checks run over
  `-with-goldens`, not `-with-golden-copy`: they alter nothing, so a copy
  adds nothing.
- T5's third bullet (over unmodified goldens, slice record `equal` to
  `satan-goad-read-record`'s) was already pinned by
  `slice-pairs-every-entry-with-its-record`; not duplicated.
- T6 goes through `satan-percept-persist` rather than restating
  `json-serialize (satan-jsonl-prepare …)` — the persist path is exactly that
  call, and testing it pins the real wire.
- Added fixture helpers beyond the sheet (`-golden-entry`, `-golden-record`,
  `-keys`, `-answer`, `-iids`, `-day`) and the `-with-tmp` hygiene fix — per
  T7's "belongs in the fixture as one helper".

**Findings:** none requiring action here. `satan-jsonl--plist-p` is used
cross-module as a private (`--`) function by `satan-goad.el` — a candidate
for promotion to public if a third consumer appears.

### PHASE-10

Corpus rework of PHASE-02, landing the answer form (DEC-024/025) into
`goad/backend.py`. Change 7 of design sec-3.

**Files:**
- Corpus (`~/satan`): `goad/backend.py` (`Ask.form`, `is_form`, `find_ask`,
  `ask_options`, `DEFAULT_FORM`, `parse_ask`/`view_for`/`answer` reworked;
  `place_of` reuses `find_ask`), `goad/test_backend.py` (65 → 77: T1 retires
  one, T2–T6 add 13), `goad/goldens.py` (`ask()` gains `form=`, `option()`
  rebuilt around `opt:`, a `form` ask added between `untouched` and
  `midnight`), `goad/README.md` (schema, option ids, the record's `value`
  row, goldens paragraph), `goad/convert_toml_days.py` **deleted**.
- Dev (`~/dev/satan`): `satan/test/goad-fixtures/{queue.json,
  data/2026-09-23.json,README.md}` regenerated/updated;
  `satan/test/satan-goad-fixture.el` (`form` entry added to
  `satan-goad-fixture-ids`, between `untouched` and `midnight`);
  `satan/test/satan-goad-test.el` and `satan-memory-evidence-test.el`
  (three literal `7`s → `(length satan-goad-fixture-ids)`); this file.

**A1–A6 as landed:**
- A1 — `response.get("values")` is `None` for both an absent key and a JSON
  `null` (R-51); `answer()` stores `{}` in both cases, never `or {}` (a
  falsy-but-present value, e.g. `0` or `false`, is kept). Pinned by
  `test_opt_answer_without_values_stores_empty_values`.
- A2 — `parse_ask` drops the whole entry when `"form"` is a key and
  `is_form()` is false, `null` included — it does not fall back to "absent".
  Pinned by `test_malformed_form_dropped`'s `"not a list: null"` case.
- A3 — `ask_options` builds each rendered option from exactly `id` (rewritten
  to `opt:…`), `label`, and `fields` when present and not `null`; no other
  key on a queued option is forwarded.
- A4 — `answer()` guards `opt:` to ask item ids and `yes:`/`no:` to checklist
  ids; any mismatch returns before any write. Pinned by
  `test_yes_verb_on_an_ask_writes_nothing` and
  `test_opt_verb_on_a_checklist_id_writes_nothing`.
- A5 — the backend never checks that a chosen option belongs to the ask's
  form; unchanged from the design.
- A6 — `QUEUE_FIELDS` stays the five required string fields; `form` is
  checked separately inside `parse_ask`. `test_fields_are_the_five_of_a3`
  still holds.

**VT-45/46/49/53 evidence** (waived rows — verified by `~/satan/goad just
check`, not the dev suite):
- VT-45 — `test_form_ask_renders_its_options_and_fields`,
  `test_form_answer_stores_option_and_values_verbatim`.
- VT-46 — `test_default_form_renders_yes_no_as_opt_ids`,
  `test_default_form_answer_stores_option_and_values`.
- VT-49 — `test_malformed_form_dropped` (ten `subTest` cases: non-list
  values, `null`, a non-object option, a non-string/missing `id` or `label`,
  and a good option followed by a bad one — each beside a good entry that
  still renders).
- VT-53 — `goldens.py` contains `form` and `opt:`; covered by
  `Goldens.test_queue_entries_carry_exactly_the_queue_fields`,
  `test_each_outcome_leaves_its_record` (now includes `form`),
  `test_unanswered_asks_have_no_value_key`.

**Counts:**
- Corpus `just check`: T0 baseline 65 OK → final 77 OK, 0 failures, clean
  output.
- Dev `just check`: T0 1175 ran / 1169 expected / 0 unexpected / 6 skipped;
  T8 (after fixture regen + the three sanctioned edits) same counts. STOP-3
  not triggered — no reader needed to change.
- T0 live snapshot (`backend.run` against a copy of the live `goad/data`,
  fixed `now`, empty queue): byte-identical after every `backend.py` save
  (T2–T5) and at close-out.

**VT-40 retirement (T1):** the "a converted legacy TOML day loads equal"
clause of PHASE-01's VT-40 is retired along with `goad/convert_toml_days.py`
and the `tomllib` keyword — `rg -n 'convert_toml|tomllib' ~/satan/goad`
returns nothing. `Record.test_legacy_toml_day_loads_equal` removed with it.

**`PENDING-corpus-commit` marker:** `satan/test/goad-fixtures/README.md`'s
provenance table carries the literal `PENDING-corpus-commit` in the corpus
commit cell. The orchestrator commits `~/satan` first, then substitutes the
resulting sha — the recorded shas
(`backend.py` `3359a75…`, `goldens.py` `3ef31fa…`, `queue.json` `3207449…`,
`data/2026-09-23.json` `627277d…`) are valid only against the worker's bytes,
unchanged since.

**Deviations from the sheet:** none. A6's suggested `OPTIONAL_QUEUE_FIELDS`
constant was not introduced — `parse_ask` checks `form` inline, which the
sheet allowed ("or inside `parse_ask`").

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
