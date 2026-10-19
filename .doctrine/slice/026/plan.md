# Implementation Plan SL-026: malebolge coding layer: project context, cwd, ripgrep grep

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

The design (`design.md`, locked) splits into a shared pure core, two
room-facing layers on the runner side, one host-facing tool, the daemon's
wiring, the text and fleet edges, and a live check. Each phase ends green
(`just check` in malebolge) and leaves the agents working as before until
the next phase consumes it.

```text
PHASE-01 shared module ─┬─► PHASE-02 shell limits ─► PHASE-03 runner fetch ─► PHASE-04 compose + admit ─┐
                        └─► PHASE-05 grep ──────────────────────────────┬────────────────────────────────┤
                                                    PHASE-06 daemon ◄───┘                                │
                                                                         PHASE-07 corpus/fleet/docs ◄────┘
                                                                                    │
                                                                         PHASE-08 live VH
```

## Sequencing & Rationale

- **Shared module first.** `project-context.ts`, `truncate.ts` and `xml.ts`
  are pure (bar `nodeSourceReader`) and are consumed by every later phase.
- **Limits before the fetch.** The fetch's safety rests on `ShellLimits`;
  landing them alone (PHASE-02) tests the shell's overflow/timeout/abort
  semantics without the fetch's branching on top, and bounds the existing
  `preparing` execs (RV-033 F-17) independently.
- **Fetch before admission.** PHASE-03 produces `Fetched` as data and changes
  `readyRoom`'s shape; PHASE-04 is the only place that writes events and
  touches the prompt, so the trust invariant (DEC-073) is tested where it
  lives.
- **grep is independent of the runner chain**; it needs only `truncate.ts`.
  It precedes the daemon phase because the daemon installs it.
- **Text and fleet last among code phases**: the corpus names a tool that must
  exist, and the jail probe asserts a binary the daemon's `grep` now needs.
- **Live last**, gated on SL-025's room targets.

## Notes

- **Probe findings (RV-033 F-1, F-2).** Their adversary and criterion are
  transcribed as PHASE-03/EX-3 + VT-2 and PHASE-05/EX-2 + VT-2. After
  `slice phases`, the raiser verifies the transcription on RV-033.
- **PHASE-03 is the largest phase** (reader, doctrine step, classification,
  `readyRoom` reshape). Split it at phase-plan time if the sheet exceeds one
  sitting: `readyRoom` FinalStep + room reader, then the doctrine step.
- **Parallelism**: PHASE-05 needs only PHASE-01, so it may run beside
  PHASE-02..04.
- **Fixture name**: design §6 says `openFauxHarness`; the fixture is
  `openTestHarness` in `test/harness-fixture.ts` (with
  `systemPromptSections`). A naming slip, not a design change.
- **Jail probe shape**: `jailProbes` are literal text checks over built
  launchers (DEC-046), so PHASE-07 asserts a launcher string carrying
  `pkgs.ripgrep`'s store path; the exact string is settled at phase-plan.
- **Unknown to settle in PHASE-03's phase-plan**: how the probe test puts fake
  binaries first on PATH under `localConnection()` (pi-env local exec env).
- Cross-repo: PHASE-07 edits `~/satan-corpus` (commit with `just commit`
  there) and `~/dev/satan/flake.nix`.
