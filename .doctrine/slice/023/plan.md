# Implementation Plan SL-023: Patch runner for the oubliette assistant room

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Seventeen phases in four groups (PHASE-16 and PHASE-17 appended later; see
Sequencing). PHASE-15 was appended after the design's
room-adapter amendment (rev 56, DEC-065); it runs between PHASE-10 and the
cutover, so ids no longer follow execution order:

```
prove ─────────▶ gate ──▶ build the runner (in ~/dev/malebolge) ─────────────▶ cut over
PHASE-01 spike   PHASE-02  03 pure core → 04 store → 05 socket → 06 git channel   11 fence
                 lint      → 07 run path → 08 ceilings → 09 pause → 10 recovery  12 deploy
                           → 15 room adapter + door kind                         13 Emacs client
                                                                                 14 retire Go, closure
```

Phases 01–10 and 15 change `~/dev/malebolge` only (plus doctrine records here).
Phases 11–14 are the DEC-063 cutover, one deployment step each, and touch this
repo, `~/flakes`, `~/.config/emacs` and `~/satan-corpus`.

## Sequencing & Rationale

- **Spike first (PHASE-01).** The design rests on two unproven mechanisms,
  routed to demonstration by RV-025: the model gate (F-1, design §6 OQ-1) and
  pi-env's typed room-stop failure at an env wrapper (F-2), plus the §6 spike
  confirmations. Each failure mode changes a decision (DEC-057 weaker
  guarantee; DEC-055 pause recognition), so it is cheapest to learn before any
  runner code. The faux-provider gate test is written where PHASE-08 will
  extend it (`test/runner/model-gate.test.ts`), so nothing is thrown away. The
  live room-stop part needs the user to start and stop slot f (sudo).
- **Lint before runner code (PHASE-02).** DEC-053 / IMP-041: the runner is
  written under typescript-eslint `strictTypeChecked`, not retrofitted. The
  spike's code is raised to the bar here with the rest of malebolge.
- **Inside-out build (03–10).** Pure modules first (cheap to test, pin ported
  behaviour as acceptance fixtures before the elisp tests are deleted in
  PHASE-13), then the store they sit on, then the socket, the git channel, the
  run path, and the three behaviours that complicate a run — ceilings, pause,
  recovery — each on a working run path. Recovery is last because its table
  spans every state the earlier phases create.
- **Room adapter after recovery (PHASE-15).** DEC-065 builds the room
  `GitChannel` adapter and `[door] kind` against oubliette SL-006 sec-6
  fixtures, provisional until SL-006 locks. It follows PHASE-10 because its
  trust failure is judged against PHASE-09's pause and its `preparing` checks
  and post-collect clean extend PHASE-10's recovery rows. It precedes the
  fence (PHASE-11 EN-2) so the cutover outage starts with a feature-complete
  runner. Door-agnostic parts of the amendment sit in their natural phases:
  the scheduler seat (PHASE-07 EX-8), restart gating on `enabled`, `parked_at`
  and the post-admission `preparing` row (PHASE-10 EX-6..EX-8), the slot's
  configured alias and seeded `known_hosts` at deploy (PHASE-12 EX-4).
- **Cutover in DEC-063's order (11–14).** Fence, deploy, client, retire. The
  one-consumer invariant (I1) holds at every step; each step is checked
  against deployed state, not only green checks. PHASE-12 smoke-tests the
  runner over its socket before any producer can reach it.
- **Rulings of 2026-10-19 (PHASE-16, PHASE-17, PHASE-12 amended).** PHASE-16
  applies design rev 63 (room probe = the job's collect; DEC-057 rulings).
  PHASE-17 builds the gateway-routed provider no earlier phase built (design
  §5.1, §10): provider `gateway`, catalog rendered from `~/flakes`
  `agents/gateway.nix` as the jails render it, key by systemd
  `LoadCredential=`. PHASE-12 then deploys against the live `assistant` room,
  not a slot (EX-6..EX-12 supersede EX-3/EX-4 and VH-1's slot wording), covers
  CHR-016's live items there, and runs from malebolge's live tree until
  CHR-017 packages it. Execution order: … 15 → 16 → 17 → 12 → 13 → 14.

## Notes

- **Cross-repo VT mandates.** VT `test_file` paths in `~/dev/malebolge` are
  absolute; `doctrine slice verify-vt` resolves them but reports
  UNATTRIBUTABLE, because this repo's git cannot see malebolge commits. That
  verdict is expected and non-halting. Keywords are a floor; each phase's
  `/phase-plan` sharpens them once real identifiers exist.
- **Human steps.** PHASE-01 (slot start/stop), PHASE-11 and PHASE-12 (flakes
  switch and deploy, Emacs reload), PHASE-14 (promote/reject from the inbox).
  An agent cannot run `capsule … start` or a NixOS switch; it asks the user.
- **Stop conditions.** PHASE-01 EX-2 failing stops the slice for a DEC-057
  amendment (user ruling already given: amend to the weaker guarantee).
  PHASE-01 EX-3 failing stops it for a DEC-055 rethink. PHASE-12 EN-2 (gateway
  credential) may block on `~/flakes` SL-011.
- **Live room rung (CHR-016).** One job against a real room, reconnect after
  a room stop, a changed host key refusing, non-interactive verbs as the
  runner user. Waits on oubliette SL-006 shipping; backlog, not a phase and not
  closure evidence (design §9). The slot stays the live rung for PHASE-12/14.
  Amended by user ruling 2026-10-19: PHASE-12 covers the rung's live items
  against the `assistant` room (EX-10); the rest stays in CHR-016.
- **Out of the phases.** Ledger rows (DEC-062) land at audit; the runner tech
  spec (DEC-064) at reconcile; issue closures at close. PHASE-14 gathers their
  evidence.
- **malebolge's working tree** has an uncommitted `biome.json` change that
  predates this plan; PHASE-02 replaces Biome's lint role, so the phase must
  look at that change first and not clobber it.
