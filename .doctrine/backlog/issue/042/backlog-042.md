# ISS-042: Jails bind satan-mcp's socket as a file; an Emacs restart of satan-mcp leaves jpi on a dead socket

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found during IMP-037. `~/notes/flake.nix` `jailEnvOptions` binds
`/run/user/1000/satan/mcp/mcp.sock` with `try-readwrite` — a bind of the
socket file. A bind mount pins the inode, so when Emacs restarts satan-mcp
(unlink + re-listen) the jail keeps the dead socket, and jpi's SATAN tools fail
until the jail restarts. If the socket is absent at jail start, `try-` skips the
bind and the jail never sees it.

Confirmed: `satan-mcp-start` deletes and re-listens (`satan/satan-mcp.el`
~l.446). Reproduced 2026-10-17 with bwrap 0.12.0: a server recreated at the
path is `ECONNREFUSED` through a file bind and reachable through a directory
bind, including the directory-then-parent overlap `jailed-malebolge` uses.

Fix: bind the directory `/run/user/1000/satan/mcp` instead, as
`jailed-malebolge` binds `/run/user/1000/satan` (IMP-037). Same access today:
`mcp.sock` is the directory's only entry.

## Progress (2026-10-17)

Fixed in `~/notes/flake.nix` `jailEnvOptions`: `try-readwrite
"/run/user/1000/satan/mcp"`, so every jail (jpi, jcl, jailed-shell,
jailed-malebolge) follows a satan-mcp restart. `jailed-malebolge` again
inherits `jailEnvOptions` whole, adding the parent directory for its daemon
socket. Devshell builds; built launchers show the directory bind.

Pending: live check in jpi — restart satan-mcp, call a SATAN tool.
