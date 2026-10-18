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
   and owns the approval surface.
2. **Decide where the runner lives**, on evidence: elisp, the existing Go
   `satan-patcher` retargeted, or a new daemon (POL-001 names Rust as the
   target). Weigh POL-001 / IMP-006 (patch runner is an extraction candidate),
   ADR-017 (each authority item has one owner; Emacs keeps the approval
   surfaces), and elisp's single-threaded blocking.
3. **Fix the `patch_jobs` contract**, including ISS-041 (`base_ref` must be a
   branch name, or something the consumer resolves to one).
4. **Drive jobs into the room and back**: dispatch over the door oubliette
   pins (Plan F §5, ssh as a non-root agent user), result collection from the
   quarantine (Plan F §4), and classification.
5. **Promote from quarantine** through an Emacs approval surface (ADR-017).
6. **Retire the old path** on adoption: one queue consumer, not two.

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

- `satan/satan-patch-*.el`, `satan/satan-tools-patch.el` — runner, store,
  adapters, prompt, classify, inbox, listener; producer tool.
- `~/dev/satan-patcher` — retargeted or retired.
- `~/flakes/modules/home/linux/satan-patcher.nix`, `~/.config/emacs/apps/dl-satan.el`
  (`satan-patch-runner-enabled`) — deployment and disable switches.
- `.doctrine/adr/017/authority-ledger.md` — a new queue-consumer /
  job-lifecycle row; row 6 (kill switches) split if a daemon owns its switch.
  Credential custody is not a ledger item (DEC-049).

## Risks, assumptions, open questions

- **Assumption:** satan-patcher works and only its integration is broken
  (user recollection; research verifies).
- **Risk:** designing door-touching parts before oubliette pins §4/§5 means
  designing against a sketch.
- **Open:** runner on this host (unix-socket relay) or on the tailnet? Plan F
  expects this host.
- **Open:** does an always-up room's probe-blocking cost (Plan F, "Two
  operational costs") change anything SATAN-side?

## Verification / closure intent

- A job created by `patch_job_create` runs end to end in the room (or a
  stand-in slot before the room lands), lands in quarantine, is classified,
  and is promoted or rejected from Emacs.
- Exactly one `patch_jobs` consumer is enabled.
- ADR-017 authority ledger updated for every item that changed owner.
- ISS-030, ISS-038, ISS-039, ISS-041 and CHR-003 closed (fixed or
  superseded); IDE-007 resolved into this slice.

## Summary

## Follow-Ups
