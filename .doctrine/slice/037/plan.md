# Implementation Plan SL-037: Signal loss (F1): add the reason the daemon lacks, preserving the backlog until it deploys

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Four phases: hold the probe off, change the daemon and contract, change the broker, then release. The design owns the mechanism; this plan owns the order.

## Sequencing & Rationale

```text
PHASE-01 interim ──────────────┐
PHASE-02 daemon + contract ────┼──> PHASE-04 release and closure
PHASE-03 broker ───────────────┘
```

PHASE-01 goes first because the loss is live: each tick still consumes evidence. It needs no code, so nothing waits on it being cheap to run, and it needs the user's approval because it edits the Emacs config repo.

PHASE-02 and PHASE-03 touch different repos and do not depend on each other. With the flag off, either can land first. The contract edit sits with the daemon phase because it declares the same row.

PHASE-04 is last by necessity. The flag returns only after both changes are live, or the daemon deletes the row or the listener rejects its event. It rebuilds a host service, so it needs the user's approval.

## Notes

- `RV-064` F-3 and F-4 are carried as criteria, split where their placement requires it: F-4 across PHASE-01 and PHASE-04, F-3 across PHASE-03 and PHASE-04.
- The daemon's VT rows are waived from `verify-vt` because the tests live outside this repo, as `SL-016` did for goad; they are checked by `just check` in the devshell and recorded in the notes.
- The daemon has no independent review yet (see the notes). A pi pass over `~/dev/satan-attrd` during PHASE-02 needs the quotient form re-approved first.
