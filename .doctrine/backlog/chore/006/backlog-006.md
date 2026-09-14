# CHR-006: Retarget ~/notes/satan paths in docs/ prose to ~/satan and the state root (SL-015 follow-up)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

SL-015 moved SATAN's model-facing corpus from `~/notes/satan/` to `~/satan/`
(its own repo) and runtime state (`runs/`, `log/wpm/`) to
`~/.local/state/satan/`. Design D9 kept prose inside the code repo out of the
cutover: these docs are not read by the model, so a stale path there misleads
a human reader but breaks nothing. PHASE-04 retargeted only the production
docstrings (`566969e`) and `docs/perceptual-design.md` (`b6c5845`).

Remaining `notes/satan` lines under `docs/` (measured 2026-09-14):

| File | Lines |
|---|---|
| `docs/governance.md` | 31 |
| `docs/data-collection.md` | 20 |
| `docs/at-satan/design.md` | 12 |
| `docs/patch/archive/handover-phase3-mechanism.md` | 9 |
| `docs/patch/plan.md` | 7 |
| `docs/at-satan/plan.md` | 7 |
| `docs/patch/handover.md` | 4 |
| `docs/patch/brief.md` | 3 |
| `docs/review/CODE_REVIEW.md` | 2 |
| `docs/review/00-CONTEXT.md` | 2 |
| `docs/memory/design.md` | 2 |
| `docs/review/THEMES.md` | 1 |
| `docs/review/12-HARNESS-BOUNDARY.md` | 1 |
| `docs/refactor/T3-capsule-registry.md` | 1 |
| `docs/protocol.md` | 1 |
| `docs/memory/handover.md` | 1 |

Mapping: corpus content (`prompts/`, `system/`, `tools/`, `hippocampus/`,
`motives*.org`, `inbox.org`, `patch-agent/`) → `~/satan/…`; `runs/` and
`log/wpm/` → `~/.local/state/satan/…`. Where a doc explains a mechanism, prefer
naming the defcustom (`satan-corpus-root`, `satan-state-root`) over a literal
path, as the docstrings now do.

Some hits are historical (review snapshots, handovers, archived plans) —
decide per file whether it is living documentation or a dated record; dated
records may stay as written.
