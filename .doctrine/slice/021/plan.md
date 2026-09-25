# Implementation Plan SL-021: Replay current_window from the desktop event series

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See glossary.md § reference forms. -->

## Overview

The design (locked, `design.md`) replaces SATAN's last present-tense read,
`current/desktop.json`, with one pure reader, `satan-desktop-at`, that replays
the focused window at any instant from panopticon's raw desktop log. Two
callers move onto it: the evidence assembler (at the window end) and
`activity_read`'s `current` scope (at the wall-clock now).

```
PHASE-01 canon date helpers ──▶ PHASE-02 satan-desktop reader + fixture
                                          │
                        ┌─────────────────┴──────────────┐
                        ▼                                ▼
          PHASE-03 evidence + alerts          PHASE-04 activity_read
                        └──────────────┬─────────────────┘
                                       ▼  (package deployed)
                          PHASE-05 corpus tool description
```

## Sequencing & Rationale

- **PHASE-01 first, alone.** Lifting `local-date` and `day-shift` into canon
  is a behaviour-preserving refactor (RV-021 F-10). Landing it on its own
  keeps its green bar separate from the new behaviour, and the reader
  in PHASE-02 depends on it.
- **PHASE-02 adds the reader with no callers.** The whole contract (sec-2) is
  tested in isolation through the new fixture module, including the pin
  test against real umbriel/niri lines. Nothing in production changes yet.
- **PHASE-03 and PHASE-04 cut over one consumer each.** PHASE-03 is the larger:
  the assembler, the sensor-alert vocabulary (retiring `stale` there removes the
  status the old probe produced, so they move together), and the percept,
  resonance and evidence fixtures whose assertions ride on the probe. The
  retired-cause samples (fixtures.json, audit, broker) go in the same phase
  because the cause disappears there. PHASE-04 is the tool, and it ends with
  the full closure grep, because only then is every `current/` reader gone.
  PHASE-03 must precede PHASE-04 only because PHASE-04's closure grep covers
  both.
- **PHASE-05 is gated on deployment**, not on code: the corpus description
  lands after the package runs in Emacs (sec-4, "Landing order"; SPEC-002
  REQ-015), and the user confirms the deployment (VH-1).

## Notes

- Tests stay independent of production data: the pin test copies a
  handful of live lines into the test as literals; it never reads
  `~/.local/state/behaviour`.
- PHASE-03 also switches `~/.emacs.d/lisp/dl-sleipnir-doctor.el` to
  `satan-desktop-at` before it removes `--current-window-status`. The design
  missed this caller; the user ruled to plan it now and correct design sec-3
  at reconcile.
- Documents that reconcile will touch are listed in `notes.md`, not in any phase.
