# Bough feature flag: satan-bough-tools-enabled

## Context

Bough integration is currently unconditional: SATAN always loads
`satan-tools-bough`, registers `bough_read`, makes three bough calls during
evidence assembly, and synthesises a `:bough` sensor_status. When bough is
unreachable this fires `bough_unreachable` alerts — a disabled or absent bough
installation reports as a *failing* one.

Brief: `docs/bough-feature-flag-brief.md` (claims verified against the tree
2026-07-17). Depends on SL-012 (rename + move to this repo) — landed.

## Scope & Objectives

Add a `satan-bough-tools-enabled` defcustom (default `t`). When `nil`, bough is
treated as absent, not degraded:

- `bough_read` is not exposed to any harness: filtered from tool
  listing/manifests and denied at dispatch across all bough-carrying modes
  (7 registered: 5 in `satan-mode.el`, plus tick-pulse and tick-agent from
  `satan-tick.el`).
- Evidence assembly skips all three bough calls; `:bough_recent`,
  `:bough_active`, `:bough_day` are nil; truncation metadata never names
  bough labels it didn't actually drop.
- `:bough` is **absent** from sensor_status — the synthesis is skipped
  entirely (`--bough-status` maps zero attempts to `"ok"`, so gating the
  calls alone is insufficient) — and the sensor capsule render emits no
  `bough=` segment for the absent key (round-1 RN-1: today an absent key
  still renders `bough=ok`).
- No `bough_unreachable` alerts (follows from the absent key —
  `--derive-causes` is already nil-safe).
- Toggling at runtime is safe in both directions, with no
  listed-but-denied / hidden-but-callable half-states (design §5.4).

Defcustom home: `satan-custom.el`.

## Non-Goals

- No change to bough behaviour when the flag is `t` (today's default path is
  untouched).
- No tank-render change: `satan-tank.el` is already nil-safe; `bough_active:
  0 nodes` when disabled is acceptable. Hiding the line is cosmetic and out of
  scope.
- No changes to canon rules, observer predicates, or alert cause derivation —
  verified already nil-safe. (The sensor *capsule render* is NOT nil-safe and
  is in scope — see design RN-1/D4.)

## Summary

## Follow-Ups
