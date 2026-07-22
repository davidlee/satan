# Implementation Plan SL-011: SATAN tick performance: observe and bound

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Cite entities by padded id (SL-020, REQ-059); phases as PHASE-01,
     criteria as EN-1/EX-1/VT-1/VA-1/VH-1. See .doctrine/glossary.md § reference forms. -->

## Overview

Seven phases: one immediate pain-killer, one foundation module, four
integration phases, one closure phase. Design: `design.md` (locked
2026-07-10). Everything lands before SL-012's move+rename sweep
(`SL-012 after SL-011`).

## Sequencing & Rationale

**PHASE-01 first, standalone.** The index-lock contention is live
user-facing pain and the fix is a one-line env injection — the slice
explicitly says ship it first. It deliberately does NOT wait for the trace
module: env is let-bound at the existing git call sites, and PHASE-03 later
folds it into `trace-call :env` with the PHASE-01 test as the
behaviour-preservation guard.

**PHASE-02 is the foundation** — everything downstream consumes the
accumulator, macros, or `trace-call`. Built and tested pure (no call-site
edits) so its ert suite pins the API before nine files start depending on
it. Byte-comp ordering hazard lives here: macros must be `require`d by
consumers at compile time; keeping the module dependency-thin
(`dl-satan-jsonl` + cl-lib only, no cycles) makes that safe for
compile-angel.

**PHASE-03 (bound) before PHASE-04 (observe)** — deadlines relieve the
worst UX risk (a hung probe stalling the editor indefinitely) and the
choke-point conversion is mechanically independent of stage wrapping.
Ledger rows start flowing here, so even before stage timing exists,
lock-contention incidents correlate against subprocess evidence.

**PHASE-04 then PHASE-05**: budget enforcement needs the accumulator
threaded end-to-end (t0, skip recording, tick-row flush) — that plumbing is
PHASE-04's deliverable. Splitting observe from bound also keeps each diff
reviewable: PHASE-04 changes no behaviour (pure timing), PHASE-05 changes
behaviour (skips) behind a defcustom.

**PHASE-06 is independent** of stages/budget (needs only `trace-call`) and
could run any time after PHASE-02; it sits late because it touches the
patch subsystem, which is otherwise untouched — keeping it out of the busy
early diffs.

**PHASE-07 produces the behavioural closure evidence** the slice promises
(VH tick + git-status loop; VA residue sweep for unconverted call sites)
and the CHANGELOG note. No new mechanism.

## Notes

- TDD red/green/refactor per phase; every phase exits `just check` green
  with zero new byte-compile warnings (commit gate).
- Elisp edits follow AGENTS.md: `bin/elisp-locate-paren-error` after every
  `.el` change, before byte-compile/tests.
- Trace-file location is runtime state (`$XDG_STATE_HOME/satan/`) — never
  committed, never referenced from authored docs as data.
- At close: verify/correct memory `mem.fact.git.optional-locks` (written
  prospectively; cites the fix as applied).
