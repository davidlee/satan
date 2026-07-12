# 07-CORRECTNESS-SNIFFS.md — Correctness sniff test

## TODO / FIXME / XXX / HACK inventory

**No TODO, FIXME, XXX, or HACK comments found in any SATAN source files.** This is unusual for a codebase of ~14k LOC and 48 files. Possible explanations:
1. Rigorous cleanup policy (consistent with governance doc's quality ethos)
2. Comments use different markers (e.g., `;; FIXME: ` with different formatting)
3. Unresolved items tracked externally (CHANGELOG, handover docs, GitHub)

The CHANGELOG and handover docs track open issues (e.g., patch-agent PATH resolution, supervisor pivot question, `patch_job_cancel` not killing processes). These are surfaced in `99-QUESTIONS.md`.

confidence: high — confirmed via grep that no source file contains any of these markers.

## Error paths

### Swallowed errors

`dl-satan-tools-hippocampus.el` — cross-ref errors are soft-logged via `message`; the file write is load-bearing and never gated on substrate availability. Governance docs say "Cross-ref errors are soft-logged via message" (handover.md). This is intentional but means the `auto_rule` trace can silently fail while the org file write succeeds.

  `dl-satan-tools-hippocampus.el` — cross-ref implementation
  confidence: high — documented design choice.

`dl-satan-observer.el` — per-iv errors caught; loop continues. `observer-process` takes care to catch per-intervention errors so one bad intervention doesn't crash the cycle. This is good error handling.

  `dl-satan-observer.el:721` — `observer-process`
  confidence: high — intentional resilience.

### Timeout handling

`dl-satan-tools-agenda.el` wraps gcalcli in `timeout(1)`. This prevents a stalled gcalcli from freezing the broker. Good pattern.

  `dl-satan-tools-agenda.el` — timeout-wrapped gcalcli
  confidence: high

### Process lifecycle

`dl-satan-broker.el` drives `make-process` with explicit timeout timer. Sentinel handles various exit conditions (timeout, failure, success). This is the broker's core job and appears well-implemented.

  `dl-satan-broker.el:638` — `broker--spawn` (158 LOC)
  confidence: high — central, well-tested path.

## Multi-shape returns

Not systematically checked. Functions that return multiple types (some nil, some list, some error shape) are a potential signal. Key suspects to check manually:

- `dl-satan-broker--spawn` — returns `process-status` on failure, `nil` on success? Check at line 638.
- `dl-satan-patch-store--parse-row` — returns different shapes based on input column presence (238 LOC function).
- `dl-satan-motive--cooling-down-remaining` — returns nil when cooling down not applicable, seconds otherwise.

  confidence: low — spot-check these specific functions.

## Skipped/disabled tests

Not verified. Check `ert` test files for `:expected-result :failed` or conditional skip (`skip-unless`). Known pattern: integration test skips unless `SATAN_TEST_JAIL_BIN` is set.

  confidence: medium — integration test in `dl-satan-integration-test.el` uses `skip-unless`.

## Error context in re-raises

Not systematically checked. Common pattern in elisp: `(error "msg")` with no added context from the catch site. Key files to check:
- `dl-satan-memory-store.el` — psql subprocess calls
- `dl-satan-patch-worktree.el` — git operations (worktree create, commit)

  confidence: low — spot-check psql error paths for context propagation.
