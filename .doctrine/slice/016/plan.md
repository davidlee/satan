# Implementation Plan SL-016: goad as SATAN's elicitation surface

Prose companion to `plan.toml`. Narrative only — the phase list, criteria,
verification and links live in the TOML.

## Overview

Twelve phases across three repos: `~/satan` (corpus: `backend.py`, the tool
description), `~/dev/satan-attrd` (two attribute reasons), and this repo. The
build goes producer-first: the backend that writes the record lands and is
tested before any SATAN code reads it, so SATAN's fixtures are the backend's
own output.

```
PHASE-01  backend.py fixtures, JSON record      (~/satan)   done
PHASE-02  backend.py asks + goldens             (~/satan)   done — boolean answers
PHASE-03  PERCEIVE readers, :goad, canon rule               done
    │   ── design revised: answer forms (DEC-024..028) ──
PHASE-10  backend.py answer forms: opt: ids,    (~/satan)   rework of PHASE-02
          {option, values}, shape check,
          goldens regenerated
    │
PHASE-11  PERCEIVE rework: form on the queue                rework of PHASE-03
          entry, object values, 1 KiB truncation
    │
PHASE-04  seams: undelivered writer, quiet-p,   refactor; + state-home helper
          defcustoms, capability, XDG helper    (DEC-027)
    │
PHASE-12  intervention record: migration 0008,  DEC-024, DEC-028
          :form, JSON row reads, open-asks query
    │
PHASE-05  attrd reasons + SATAN builder         (~/dev/satan-attrd)
    │
PHASE-06  goad_ask: form validator, refusal,    disabled by default
          queue from open-asks (+ goad_ask.md)
    │
PHASE-07  the loop 1: correlation, midnight,    ask-scoped
          answer predicate (any value shape)
    │
PHASE-09  the loop 2: negative branch, labels,  ask-scoped
          {option, values} trace, retirement
    │
PHASE-08  end to end incl. a form ask;          enable, with the user
          apply 0008, redeploy attrd, VH-1/2
```

## Sequencing & Rationale

- **Fixtures before the backend changes (PHASE-01).** `backend.py` has no
  tests and carries six of the slice's changes (design sec-3, slice R2). The
  characterisation suite pins today's checklist behaviour so every later
  backend phase can prove it did not break the keeper's daily checklist. The
  JSON switch rides in the same phase because it is a pure format change the
  characterisation tests already cover.
- **Backend asks before SATAN reads them (PHASE-02 → PHASE-03).** Design sec-8:
  a fixture must not build the value under test (the ISS-014 lesson). A
  corpus `just goldens <dir>` recipe drives the real backend and writes golden
  day files and a queue, committed here by hand; SATAN's tests read those. No
  test writes across repos. PHASE-08 VT-43 re-derives them from the real backend so they cannot
  drift.
- **Perceive before prompt (PHASE-03 → PHASE-06).** Design sec-9: the evidence
  slice is what both the percept and the observer read. The tool's
  goad-minted-subject refusal also needs the queue reader.
- **Seams in their own phase (PHASE-04).** Moving notify's undelivered writer
  and widening `satan-tick-quiet-p` are refactors of shipped code with
  existing tests; keeping them apart from new behaviour keeps a regression
  attributable.
- **attrd before the first enqueue (PHASE-05 → PHASE-06).** attrd rejects
  unknown reasons and drops the row (ISS-011). The reasons must exist before
  SATAN emits them, and attrd must be redeployed before the switch is on.
- **Tool before observer (PHASE-06 → PHASE-07).** The observer legs read what
  the tool records (`related_motive_id`, `cue_handles`, window 60); the queue
  rewrite function the observer calls at classification is built with the
  tool.
- **The observer work is split (PHASE-07 → PHASE-09).** PHASE-07 settles
  *whether* an ask is classified and what counts as its answer; PHASE-09 adds
  what silence means. The split keeps each observer change reviewable, and
  PHASE-09's verdict table rests on PHASE-07's routing. PHASE-09 runs before
  PHASE-08: ids are immutable, so array order, not the number, is execution
  order.
- **Rework before new work (PHASE-10 → PHASE-11).** PHASE-02/03 landed
  before the answer-form revision, on boolean answers and `yes:ask:` ids.
  Phase ids are immutable, so the rework is appended rather than reopening
  them, and it runs first: every later phase reads the revised record, and
  SATAN's fixtures must again be the backend's own output before anything
  new is built on them.
- **The record before the tool (PHASE-12 → PHASE-06).** The tool records a
  form and rewrites the queue from the open-asks query; both live in
  `satan-intervention.el`. Keeping that work in its own phase isolates the
  riskiest change of the revision — every intervention reader moving from a
  `|` split to JSON — behind the existing suites, before any goad behaviour
  depends on it.
