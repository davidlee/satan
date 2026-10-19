# Implementation Plan SL-024: malebolge: advertise Agent Skills in the system prompt

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Three phases, inside-out: the pure module, then its wiring in malebolge,
then the deployment in this repo's flake and the live check.

## Sequencing & Rationale

- **PHASE-01 first** because everything else consumes `Skill[]`. It holds
  all of the parity logic (pi's parse, duplicate and render rules) and is
  fully testable without a daemon, so most of the slice's risk is retired
  here under TDD.
- **PHASE-02** is thin: one config field and three lines in
  `daemon-main.ts`. It is kept separate so PHASE-01 lands as a reviewable,
  unwired unit, and because `daemon-main.ts` is outside the coverage gate,
  so its check is an agent read plus a smoke run rather than a test.
- **PHASE-03** comes last because the jail runs malebolge's checkout
  (`malebolgeRoot`), so the code must be committed there first. The
  RV-028 F-3 package check and its negative control sit here, before the
  user's live check, so a wrong store path fails `nix flake check` rather
  than a model session.

Two repos: malebolge commits carry `SL-024` in their subject, as SL-023's
do. This repo holds the doctrine record and the `flake.nix` change.

## Notes

- The user has uncommitted edits in malebolge (`biome.json`,
  `docs/internals.md`, `justfile`) that predate this slice. PHASE-02
  touches `docs/internals.md`; commit only this slice's hunks.
- The live check (PHASE-03 VH-1) needs the user: rebuilding and starting
  the jailed daemon are theirs to run.
