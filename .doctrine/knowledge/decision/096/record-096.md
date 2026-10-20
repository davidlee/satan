## Decision

Every termination path uses the same ladder: SIGTERM to the child's process group, a bounded grace (2 s), then SIGKILL to the group; then audit, then return.

| trigger | behaviour |
|---|---|
| MCP `notifications/cancelled` | ladder; result `state: incomplete`, partial transcript, audit `abort(cancelled)` |
| server stdin EOF | ladder, then the server exits (EOF is shutdown: the driver owns its stdin) |
| driver death | the above, via EOF or SIGTERM |
| server SIGTERM | ladder, then exit |
| server SIGKILL | residual only: the child dies via the jail's `--die-with-parent`. Documented as the one un-audited path |

The server keeps consuming the child's event stream **and** its own stdin concurrently: a blocking *result* does not make a blocking *reader*. A call in flight must not stop the MCP loop from accepting a cancellation.

## Never detach

The child is never backgrounded. `jailed-pi` dies when its launching shell exits (`bwrap --die-with-parent`, `mem.fact.jail.background-launch-dies-with-shell`), so a detached delegate yields a dead jail and no result. "Detach and poll" - the obvious answer for a long call - is explicitly rejected.

## Consequence

Cancellation is a control decision and is audited (DEC-094). A cancelled run's partial transcript is returned, not discarded: the driver may resume it via the session id (inq-6).
