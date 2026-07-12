# 10-LAYER-MAP.md — File-to-layer mapping

Per `architecture.md`, the seven canonical layers are:
**Invocation** / **Broker** / **Harness** / **Model** / **Tool** / **Output** / **State**

| File | LOC | Layer(s) | Notes |
|---|---|---|---|
| `dl-satan.el` | 51 | **Invocation** | Aggregator + `my/satan-run` |
| `bin/satan-run` | 6 | **Invocation** | Shell wrapper |
| `bin/satan-run-tick` | 6 | **Invocation** | Tick wrapper |
| `dl-satan-tick.el` | 120 | **Invocation**, **Broker** | Tick registration + invocation |
| `dl-satan-broker.el` | 797 | **Broker** | Core orchestration (mode, dispatch, lifecycle) |
| `dl-satan-context.el` | 526 | **Broker** | Bundle assembly + prompt rendering |
| `dl-satan-mode.el` | 149 | **Broker** | Mode registry |
| `dl-satan-audit.el` | 291 | **Output**, **State** | Run artifact writer + verifier |
| `dl-satan-budget.el` | 77 | **Broker** | Daily token ceiling (pre-spawn gate) |
| `dl-satan-jsonl.el` | 98 | **State** | JSON line handler |
| `dl-satan-protocol.el` | 173 | **Broker** | Protocol validator (membrane) |
| `dl-satan-block.el` | 117 | **Output** | Owned-block find/replace |
| `dl-satan-output.el` | 90 | **Output** | Mode output handlers |
| `dl-satan-tools.el` | 325 | **Tool** | Tool registry, dispatch, schema validator |
| `dl-satan-tools-org.el` | 164 | **Tool** | org_read_context, org_update_owned_block, proposal_stage |
| `dl-satan-tools-notify.el` | 59 | **Tool** | notify_send |
| `dl-satan-tools-hippocampus.el` | 153 | **Tool**, **State** | hippocampus_write + cross-ref |
| `dl-satan-tools-inbox.el` | 121 | **Tool** | inbox_append |
| `dl-satan-tools-agenda.el` | 94 | **Tool** | agenda_read |
| `dl-satan-tools-activity.el` | 148 | **Tool** | activity_read |
| `dl-satan-tools-notes.el` | 184 | **Tool** | notes_recent |
| `dl-satan-tools-docs.el` | 250 | **Tool** | docs_list, docs_search, docs_read |
| `dl-satan-tools-sway.el` | 150 | **Tool** | sway_border_set, sway_border_reset |
| `dl-satan-tools-bough.el` | 354 | **Tool** | bough_read |
| `dl-satan-tools-memory.el` | 311 | **Tool**, **State** | memory_mark, memory_resonate, memory_show_trace |
| `dl-satan-tools-motive.el` | 110 | **Tool**, **Broker** | motive_read |
| `dl-satan-tools-atsatan.el` | 392 | **Tool**, **Broker** | @satan directive scanning + claiming |
| `dl-satan-tools-patch.el` | 327 | **Tool** | patch_job_* tools |
| `dl-satan-memory.el` | 140 | **State** | Memory aggregator + interactive commands |
| `dl-satan-memory-grammar.el` | 162 | **State** | Grammar enums |
| `dl-satan-memory-canon.el` | 570 | **State** | Canonicalizer + rules |
| `dl-satan-memory-evidence.el` | 560 | **State** | Evidence-window assembly |
| `dl-satan-memory-store.el` | 372 | **State** | PG store backend |
| `dl-satan-memory-migrate.el` | 496 | **State** | Migration runner |
| `dl-satan-percept.el` | 137 | **Broker**, **State** | Percept capsule (uses memory substrate) |
| `dl-satan-resonance.el` | 141 | **Broker** | Auto-resonance (uses memory-store) |
| `dl-satan-motive.el` | 626 | **Broker** | Motive file reader/renderer |
| `dl-satan-observer.el` | 859 | **Broker**, **Output**, **State** | Outcome observer (spans three layers) |
| `dl-satan-sensor-alerts.el` | 398 | **Broker** | Sensor alert assembly |
| `dl-satan-tank.el` | 554 | **Broker**, **State** | Observation tank (bridges broker + state) |
| `dl-satan-patch.el` | 20 | **Invocation** | Patch-agent aggregator |
| `dl-satan-patch-adapter.el` | 85 | **Harness** | Abstract adapter base |
| `dl-satan-patch-adapter-pi.el` | 314 | **Harness** | Pi coding-agent adapter |
| `dl-satan-patch-classify.el` | 87 | **Broker** | Work classification |
| `dl-satan-patch-inbox.el` | 120 | **Output** | Inbox handoff |
| `dl-satan-patch-listener.el` | 198 | **Broker** | PG LISTEN listener |
| `dl-satan-patch-prompt.el` | 173 | **Broker** | Job prompt builder |
| `dl-satan-patch-runner.el` | 297 | **Broker** | Job runner (lifecycle, sentinel) |
| `dl-satan-patch-store.el` | 396 | **State** | Patch job DB store |
| `dl-satan-patch-worktree.el` | 281 | **State** | Git worktree management |

