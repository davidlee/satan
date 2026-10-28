Observed while building malebolge's `satan.wake` task (SL-034, PHASE-04..07) against
pi-durable 1.4.0. Complements [[mem.fact.pi-durable.scheduled-turn-mechanics]].

- `RunningTask.state` is `{status, checkpoint}`; read the checkpoint there.
- `inspect()` reports a task whose phase awaits `Submission.wait()` as `running`,
  even when its input is stuck queued behind a failed run. Start-time detection
  cannot see that case; bound the wait in the phase instead.
- `Submission.abort()` withdraws only a **queued** input (check + withdraw in one
  commit); a placed input answers `already_placed`, a settled one `settled`.
  `abortTask` does not withdraw a task's inputs: the abort handler must.
- Aborting a **definition-blocked** task with nothing live settles it `orphaned`
  in the abort's own commit **without running its handler**, and `inspect()`
  lists live tasks only. Withdraw its queued inputs *before* `abortTask`.
- `abortTask` joins an active invocation before the handler runs, so "never
  admitted" seen in the handler is reliable.
- Sleeps are recorded asynchronously: in tests, poll `inspect()` with
  `vi.waitFor` rather than asserting right after a clock move.
- `SessionOptions.setTimer` → `HarnessOptions.setTimer` drives in-phase timers
  (`runtime.setTimer`) on a fake clock, but also captures the scheduler's own
  timer; a held faux model turn must be released or the test hangs.
- Model errors: a run is retried only on `stopReason: "error"` with wording
  pi-ai classifies as retryable; otherwise the run fails `model_error` and its
  inputs settle `unanswered` (see [[mem.fact.pi-ai.stream-timeout-and-retry]]).
