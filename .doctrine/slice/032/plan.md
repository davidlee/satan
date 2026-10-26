# Implementation Plan SL-032: MCP run identity per conversation, not per connection

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Six satan phases, one malebolge phase, one live check. Satan lands first
(design sec-7, rollout R1): an older server ignores the identity capability,
so the malebolge client is correct against either server, but the reverse is
not true.

```
PHASE-01 attribution ──▶ PHASE-02 retire DEC-8 ──▶ PHASE-03 lazy mint
                                                        │
PHASE-06 close/admission/cancel ◀── PHASE-05 settle ◀── PHASE-04 identity
        │
        ▼
PHASE-07 malebolge pool ──▶ PHASE-08 live (VH)
```

## Sequencing & Rationale

- **Attribution before DEC-8 (01 → 02).** DEC-8's exclusion is what kept
  the dynamic run-id variable honest (DEC-124). Removing the exclusion first
  would open a window where a broker tick and an MCP call overlap and
  mis-attribute. With explicit attribution in place, retiring DEC-8 is pure
  deletion.
- **Lazy mint before identity (03 → 04).** The -32600 rule ("initialize
  after a run is minted") and the manifest's `:conversation` field both
  presuppose a mint that happens after `initialize`.
- **Settle before close lifecycle (05 → 06).** Deferred finalisation waits
  for `in-flight` to reach 0, and `in-flight` is released by the settle
  path. Building close on top of an unsettled count would make I3 depend on
  I4's repair. PHASE-05 therefore verifies on a live session only; the
  closing-session cases of V15 move to PHASE-06, where `closing` exists.
- **The three severe RV-060 findings land where their mechanism does.**
  F-2 (probe) in PHASE-05 and PHASE-06, F-1 (probe) in PHASE-06, F-3
  (demonstrate) in PHASE-07. Each carries a VA row naming its adversary,
  and PHASE-05/06 carry negative controls (the F-6 boolean-busy-flag mutant,
  and dropping the non-local tool-result write) so the VT rows are shown to
  reject a wrong implementation.
- **PHASE-08 is separate** because it needs both repos deployed in the room
  and an operator; it records the revisions exercised (RSK-020).

## Notes

- PHASE-05 leaves the sentinel's finalise-at-once behaviour in place; a
  `quit` there closes the transport after settling, so the early finalise
  sees a settled call. PHASE-06 replaces it with deferred finalisation.
- Reconcile-time follow-through (SPEC-002 transports row, SPEC-001 REQ-007 /
  QUE-001, the DEC-8 memory, malebolge IDE-002 note) is design sec-91's list,
  owned by `/audit` → `/reconcile`, not a phase.
