# Notes SL-016: goad as SATAN's elicitation surface

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest

**fresh-as-of:** PHASE-01 implemented, 2026-09-23 — `goad/backend.py` has a
test harness (17 tests, stdlib `unittest`, `just check`), the day record is
JSON (DEC-009), and the corpus's `data/*.toml` files are converted in place.
Not yet committed (orchestrator's to commit). Next: `/execute PHASE-02` (or
audit if PHASE-01 is the last phase touched before a checkpoint).

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

**Files changed** (corpus repo `~/satan`, none staged/committed):
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
