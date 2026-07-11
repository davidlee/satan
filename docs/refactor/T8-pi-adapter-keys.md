---
name: satan-refactor-T8
description: Externalise the pi-adapter API-key list into a shared spec
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: not-started
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T8 — Quick win: externalise pi-adapter API-key list

**Impact:** Low. **Effort:** S. **Risk:** Low.

## Current shape

`satan-patch-adapter-pi-api-key-vars` is a hardcoded 7-element list in elisp; the pi binary (built by Nix flake) must accept the same env var names. No shared spec (`review/12-HARNESS-BOUNDARY.md` §items-from-one-side).

## Target shape

Either a shared `satan/protocol/api-key-vars.json` consumed by both sides, or a short README in `docs/satan/patch/adapter-pi.md` documenting the contract and the discipline.

## First concrete step

Either PR (extract to JSON) or doc PR. User-decidable; the JSON path is mechanically cleaner.

## Open questions

- JSON spec file vs short README. (Recommend JSON; mechanically cleaner. User-decidable — also tracked in `plan.md` open questions §5.)

## PR log

- [ ] PR 1: extract to JSON OR write adapter-pi README (path TBD) — pending
