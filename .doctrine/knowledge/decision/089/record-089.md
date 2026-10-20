## Decision

`pi_agent` starts the flake-provided wrapped runner once per call, with the child process's cwd set to the call's root. There is no per-call launcher surface to build, no root fixed at server launch, and no bwrap argv in `pi/mcp`.

## Evidence

`flakes/agents/jailed-agents.nix:197-198`: `launchDirOptions` binds the launcher's `$PWD` to `/workspace/$(basename "$PWD")` and `--chdir`s there. The root is therefore evaluated from the wrapper's own cwd at exec time, not baked at build time. Since a delegate call is one `pi --mode json` process (`research/research.md`, Thread 2), a fresh wrapper per call gives a fresh jail per call for free — the root is per call by construction.

## Consequences

1. Jail-internal coordinates differ from host ones: the root appears as `/workspace/<basename>`, siblings as `/workspace/<name>`. Host-side redirection of the child's stdout into `events.jsonl` and a prompt on the child's stdin are unaffected (both are fds the server holds), but any path the *child* is told about must be jail-coordinate: prompt-file paths and the session dir.
2. The session dir cannot live in `/tmp` (a per-run tmpfs): it must sit inside the bound root (inq-6).
3. Read-only remains a separate wrapped form, because this one binds the root rw (inq-5).
4. The server still needs a path grammar on `root` — absolute, existing, not `/`, not `$HOME` — but it is validating its own input, not the jail (inq-4).

## Rejected

- One root fixed at server launch with refusal outside it: needs a refusal path and defeats cross-repo delegation, while buying nothing the per-call process does not already give.
- A flake-provided per-call launcher taking `--root`: duplicates the `$PWD` bind above and would be a second place jail policy is expressed.