- **The state-home helper rides PHASE-04.** It is a seam fix to shipped code
  (three copies of one defect), the same character as the phase's other
  refactors.
- **Disabled until PHASE-08.** `satan-goad-enabled` defaults nil. Nothing
  between PHASE-02 and PHASE-08 changes what the keeper sees: without a queue
  file the backend is byte-identical, and without the switch the tool
  refuses.

## Resolved during planning

- **goad re-evaluates at the end of an `engaged` exchange** (design sec-4's
  open question). `engaged` is set only by `Exchanged::Answer` — the keeper's
  own click in flight (`crates/goad/src/controller.rs:398-422`, goad
  `3434b76`) — and that exchange *is* a backend call whose reply is the next
  view (`absorb` → `Shift::Replaced`, `:186-213`). So a ring refused as
  `engaged` is followed at once by an evaluation that reads the queue. No
  retry needed. Remaining edge: if that click was **Enough**, the fresh ask is
  bulk-deferred unseen and later matures `undelivered` — the design's
  precedence already handles it.
- **Design premises re-checked** against HEAD `28734a2`: every function,
  defcustom and file the design names resolves; `backend.py` line references
  match `eeb4f3c`.

## Risks and how the plan meets them

| risk | mitigation |
|---|---|
| Round-3 review answers (design sec-2 emit date, sec-5 window-end judgement) never independently verified | encoded as tests, not prose: VT-24, VT-25, VT-31 (emit date), VT-15, VT-23 (window end). Re-read sec-2 at PHASE-03 and PHASE-07 phase-plan, sec-5 at PHASE-09 |
| The live goad unit runs `backend.py` from the corpus tree — every edit is live on save | PHASE-01/02 develop test-first; the format switch and data conversion land together; with no queue file PHASE-02 is inert; one live evaluate after each commit |
| Tick timer dormant (ISS-022) | PHASE-08's live asks come from a driven tick-pulse run |
| The user's uncommitted corpus changes (`goad/data/*`, `goad/goad.service` deleted, `motd.txt`) | not touched; the day-file conversion in PHASE-01 asks first, since today's file is uncommitted and live |
| attrd delta values are a behavioural tuning choice | taken with the user at PHASE-05 phase-plan |
| Green is not green (DB tests skip without `SATAN_DB_HOST`; `just check` exits 0 on failures, ISS-008; concurrent runs clobber, ISS-013) | every phase records ran/skipped counts; one `just check` at a time |
| Out-of-repo tests are waived for verify-vt | verified by that repo's check and recorded in notes.md |
| `goad_ask.md` missing breaks every allowlisting run | PHASE-06 EX-2: corpus description commits before the allowlist change |
| The JSON switch of every intervention reader (DEC-028) touches shipped code the observer depends on | its own phase (PHASE-12); existing intervention, observer and mark suites must stay green unchanged, with DB tests counted, not skipped |
| Migration 0008 not applied live — a form ask then fails to project | PHASE-12 keeps formless projection independent of 0008 (VT-52); PHASE-08 EX-4 applies it before enabling |
| A hand-edited queue can carry a form the host rejects | accepted (design sec-9): the backend checks shape only; goad shows nothing until that ask expires |
| The autonomous producer needs an authenticating unattended run (SL-018) | enablement only; nothing here needs it to build or verify |

## Choices made in planning (reversible, stated)

- ~~v1 asks are yes/no.~~ Superseded by the answer-form revision
  (DEC-024, DEC-025): an ask may carry a form of options and fields; with
  none it is Yes / No. Later and Enough are unchanged.
- An ask's record is a separate `asks` map in the day file, keyed by
  `intervention_id`; the checklist `items` map is unchanged.
- ~~Option ids: `yes:ask:<intervention_id>`.~~ Superseded by DEC-025:
  `opt:<option-id>:ask:<intervention_id>` for every ask option.
- Queue path default `$XDG_STATE_HOME/satan/goad/queue.json`, with a
  `GOAD_SATAN_QUEUE` override for tests; SATAN's side is
  `satan-state-path "goad/queue.json"`.
- `topic:` handles are `satan-goad-subject-topic` of the subject, one
  function over `satan-memory-canon--slugify`, shared by the canon rule and
  the tool's goad-minted check: raw subject values (`/`, `~`) fail the cue
  regex.
- ~~The queue rewrite reuses `satan-intervention-pending`.~~ Wrong:
  pending returns matured rows only (RV-015). The queue reads its own
  open-asks query (DEC-028, PHASE-12).
- New modules: `satan-goad.el` (paths, pure readers, queue rewrite) and
  `satan-tools-goad.el` (the tool). Both POL-001 No-branch tenants
  (DEC-008).

## Notes

- `ISS-021` (the `crosses_midnight` guard slicing dates from GMT `ts`) is not
  this slice's; kind "ask" is exempt from the guard by design.
- Revision candidates for `/reconcile` stay as listed in notes.md.
