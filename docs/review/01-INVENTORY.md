# 01-INVENTORY.md — File inventory

## Source files

| Path | LOC | Purpose | Exports (count) | Test file | Notes |
|---|---|---|---|---|---|
| `satan/dl-satan.el` | 51 | Aggregator + `my/satan-run` interactive entry | 1 (`provide 'dl-satan`) | `test/dl-satan-test.el` | Load-everything aggregator; 25 `require` calls |
| `satan/dl-satan-audit.el` | 291 | Append-only run artifact writer + 6-predicate verifier | 19 defuns | `test/dl-satan-test.el` | Audit writer + `dl-satan-audit-verify-run` |
| `satan/dl-satan-block.el` | 117 | Owned-block find/replace (`#+begin_satan`) | 6 defuns | `test/dl-satan-test.el` | Refuses multi-match; creates-at-end |
| `satan/dl-satan-broker.el` | 797 | `make-process` driver: sentinel, timeout, direnv, tool dispatch | 35 defuns | `test/dl-satan-test.el` | **Largest .el file**; orchestrates full run lifecycle |
| `satan/dl-satan-budget.el` | 77 | Daily token ceiling gate | 4 defuns | `test/dl-satan-test.el` | Pre-spawn budget check; sums today's runs |
| `satan/dl-satan-context.el` | 526 | Per-mode bundle assembly, prompt rendering, recent-runs block | 25 defuns | `test/dl-satan-context-test.el` | Imports percept, resonance, motive, sensor-alerts |
| `satan/dl-satan-jsonl.el` | 98 | Line-buffered filter + writer + `dl-satan-jsonl-prepare` | 5 defuns | `test/dl-satan-test.el` | Walks payloads coercing lists→vectors |
| `satan/dl-satan-memory.el` | 140 | Memory aggregator + `my/satan-memory-*` interactive commands | 6 defuns | — | Aggregator, no dedicated test file |
| `satan/dl-satan-memory-canon.el` | 570 | Canonicalizer + rule registry (PURE — grep-lint enforced) | 14 defuns | `test/dl-satan-memory-canon-test.el` | Purity boundary; 33 ert |
| `satan/dl-satan-memory-evidence.el` | 560 | Impure evidence-window assembly (panopticon, bough, git) | 25 defuns | `test/dl-satan-memory-evidence-test.el` | Impure counterpart to canon |
| `satan/dl-satan-memory-grammar.el` | 162 | Closed-world enums, alias seed, default weights | 6 defuns | `test/dl-satan-memory-grammar-test.el` | Grammar v1 constants |
| `satan/dl-satan-memory-migrate.el` | 496 | Forward-only migration runner + renormalize CLI | 22 defuns | `test/dl-satan-memory-migrate-test.el` | Handles 5 SQL migrations |
| `satan/dl-satan-memory-store.el` | 372 | PG store: mark/resonate/show via psql subprocess | 8 defuns | `test/dl-satan-memory-store-test.el` | psql subprocess communication |
| `satan/dl-satan-mode.el` | 149 | Mode registry: morning, motd, self-edit-{mech,mind}, tick-* | 5 defuns | — | No dedicated test file |
| `satan/dl-satan-motive.el` | 626 | Motive file reader, resolver, renderer, cooldown | 22 defuns | `test/dl-satan-motive-test.el` | Perceptual layer v0 |
| `satan/dl-satan-observer.el` | 859 | Outcome observer: verdict, persistence, broker integration | 33 defuns | `test/dl-satan-observer-test.el` | **Largest file**; Phase 5 of perceptual layer |
| `satan/dl-satan-output.el` | 90 | Mode output handlers (morning, motd, tick, self-edit) | 6 defuns | — | No dedicated test file |
| `satan/dl-satan-patch.el` | 20 | Patch-agent aggregator (load-everything) | 1 defun | — | Bootstrap file; 10 `require` calls |
| `satan/dl-satan-patch-adapter.el` | 85 | Abstract patch adapter base | 4 defuns | `test/dl-satan-patch-adapter-test.el` | Protocol for pi/other adapters |
| `satan/dl-satan-patch-adapter-pi.el` | 314 | Pi coding-agent adapter (resolved-env, stdin EOF, system-prompt) | 7 defuns | — | pi-specific; real harness integration |
| `satan/dl-satan-patch-classify.el` | 87 | Patch-shaped work classifier | 3 defuns | `test/dl-satan-patch-classify-test.el` | Routes tool-dispatch vs patch-shaped |
| `satan/dl-satan-patch-inbox.el` | 120 | Inbox handoff for completed patch jobs | 3 defuns | `test/dl-satan-patch-inbox-test.el` | Writes patch-ready headlines |
| `satan/dl-satan-patch-listener.el` | 198 | PG LISTEN → inbox handoff (opt-in) | 9 defuns | `test/dl-satan-patch-listener-test.el` | Async PG notification listener |
| `satan/dl-satan-patch-prompt.el` | 173 | Job prompt assembly from mode, store, worktree | 6 defuns | — | No dedicated test file |
| `satan/dl-satan-patch-runner.el` | 297 | Patch job runner: lifecycle, sentinel, timeout | 13 defuns | `test/dl-satan-patch-runner-test.el` | Core orchestrator for patch jobs |
| `satan/dl-satan-patch-store.el` | 396 | Patch job DB store (PG) | 7 defuns | `test/dl-satan-patch-store-test.el` | CRUD over `patch_jobs` table |
| `satan/dl-satan-patch-worktree.el` | 281 | Git worktree creation/cleanup | 12 defuns | `test/dl-satan-patch-worktree-test.el` | Worktree management |
| `satan/dl-satan-percept.el` | 137 | Percept capsule assembly | 6 defuns | `test/dl-satan-percept-test.el` | Phase 1 of perceptual layer |
| `satan/dl-satan-protocol.el` | 173 | JSONL protocol validator + fixture loader | 16 defuns | `test/dl-satan-test.el` | Shared validators |
| `satan/dl-satan-resonance.el` | 141 | Auto-resonance engine | 4 defuns | `test/dl-satan-resonance-test.el` | Phase 2 of perceptual layer |
| `satan/dl-satan-sensor-alerts.el` | 398 | Sensor alerts: reading, dedup, rendering | 20 defuns | `test/dl-satan-sensor-alerts-test.el` | Phase 4 of perceptual layer |
| `satan/dl-satan-tank.el` | 554 | Observation tank: reading, rendering, aggregating | 28 defuns | `test/dl-satan-tank-test.el` | Framework; requires broker, memory-evidence, memory-store |
| `satan/dl-satan-tick.el` | 120 | Tick mode family: weighted picker, quiet-hours, register | 4 defuns | — | No dedicated test file |
| `satan/dl-satan-tools.el` | 325 | Tool registry, dispatch, schema validator, JSON-Schema builder | 16 defuns | `test/dl-satan-test.el` | Core tool infrastructure |
| `satan/dl-satan-tools-activity.el` | 148 | `activity_read` tool (panopticon consumer) | 5 defuns | — | Read-only tool |
| `satan/dl-satan-tools-agenda.el` | 94 | `agenda_read` tool (gcalcli) | 2 defuns | — | Read-only, timeout-wrapped |
| `satan/dl-satan-tools-atsatan.el` | 392 | `@satan` directive scanning, claiming, tick-agent registration | 13 defuns | `test/dl-satan-tools-atsatan-test.el` | Cross-cutting: scans notes for directives |
| `satan/dl-satan-tools-bough.el` | 354 | `bough_read` tool (shell-out to `bough --json`) | 17 defuns | `test/dl-satan-tools-bough-test.el` | Read-only; 6 scopes |
| `satan/dl-satan-tools-docs.el` | 250 | `docs_list`, `docs_search`, `docs_read` | 12 defuns | `test/dl-satan-tools-docs-test.el` | Lazy lookup over doc chunks |
| `satan/dl-satan-tools-hippocampus.el` | 153 | `hippocampus_write` + auto_rule cross-ref | 5 defuns | `test/dl-satan-tools-hippocampus-test.el` | Cross-ref hook via memory-store |
| `satan/dl-satan-tools-inbox.el` | 121 | `inbox_append` + interactive commands | 5 defuns | — | No dedicated test file |
| `satan/dl-satan-tools-memory.el` | 311 | `memory_mark`, `memory_resonate`, `memory_show_trace` handlers | 12 defuns | `test/dl-satan-tools-memory-test.el` | Entry points for memory operations |
| `satan/dl-satan-tools-motive.el` | 110 | `motive_read` tool | 5 defuns | `test/dl-satan-tools-motive-test.el` | |
| `satan/dl-satan-tools-notes.el` | 184 | `notes_recent` tool | 8 defuns | — | No dedicated test file |
| `satan/dl-satan-tools-notify.el` | 59 | `notify_send` tool (D-Bus) | 1 defun | — | Simplest tool file |
| `satan/dl-satan-tools-org.el` | 164 | `org_read_context`, `org_update_owned_block`, `proposal_stage` | 7 defuns | — | No dedicated test file |
| `satan/dl-satan-tools-patch.el` | 327 | `patch_job_*` broker-facing tools | 9 defuns | `test/dl-satan-tools-patch-test.el` | Tool handlers wrapping patch-store + patch-runner |
| `satan/dl-satan-tools-sway.el` | 150 | `sway_border_set`, `sway_border_reset` | 4 defuns | `test/test-sway-border.el` | Ephemeral Sway IPC |

