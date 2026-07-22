# Bough feature flag — brief

Status: **superseded** — bough dormant since ~2026-05, so SL-001 (the flag
slice this brief seeded) was abandoned in favour of SL-002 (remove the
integration). Retained for the verified seam analysis below; the fuller map
is SL-001 `design.md` §2/§10.

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

> Superseded by SL-001 `design.md` (D1: runtime exposure gating — requires,
> registration, and mode `:tools` lists stay untouched; the flag filters at
> the consumption seams). Rows below record the original sketch.

| Surface | File | Change |
|--------|------|--------|
| Defcustom | `satan-custom.el` | `satan-bough-tools-enabled` default t |
| Evidence assembly | `satan-memory-evidence.el` | Skip all 3 bough calls when disabled; skip the `:bough` sensor_status synthesis entirely (`--bough-status` maps zero attempts to `"ok"`, so gating the calls alone is not enough — the key must be omitted); set evidence fields (`:bough_recent`, `:bough_active`, `:bough_day`) to nil |
| Tool registration | `satan-tools-bough.el` | Don't register `bough_read` when disabled |
| Mode allowlists | `satan-mode.el` | Remove `bough_read` from 5 mode specs (or filter at runtime) |
| Load points | `satan-memory.el`, `satan-memory-evidence.el` | Gate both `(require 'satan-tools-bough)` sites |

## Already nil-safe (no changes needed)

- **Sensor alerts**: `--derive-causes` iterates `:bough` from source-order; missing key → `plist-get` nil → `--match-kind` nil → no cause tuple → no alert
- **Canon rules**: `bough.recent_status_change` and `bough.active_focus` check for non-nil evidence before firing
- **Observer predicates**: `--predicate-bough-event-match` checks `:bough_recent` — nil → no match

## NOT nil-safe (inquisition round 1 corrections — see SL-001 design §10)

- **Sensor capsule render**: `satan-sensor-render-block` iterates the fixed
  source order and maps an absent/nil `:bough` to `bough=ok` — a disabled
  bough still renders as healthy. Needs a presence-aware render seam (D4).
- **Truncation metadata**: `--truncate` hard-cap pass 5 unconditionally
  records `"bough_recent"` in `:truncated_at` even with no bough evidence
  collected. Needs to be conditional on a non-nil payload.
- **Mode inventory**: 7 registered modes carry `bough_read`, not 5 —
  tick-pulse and tick-agent (`satan-tick.el` defaults) in addition to the 5
  specs in `satan-mode.el`. The Python harness tier-2 drop set names
  `bough_read` but only filters supplied tools — no change needed.
- **Tank render**: `satan-tank.el` is already nil-safe — `(length nil)` is 0 in
  Emacs Lisp and `--render-bough-active` guards `(null nodes)`. When disabled it
  prints `bough_active: 0 nodes`; hiding the line entirely is a cosmetic design
  choice, not a fix. (An earlier draft claimed a latent nil crash here — wrong.)

## Dependency

SL-012 (rename `satan-*` → `satan-*`, move to this repo) — landed.
All references above use the post-SL-012 names.
