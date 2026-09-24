# Review RV-018 — reconciliation of SL-016

Adversarial-review ledger (ADR-007). Structured findings live in the sister
ledger toml; this prose companion carries the reviewer's framing.

## Brief

**Mode:** conformance, self-audit (raiser and responder driven with `--as`).
**Surface reviewed:** main tree at `bfee32b` (solo phases, no dispatch
candidate); corpus `~/satan` at its current head.

Lines of attack:

1. **Closed loop (design sec-8 items 1–25, 45–52).** Every VT row passes
   `doctrine slice verify-vt 16`, or is waived with a recorded out-of-repo
   verifier. Live evidence: VH-1 passed (intervention
   `20260924T171554-tick-pulse-b52b8e.iv001` matured `:worked`); VH-2 waived
   by the user, with VT-3 standing in.
2. **Suite honesty** (design "Two traps"). Run `SATAN_DB_HOST=127.0.0.1 just
   check` against the test DB, not a skip-everything checkout, and run
   `~/satan/goad just check` for the backend.
3. **Path conformance.** Compare `doctrine slice conformance 16` with the
   files SL-016 commits actually touched. Look for new modules and seams
   that design sec-9 does not name.
4. **Recorded truth versus shipped truth.** Check the changes made after the
   design locked: RV-017 F-6 (the classification-time queue rewrite was
   deleted, so VT-8 is withdrawn), the pre-0008 failure scope, and the
   scope document's PERCEIVE item against IMP-025.
5. **Governance posture.** Elicit-only: no authority item and no ADR-017
   ledger row. The POL-001 No-branch tenancy (DEC-008). The revision
   candidates that design sec-8 deferred to reconcile.
6. **Ledger hygiene.** Earlier review ledgers on this slice must be terminal
   (RV-015, RV-016, RV-017).

Invariants held: no goad host change, no new stateful layer, delivery failure
never recorded as silence, and the perceive leg stays pure (ADR-001).

## Synthesis

**Closure story.** SL-016 delivers the closed loop its design locked. SATAN
emits kind `"ask"` through `goad_ask` on tick-pulse, correlated only to a
subject it already perceives. It records, projects, then rewrites the queue
file that `backend.py` merges into `pending()`, with no goad host change. It
rings the doorbell as a hint. It reads the answer back as an `{option,
values}` record keyed by the option id, and credits the emit-time motive.
Asks carry their own answer forms (DEC-024..028), validated at emit.
Delivery failure is never recorded as silence: it records `undelivered`, or
`:unknown :high` when the ask was never presented. Suppression and a matured
`:no_correlation` reach satan-attrd as attributes. The keystone that RFC-016
D3 names, silence classified as `:ignored`, is tested without a compositor or
panopticon.

Evidence:
- `SATAN_DB_HOST=127.0.0.1 just check`: 1293 tests, 0 unexpected, 6 known
  skips. Before and after the audit's test fix.
- `~/satan/goad just check`: 77 tests.
- `doctrine slice verify-vt 16`: exit 0. Every row passes or is waived with a
  recorded out-of-repo verifier; VT-8 is waived because it was withdrawn.
- VH-1 passed live: intervention `20260924T171554-tick-pulse-b52b8e.iv001`
  matured `worked` / `medium` / `mature` with predicate `goad_answer`, and
  the trace carried the question and value. VH-2 was waived by the keeper,
  with VT-3 standing in over goldens that VT-43 checks against the real
  backend.

The findings are about recorded truth, not code defects:

- **F-1 (major, fixed in audit):** RV-015 had been left active with ten
  answered findings. It is now verified and done.
- **F-2, F-4, F-7:** design and scope prose lag the shipped slice (the
  withdrawn classification-time rewrite, the pre-0008 blast radius, the
  scope document).
- **F-3 (fixed in audit):** VT-8 carries a waiver annotation, so the VT gate
  is clean.
- **F-5 and F-6:** selector-registry bookkeeping. The two new modules were
  never declared.
- **F-8 and F-9:** the governance questions design sec-8 deferred to
  reconcile.
- **F-10:** RV-017's leftover nits. One is fixed, two are tolerated, and one
  is filed as ISS-027.

**Standing risks.**

- Open asks are unbounded (IMP-027, deferred by the keeper to live use). A
  chatty SATAN could starve the checklist.
- The autonomous producer depends on a live credential session (SL-018
  DEC-022). After an Emacs restart, unattended runs defer, and matured asks
  wait for the next spawned run.
- SATAN perceives this repo's commit subjects, and rollout commits steered
  its VH-2 judgement. Operator commits are part of its percept.
- `satan-goad.el` couples the read side to the queue writer (IMP-026).
- The drift check on SATAN's goldens now lives in the corpus (IMP-028).
- Satan-attrd must be running before goad is enabled, or
  `ask_suppressed`/`ask_uncorrelated` rows are dropped.
- Pre-existing and not caused by this slice: ISS-021 (`crosses_midnight` on
  UTC dates; asks are exempt), ISS-001 (evidence cap), ISS-013 (concurrent
  test DBs).

**Tradeoffs consciously accepted.**
- The classification-time queue rewrite was dropped (keeper, RV-017 F-6),
  and `expires_at` alone retires stale entries.
- Unbounded asks (IMP-027).
- VH-2 waived in favour of VT-3.
- RV-017 F-3: migration 0008 ordering is enforced by the runbook, not the
  code.
- Interleaved phase boundaries (F-6).

## Reconciliation Brief

### Per-slice (direct edit)

- **RV-018 F-2 — design.md sec-8 "Done is a closed loop", item 8.** Replace
  "and retires an entry at classification" with a note that VT-8 was
  withdrawn (RV-017 F-6, `5c035b8`): the queue regenerates only at emit, and
  `expires_at` (item 16) keeps a matured entry off screen.
