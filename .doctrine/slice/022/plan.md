# Implementation Plan SL-022: SATAN's jails and patcher on the LLM gateway

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Six phases in this repo, then two cross-repo rollout phases. The in-repo
phases go from additive to destructive: first the parts that work under
today's broker, then the deletions that require the new harness to be
deployed.

```
PHASE-01 harness ──> PHASE-02 jails + flake check ──> PHASE-03 refusal + frontiers
                                                            │
PHASE-08 Emacs cutover <── PHASE-07 deploy <── PHASE-06 docs <── PHASE-05 retire creds <── PHASE-04 patch keyless
```

## Sequencing & Rationale

- **PHASE-01 first.** The harness change is self-contained Python, and the
  new harness runs under today's broker (design § Across repos). Every later
  phase can assume it.
- **PHASE-02 after PHASE-01.** The gateway-mode jail stops forwarding
  `SATAN_PROVIDER`, which only the old harness needed. The flake check lands
  with the jail it asserts, and its negative control (VA-1) proves the check
  can fail before anything relies on it.
- **PHASE-03 before the deletions.** The refusal path and the move of the
  frontier commits to `ready` are new behaviour, and they are additive: the
  credential path still works alongside them. Landing them on their own keeps
  the riskiest broker change (the frontier move, RV-023 F-1/F-16/F-18) in a
  diff that deletes nothing, and easy to review.
- **PHASE-04 before PHASE-05.** `satan-credential.el` is consumed by both the
  patch path and the broker. Emptying the smaller consumer first leaves
  PHASE-05 with one consumer to cut and then the module to delete.
- **PHASE-05 opens the rollout hazard.** From here the working tree's broker
  sends no key and no `SATAN_PROVIDER`. The deployed (old) harness would fail
  under it, so the running Emacs must not reload satan until PHASE-07's
  `home-switch`. That condition is the phase's EN-2.
- **PHASE-06** documents the end state in one pass, once the code no longer
  changes.
- **PHASE-07 / PHASE-08** follow DEC-048's order: key, push, flakes and
  `home-switch` (new harness, old broker), policy file, then restart Emacs,
  and only then the emacs config edit. Both need the user present: they push,
  commit in other repos, and restart the user's editor.

## Notes

- Instrument-routed design-review findings: none. RV-023's two majors are
  routed `review` and were repaired in prose.
- `~/flakes/agents/gateway.nix` has another session's uncommitted work.
  PHASE-02 only reads `~/flakes/agents`; PHASE-07 edits in `~/flakes` leave
  that file alone.
- Open, non-blocking: QUE-004 (where the flat `reasoning_effort` convention is
  written down); the satan key's $20 budget (DEC-048) is the user's call at
  PHASE-07.
