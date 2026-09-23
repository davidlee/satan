# Implementation plan SL-018: Unattended runs acquire credentials by per-mode policy: probe, then prompt or defer

Prose companion to `plan.toml`. Narrative only — the phase list, criteria,
verification and links live in the TOML.

## Overview

Eight phases across two repos. PHASE-01 lands the 1Password backend in
`~/.emacs.d`. PHASE-02..PHASE-07 build the SATAN side bottom-up: seam first,
then the independent overlap fix, then policy, gate, eviction, patch runner.
PHASE-08 is live acceptance plus a standing watch on ASM-002 (the assumption
that a read inside a live 1Password session never prompts).

```
PHASE-01  dl-secret backend  (~/.emacs.d)        inert: nothing reads it yet
    │
PHASE-02  satan-credential.el  seam + fixture    no callers yet
    │
PHASE-03  run_busy + sentinel reset             independent of credentials
    │
PHASE-04  mode keys, policy fn, attended flag    pure; gate untouched
    │
PHASE-05  broker gate  ◄── the behavioural switch-over (broker only)
    │
PHASE-06  evict-on-auth in finalize
    │
PHASE-07  patch runner + adapter under the seam  last my/* goes
    │
PHASE-08  restart Emacs; VH-2, VH-3; arm VH-1 watch
```

## Sequencing & Rationale

- **Backend first (PHASE-01).** Design sec-9 rollout: `dl-secret.el` must
  offer `my/satan-credential` before SATAN depends on it, otherwise the live
  Emacs would reach the no-backend path (defer everything, prompt modes record
  `credential_unavailable`) at the next restart. Setting
  `satan-credential-function` before the defcustom exists is harmless: the
  later `defcustom` keeps the value.
- **Seam before callers (PHASE-02).** The module is pure over an explicit ENV
  and a function variable, so it is fully testable in isolation. Its fake
  backend fixture (`satan/test/satan-credential-fixture.el`, a non-`-test.el`
  name so the runner does not load it as a suite) is the test seam every later
  phase reuses. No test calls `op`.
- **Overlap refusal early (PHASE-03).** ISS-020 (a sentinel that never clears
  `satan-run--spawn-running` after a finalize error) is a live bug, and
  DEC-023's `run_busy` gate makes it worse: a stuck flag would refuse every
  scheduled run. So the unwind-protect lands with, not after, the gate. Both are
  credential-independent; the gate's nil-verdict arm waits for PHASE-05.
- **Policy as a pure function (PHASE-04)** before it is wired in. Escalation
  (DEC-022) reads SL-017's `satan-run-outcome-streak` over real run
  fixtures; testing it apart from the gate keeps PHASE-05's tests about
  ordering and outcomes, not streak arithmetic. The attended binding in
  `satan-run` is tiny and testable here by capturing the flag.
- **One switch-over (PHASE-05).** All broker behaviour changes land together:
  acquisition before `satan-run-new-ctx`, the two new outcomes, `--spawn`
  consuming the verdict, `my/*` removed. Splitting it would leave a window
  where the key is resolved twice or by two paths. This is the largest phase
  (nine design VTs); `/phase-plan` should break it into red/green steps along
  the cond branches.
- **Eviction after the refs exist (PHASE-06).** It needs the
  `credential-refs` slot that PHASE-05's `--spawn` fills.
- **Patch last (PHASE-07).** Different subsystem, DB-backed tests, and the
  lenient resolve path. It removes the last `my/*` references, so the
  package-wide guard (VT-10) belongs here.

### VH-1 correction

Design sec-9 originally said "VH-1: validate ASM-002 on the live host". That
was wrong: ASM-002's open case is a session that reports live yet later
demands re-authentication, and positive reads cannot rule it out (see
ASM-002's validation plan, EVD-003). VH-1 is therefore a **watch condition**
armed in PHASE-08, not a pass/fail check. Its trigger: a dialog raised by a
defer-mode run whose context label lacks "escalated", while `op whoami`
reported a live session. Slice closure does not wait on it. Design sec-9 is
amended to match.

## Notes

- **Two repos, two commits.** PHASE-01 commits in `~/.emacs.d`; everything
  else in `~/dev/satan`. Commit with explicit pathspecs (other files may be
  pre-staged by a concurrent writer).
- **Live Emacs loads the working tree.** Mid-slice working-tree states are
  what a restarted Emacs would run. Each phase ends green and self-consistent;
  PHASE-05 is the first that changes live behaviour. Do not restart the live
  Emacs before PHASE-08 unless every phase through PHASE-05 is complete.
- **VT numbering is slice-wide.** VT-1..VT-24 are design sec-9's ids,
  unchanged. This plan adds VT-25..VT-29 (backend probe, backend adapter,
  plain `run_busy`, `satan-run-id-time`, two-run rotation recovery). PHASE-01's VTs are waived for
  `verify-vt` only because the test file is outside this repo.
- **VT-10 splits.** Its `my/*`-absence half becomes a standing test; its "no
  error-swallowing around key resolution" half cannot be expressed as a
  substring and is VA-1 (agent inspection) in PHASE-07.
- **Tolerated from RV-013:** F-9 (DST can skew the escalation age by up to an
  hour) and F-12 (Pi's seven-key list is a superset; narrowing it is the
  keeper's config lever).
- **Plan review (2026-09-23, codex gpt-6-sol, 6 findings, all accepted).**
  Six changes followed. PHASE-01 must show its suite actually ran, because
  dl-test passes on zero files. PHASE-05 updates every `--spawn` caller and
  stub. PHASE-07 has the runner merge resolve failures into `:warnings` and
  persist them on `adapter_failed`. The ban on `my/` symbols is narrowed to
  credential symbols. VT-29 proves recovery, not only eviction. The pi-var
  readiness gate also holds back `fake`-adapter test jobs; the tests bind the
  backend and env. Per-adapter readiness stays design debt (design sec-7), not
  a plan change.
