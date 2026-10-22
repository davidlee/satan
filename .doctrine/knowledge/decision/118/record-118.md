# DEC-118: quotient clients: Claude Code and Codex, blocking calls in v1

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

The server kills its child process groups on stdin EOF, SIGTERM and SIGINT (today it does not: the child is detached, spawn.ts:290, and a client-killed server can orphan it); together with form-1's die-with-parent this covers Codex killing the server at tool_timeout_sec. Printed client snippets use the absolute path of the quotient bin; tool_timeout_sec = policy maxima.wall_clock_s plus a stated margin.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

Correction: stdin EOF already aborts every in-flight call through the ladder with cause eof (pi/mcp/server.ts serve, post-loop). The gap is SIGTERM/SIGINT only. They take the same shutdown path and record cause eof ('client gone'); no new termination token, pi-agent-result/1 unchanged. Server SIGKILL with an unconfined form orphans the child: documented limitation.