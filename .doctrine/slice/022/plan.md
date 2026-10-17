# Implementation Plan SL-022: SATAN's jails and patcher on the LLM gateway

Prose companion to `plan.toml`. Narrative only — no queried data lives here
(the storage rule); the phase list, criteria, verification, and links are
authored in the TOML. Use this for the plan's rationale and sequencing.
<!-- Reference forms: `lib:reference/glossary.md` § reference forms. -->

## Overview

Eight phases. Ids are immutable, so the execution order (the array order in
`plan.toml`) is not numeric: the deploy phase, PHASE-07, runs third.

```
PHASE-01 harness ─> PHASE-02 jails + flake check ─> PHASE-07 deploy harness (cross-repo)
                                                          │
PHASE-08 Emacs cutover <─ PHASE-06 docs <─ PHASE-05 retire creds <─ PHASE-04 patch keyless <─ PHASE-03 refusal + frontiers
```

## Sequencing & Rationale

- **PHASE-01, PHASE-02: everything the deployed side needs.** The harness
  becomes a gateway client, and the jails move to gateway mode with a flake
  check that asserts them. Both work under today's broker (design § Across
  repos). PHASE-02's negative control (VA-1) proves the check can fail before
  anything relies on it.
- **PHASE-07 next: deploy before the broker work** (user, 2026-10-18; DEC-048
  amended). Push satan at PHASE-02, lock flakes to it, run `home-switch`. No
  later phase touches `flake.nix` or the harness, so this one deploy is
  final. From then on, the running Emacs can reload satan at any point. That
  removes the window RV-023 F-2 described, instead of guarding it by
  discipline.
- **PHASE-03 before the deletions.** The refusal path and the move of the
  frontier commits to `ready` are new behaviour, and they are additive.
  Landing them alone keeps the riskiest broker change (RV-023 F-1/F-16/F-18)
  in a diff that deletes nothing. With gateway jails deployed, a missing key
  file already produces real launcher refusals, so the new path is useful
  from the start.
- **PHASE-04 before PHASE-05.** `satan-credential.el` has two consumers.
  Emptying the patch path first leaves PHASE-05 one consumer to cut, then the
  module to delete.
- **PHASE-06** documents the end state once the code stops moving.
- **PHASE-08** pushes the final satan, restarts Emacs onto it, and only then
  drops the emacs credential backend, which the old broker would still have
  called. It runs the live checks.

PHASE-07 and PHASE-08 need the user present: they issue a key, push, commit
in other repos, and restart the user's editor.

## Notes

- Instrument-routed design-review findings: none. RV-023's two majors are
  routed `review` and were repaired in prose.
- `~/flakes/agents/gateway.nix` has another session's uncommitted work.
  PHASE-02 only reads `~/flakes/agents`; PHASE-07 edits in `~/flakes` leave
  that file alone.
- design.md § Across repos draws a single satan landing. The split into two
  pushes keeps its one ordering constraint (the deployed harness changes
  before Emacs loads a broker that sends no key), so the design stands; DEC-048
  carries the amended order.
- Open, non-blocking: QUE-004 (where the flat `reasoning_effort` convention is
  written down); the satan key's $20 budget (DEC-048) is the user's call at
  PHASE-07.
