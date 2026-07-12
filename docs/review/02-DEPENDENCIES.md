# 02-DEPENDENCIES.md — Dependency map

## Adjacency list (elisp files only)

Each entry lists `file → [files it `require`s]` (in-project dependencies only; stdlib/external omitted).

| File | Requires (in-project) |
|---|---|
| `dl-satan.el` | `dl-satan-audit`, `dl-satan-budget`, `dl-satan-jsonl`, `dl-satan-block`, `dl-satan-tools`, `dl-satan-tools-org`, `dl-satan-tools-notify`, `dl-satan-tools-hippocampus`, `dl-satan-tools-inbox`, `dl-satan-tools-agenda`, `dl-satan-tools-activity`, `dl-satan-tools-notes`, `dl-satan-tools-docs`, `dl-satan-tools-sway`, `dl-satan-tools-motive`, `dl-satan-memory`, `dl-satan-sensor-alerts`, `dl-satan-mode`, `dl-satan-context`, `dl-satan-output`, `dl-satan-broker`, `dl-satan-tick`, `dl-satan-tools-atsatan`, `dl-satan-patch`, `dl-satan-tank` |
| `dl-satan-audit.el` | `dl-satan-jsonl` |
| `dl-satan-block.el` | *(none)* |
| `dl-satan-broker.el` | `dl-satan-audit`, `dl-satan-budget`, `dl-satan-jsonl`, `dl-satan-protocol`, `dl-satan-tools`, `dl-satan-tools-org`, `dl-satan-mode`, `dl-satan-context`, `dl-satan-output`, `dl-satan-percept`, `dl-satan-resonance`, `dl-satan-motive`, `dl-satan-observer`, `dl-satan-sensor-alerts` |
| `dl-satan-budget.el` | `dl-satan-jsonl` |
| `dl-satan-context.el` | `dl-notes-paths`, `dl-denote-journal`, `dl-satan-percept`, `dl-satan-resonance`, `dl-satan-motive`, `dl-satan-sensor-alerts` |
| `dl-satan-jsonl.el` | *(none)* |
| `dl-satan-memory.el` | `dl-satan-memory-grammar`, `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-store`, `dl-satan-memory-migrate`, `dl-satan-tools-bough`, `dl-satan-tools-memory` |
| `dl-satan-memory-canon.el` | `dl-satan-memory-grammar` |
| `dl-satan-memory-evidence.el` | `dl-satan-tools-activity`, `dl-satan-tools-bough` |
| `dl-satan-memory-grammar.el` | *(none)* |
| `dl-satan-memory-migrate.el` | *(none)* |
| `dl-satan-memory-store.el` | `dl-satan-memory-grammar` |
| `dl-satan-mode.el` | `dl-notes-paths` |
| `dl-satan-motive.el` | `dl-notes-paths` |
| `dl-satan-observer.el` | `dl-satan-jsonl`, `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-grammar`, `dl-satan-memory-store`, `dl-satan-motive` |
| `dl-satan-output.el` | `dl-satan-tools`, `dl-satan-tools-org` |
| `dl-satan-patch.el` | `dl-satan-patch-store`, `dl-satan-patch-worktree`, `dl-satan-patch-adapter`, `dl-satan-patch-prompt`, `dl-satan-patch-classify`, `dl-satan-patch-runner`, `dl-satan-patch-adapter-pi`, `dl-satan-patch-inbox`, `dl-satan-patch-listener`, `dl-satan-tools-patch` |
| `dl-satan-patch-adapter.el` | *(none)* |
| `dl-satan-patch-adapter-pi.el` | `dl-satan-patch-adapter` |
| `dl-satan-patch-classify.el` | *(none)* |
| `dl-satan-patch-inbox.el` | `dl-satan-tools-inbox`, `dl-satan-patch-runner` |
| `dl-satan-patch-listener.el` | `dl-satan-patch-store`, `dl-satan-patch-inbox` |
| `dl-satan-patch-prompt.el` | `dl-notes-paths`, `dl-satan-patch-store`, `dl-satan-patch-worktree` |
| `dl-satan-patch-runner.el` | `dl-satan-patch-store`, `dl-satan-patch-worktree`, `dl-satan-patch-prompt`, `dl-satan-patch-adapter` |
| `dl-satan-patch-store.el` | *(none)* |
| `dl-satan-patch-worktree.el` | `dl-satan-patch-store` |
| `dl-satan-percept.el` | `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-grammar`, `dl-satan-audit` |
| `dl-satan-protocol.el` | *(none)* |
| `dl-satan-resonance.el` | `dl-satan-memory-store` |
| `dl-satan-sensor-alerts.el` | `dl-satan-tools` |
| `dl-satan-tank.el` | `dl-satan-broker`, `dl-satan-memory-evidence`, `dl-satan-memory-store`, `dl-satan-memory-grammar` |
| `dl-satan-tick.el` | `dl-satan-mode`, `dl-satan-context`, `dl-satan-output`, `dl-satan-broker` |
| `dl-satan-tools.el` | `dl-notes-paths` |
| `dl-satan-tools-activity.el` | `dl-satan-tools` |
| `dl-satan-tools-agenda.el` | `dl-satan-tools` |
| `dl-satan-tools-atsatan.el` | `dl-notes-paths`, `dl-satan-tools`, `dl-satan-tick` |
| `dl-satan-tools-bough.el` | `dl-satan-tools` |
| `dl-satan-tools-docs.el` | `dl-satan-tools` |
| `dl-satan-tools-hippocampus.el` | `dl-notes-paths`, `dl-satan-tools`, `dl-satan-memory-grammar`, `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-store` |
| `dl-satan-tools-inbox.el` | `dl-notes-paths`, `dl-satan-tools` |
| `dl-satan-tools-memory.el` | `dl-satan-tools`, `dl-satan-memory-grammar`, `dl-satan-memory-canon`, `dl-satan-memory-evidence`, `dl-satan-memory-store` |
| `dl-satan-tools-motive.el` | `dl-satan-tools`, `dl-satan-motive` |
| `dl-satan-tools-notes.el` | `dl-notes-paths`, `dl-satan-tools` |
| `dl-satan-tools-notify.el` | `dl-satan-tools` |
| `dl-satan-tools-org.el` | `dl-notes-paths`, `dl-denote-journal`, `dl-satan-tools`, `dl-satan-block` |
| `dl-satan-tools-patch.el` | `dl-satan-tools`, `dl-satan-patch-store`, `dl-satan-patch-worktree`, `dl-satan-patch-runner` |
| `dl-satan-tools-sway.el` | `dl-satan-tools` |

