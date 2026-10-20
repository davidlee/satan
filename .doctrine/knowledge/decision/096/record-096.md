## Decision

Every termination path uses the same ladder: SIGTERM to the child's process group, a bounded grace (2 s), then SIGKILL to the group; then audit, then return.

| trigger | behaviour |
|---|---|
| MCP `notifications/cancelled` | ladder; result `state: cancelled`, `termination: "cancelled"`, partial transcript, audit `abort(cancelled)` |
| server stdin EOF | ladder, then the server exits (EOF is shutdown: the driver owns its stdin) |
| driver death | the above, via EOF or SIGTERM |
| server SIGTERM | ladder, then exit |
| server SIGKILL | residual only: the child dies via the jail's `--die-with-parent`. Documented as the one un-audited path |

The server keeps consuming the child's event stream **and** its own stdin concurrently: a blocking *result* does not make a blocking *reader*. A call in flight must not stop the MCP loop from accepting a cancellation.

## Never detach

The child is never backgrounded. `jailed-pi` dies when its launching shell exits (`bwrap --die-with-parent`, `mem.fact.jail.background-launch-dies-with-shell`), so a detached delegate yields a dead jail and no result. "Detach and poll" - the obvious answer for a long call - is explicitly rejected.

## Consequence

Cancellation is a control decision and is audited (DEC-094). A cancelled run's partial transcript is returned, not discarded: the driver may resume it via the session id (inq-6).


## RV-043 F-9: the termination domain is created, not assumed

Every call is spawned as a **process-group leader** (its own session:
`setsid`/`detached`). The ladder signals `-pid`, so it can never reach the server
or a concurrent call — the failure mode the jail's `no-new-session` would
otherwise guarantee (`jailed-agents.nix:184`). Reaping and stream drain complete
before the result is returned and before the session lock is released.

"Never detached" in this decision always meant *lifetime* coupling — no
fire-and-forget, no backgrounding — not session isolation. Restated, because
conflating the two is what left the ladder without a group to signal.

Verification: two simultaneous calls plus a grandchild that ignores SIGTERM;
cancel one and assert its subtree is gone after the grace, the other calls and the
server remain alive, and the session lock is released only after cleanup.

## RV-043 F-12: a cancel is its own outcome

The trigger table above said a cancellation returns `state: incomplete`, which
predates DEC-093's cause table. Cancellation is a named cause with its own state —
`cancelled`, `final: false`, `result: null`, partial transcript returned — so a
driver can tell "the model had not finished" from "we stopped it". Corrected in the
table above; `causes` carries any later cause (an audit append that also failed)
rather than hiding it.
