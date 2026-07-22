# SATAN tick performance: observe and bound

> **Imported 2026-07-22** from the `.emacs.d` doctrine corpus, frozen for SATAN.
> Ids cited below resolve in that corpus unless they also exist here; `DE-`/`DR-`
> have no doctrine equivalent, and `IMPR-NNN` / `ISSUE-NNN` are pre-doctrine
> prefixes for `IMP-NNN` / `ISS-NNN`.

## Context

Two user-visible performance problems attributed to SATAN, both grounded by
code inspection (2026-07-06):

1. **Git index-lock contention in working repos.**
   `dl-satan-memory-evidence--git-state`
   (`satan/dl-satan-memory-evidence.el:433-455`) runs `git status --porcelain`
   without `--no-optional-locks`. Plain `git status` refreshes the stat cache
   and writes `.git/index.lock` as a side effect. Evidence assembly runs this
   against the segment-derived cwd — i.e. repos the user was recently active
   in — so a background tick takes index locks in the user's working repos and
   concurrent user git operations fail with lock errors.

2. **Editor stalls while a tick runs.** Evidence assembly + broker prepare is
   one synchronous pipeline on the emacs main thread: psql queries, four bough
   subprocess calls, git, content probe, JSON parsing — all blocking
   `call-process`, serially summed. (Design-time correction 2026-07-10: the
   pipeline is now the DR-010 perceive/spawn split — perceive runs pre-gate
   in `dl-satan-broker-run`, spawn-side enrichment in `dl-satan-broker--spawn`
   — but both halves remain synchronous on the main thread; denied ticks
   still perceive, so observability must cover both halves and denied
   outcomes.) Freeze duration ≈ sum of every probe's latency; one slow probe
   (cold psql, hung bough) stalls the UI for seconds. Today there is no
   per-stage timing, so slow ticks are felt but not attributable.

Structural fix for (2) — perception out of the editor process — is the
ADR-001 / RFC-001 direction and out of scope here. This slice makes the
current in-process pipeline **observable** (evidence before argument) and
**bounded** (worst case capped), without fighting the extraction direction.

## Scope & Objectives

### Observe

- **Tick trace.** Time each stage of the prepare/evidence pipeline; emit one
  JSONL trace row per tick (`stage → ms`, total wall). Reuse the existing
  `dl-satan-jsonl` infra. Durable — answers "which stage is slow" for any past
  tick, not just one profiled run.
- **Subprocess ledger.** Log argv, cwd/repo, duration, and exit code at the
  existing choke points (`dl-satan-db` for psql; `--git-output` for git; the
  remaining probe call sites). Timestamped, so lock-contention incidents in
  other repos correlate directly against ledger rows.

### Bound

- **`GIT_OPTIONAL_LOCKS=0`** on every read-only SATAN git invocation, applied
  at the `--git-output` / `--git-state` choke point. Kills the index-lock side
  effect; the designed-for-background-tooling git mechanism. Ship first —
  safe, one line, independent of everything else.
- **Per-probe deadlines.** Every probe subprocess gets a timeout; on breach
  the probe degrades to an error entry in `sensor_status` (slots already
  exist) instead of hanging the tick. The percept records "sensor timed out"
  — honest and bounded.
- **Tick wall-clock budget.** Total prepare ceiling; when exceeded, log the
  breach in the trace row, truncate remaining optional stages, proceed.
- **Worktree confinement assertion.** Verify patch/worktree ops
  (`dl-satan-patch-worktree.el`, runner) only ever operate in satan-owned
  worktrees, never user working trees; make the invariant explicit (guard or
  test), not incidental.

## Non-Goals

- Moving perception/probes off the main thread (async `make-process`
  refactor) — parallel-implementation effort against the ADR-001 extraction
  direction; the daemon split supersedes it.
- Extracting any module out of elisp (POL-001 / RFC-001 territory).
- Percentile reporting / alerting on trace data (phase 3 of the audit plan —
  follow-up once trace data exists).
- Fixing bough/psql server-side latency itself; this slice measures and caps
  it.

## Summary

Make SATAN tick cost observable (per-stage JSONL trace + subprocess ledger)
and bounded (no optional git locks, per-probe deadlines, tick wall budget),
eliminating background index-lock contention in user repos and capping
worst-case editor stalls.

## Follow-Ups

- Phase-3 reporting: p50/p95 per stage from trace JSONL; budget breach →
  sensor alert via existing alerts infra.
- ADR-001 / DE-010 perception extraction removes the main-thread pipeline
  entirely; trace data from this slice quantifies the win.

## Risks / Assumptions / Open Questions

- **Assumption**: `GIT_OPTIONAL_LOCKS=0` covers all lock-taking read paths in
  evidence assembly; verify no other satan git call site writes locks
  (`rev-parse` and `log` do not; `status` was the offender).
- **Assumption**: existing `sensor_status` error slots are consumed gracefully
  downstream (percept render, model prompt) when probes degrade.
- **Risk (resolved in design)**: timeout mechanism — `timeout(1) -k 2`
  wrapper at choke points (design §2 D2); `with-timeout` rejected (does not
  kill the child), `make-process`+sentinel rejected (IO-plumbing rewrite).
- **OQ-1 (resolved)**: new day-bucketed JSONL under `$XDG_STATE_HOME/satan/`,
  one file with `kind` field for tick + subprocess rows (design §1 D1).
  Audit log stays semantic.
- **OQ-2 (resolved)**: log every call; volume is tens per tick (design §1).
- **Constraint (added at design)**: SL-012 renames `dl-satan-*` → `satan-*`
  and moves the tree; SL-011 lands first (`SL-012 after SL-011` recorded).
  New symbols follow current canon; trace stage names / JSONL keys are
  prefix-free, sweep-immune.

## Verification / Closure Intent

- ert coverage for: choke-point env injection (`GIT_OPTIONAL_LOCKS=0`
  present), probe-timeout degradation path, budget-breach truncation, trace
  row shape.
- Behavioural check: run a tick, inspect trace row + ledger; run `git status`
  loop in a user repo during a tick and observe zero `index.lock` collisions.
- Zero byte-compile warnings; `just check` green.
