# ISS-055: malebolge: a daemon running older source rejects a newer client with an opaque protocol error

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Observed (2026-10-21)

`malebolge-room.service` runs `node ~/dev/malebolge/src/daemon-main.ts` from the
live checkout, so the daemon's code is whatever was on disk when it started. It
started 2026-10-20 21:29; SL-030 PHASE-04 (malebolge `2f84bce`, 2026-10-21) made
the client's first line an `attach` frame. `malebolge-attach` spawns
`attach-main.ts` fresh, so client and daemon disagreed: the old daemon replayed
the transcript on connect, then answered `unknown message type "attach"`.
A unit restart fixed it.

## Options

- Version handshake: the daemon names its protocol version on connect; the
  client refuses a mismatch with "daemon is older than this client — restart
  malebolge-room.service".
- Process: restart the unit as part of landing any phase that changes
  `src/protocol.ts` (cheaper, easy to forget).