## Reverse dependencies (who depends on each module)

| Module | Required by (count) | Required by (files) |
|---|---|---|
| `dl-satan-tools` | **14** | activity, agenda, atsatan, bough, docs, hippo, inbox, memory, motive, notes, notify, org, patch, sway, (sensor-alerts, output, broker, dl-satan) |
| `dl-satan-memory-grammar` | **12** | memory, canon, store, observer, percept, hippo, tools-memory, tools-hippo, tank, (dl-satan-memory) |
| `dl-satan-memory-store` | **8** | memory, observer, resonance, tank, tools-memory, tools-hippo, (dl-satan-memory) |
| `dl-notes-paths` | **8** | context, mode, motive, tools-atsatan, tools-hippo, tools-inbox, tools-notes, tools-org, patch-prompt |
| `dl-satan-audit` | **3** | broker, percept, dl-satan |
| `dl-satan-jsonl` | **3** | audit, broker, budget, observer, dl-satan |
| `dl-satan-memory-canon` | **5** | memory, observer, percept, tools-memory, tools-hippo |
| `dl-satan-memory-evidence` | **5** | memory, observer, percept, tank, tools-memory, tools-hippo |
| `dl-satan-broker` | **3** | tank, tick, dl-satan |
| `dl-satan-context` | **2** | broker, tick, dl-satan |
| `dl-satan-mode` | **2** | broker, tick, dl-satan |
| `dl-satan-output` | **2** | broker, tick, dl-satan |
| `dl-satan-patch-store` | **5** | listener, prompt, runner, tools-patch, patch, worktree |
| `dl-satan-patch-runner` | **3** | inbox, tools-patch, patch |
| `dl-satan-patch-worktree` | **3** | prompt, runner, tools-patch, patch |
| `dl-satan-tick` | **2** | tools-atsatan, dl-satan |
| `dl-denote-journal` | **2** | context, tools-org |
| `dl-satan-block` | **1** | tools-org |
| `dl-satan-percept` | **2** | broker, context |
| `dl-satan-resonance` | **2** | broker, context |
| `dl-satan-motive` | **3** | broker, context, tools-motive |
| `dl-satan-observer` | **1** | broker |
| `dl-satan-sensor-alerts` | **2** | broker, context |
| `dl-satan-protocol` | **1** | broker |
| `dl-satan-budget` | **1** | broker, dl-satan |
| `dl-satan-patch-adapter` | **1** | adapter-pi, patch, runner |
| `dl-satan-patch-adapter-pi` | **1** | patch |
| `dl-satan-patch-prompt` | **1** | runner, patch |
| `dl-satan-patch-classify` | **1** | patch |
| `dl-satan-patch-inbox` | **1** | listener, patch |
| `dl-satan-patch-listener` | **1** | patch |
| `dl-satan-tools-patch` | **1** | patch |
| `dl-satan-tank` | **1** | dl-satan |

