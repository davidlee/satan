---
name: satan-refactor-T2
description: Extract the pre-spawn chain from broker--spawn into a declarative step list
metadata:
  type: refactor-theme
  topic: satan-refactor
  status: not-started
  blocked_by: []
  updated_at: 2026-05-23
---

# Theme T2 — Extract the pre-spawn pipeline (narrow)

**Impact:** High. **Effort:** L. **Risk:** M. **Reversibility:** Medium.

## Current shape

`satan-broker--spawn` (`broker.el:638`, 157 LOC, the largest function in the codebase) hand-threads a `prepare` plist through 6 sequential pre-spawn steps via a 6-level nested `plist-put` accumulator. Inline comments name "Phase 1.1+1.2", "Phase 2.1+2.2", "Phase 3.3", "Phase 5.8" — the chain has accreted four times. Per-step error policy is encoded ad-hoc by writing or not writing a `condition-case` at the callsite (2 of 6 are wrapped; the other 4 propagate raw).

Sub-agent A confirmed only the broker calls the six pre-spawn helpers.

## Why it hurts

Adding attributes' per-run `attribute-update` step becomes the 7th nested plist-put. GPT-5.5: *"you are not merely 'adding a seventh nested plist-put'; you are encoding lifecycle, error policy, and audit timing into the old shape, then asking a later refactor to preserve behaviour nobody designed cleanly."*

## Target shape

A declarative step list in a new `satan-pre-spawn.el`. Each step carries `:name`, `:fn`, `:error :tolerate|:raise`. A runner folds the list over the accumulating `prepare` plist applying the policy. `broker--spawn` shrinks from 157 LOC to ~30. Adding attribute-update = adding one list entry.

## Scope discipline

Extract pre-spawn only. Do not extend to sentinel / post-tool-call flow.

## Migration sketch

One behaviour-neutral PR: extract + cut over together (GPT-5.5: per-step PRs stretch the risk window across the broker's hot path). A possible second PR makes data-dependencies explicit as `:takes`/`:puts` slots **if and only if** the extraction surfaces hidden ones.

## Abort condition

T2 is only worth merging if the extracted form makes data dependencies and tolerated failures clearer than today. If it merely shortens the function, defer.

## Considered and rejected

- Hook-based dispatch — loses determinism + ordering control; A3 byte-identical-rerun invariant becomes harder to test.
- `cl-generic` per-step — over-engineered for 6 steps.
- Extract only the plist-put chaining into a helper — doesn't address accretion.
- Leave `broker--spawn` alone, add attribute-update inline — defers the cost into a future bigger refactor.

## First concrete step

PR that defines `satan-pre-spawn-steps` + `pre-spawn-run` in `satan/satan-pre-spawn.el`, replaces the 157-LOC inline chain in `broker--spawn` with the runner call. A3 determinism test must remain green.

## Open questions

- `defvar` or `defcustom` for the step list? (Recommend `defvar`; tests `let`-rebind.)
- Does the runner need conditional steps (`:when`)? Today no — every mode runs every step.

## PR log

- [ ] PR 1: `satan-pre-spawn.el` + cutover (behaviour-neutral) — pending
- [ ] PR 2 (conditional): `:takes`/`:puts` slots if hidden deps surface — pending
