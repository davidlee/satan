---
name: satan-refactor-T4
description: Collapse tool/mode-allowlist duality — drop documentary-only :modes field from tool specs
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: merged
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T4 — Quick win: collapse tool/mode-allowlist duality

**Impact:** Low. **Effort:** S. **Risk:** Low. **Reversibility:** Trivial.

## Current shape

Three places to know about tool→mode mapping:
1. `satan-mode.el` mode-spec `:tools` list — authoritative; broker consults it.
2. `satan-tools-atsatan.el` calls `satan-tick-register` at load time to dynamically add `patch_job_*` to the tick-agent mode.
3. Each tool spec carries a `:modes` field — per `docs/satan/patch/handover.md`, *documentary only; the broker does not consult it*.

## Target shape

Delete the `:modes` field from tool specs. Add a load-time consistency check that asserts every tool referenced in a mode spec exists in the registry.

## First concrete step

PR that greps every tool spec for `:modes`, confirms no runtime consumer, deletes the field, adds the consistency check.

## Considered and rejected

- Invert: make `:modes` authoritative — would invert the established mode-centred ethos (also in anti-recommendations §5 #4).

## PR log

- [x] PR 1: delete `:modes` field + load-time consistency check — merged 2026-05-23 (22 sites stripped across 14 modules; `satan-mode-check-tool-references' enforces the invariant at load; affected tests rewritten; new `satan-mode-test.el' covers the guard)
