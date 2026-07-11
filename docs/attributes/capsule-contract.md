---
name: capsule-contract
description: T-attr-1d — capsule render contract for the attribute bar block
metadata:
  type: design-contract
  topic: attributes/capsule
  status: draft
  feeds: [T-attr-1d]
  authority: blocking
  parent: design-contract.md
  updated_at: 2026-05-24
---

# Capsule render — contract (T-attr-1d)

> **Status.** Draft. Pins decisions for T-attr-1d implementation (broker-only).
> **Parent.** `design-contract.md` §9 (disable switch), §17.1 (broker-assembled capsule).

This contract pins the five open shape choices from `handover.local.md` and the
brief §4 bar-chart reference.

---

## 1. Data source — direct SELECT

The capsule queries `satan_attributes` directly via `dl-satan-attribute--query`:

```sql
SELECT name, value FROM satan_attributes
WHERE scope = 'global' ORDER BY name
```

No daemon RPC. The projection table is co-located in the broker's existing
`satan_memory` database. Daemon-as-RPC deferred to if/when the projection moves
to a daemon-private DB.

---

## 2. Disabled marker

Per `design-contract.md` §9: when `dl-satan-attribute-updates-enabled` is nil,
the capsule renders a single line:

```text
# Attributes
Attributes: disabled
```

The block MUST NOT expose frozen projection values.

---

## 3. Bar rendering

### 3.1 Glyph + grid

```text
# Attributes
  Curiosity      ███░░░░░░░  0.30
  Hunger         ███████░░░  0.70
  Suspicion      █████░░░░░  0.50
  Doubt          ███░░░░░░░  0.30
  Cruelty        ██████░░░░  0.60
  Shame          ███░░░░░░░  0.30
  Brooding       ████░░░░░░  0.40
  Metamorphosis  █████░░░░░  0.50
```

- Filled glyph: `█` (U+2588 FULL BLOCK).
- Empty glyph: `░` (U+2591 LIGHT SHADE).
- Bar width: 10 cells. Each cell = 0.10 of the [0, 1] range.
- Fill count: `round(value * 10)`, clamped to [0, 10].
- Numeric label: 2 decimal places, right of bar, separated by 2 spaces.

### 3.2 Label column

- Labels are the 8 public names from `design-contract.md` §2.
- Left-aligned, padded to 13 characters (length of "Metamorphosis").
- 2-space indent before each label.

### 3.3 Row order

Fixed vocabulary order from `design-contract.md` §2 — not sorted by value:

```text
Curiosity, Hunger, Suspicion, Doubt, Cruelty, Shame, Brooding, Metamorphosis
```

Internal names map 1:1: `:curiosity` → Curiosity, `:friction` → Cruelty.
All others: internal name capitalised = public label.

### 3.4 Zero state

All attributes seeded at 0.0. The capsule renders 8 rows of `░░░░░░░░░░  0.00`.
This is intentional — the model sees a "cold organism" until the dispatcher fires.

---

## 4. `caps_applied` — silent

`caps_applied` is audit-trail metadata (which caps reduced a delta). Not
surfaced in the capsule. The model sees final values, not the path that produced
them.

---

## 5. Capsule placement

Block order: Now → **Attributes** → Percept → Resonance → Motive → Sensors →
Today → Sources → Recent Runs.

Attributes are organism metabolism (`design-contract.md` §3.1). Placed before
perception so the model reads internal state before external signals.

---

## 6. Block suppression

The attribute block self-suppresses (returns nil, block omitted from prompt)
when:

- DB query fails (psql error, missing table, connection refused).
- No attribute rows returned (table exists but empty — should not happen after
  migration seeds, but defensive).

When suppressed, the capsule omits the block entirely — no header, no
placeholder. Log a warning so operators notice.

---

## 7. Implementation surface

All broker-side (`~/.emacs.d/satan/`). No daemon changes.

| File | Responsibility |
|---|---|
| `dl-satan-attribute-render.el` | Snapshot query + bar rendering |
| `dl-satan-context.el` | Wire attribute block into render pipeline |
| `framing.txt` | `attributes_block_header=# Attributes` key |
| `dl-satan-attribute-render-test.el` | ert tests for render + snapshot |

### 7.1 Test surface

- All-zero values → 8 rows, all `░░░░░░░░░░  0.00`.
- Mixed values → correct bar widths + labels + numerics.
- Disabled switch → single `"Attributes: disabled"` line under header.
- Nil snapshot (query failure) → nil return (block suppressed).
- Boundary values: 0.0, 1.0, 0.05 (rounds to 1 bar), 0.95 (rounds to 10).
- Label order matches §3.3 vocabulary order.
- Internal→public name mapping: `:friction` → `Cruelty`.

---

## 8. Change history

| Date | Change | Source |
|---|---|---|
| 2026-05-24 | Initial contract — pinned 5 open choices from handover.local.md. | T-attr-1d pre-impl pass. |