## Hubs (required by ≥5 files)

1. **`dl-satan-tools`** — 14 callers (core tool infrastructure)
2. **`dl-satan-memory-grammar`** — 12 callers (shared enums/aliases)
3. **`dl-notes-paths`** — 8 callers (shared note path resolution)
4. **`dl-satan-memory-store`** — 8 callers (PG backend)
5. **`dl-satan-memory-canon`** — 5 callers (canonicalizer)
6. **`dl-satan-memory-evidence`** — 5 callers (evidence assembler)
7. **`dl-satan-patch-store`** — 5 callers (patch job DB)

## Orphans (required by no other file)

- `dl-satan-block.el` — only required by `tools-org` (1 caller, not an orphan)
- `dl-satan-patch-classify.el` — only required by `patch` aggregator
- `dl-satan-patch-adapter.el` — required by `adapter-pi`, `patch`, `runner` (3 callers)

No true orphans found. Every module has at least one consumer.

## Cycles

**No direct dependency cycles detected** from the `require` graph. The dependency tree is a DAG.

Potential **runtime cycles** (A calls B's private symbols without requiring B — see coupling analysis):

- `dl-satan-broker.el` calls many private symbols from percept, resonance, motive, observer, sensor-alerts, output, context, mode — these are the correct programming model (broker orchestrates), not cycles per se.
- `dl-satan-context.el` requires `dl-satan-percept`, `dl-satan-resonance`, `dl-satan-motive`, `dl-satan-sensor-alerts` — broker-like aggregation in context assembly.

## Architectural notes

The dependency graph aligns with the architecture doc:
- **Core infrastructure**: `dl-satan-tools`, `dl-satan-jsonl`, `dl-satan-protocol`, `dl-satan-audit` — broad but shallow dependencies
- **Memory substrate**: Grammar → Canon → Evidence → Store — linear chain, clean layering
- **Patch agent**: Store → Worktree → Prompt → Runner → Adapter → Inbox — linear chain
- **Perceptual layer**: Percept → Resonance → Motive → Observer → Sensor-alerts — all pull from memory substrate
- **Broker**: Central hub requiring 14 modules; called by 3 (tank, tick, dl-satan)
- **Aggregators**: `dl-satan.el` (25 requires) and `dl-satan-patch.el` (10 requires) load-everything bootstrap files

The `dl-notes-paths` and `dl-denote-journal` dependencies sit outside `satan/` (in `core/` and `org/`), which is expected for an Emacs config that reads notes paths and journal files.
