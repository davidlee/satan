# DEC-118: quotient clients: Claude Code and Codex, blocking calls in v1

<!-- Knowledge record body — context, detail, links. The structured, queried
     fields live in the sister `record-NNN.toml`; this prose is free-form and is
     never structurally parsed (the storage rule). -->


## Amendment 2026-10-22 (devil's-advocate review, operator: "Apply all")

The server kills its child process groups on stdin EOF, SIGTERM and SIGINT (today it does not: the child is detached, spawn.ts:290, and a client-killed server can orphan it); together with form-1's die-with-parent this covers Codex killing the server at tool_timeout_sec. Printed client snippets use the absolute path of the quotient bin; tool_timeout_sec = policy maxima.wall_clock_s plus a stated margin.

## Amendment 2026-10-22b (design synthesis, operator: "accept")

Correction: stdin EOF already aborts every in-flight call through the ladder with cause eof (pi/mcp/server.ts serve, post-loop). The gap is SIGTERM/SIGINT only. They take the same shutdown path and record cause eof ('client gone'); no new termination token, pi-agent-result/1 unchanged. Server SIGKILL with an unconfined form orphans the child: documented limitation.


## Amendment 2026-10-23 (SL-031 reconcile, RV-059 F-2; operator "fix now" in PHASE-10, Q `6c31180`)

The printed client snippets name the absolute path the bin was run as, with symlinks kept (`path.resolve`, not realpath). Under the nix wrapper, that path is `QUOTIENT_LAUNCHER`: the wrapper's own `$0`, made absolute. A relative or empty value is ignored, never refused, because it is a hint, not a location. Reason: under nix, the realpath of `process.argv[1]` is a store path to `dist/cli.js`. Its `/usr/bin/env node` shebang bypasses the node-carrying wrapper, and the path disappears at the next rebuild and GC.
