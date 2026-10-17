# Bind a socket's directory into a jail, never the socket file

A bwrap `--bind` of a unix socket *file* pins that inode. A server that
restarts by deleting and re-listening at the same path — `satan-mcp-start`
does exactly this (`satan/satan-mcp.el`, `delete-file` then
`make-network-process`) — creates a new inode the jail cannot see: connects
through the old bind fail with `ECONNREFUSED` until the jail restarts.

Bind the socket's **directory** instead. Reproduced 2026-10-17 (bwrap 0.12.0):
file bind refused, directory bind reached the new server, and a child-then-parent
overlap of directory binds still works.

Applied in `~/notes/flake.nix` `jailEnvOptions` (ISS-042): every jail binds
`/run/user/1000/satan/mcp`. Malebolge's reconnect (IMP-038) depends on it.
A `try-` bind of a socket absent at jail start is silently skipped — a
directory exists far more reliably than the socket in it.
