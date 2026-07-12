# 08-TESTABILITY.md — Testability observations

## Coverage shape (structural gaps — NOT line-coverage numbers)

### Source files without dedicated test files

| File | LOC | Test coverage | Gaps |
|---|---|---|---|
| `dl-satan-mode.el` | 149 | Via shared `dl-satan-test.el` | Mode specs not tested individually |
| `dl-satan-output.el` | 90 | Via shared `dl-satan-test.el` | Output handlers not independently tested |
| `dl-satan-tick.el` | 120 | Via shared `dl-satan-test.el` | Tick registration, quiet-hours not isolated |
| `dl-satan-tools-activity.el` | 148 | Via shared `dl-satan-test.el` | Activity tool handler not isolated |
| `dl-satan-tools-agenda.el` | 94 | Via shared `dl-satan-test.el` | Agenda tool (gcalcli) untestable offline |
| `dl-satan-tools-inbox.el` | 121 | Via shared `dl-satan-test.el` | Inbox tool not isolated |
| `dl-satan-tools-notes.el` | 184 | Via shared `dl-satan-test.el` | Notes tool not isolated |
| `dl-satan-tools-notify.el` | 59 | Via shared `dl-satan-test.el` | Notifications untestable in batch |
| `dl-satan-tools-org.el` | 164 | Via shared `dl-satan-test.el` | Org tools depend on notes tree |
| `dl-satan-tools-sway.el` | 150 | Via `test-sway-border.el` | Sway IPC untestable offline |
| `dl-satan-patch-adapter-pi.el` | 314 | **No test file** | pi adapter — env resolution, sentinel untested |
| `dl-satan-patch-prompt.el` | 173 | **No test file** | Prompt builder untested |
| `dl-satan-patch.el` | 20 | **No test file** | Trivial aggregator |
| `dl-satan-memory.el` | 140 | Via shared `dl-satan-test.el` | Aggregator; commands untested in isolation |

**3 files** have no test coverage at all (`adapter-pi`, `patch-prompt`, `patch`). The remaining ~15 share the monolithic `dl-satan-test.el`.

### Monolithic test file

`test/dl-satan-test.el` at **2337 LOC** contains tests for approximately 15 modules. This is the largest file in the entire `satan/` tree. Tests are interleaved by module but not clearly sectioned. A maintenance burden:
- Hard to find relevant tests
- Runs all tests even when only one module changed
- Module-specific setup/teardown mixed together

  confidence: high — 2337 LOC is excessive for a single test file.

### Memory substrate test coverage (well-structured)

The memory substrate has excellent test isolation:
- `test/dl-satan-memory-migrate-test.el` — 9 ert (migration runner)
- `test/dl-satan-memory-grammar-test.el` — 6 ert (grammar + DB sync)
- `test/dl-satan-memory-canon-test.el` — 33 ert (canonicalizer + purity + lint)
- `test/dl-satan-memory-evidence-test.el` — 16 ert (evidence assembly)
- `test/dl-satan-memory-store-test.el` — 18 ert (store backend)
- `test/dl-satan-tools-memory-test.el` — 28 ert (tool handlers)
- `test/dl-satan-memory-renormalize-test.el` — 6 ert (renormalize CLI)
- `test/dl-satan-tools-hippocampus-test.el` — 3 ert (cross-ref)

Each has its own file, clear scope, and DB test database pattern.

  confidence: high — 119 ert for memory substrate alone.

### Patch-agent test coverage (incomplete)

- `test/dl-satan-patch-adapter-test.el` — 67 LOC (abstract adapter)
- `test/dl-satan-patch-classify-test.el` — 56 LOC
- `test/dl-satan-patch-inbox-test.el` — 109 LOC
- `test/dl-satan-patch-listener-test.el` — 196 LOC
- `test/dl-satan-patch-runner-test.el` — 369 LOC
- `test/dl-satan-patch-store-test.el` — 303 LOC
- `test/dl-satan-patch-worktree-test.el` — 226 LOC
- `test/dl-satan-tools-patch-test.el` — 247 LOC

No tests for `adapter-pi` (real pi integration) or `patch-prompt` (prompt builder). The runner tests exist but the handover notes indicate acceptance hasn't been achieved yet (no clean `needs_review` end-to-end).

  confidence: high — patch-agent has test scaffolding but real-harness integration is untested.

### Happy-path bias

Likely high: the shared test file (`dl-satan-test.el`) exercises tool registration, dispatch, schemas — mostly happy-path. Error paths (timeouts, denials, schema validation failures) are covered where they're cheap to test (protocol validation via fixtures).

  confidence: medium — not verified line-by-line.

### External dependencies required for tests

- PostgreSQL (`satan_memory_test` DB) — required for memory substrate tests; `skip-unless` when DB unreachable
- `bough` CLI — required for bough tests
- Bubblewrap-jailed harness — required for integration test (skips when `SATAN_TEST_JAIL_BIN` unset)
- Panopticon data directory — required for evidence tests

These are natural dependencies for a system that integrates with these components. The `skip-unless` pattern is used consistently.
