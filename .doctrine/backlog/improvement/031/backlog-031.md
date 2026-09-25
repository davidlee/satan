# IMP-031: Decouple the satan package from host literals and editor config

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Violates SPEC-002 NF-006 (REQ-018).

- `satan-tools-org.el:12,51` calls `my/journal--week-file` from `~/.emacs.d` (`dl-denote-journal`) — an undeclared dependency on user config. Use a defcustom function, like `satan-journal-today`.
- The MCP client extension lives at `~/.emacs.d/.pi/extensions/satan.ts`, not in the satan repo; its comments name retired `dl-satan-*` symbols.
- `~/.emacs.d/lisp/dl-sleipnir-doctor.el` checks `satan-broker--failure-streak-count`, which no longer exists.
- `satan-tools-activity.el:36` hard-codes `~/.local/state/behaviour/` (other readers honour `XDG_STATE_HOME`).
- Jails hard-code `/run/user/1000/...` and `$HOME/satan/hippocampus` (`~/dev/satan/flake.nix:72-76,143`) instead of deriving them from the roots.
