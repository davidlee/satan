# Patch runner for the oubliette assistant room

## Context

IDE-007 (direction agreed 2026-10-16) replaces the satan-patcher bridge with a
persistent oubliette microVM — a *room*, not a capsule slot — holding clones of
about seven of the user's repos. The guest has no egress and no git
credentials; it reaches models through a socket door to the host LLM gateway
(~/flakes SL-011), and returns work only as git the host fetches into a
per-repo quarantine. Promotion from quarantine into the real repo is a human
step.

Oubliette owns the room, the model door and the git channel (its IDE-002,
`docs/plan-f-assistant.md`, "Plan F"; room design is in progress there). This
slice is the SATAN-side half: whatever drives work into the room and brings it
back to a human.

Today two `patch_jobs` consumers exist and neither completes a job: the elisp
runner (`satan/satan-patch-*.el`) and the Go `satan-patcher`
(`~/dev/satan-patcher`) — ISS-030, ISS-038, ISS-039, ISS-041. The user's
recollection (2026-10-18): satan-patcher itself works and carries
responsibilities oubliette and pi do not (scheduling, queueing, …); what was
never tested is the integration. ISS-041 (producer sends `base_ref = "HEAD"`,
clone rejects it) is consistent with that.

## Scope & Objectives

1. **Settle the responsibility boundary** between SATAN (elisp broker and
   tools), the patch runner, oubliette (room, door, git channel, quarantine),
   the coding harness (pi) and the LLM gateway — who schedules, queues,
   composes prompts, enforces policy, classifies results, holds credentials,
   and owns the approval surface. *Decided: option D (DEC-050).*
2. **Decide where the runner lives**, on evidence: elisp, the existing Go
   `satan-patcher` retargeted, or a new daemon (POL-001 names Rust as the
   target). Weigh POL-001 / IMP-006 (patch runner is an extraction candidate),
   ADR-017 (each authority item has one owner; Emacs keeps the approval
   surfaces), and elisp's single-threaded blocking. *Decided: one TypeScript
   process in `~/dev/malebolge` hosting pi-durable (DEC-051), under ADR-018's
   2026-10-18 amendment (REV-006).*
3. **Fix the `patch_jobs` contract**, including ISS-041 (`base_ref` must be a
   branch name, or something the consumer resolves to one). *Decided:
   DEC-059 (contract, states), DEC-052 (runner-local SQLite store).*
4. **Drive jobs into the room and back**: tools run in the room through
   pi-env over the door oubliette pins (Plan F §5, ssh as a non-root agent
   user), result collection from the quarantine (Plan F §4), and
   classification (DEC-054..DEC-057, DEC-060). Room adapter and door config
   wait on oubliette SL-005 (ASM-005); a capsule slot stands in.
5. **Promote from quarantine** through an Emacs approval surface (ADR-017;
   DEC-061).
6. **Retire the old path** on adoption: one queue consumer, not two
   (DEC-063: both old runners deleted, fenced first).
7. **Hold the runner to strict quality gates** (DEC-053; lint move IMP-041
   precedes the runner code).

## Non-Goals

- The room, its network namespace, the model door, per-repo tool images and
  the git channel — oubliette's.
- The LLM gateway, its key store and budgets — ~/flakes SL-011.
- Narrowing oubliette's `any_vm_running` probe refusal.
- Any change to what the satan harness itself does on a tick.

## Dependencies and sequencing

```
oubliette room design ──pins Plan F §4/§5──▶ SL-023 design (door-touching decisions)
SL-023 research ──▶ SL-023 design (runner home, contract, boundary) — can start now
```

The door-independent decisions (boundary, runner home, contract) can be
researched and designed now. Decisions that touch the door wait for
oubliette's room design; until then the runner is testable against a capsule
slot or a stub.

## Affected surface (coarse)

- `~/dev/malebolge` — new runner binary, shared wiring, lint/test gates.
- `satan/satan-patch-*.el` — runner, store, adapters, prompt, classify,
  listener deleted; `satan-tools-patch.el` rewritten as an RPC client (still creating the
  observer's `patch_job` intervention),
  `satan-patch-inbox.el` watch-driven, a new promote/reject command; a
  migration drops `patch_jobs`.
- `~/dev/satan-patcher` — retired and archived.
- `~/flakes/modules/home/linux/satan-patcher.nix`, `~/.config/emacs/apps/dl-satan.el`
  (`satan-patch-runner-enabled`) — deployment and disable switches.
- `.doctrine/adr/017/authority-ledger.md` — rows per DEC-062 (job lifecycle,
  path allowlist; rows 4, 5, 6 split; token `patch-runner`). Credential
  custody is not a ledger item (DEC-049).
- A new runner tech spec under SPEC-002, at reconcile (DEC-064).

## Risks, assumptions, open questions

- **Assumption (retired by research):** satan-patcher works and only its
  integration is broken — half-right (research 2b); both runners retired.
- **Assumption:** ASM-005 (door as Plan F §5 sketches).
- **Risk:** designing door-touching parts before oubliette pins §4/§5 means
  designing against a sketch.
- **Risk:** pi-durable / pi-env are experimental; versions pinned.
- **Risk:** two load-bearing mechanisms are unproven: the model gate that
  enforces ceilings (RV-025 F-1, design §6 OQ-1) and pi-env's typed room-stop
  failure reaching the env wrapper (F-2). The first phase is a spike that
  demonstrates both; if the gate fails, DEC-057 is amended to the weaker
  guarantee.
- **Settled:** the runner runs on this host (DEC-050). Routine room stops
  pause a job rather than lose it (DEC-055).

## Verification / closure intent

- A job created by `patch_job_create` runs end to end in the room (or a
  stand-in slot before the room lands), lands in quarantine, is classified,
  and is promoted or rejected from Emacs.
- Exactly one job queue consumer runs: the runner. Both old runners are
  deleted and `patch_jobs` is dropped.
- ADR-017 authority ledger updated for every item that changed owner.
- ISS-030, ISS-038, ISS-039, ISS-041 and CHR-003 closed (fixed or
  superseded); IDE-007 resolved into this slice.

## Summary

## Follow-Ups
