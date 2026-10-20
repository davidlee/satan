# bwrap bind order and -try skipping

bwrap applies binds in argument order, and a jail.nix option list maps to
that order. So:

- **A later bind of a parent hides an earlier bind of its child.** Notes'
  `jailed-pi` had `satanMcpOptions` (`--ro-bind-try /run/user/1000/satan/mcp`)
  *before* `try-readwrite "/run/user/1000/satan"`, so `mcp/` came out
  writable. Fix: put the read-only child after the writable parent
  ([[DEC-101]], SL-028 PHASE-05).
- **`try-*` binds disappear when the source is missing.** `--ro-bind-try` is
  skipped if the path is absent at launch, so a read-only overlay inside a
  writable parent protects nothing until the directory exists, and the jail
  can create it itself ([[IMP-047]], RV-047 F-1). A strict bind fails the
  launch instead, so pre-create the directory (jailed-malebolge's
  `add-runtime "mkdir -p …"`).
- A socket on a read-only mount still accepts `connect()`: clients need the
  directory bound read-only, not writable. Bind the directory, not the socket
  file: a file bind pins an inode the server replaces on restart (ISS-042).

Check a built launcher, not the nix source: grep the store script for the
`--bind`/`--ro-bind` sequence and compare byte offsets.

Related: [[mem.fact.jail.bind-the-socket-directory-not-the-file]], [[mem.fact.jail.unix-socket-ro-bind]].
