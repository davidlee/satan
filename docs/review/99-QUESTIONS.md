# 99-QUESTIONS.md — Unresolved questions

These are places where I was unsure, deferred judgement, or saw ambiguous signal. The architect should resolve.

## Architecture/layering

1. **`dl-satan-observer.el` spans 3 layers (Broker + Output + State).** At 859 LOC, it's the largest file. The governance doc says the broker "owns" output and audit, but the observer writes memory traces and touches motive files independently. Is this observer→motive→store chain a natural extension of the broker, or should it be refactored into a separate "observer layer"?
   Evidence: `observer.el:25-32` requires 6 modules spanning 3 layers.

2. **`dl-satan-tank.el` bridges broker and memory substrate.** It requires `dl-satan-broker` (orchestration) and `dl-satan-memory-evidence`/`store` (state). The tank reads audit data AND memory substrate data. Is this cross-layer bridging intended, or should the tank be split into an audit-tank and a memory-tank?
   Evidence: `tank.el:24-27` — requires broker, evidence, store, grammar.

3. **`dl-satan-context.el` imports from the perceptual layer** (percept, resonance, motive, sensor-alerts). Context assembly is meant to be a "broker layer" concern, but it now assembles perceptual blocks. Is context becoming a second orchestration hub?
   Evidence: `context.el:10-15` — 4 perceptual-layer requires.

## Governance doc drift

4. **Governance.md tool table vs actual implementation.** The governance doc lists 15 tools. There are at least 22 elisp-registered tools plus `notes_recent`, `motive_read`, and 4 `patch_job_*` tools not in the governance tool table. Is the governance doc simply lagging, or are these tools intentionally undocumented?
   Evidence: governance.md §Tools vs `dl-satan-tools.el` registry + `dl-satan-tools-notes.el` + `dl-satan-tools-motive.el` + `dl-satan-tools-patch.el`.

## Patch-agent

5. **`patch_job_cancel` doesn't kill the process.** The handover doc says cancel only updates the DB row to `cancelled` but the runner's `_active` slot and live bwrap process keep running. Is this acceptable for v1 or a blocker?
   Evidence: handover.md §Open issues #2.

6. **PATH resolution for `jailed-pi`** remains unresolved. When invoked from emacsclient eval or timer fire without direnv env loaded, `executable-find` returns nil. The handover doc suggests a resolver but none is committed. Is a cached absolute path (via `direnv exec`) acceptable, or should the supervisor pivot be considered first?
   Evidence: handover.md §Open issues #1.

7. **Patch-job acceptance never achieved end-to-end.** The handover doc records "last observed acceptance run" failed due to `--system-prompt-file` flag (since fixed) and then PATH resolution. A clean `needs_review` row with commits has not been observed. Is this a priority to fix, or is the patch-agent in a "good enough" state for manual invocation from direnv-loaded buffers?
   Evidence: handover.md "Where things stand" + "§4.6 acceptance still owed".

## Memory substrate

8. **`dl-satan-memory-canon-normalize-hints` (296 LOC).** This is the largest single function in the codebase. I did not read it end-to-end. Is its size justified by the complexity of the canonicalization rules, or does it hold a large data/pattern-match structure that could be split?
   Evidence: `memory-canon.el:190` — 296-LOC function.

9. **`dl-satan-patch-store--parse-row` (238 LOC).** Another very large function. Row parsing from PostgreSQL. Does the size come from handling multiple column combinations, or is there structural factoring opportunity?
   Evidence: `patch-store.el:157` — 238-LOC function.

## Tool registry

10. **Tool `:modes` field is documentary only.** The handover says the broker doesn't consult it; the real gate is the mode's `:tools` list. Two sources of truth for tool→mode mapping. Is the `:modes` field dead documentation, or should it be made authoritative (or removed)?
    Evidence: handover.md "Tool-spec `:modes` is documentary only; the broker does not consult it."

## Cross-module private access

11. **Several files call private (`--`) symbols from other modules.** The broker calls `--` symbols from percept, resonance, motive, observer, sensor-alerts. The observer calls `--` symbols from motive. This is by design for the broker hub pattern, but module boundaries are soft. Is there a policy on when `--` access is acceptable vs. when it signals a missing public API?
    Evidence: coupling analysis in 05-COUPLING.md.

## defcustom consolidation

12. **Defcustoms are spread across ~30 files** with a max of 8 in one file (`memory-evidence.el`). No obvious grouping issues, but total defcustom count wasn't checked. Is there a convention on defcustom placement when multiple files share a tunable?
    Evidence: defcustom count per file in 03-SIZE.md (15+ files with defcustoms).

## Test coverage

13. **`dl-satan-test.el` (2337 LOC)** is a monolithic test file covering ~15 modules. Is this acceptable technical debt, or should it be split into per-module test files (matching the memory substrate pattern)?
    Evidence: 08-TESTABILITY.md — 2337 LOC shared test file.

14. **`dl-satan-patch-adapter-pi.el`** has no test file at all. It contains the pi coding-agent integration (env resolution, sentinel, stdin EOF handling). Is this a testing gap that should be addressed before relying on the patch-agent for real work?
    Evidence: 08-TESTABILITY.md — adapter-pi untested.

## Protocol / harness

15. **Pi adapter env contract is implicit.** The `dl-satan-patch-adapter-pi-api-key-vars` list (7 API keys) is hardcoded in elisp. The pi coding agent must be configured to read these same env vars. There's no shared spec between the two. Is this acceptable for an internal integration?
    Evidence: handover.md Op-cache path port section.