## Python harness files

| File | LOC | Layer(s) | Notes |
|---|---|---|---|
| `harness/__main__.py` | 36 | **Harness** | Entrypoint |
| `harness/bundle.py` | 46 | **Harness** | Bundle/manifest loading |
| `harness/protocol.py` | 237 | **Broker** (membrane) | JSONL validator (mirrors elisp) |
| `harness/providers/__init__.py` | 50 | **Harness** | Provider registry |
| `harness/providers/base.py` | 87 | **Harness** | Provider ABC |
| `harness/providers/deepseek.py` | 15 | **Harness** | DeepSeek adapter |
| `harness/providers/openrouter.py` | 9 | **Harness** | OpenRouter adapter |
| `harness/runloop.py` | 185 | **Harness** | Turn loop + dispatch |

## Cross-layer observations

### Files spanning multiple layers

1. **`dl-satan-observer.el`** (Broker + Output + State) — 859 LOC, spans 3 layers. Contains classification logic (broker), persistence (state), and integration (output). This is the widest span.

2. **`dl-satan-tank.el`** (Broker + State) — bridges broker audit data with memory substrate data. Two distinct data domains in one file.

3. **`dl-satan-tools-hippocampus.el`** (Tool + State) — tool handler that also writes memory traces via cross-ref hook.

4. **`dl-satan-tools-memory.el`** (Tool + State) — tool handlers wrapping memory substrate.

5. **`dl-satan-tools-atsatan.el`** (Tool + Broker) — tool + mode registration side effects.

6. **`dl-satan-tools-motive.el`** (Tool + Broker) — tool handler + broker-side renderer.

7. **`dl-satan-percept.el`** (Broker + State) — reads memory substrate for percept assembly.

8. **`dl-satan-audit.el`** (Output + State) — both writes artifacts and verifies them.

### Files cleanly within a single layer

- **Invocation**: `dl-satan.el`, `bin/satan-run`, `bin/satan-run-tick`
- **Tool**: `dl-satan-tools.el`, `tools-org.el`, `tools-notify.el`, `tools-inbox.el`, `tools-agenda.el`, `tools-activity.el`, `tools-notes.el`, `tools-docs.el`, `tools-sway.el`, `tools-bough.el`, `tools-patch.el`
- **State**: All `dl-satan-memory-*.el` files (grammar, canon, evidence, store, migrate)
- **Harness (python)**: All `harness/*.py` files
- **Harness (elisp)**: `dl-satan-patch-adapter.el`, `dl-satan-patch-adapter-pi.el`

### Tool-to-layer ratio

14 tool files (`dl-satan-tools*.el`) × avg ~180 LOC = ~2520 LOC of tool infrastructure. This is the largest single-layer code volume, consistent with SATAN's tool-oriented architecture.
