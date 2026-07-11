# Bough feature flag — brief

Status: placeholder for a future doctrine slice in this repo (after SL-012 lands).

## Intent

Add a `satan-bough-tools-enabled` defcustom (default `t`). When `nil`, SATAN
treats bough as if it doesn't exist — no tool, no evidence, no sensor signal, no
alerts. Not an error. Not a degraded sensor. Just absent.

## Constraint: irrelevant signal, not defect signal

Today, when bough is unreachable, SATAN fires `bough_unreachable` sensor alerts
and reports `:bough "unreachable"` in sensor_status. A disabled feature must
not report as a failing one. The `:bough` key must be **absent** from
`sensor_status` entirely (not `"ok"`, not `"unreachable"` — missing). The alert
system's `--derive-causes` already handles a missing key gracefully → no alert.

## Gate points

| Surface | File | Change |
|--------|------|--------|
| Defcustom | `satan-something.el` (TBD) | `satan-bough-tools-enabled` default t |
| Evidence assembly | `satan-memory-evidence.el` | Skip all 3 bough calls when disabled; omit `:bough` from `sensor_status`; set evidence fields (`:bough_recent`, `:bough_active`, `:bough_day`) to nil |
| Tool registration | `satan-tools-bough.el` | Don't register `bough_read` when disabled |
| Mode allowlists | `satan-mode.el` | Remove `bough_read` from 5 mode specs (or filter at runtime) |
| Load point | `satan-memory.el` | Gate `(require 'satan-tools-bough)` |
| Tank render | `satan-tank.el` | Guard `(length active)` → `(if active (length active) 0)` — existing latent bug; crashes on nil |

## Already nil-safe (no changes needed)

- **Sensor alerts**: `--derive-causes` iterates `:bough` from source-order; missing key → `plist-get` nil → `--match-kind` nil → no cause tuple → no alert
- **Canon rules**: `bough.recent_status_change` and `bough.active_focus` check for non-nil evidence before firing
- **Observer predicates**: `--predicate-bough-event-match` checks `:bough_recent` — nil → no match
- **Sensor render order**: `dl-satan-sensor--source-order` (→ `satan-sensor--source-order`) keeps `:bough` — harmless when key is absent from plist

## Dependency

After SL-012 (rename `dl-satan-*` → `satan-*`, move to this repo).
All references above use the post-SL-012 names.

## Discovered bug (fix independently)

`satan-tank.el` `(length active)` crashes when `active` is nil — should be
`(if active (length active) 0)`. Exists regardless of bough flag; fix
separately.
