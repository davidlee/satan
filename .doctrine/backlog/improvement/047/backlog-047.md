# IMP-047: Drop notes jailed-pi's writable /run/user/1000/satan bind; update goad backends through satan-runner

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found in SL-028 PHASE-05 (2026-10-20).

`~/notes/flake.nix` `jailed-pi` adds `try-readwrite "/run/user/1000/satan"`
(notes `e2965c4`, 2026-10-19) so the jail can reach goad's ingress socket
`satan/goad.sock`. A writable bind of the whole SATAN runtime dir lets the
jail replace any socket under it or rename its subdirectories, e.g.
`durable/` (fake malebolge's attach socket) or `goad.sock` itself.

SL-028 PHASE-05 contained the satan-mcp part only: `satanMcpOptions` is
applied after that bind, so `mcp/` is a read-only mount inside the writable
parent (DEC-088 holds). The rest of the dir stays writable.

User direction (2026-10-20): remove the goad socket from the jail entirely,
and make satan-runner (the malebolge patch runner) the mechanism for
updating goad backends, instead of the interactive jail writing them in
place. Related: IMP-020 (SATAN rewrites its own goad backend via the
patcher — now the runner).

RV-047 F-1 (2026-10-20) sharpens the risk. The read-only overlay applies
only when `mcp/` exists at jail launch (`--ro-bind-try` skips a missing
source). If it doesn't, the jail can create `mcp/mcp.sock` itself and
serve clients until satan-mcp-start replaces it. The bind order is also
protected only by a comment. Both go away once the jail no longer gets a
writable satan dir. Acceptance: no jail in `~/notes/flake.nix` binds
`/run/user/1000/satan` writable.
