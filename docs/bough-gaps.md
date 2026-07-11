---
name: satan-bough-gaps
description: Bough CLI gaps surfaced by SATAN's memory substrate (tracking; B1 closed, B2 open)
metadata:
  type: tracking
  topic: satan
  status: living
  updated_at: 03398479
  verified_at: 03398479
---

# Bough CLI gaps surfaced by SATAN memory substrate

One read-side capability remains missing from bough as of 2026-05-21
(B2 — `--max-depth N` on `node subtree`).  SATAN works around it in
elisp.  B1 (per-status-transition history) closed by bough DR-116
on 2026-05-21; SATAN's `recent_changes` scope now consumes
`node status-transitions` + `node created` directly.

Context: SATAN consumes bough exclusively via `bough --json` (no
direct PG access; enforced by grep-lint). The `bough_read` tool in
SATAN exposes six scopes — `node`, `recent_changes`, `active`, `day`,
`week`, `project_subtree` — and maps each to one or more CLI calls.

---

## B1. Per-status-transition history  — CLOSED 2026-05-21

Closed by bough DR-116 (subcommands `node status-history <NANOID>`,
`node status-transitions`, `node created`).  SATAN's `recent_changes`
scope now invokes `bough --json node status-transitions --since` +
`bough --json node created --since` and emits two peer arrays
(`:transitions`, `:created`).  The evidence assembler synthesizes
`:event "status_changed"` per transition row and `:event "created"`
per created row, which wakes the previously-dormant canon rule
`bough.recent_status_change`.

Historical brief retained below for context.

### Original brief

**Today**

`bough --json node tree` supports date filters on `updated_at` and
`created_at` (e.g. `--after updated_at=2026-05-19T00:00:00Z`) but
exposes no notion of *when status changed*. There is no `status_at`
filterable field, and no per-node history endpoint in the CLI.

**Why SATAN cares**

The `recent_changes` scope is meant to answer "which tasks moved
since X?" — the natural input to an evidence window. Without
status-change time, SATAN falls back to "nodes whose `updated_at >=
since`", which is correct but loose: a title rename, an annotation,
or a description edit all look the same as a status transition.

The substrate documents the looser semantics in its tool description
("nodes whose updated_at >= since"). When B1 lands, SATAN tightens
`recent_changes` to literal transitions; the trace schema already
admits `event:status_changed` and pairs like `bough_event:status_changed`.

**Proposed shape (either is sufficient)**

1. New subcommand:
   ```
   bough --json node history <NANOID> [--since ISO8601] [--limit N]
   bough --json node transitions --since ISO8601 [--workspace WS] [--limit N]
   ```
   Returns rows of `{nanoid, from_status, to_status, at, actor?}`.
   The workspace-wide form is what SATAN actually wants for
   `recent_changes`; the per-node form is independently useful for
   audit and would compose with `node`.

2. Or: extend `node tree` with a `status_at` filterable field
   (alongside `updated_at` / `created_at`), and emit one row per
   transition rather than one per node when the filter is active.
   Closer to existing surface area, harder to interpret — option 1
   is preferred.

**Plumbing**

Status changes already write rows somewhere (the TUI shows transition
history); exposing them is a read-path addition, not a model change.

**Status (2026-05-20).** Bough DR-116 in flight at
`~/dev/vk/.spec-driver/deltas/DE-116-bough_cli_per_status_transition_history/DR-116.md`.
Adds three subcommands — `node status-history <NANOID>`,
`node status-transitions`, `node created` — backed by a new
`status_log` table + DB trigger. JSON shape locked (DR-116 §4.5):
flat array DESC by `(at, seq)`, fields `seq, nanoid, from_status,
to_status, at, actor`; `seq BIGSERIAL` is a stable cursor;
`--after-seq N` for incremental polling.  Append-only (D14): rows
survive soft-delete/archive.  Truncation is exit 1 with no partial
JSON (D10).

**SATAN follow-up once DR-116 ships (out of v1 memory scope):**

1. `satan-tools-bough.el:280` (the `recent_changes` scope) —
   replace the `node tree --after updated_at=...` proxy with
   `bough --json node status-transitions --since ...`, or add a
   sibling `status_transitions` scope.
2. `satan-memory-evidence.el:156` — synthesize
   `:event "status_changed"` per status_log row so the dormant canon
   rule `bough.recent_status_change`
   (`satan-memory-canon.el:357`) starts firing.
3. Compose `node created` (DR-116 §D18 peer event feed) alongside
   `status-transitions` for the full "what's new + what moved" view;
   initial-status assignments never appear in the transitions feed
   (DR-116 D2).
4. Close this section (B1) and update `memory/design.md` §10.2.

---

## B2. `--max-depth N` on `node subtree`

> Tracked in the backlog as **IMPR-004** (2026-05-30). Detail below retained as
> the upstream brief.

**Today**

`bough --json node subtree <NANOID>` returns the full subtree with no
depth limit. There is no `--max-depth`, `--level`, or `--limit` flag.

**Why SATAN cares**

The `project_subtree` scope feeds the LLM a bounded view of a
project's structure. SATAN currently fetches the full subtree and
prunes in elisp at a configurable depth (default 3), marking the
truncation point with a `children_truncated_count` field so the
caller knows pruning happened. For small workspaces this is fine.
For larger projects (think: the user's personal task tree across
years), the full-subtree fetch is wasted work and the JSON pipe gets
unnecessarily large before the prune step throws most of it away.

**Proposed shape**

```
bough --json node subtree <NANOID> [--max-depth N]
```

- `--max-depth 0` returns the root only.
- `--max-depth 3` returns root + three levels of children.
- When the limit is hit, each truncated parent gets a
  `children_truncated_count: N` field in the JSON output (mirrors
  what SATAN already does in elisp).
- No flag → today's behaviour (full subtree). Backwards-compatible.

**Plumbing**

Pure server-side filter on tree assembly; no schema change.

---

## Not gaps, recorded for completeness

- `bough day show -d <DATE>` returning `error: day not found` for
  uncreated days is correct and SATAN handles it (the tool translates
  to `ok { day: null }`). No change needed.
- The lack of a `bough week` subcommand is fine; `day list MON SUN`
  composes adequately.
- `node get` returning only the node with `parent_nanoid` (not the
  chain or annotations) is acceptable — SATAN composes with `node
  annotations` and walks parent_nanoid upward. A convenience
  `--with-chain --with-annotations` would be ergonomic but not
  load-bearing; do not prioritise.
