# Implementation Plan SL-025: Patch lanes end to end: self-edit and tick jobs through the runner, scoped per mode

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Five phases across five repos. The first three author changes that deploy
nothing on their own; the fourth deploys them together; the fifth proves the
lanes live.

```
PHASE-01 malebolge: mode scope ─┐
PHASE-02 satan: stamp the mode ─┼─▶ PHASE-04 cutover (one sitting) ─▶ PHASE-05 live
PHASE-03 fleet: room targets ───┘     drain → switch → restart →
          + user room rebuild           prompts → Emacs reload
```

## Sequencing & Rationale

- **PHASE-01 and PHASE-02 are independent** (different repos, no shared
  files) and can run in either order or in parallel. Each ends green and
  committed, but neither is live: the runner is a store build that changes
  only at a home switch, and Emacs builds the tool schema at load.
- **PHASE-03 precedes PHASE-04** because the runner must not name repos the
  room does not hold (a push to one exits 2). Its last step is a user act —
  the system switch that rebuilds the room image, and a room reboot.
- **PHASE-04 is one phase, not three,** because its steps are only safe
  together (design §4.6): the old runner refuses the new config keys and the
  new runner refuses the old `[mode.fix]`, so code and config ship in one home
  switch; a queued `fix` job would fail once `fix` is gone, so the drain comes
  first; the old Emacs still sends `fix`, and the corpus is read live from its
  working tree, so the prompts land and Emacs reloads straight after the
  restart. `runner.nix` is authored at the start of the phase; it reaches
  nothing until the switch.
- **PHASE-05 is separate** so the cutover can be judged on its own (the runner
  starts, the schema changed) before spending model calls on live jobs.

## Notes

- The design-review ledger RV-031 has no findings routed `demonstrate`,
  `probe` or `control`; nothing to transcribe.
- The `tick-agent` live job (PHASE-05/EX-1) needs a tick run: ticks fire once at
  boot, so the user triggers one by hand against an `@satan` directive
  whose work belongs in a non-SATAN room repo.
- Commit SL-025 by path: another session has uncommitted doctrine edits. The
  corpus's `just commit` sweeps all dirty state; commit prompt files by path.
- PHASE-04's drain is before the home switch, not merely before the restart:
  the switch may restart the user unit itself.
- PHASE-03's `nix flake lock` fetches the private `satan-corpus` over ssh, so
  it needs the user's agent; the `satan` input pulls satan's own inputs into
  the fleet lock (only `nixpkgs` and `doctrine` follow).