### Python harness

| Path | LOC | Purpose | Test file |
|---|---|---|---|
| `harness/__main__.py` | 36 | Entrypoint: sys.path bootstrap + `main` | — |
| `harness/bundle.py` | 46 | `load_bundle` / `load_manifest` / `build_system_prompt` / `build_tools` | — |
| `harness/protocol.py` | 237 | JSONL validator + `emit*` / `read_tool_result` | `test_gptel_harness.py` |
| `harness/providers/__init__.py` | 50 | `build_provider` registry | — |
| `harness/providers/base.py` | 87 | `Provider` ABC | — |
| `harness/providers/deepseek.py` | 15 | DeepSeek provider (minimal) | — |
| `harness/providers/openrouter.py` | 9 | OpenRouter provider (minimal) | — |
| `harness/runloop.py` | 185 | Turn loop + budget guard + tool-call dispatch | — |
| `harness/test_gptel_harness.py` | 442 | stdlib unittest cases (no network) | self |

### SQL migrations

| Path | LOC | Purpose |
|---|---|---|
| `memory/migrations/0001_init.sql` | 123 | Substrate schema §6.2 |
| `memory/migrations/0002_grammar_v1.sql` | 47 | v1 grammar seed |
| `memory/migrations/0003_memory_functions.sql` | 185 | Store functions |
| `memory/migrations/0004_grammar_v2_fixture.sql` | 27 | Operator-applied v2 fixture |
| `memory/migrations/0005_patch_jobs.sql` | 77 | Patch agent job DB schema |

### Shell scripts

| Path | LOC | Purpose |
|---|---|---|
| `bin/satan-run` | 6 | Shell wrapper (`emacsclient --eval`) |
| `bin/satan-run-tick` | 6 | Tick wrapper |

### Protocol fixtures

| Path | LOC | Purpose |
|---|---|---|
| `protocol/fixtures.json` | 281 | Shared valid/invalid protocol fixtures |

### Test canon fixtures

| Path | LOC | Purpose |
|---|---|---|
| `test/canon-fixtures/minimal_firefox.json` | 20 | Minimal canon golden test |
| `test/canon-fixtures/rich_window.json` | 74 | Rich canon golden test |

**Totals**: 48 `.el` source files (~14,011 LOC), 9 Python files (~1,107 LOC), 1 `.json` fixture (281 LOC), 5 SQL migrations (459 LOC), 2 shell scripts (12 LOC), 2 canon JSON fixtures (94 LOC).
