# Implementation Plan SL-016: goad as SATAN's elicitation surface

Prose companion to `plan.toml`. Narrative only — the phase list, criteria,
verification and links live in the TOML.

## Overview

Eight phases across three repos: `~/satan` (corpus: `backend.py`, the tool
description), `~/dev/satan-attrd` (two attribute reasons), and this repo. The
build goes producer-first: the backend that writes the record lands and is
tested before any SATAN code reads it, so SATAN's fixtures are the backend's
own output.

```
PHASE-01  backend.py fixtures, JSON record      (~/satan)   behaviour unchanged
    │
PHASE-02  backend.py asks: queue, priority,     (~/satan)   inert: queue absent
          presented_at, provenance, emit date,
          expiry  ──► golden fixtures into satan/test/goad-fixtures/
    │
PHASE-03  PERCEIVE: satan-goad.el readers,      pure; queue still empty
          evidence :goad slice, canon rule
    │
PHASE-04  seams: shared undelivered writer,     refactor; no new behaviour
          quiet-p window arg, defcustoms,
          goad-ask capability
    │
PHASE-05  attrd reasons ask_suppressed /        (~/dev/satan-attrd)
          ask_uncorrelated + SATAN builder
    │
PHASE-06  PROMPT + DOORBELL: goad_ask           disabled by default
          (+ ~/satan/tools/goad_ask.md)
    │
PHASE-07  the loop: observer legs, kind "ask"   ask-scoped; other kinds unchanged
    │
PHASE-08  end-to-end through real backend.py;   enable, with the user
          redeploy attrd; live VH-1, VH-2
```

## Sequencing & Rationale

- **Fixtures before the backend changes (PHASE-01).** `backend.py` has no
  tests and carries six of the slice's changes (design sec-3, slice R2). The
  characterisation suite pins today's checklist behaviour so every later
  backend phase can prove it did not break the keeper's daily checklist. The
  JSON switch rides in the same phase because it is a pure format change the
  characterisation tests already cover.
- **Backend asks before SATAN reads them (PHASE-02 → PHASE-03).** Design sec-8:
  a fixture must not build the value under test (the ISS-014 lesson). The
  backend tests emit golden day files and a golden queue; SATAN's tests read
  those. PHASE-08 VT-43 re-derives them from the real backend so they cannot
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
| Round-3 review answers (design sec-2 emit date, sec-5 window-end judgement) never independently verified | encoded as tests, not prose: VT-24, VT-25, VT-31 (emit date), VT-15, VT-23 (window end). Re-read both sections at PHASE-03 and PHASE-07 phase-plan |
| The live goad unit runs `backend.py` from the corpus tree — every edit is live on save | PHASE-01/02 develop test-first; the format switch and data conversion land together; with no queue file PHASE-02 is inert; one live evaluate after each commit |
| The user's uncommitted corpus changes (`goad/data/*`, `goad/goad.service` deleted, `motd.txt`) | not touched; the day-file conversion in PHASE-01 asks first, since today's file is uncommitted and live |
| attrd delta values are a behavioural tuning choice | taken with the user at PHASE-05 phase-plan |
| Green is not green (DB tests skip without `SATAN_DB_HOST`; `just check` exits 0 on failures, ISS-008; concurrent runs clobber, ISS-013) | every phase records ran/skipped counts; one `just check` at a time |
| Out-of-repo tests are waived for verify-vt | verified by that repo's check and recorded in notes.md |
| `goad_ask.md` missing breaks every allowlisting run | PHASE-06 EX-2: corpus description commits before the allowlist change |
| The autonomous producer needs an authenticating unattended run (SL-018) | enablement only; nothing here needs it to build or verify |

## Choices made in planning (reversible, stated)

- v1 asks are yes/no, with the checklist's Later and Enough. Free-text or
  multi-choice asks are a later extension of the args schema.
- An ask's record is a separate `asks` map in the day file, keyed by
  `intervention_id`; the checklist `items` map is unchanged.
- Option ids: `yes:ask:<intervention_id>`, which the existing single
  `partition(":")` already parses.
- Queue path default `$XDG_STATE_HOME/satan/goad/queue.json`, with a
  `GOAD_SATAN_QUEUE` override for tests; SATAN's side is
  `satan-state-path "goad/queue.json"`.
- New modules: `satan-goad.el` (paths, pure readers, queue rewrite) and
  `satan-tools-goad.el` (the tool). Both POL-001 No-branch tenants
  (DEC-008).

## Notes

- `ISS-021` (the `crosses_midnight` guard slicing dates from GMT `ts`) is not
  this slice's; kind "ask" is exempt from the guard by design.
- Revision candidates for `/reconcile` stay as listed in notes.md.
