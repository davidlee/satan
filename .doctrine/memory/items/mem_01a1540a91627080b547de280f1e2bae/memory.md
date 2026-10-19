Established in SL-026 (malebolge 0c294ae, a0efde5; design §4.3).

- pi-env's daemon spawns argv directly, so an absent binary is
  `ExecutionError` `spawn_error`, never exit 127. A room lost while starting
  an exec also carries a `spawn_error` cause but arrives as
  `ChannelUnavailable` — classify by error type before code.
- pi-env's exec `timeout` kills a process blocked opening a FIFO (`head` on a
  FIFO); it is the only thing that does.
- Closing a local pi-env `Connection` does not kill its running children: a
  failing FIFO test leaks a process. Leak checks must use `pgrep -x`, since
  `pgrep -f` matches the checking command line itself.