- **RV-018 F-2 — design.md sec-3 "The queue is a projection".** One rewrite
  trigger (emit), not two. Remove the classification-time trigger from the
  prose and any diagram.
- **RV-018 F-4 — design.md sec-7 "No new stateful layer" (~l.864) and the
  sec-9 risk-table row "Migration `0008` must be applied…".** Before 0008,
  every ask (form or not) takes the undelivered verdict, because the emit-time
  queue rewrite reads `satan-intervention-open-asks`, which selects
  `form_json`. Every other kind is unaffected.
- **RV-018 F-5 — selector registry (load-bearing).** `doctrine slice selector
  add` design-target for: `satan/satan-goad.el`, `satan/satan-tools-goad.el`,
  `satan/satan-broker.el`, `satan/satan-run.el`, `satan/satan-mcp.el`,
  `satan/satan-motive.el`, `satan/satan-jsonl.el`,
  `satan/satan-sensor-alerts.el`, `satan/satan.el`,
  `satan/satan-tools-notify.el`, `satan/satan-tools.el` (re-intent from
  scope-relevant), `dev/satan-test.el`, `docs/attributes/design-contract.md`,
  `docs/attributes/wiring-status.md`, and the SL-016 test surface
  (`satan/test/goad-fixtures/**`, `satan/test/satan-goad*.el`,
  `satan/test/satan-tools-goad-test.el`, plus the modified test files listed
  in `slice conformance 16`). Then re-run `doctrine slice conformance 16`; the
  residue should be only F-6's tolerated paths. **Mirror:** add
  `satan-goad.el` and `satan-tools-goad.el` (with their roles) to design
  sec-9's affected-surface table.
- **RV-018 F-7 — slice-016.md.**
  - Scope item 1: PERCEIVE is narrowed to outstanding asks and their answers,
    and checklist history is IMP-025.
  - R1 and verification item 5: moot (no probe, no watermark; design sec-8
    item 10).
  - A1: falsified, see DEC-008.
  - OQ-1..4: resolved by DEC-004/010/011/012.
  - D1: superseded by SL-018's credential gate (ISS-012 closed).
- **RV-018 F-9 — design.md sec-8 "No authority item, no ledger row".**
  Replace the open question ("Whether a second caller … is a question for
  /reconcile at close") with the decision: no REV, because the writer was
  moved unchanged and a second caller adds no write path.

### Governance/spec (REV)

- **RV-018 F-8 — POL-001 seat clause.** REV modify: the thin-shell seat
  rationale ("the human's editing surface is where their output lands") does
  not contemplate a non-editor human surface. Either widen it or state that
  such surfaces' shells are No-branch tenants (as DEC-008 records for goad).
  The wording is the keeper's call.

### For /close (not reconcile writes)

- Stale "Neither is written yet" in `.doctrine/governance.md:15` is owned by
  CHR-008. RFC-017 D1 G1/G2 "not written" is an RFC (evidence tier), so
  CHR-008 or the RFC's owner handles it. This slice does neither.
- Backlog born or touched by this slice stays open: IMP-020, IMP-025,
  IMP-026, IMP-027, IMP-028, ISS-027. ISS-024 and ISS-026 are already
  resolved.
- The handover (`.doctrine/slice/016/handover.md`) is stale (it predates the
  PHASE-08 flip). Retire it at close.

## Reconciliation Outcome

Keeper agreement: "agreed, A" (2026-09-24).

### Direct edits applied
- **design.md sec-3, "The queue is a projection"** (RV-018 F-2).
  - One rewrite trigger, at emit. The paragraph records that RV-007 F-11
    added the classification-time rewrite and RV-017 F-6 removed it.
    `expires_at` makes that removal safe, and VT-8 is withdrawn.
  - "Both rewrite triggers run" becomes "The rewrite runs".
- **design.md sec-7 and the sec-9 risk row for migration 0008** (F-4).
  Before 0008, every ask takes the undelivered verdict.
- **design.md sec-8, item 8** (F-2). The retirement half is struck and noted
  as withdrawn.
- **design.md sec-8, "No authority item"** (F-9). The open question is
  replaced by the decision: no ledger note.
- **design.md sec-9, affected surface** (F-5).
  - Added `satan-goad.el` and `satan-tools-goad.el`.
  - Added an "also touched in delivery" line.
  - Dropped the classification rewrite from the `satan-observer.el` row.
- **Selector registry** (F-5). Added design-target selectors for both goad
  modules and the ten touched seam and doc files, re-intented
  `satan-tools.el`, and re-intented `satan/test/**` to design-target.
  `slice conformance 16`: 46 conformant, 0 undelivered. Undeclared, apart
  from `.doctrine/**` bookkeeping:
  - `.envrc`, `flake.nix`, `skills-lock.json`
  - the three restored migrations
  - `docs/governance.md` and `satan/satan-mode.el`
  All of these are foreign commits inside the interleaved phase ranges,
  which F-6 tolerates. The last two were not in F-6's list but belong to
  the same class.
- **slice-016.md** (F-7). Appended "Reconciled against delivery": the PERCEIVE
  narrowing and IMP-025; R1 and item 5 moot; A1 falsified; OQ-1..4 resolved;
  D1 superseded.

### REVs completed
- **REV-003 (`reconcile-sl-016`): done.** POL-001 `## Scope` gains the
  non-editor-surface paragraph: goad's shells are No-branch tenants. There is
  also a dated 2026-09-24 amendment (F-8). The modify row was landed by hand.
  The rationale is in revision-003.md.

### Withdrawn / tolerated
- F-6: tolerated (phase boundaries include interleaved foreign commits).
- F-10(b) and (c): tolerated, rationale in the finding.

Reconcile pass complete — handoff to /close.
