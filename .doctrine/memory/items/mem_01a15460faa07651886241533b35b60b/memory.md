Verified 2026-10-20 (bwrap 0.12.0, SL-027; also flakes:SL-015 probe P3).

- `connect()` to a unix socket works through `--ro-bind <dir> <dir>`: the
  room door (`/run/capsule-room/assistant/ssh.sock`) returned its SSH banner
  from an `--unshare-net` jail with only a read-only bind of its directory.
- Creating a socket there fails: `bind(...): Read-only file system`. A
  process that *listens* (malebolge's `durable.sock`) needs a rw directory.
- Bind the socket's **directory**, never the file: a file bind pins the
  inode, so a server that unlinks and re-listens leaves the jail on a dead
  socket (ISS-042).
- `--unshare-net` keeps loopback up but the host's 127.0.0.1 listeners are
  unreachable; reach a host TCP service through a bound unix socket and an
  in-jail forwarder (flakes:DEC-076 `gatewaySocketOptions`).
