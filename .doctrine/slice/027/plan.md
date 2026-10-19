# Implementation Plan SL-027: malebolge daemon vm mode: coding tools in the room

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Six phases in three bands: four in malebolge (two behaviour-neutral
refactors, then two that change how the daemon starts), one in the satan
flake (the jail), and one live verification against the deployed room.

```
 malebolge, refactor            malebolge, daemon         satan flake       live
 ┌──────────┐  ┌──────────┐     ┌──────────┐ ┌──────────┐  ┌──────────┐     ┌──────────┐
 │ PHASE-01 │→ │ PHASE-02 │  →  │ PHASE-03 │→│ PHASE-04 │→ │ PHASE-05 │  →  │ PHASE-06 │
 │ root     │  │ src/room │     │ profile, │ │ daemon   │  │ room     │     │ VA / VH, │
 │ moves +  │  │ extract  │     │ door,    │ │ env in   │  │ profile  │     │ egress   │
 │ allowlist│  │          │     │ persona  │ │ the room │  │ jail     │     │ audit    │
 └──────────┘  └──────────┘     └────▲─────┘ └──────────┘  └────▲─────┘     └────▲─────┘
                                     │ EN-2: ~/flakes pushed,   │ EN-2: lock       │ EN-2: SL-015,
                                     │ agents lock updated      │ carries SL-015   │ IMP-023, fleet
                                                                                    deployed
 ◄──── runner behaviour unchanged ────►◄── old jail refuses startup until PHASE-05 ──►
```

## Sequencing & Rationale

**Refactor first, behaviour second.** PHASE-01 and PHASE-02 change no runtime
behaviour: the runner suite passing with only import-path and call-shape edits
is their bar (SPEC-004 NF-001). PHASE-01 goes first because it is small and
because it installs the structural test (`test/structure.test.ts`, an import
allowlist) that every later phase relies on to keep `src/room/` (the shared
room tier) and `src/runner/` honest — the extraction in PHASE-02 runs with that
test already in place. Its room rule passes vacuously until PHASE-02 creates
the directory.

**Why the extraction is one phase.** Moving the connection, shell, reader and
door code together is large but mechanical, and its intermediate states do not
compile cleanly apart (`roomShell` is built on `ObservedConnection`; the reader
on the shell). Splitting it would produce re-export shims the design forbids.
The one new behaviour in the room tier — `reword`, the daemon's fault wording —
is held back to PHASE-04, where its only caller arrives, so PHASE-02 stays
behaviour-neutral.

**The startup break window (user decision, 2026-10-20: push flakes first).**
`jailed-malebolge` runs the malebolge checkout directly
(`satan/flake.nix`, `malebolgeRoot`). From PHASE-03 the daemon refuses to start
without `MALEBOLGE_PROFILE`, so the old jail stops working until PHASE-05
ships the room profile. PHASE-03's EN-2 therefore requires `~/flakes` pushed
(flakes:SL-015 PHASE-05 `03dc0f0a` and its siblings are local-only today) and
the `agents` input re-locked in `~/dev/satan` before PHASE-03 starts, so
PHASE-03 → PHASE-04 → PHASE-05 run back to back with no external wait inside
the window. Pushing `~/flakes` is outward-facing: the agent asks before doing
it.

**PHASE-03 before PHASE-04.** Configuration (profile, door file, store and
socket paths, persona env file) is pure and fully unit-testable; the daemon
environment in PHASE-04 consumes `Execution`. The corpus and `~/notes`
justfile edits ride PHASE-03 because the persona change makes a missing env
file fatal: the corpus must carry `room.txt` and `pi.txt` in the same step.

**PHASE-05 after the daemon is complete.** The jail sets variables the daemon
must already understand. Its first act is RV-035 F-1's control: the
impure-devshell launcher recipe is written and seen to reject the current jail
(which binds `~/notes` rw through `JAIL_WORKSPACE_DEPS`) before the room
profile replaces it.

**PHASE-06 last, gated on deployment.** Every VA/VH check needs the room
running with user `satan`, oubliette IMP-023's readers' group, and the
flakes-side door file and key. The egress audit (RV-035 F-3) needs no
deployment and may be run earlier as a fail-fast check, but it is recorded and
gated here, at closure, against the tool set as it then stands.

## RV-035 routed findings → criteria

| finding | route | where |
|---|---|---|
| F-9 structural test is an allowlist | control | PHASE-01 EX-3 / VT-1 |
| F-4 host-key classification at startup | control | PHASE-04 EX-3 / VT-3 |
| F-1 impure launcher gains `/workspace` | control | PHASE-05 EX-1 / VT-2 |
| F-2 `satan` can read `/work`, cannot write | demonstrate | PHASE-06 EX-2 / VA-2 |
| F-3 MCP egress gate | control | PHASE-06 EX-4 / VA-4 |

Each control criterion names its incorrect candidate and requires the check to
be seen rejecting it before the fix makes it pass.

## Notes

- Design premises re-checked against malebolge `c8114ac` on 2026-10-20: every
  symbol §4.1 / §5 names resolves where the design says. One wording drift:
  §4.1 says the structural test "replaces the one-way check", but no such
  check exists in the tree; `structure.test.ts` is new (as §5 says).
- `doctrine slice research 27` reports drift only in the slice's own scope
  and design files, not in the code baseline.
- Out of plan, at reconcile: design §4.9 revisions (ADR-017 ledger row 3b,
  SPEC-002, SPEC-004 REVs; malebolge IMP-002 / RV-001 F-4 note; DEC-072,
  IMP-037).
