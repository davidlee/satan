Where a host runner can recognise failures in pi-env / pi-durable 1.3.0
(SL-023, malebolge `src/runner/`):

- **Lost connection:** `RemoteExecutionEnv.exec` drops the `RemoteError`
  (an `ExecutionError` `unknown`, no cause); file ops keep it as
  `FileError.cause`. Recognise it in a `Connection` subclass passed as
  `RemoteExecutionEnvOptions.connection`, observing `info()`, `session()` and
  `request()` (EVD-009, EVD-010). One room stop raises more than one lost
  failure: make the mark idempotent.
- **Host keys:** `Connection.#start` rewraps any command-function rejection
  as `RemoteError{spawn_error, lost: true}`; `HostKeyChangedError` /
  `HostKeyUnknownError` keep `name === "Error"`. Record them by `instanceof`
  inside the command function before rethrowing (`DaemonConnection`).
- **Model requests:** no hook can deny a request or set its options
  (`beforeRequest` returns messages; a throwing hook is skipped). Deny at the
  provider boundary with a gated `Models` view; refusal text must avoid pi-ai's
  retryable patterns (bare status digits, "overloaded", "connection lost").
- **Abort placement:** signalled from `afterTool`, an abort lands before the
  tool task commits its replaced result; `afterTools` keeps the result but a
  macrotask delay still admits one more request — gate it too.
- **node:sqlite:** a host query on the shared adapter from inside a pi
  transaction never settles (EVD-008); hooks `beforeTool`/`afterTool`/
  `afterTools` run outside transactions.
