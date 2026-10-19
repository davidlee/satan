Established in SL-027 PHASE-04 (malebolge 1c42811, test/daemon-env.test.ts).

- **Daemon argv.** pi-env's `Connection` appends its own `serve --token <hex>`
  after the command that `daemonCommand` builds. The ssh remote command is
  therefore `... '<daemon>' serve --token <hex>`. A fake `ssh` in a test must
  forward the words after the quoted daemon word: run alone, the pi-env binary
  prints `usage: pi-env serve --token <hex>` and exits 2. Assert a direct
  launch as ` '<daemon>' serve ` with no `session`, not as `endsWith('<daemon>')`.
- **Lost room vs grep.** A daemon start that fails (the room is down) reaches
  `RemoteExecutionEnv.exec` as an `ExecutionError` whose code is not
  `spawn_error`. `runGrep` throws it, and pi-durable renders the tool result
  as `<harness>\n[error] <message>`. The seam's reword still reaches the model,
  but grep's own `spawn_error` text never fires for a room fault.
- **ShellExecResult** has only `exitCode` (and `spillPath`). Collect output
  through the `onOutput` option.
