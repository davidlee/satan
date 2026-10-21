@.capsule-runs/mem-body.md

## Outcome (SL-030 complete, 2026-10-21)

All 8 phases in one session, ≈ $2.2 of pi total; Claude context stayed small. Worked well — reuse.
- Review value: 23 findings (1 major, 9 minor); real test gaps every time a phase looked clean to the
  worker (untested post-attach typing; an abort test that could not see a mis-scoped abort; docs
  stale singulars). Have the reviewer try concrete regressions ("would this test fail if…").
- Ask workers to prove a test is meaningful by temporarily breaking the src it guards, seeing red,
  restoring byte-exactly (`git diff -- src` empty). Essential for test-only phases.
- Planner-of-N+1 alongside reviewer-of-N is safe; never two writers' gates at once.
- Tweak next time: snapshot the list of unrelated untracked dirs at start (`git status --short`
  to a file) and diff it at each gate — the gate filter hid that an unrelated `_pi/` vanished.
