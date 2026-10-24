# ISS-058: A persistent MCP connection blocks every scheduled run (session_blocked, DEC-8)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed (2026-10-25)

Every scheduled tick ends `session_blocked` while the malebolge daemon runs.
Live Emacs: `satan-run--session-active` = `t`, one open `satan-mcp <N>` client.

## Cause

- malebolge (`~/dev/malebolge/src/satan-tools.ts`) holds one reconnecting
  MCP connection for the daemon's lifetime; it refreshes tools before every
  input and never disconnects when idle.
- `satan-mcp--mint-session` sets `satan-run--session-active` on connect
  (`satan-mcp.el`); only the connection sentinel clears it.
  `satan-broker-run` refuses while it holds (`satan-broker.el`, DEC-8 branch).
- The flag is a boolean, so with two clients the first close clears it while
  the second is still connected.

## Hazard DEC-8 actually guards (inference)

The process-global `satan-memory-store--current-run-id`. MCP `let`-binds it
only for the synchronous `satan-tool-dispatch` in `satan-mcp--tools-call`; a
timer can start a scheduled run inside that window only if dispatch yields.
Run/run overlap is separately covered by DEC-023 (`run_busy`).

## Fix sketch

Replace the boolean with a count of in-flight MCP tool calls (increment and
decrement around dispatch, `unwind-protect`). The scheduler refuses only while
the count is positive. Connection lifetime stops mattering; the multi-client
bug goes with it. The reverse direction (`mint-session` refusing while a
scheduled child is live) also keys on connection, and malebolge reconnects
through it; review whether to narrow it to per-call refusal too.

Related: IMP-054 (per-conversation run identity), IMP-053 (unattended-turn
ceilings), ISS-050.

## Resolution (2026-10-25)

Sketch accepted by the user; implemented as sketched.

- `satan-run--session-active` (boolean) → `satan-run--interactive-calls`
  (count), `satan-run.el`.
- `satan-mcp--tools-call` increments it around `satan-tool-dispatch` in an
  `unwind-protect`; connect/close/accept-failure no longer touch DEC-8 state.
- `satan-broker-run` refuses (`session_blocked`, unchanged reason and
  silence) only while the count is positive.
- Tests: `satan-mcp/dec8-holds-scheduler-only-during-a-call`,
  `satan-mcp/dec8-call-releases-scheduler-on-error`; the broker gate tests
  rebound to the count. `just check` green.

Left as is: the reverse direction (`satan-mcp--mint-session` and
`satan-mcp-start` refusing while a scheduled child is live) still keys on
connections. Effect: a malebolge reconnect during a scheduled run fails and
retries; established connections are unaffected. Fold into IMP-054, where
the exclusion rule is being redesigned anyway.
