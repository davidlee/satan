# Implementation Plan SL-028: malebolge room daemon as an Emacs-started user unit, robust to satan-mcp restarts

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Six phases in three bands: four in malebolge (primitives, the tools handle,
daemon wiring, client side), one across the flakes (the satan-mcp bind
combinator), and one for the unit, deployment and live checks.

```
 malebolge                                                   flakes            live
 ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐     ┌──────────┐     ┌──────────┐
 │ PHASE-01 │→ │ PHASE-02 │→ │ PHASE-03 │→ │ PHASE-04 │  →  │ PHASE-05 │  →  │ PHASE-06 │
 │ lock +   │  │ SATAN    │  │ daemon   │  │ Emacs +  │     │ satanMcp │     │ unit,    │
 │ socket   │  │ tools    │  │ startup  │  │ attach + │     │ Options, │     │ SATAN.md,│
 │ claim    │  │ handle   │  │ order    │  │ docs     │     │ 4 flakes │     │ deploy   │
 └──────────┘  └──────────┘  └──────────┘  └──────────┘     └──────────┘     └────▲─────┘
  unwired       unwired       behaviour      client side      binds + mkdir       │ EN-2: user
                              changes here                                        │ go-ahead to
                                                                                  │ push + switch
```

## Sequencing & Rationale

**Primitives before wiring.** PHASE-01 (instance lock, socket claim) and
PHASE-02 (the `satanTools` handle) each land a self-contained module with
its own tests and leave daemon startup untouched. The runner does pick up the
new `serveUnix` claim in PHASE-01, since it shares the function; its tests
are the bar there. Splitting these out keeps the subtle parts — the lock,
the error classification in the claim, the coalesced refresh with
cancellation — reviewable on their own, which is where RV-040 found every
blocker and major.

**Wiring in one phase.** PHASE-03 changes `session.ts`, `daemon.ts`,
`daemon-extensions.ts` and `daemon-main.ts` together because the startup
order (lock → claim → refresh → openSession) is one invariant; an
intermediate state would be a daemon that opens its store before claiming or
resumes a turn without SATAN tools. `connectSatanTools` survives PHASE-02 as
a thin adapter only so PHASE-02 ends green; PHASE-03 deletes it.

**Client side last in malebolge.** PHASE-04 (attach retry, `malebolge.el`,
docs) depends on nothing in PHASE-01..03 at the code level, but the docs
describe their behaviour, so it follows them.

**Flakes after malebolge settles.** PHASE-05 touches five repos' Nix
(`~/flakes/agents`, satan, corpus, emacs, notes). Agents goes first because
the others consume it as `inputs.agents`; each consumer's lock then moves.
Running it after malebolge means the satan flake's `jailed-malebolge`
launcher change (pre-creating the mcp dir) is the only daemon-facing change
in flight.

**Deploy and live last.** PHASE-06 adds the unit and needs pushes and a
home-switch: outward-facing, so its EN-2 is the user's explicit go-ahead.
The satan input deploys from GitHub, so the launcher fix reaches the unit
only after push + `nix flake update satan`. The malebolge live tree is what
the unit runs, so no malebolge deploy step exists (RSK-020).

## Notes

- **Don't home-switch mid-slice.** `~/flakes` switches build malebolge from
  the dev checkout, dirty edits included
  (mem.fact.flakes.switch-builds-dev-checkouts), and the runner shares
  `serveUnix` from PHASE-01. A switch between phases deploys whatever the
  tree holds to the runner. Every phase ends green, but the first deliberate
  switch is PHASE-06's.
- **Pushes are gated.** PHASE-05 (`~/flakes`, for the agents input every
  consumer locks from GitHub) and PHASE-06 (`~/dev/satan`, for the satan
  input) each wait for the user's go-ahead; local verification uses
  `--override-input` first.
- **Why `src/daemon-start.ts`.** `daemon-main.ts` is a top-level script with
  no test; PHASE-03's ordering invariants are only checkable if the sequence
  is a function, as the runner's is (`src/runner/start.ts`).

- Code review of PHASE-01..03 should probe the lock, the claim's error
  classes, and refresh cancellation first (notes.md § Design review).
- Governance revisions (REQ-015 tracked gap RSK-020; SPEC-002 daemon row)
  are applied at reconcile, not in a phase.
