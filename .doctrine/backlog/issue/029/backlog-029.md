# ISS-029: Jail env leaks API keys to argv and drops the budget ceiling

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-004 (REQ-016) acceptance criteria 3 and 4.

- jail.nix `try-fwd-env` expands to `--setenv NAME "$NAME"` on bwrap's argv, visible in `/proc/<pid>/cmdline`. `~/dev/satan/flake.nix:80, 206-209` forward provider keys this way for the production `jailed-satan-gptel-harness`, alongside the FD-21 path (`passApiKeysFromEnv`). Same in `.emacs.d/flake.nix:81`, `satan-attrd/flake.nix:66`. The corpus and notes flakes already warn about this leak.
- `satan-broker.el:980` sets `SATAN_MAX_BUDGET_TOKENS`; `satanGptelJailOptions` does not forward it, so `harness/runloop.py:183` reads 0 and the hard backstop is disabled in the jail (SPEC-001 REQ-004).
- The jail forwards `ANTHROPIC_API_KEY`/`OPENAI_API_KEY`, but the harness has no provider for either, and the library ref map has no `ANTHROPIC` entry.
