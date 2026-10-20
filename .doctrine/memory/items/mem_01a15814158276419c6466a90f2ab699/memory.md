Measured on pi 0.99.1, deepseek-flash, 2026-10-20.

- `pi --mode json "…"` exits 0 by itself; last record is `agent_settled`. Prompt may
  arrive on argv, as `@file`, or on stdin.
- `pi -p` is the same one-shot lifecycle with the final text on stdout and an
  honest non-zero exit on an error stop reason. Context survives across separate
  processes via `--session-id` (verified: turn 2 recalled turn 1's content).
- `pi --mode rpc` with the prompt piped and stdin then closed exits 0 having
  answered NOTHING: EOF requests shutdown, so the prompt is accepted and the turn
  never runs. That is the sole reason `scripts/lib/pi-reap.sh` exists (fifo keeper
  + tail poll + process-group kill + zombie waits). RPC also rejects `@file`
  prompts, which print/json accept.
- Stream size: one small turn in the doctrine tree is 175 KB in json mode, 187 KB
  in rpc. ~72% is context echo — `message_start`/`message_end`/`agent_end`
  replaying system and user messages. `message_update` is delta-only on the wire
  in 0.99.1, so the "50–150 MB, super-linear" poll-window note in `pi-reap.sh` is
  stale; linear growth is documented in pi's `docs/json.md`.
- Cancellation: `kill -TERM` on the `timeout` wrapper of a json-mode run ends the
  whole chain in ~6 ms with no survivors. The RPC arm's
  timeout→bwrap→wrapper→pi chain is what made group kills necessary.
- Reducer: `bin/pi-run-reduce` (`pi/reduce/`) turns a stream into `transcript.md`
  (budgeted, 8 KB default, middle-out elision), `status.json`, one status line on
  stdout and `--alert` matches on stderr. A real 175 KB turn reduces to 551 B.
