# CON-005: Malebolge execution profiles: egress never with the room attached

User direction, 2026-10-19, while scoping SL-027 (RFC-019 D1, vm mode).

```
 profile   coding tools         egress   writes                  who
 room      room `assistant`     no       room; MCP tools         daemon (SL-027), patch jobs
 egress    none / own memories  yes      own memories only       daemon, interactive, future
 host      chosen host dir/jail per jail per jail config         daemon, interactive only
```

- **Policy:** egress and the room are never combined. A session with egress
  must not reach the room (the room holds clones SATAN's jobs promote from).
- The egress and host profiles are not built by SL-027; SL-027 must keep them
  possible — the execution environment is a per-run choice, not a constant.
- Host profile is interactive-only; patch jobs never run on the host.

## From oubliette RFC-001 (room package dependencies; resolved as oubliette POL-005)

Cited with the oubliette prefix; these ids resolve in `~/dev/oubliette`.

- **oubliette RFC-001 P1:** egress and the room's contents never coexist. An
  allowlist is not a one-way valve (HTTPS `CONNECT` is opaque; allowlisted
  hosts accept uploads). Hence no "narrow egress" variant of the room profile.
- **oubliette RFC-001 P3 / POL-001:** the mode is enforced host-side. For
  malebolge, a profile is therefore a host jail (launcher + binds + network),
  not a flag the daemon reads: the egress jail holds no room credential or
  route; the room jail has no network beyond the gateway.
- **oubliette RV-021 F-1 (return channel):** state shared between a
  room-attached run and a networked one is an exfiltration path. For malebolge:
  a durable conversation is bound to one profile for life; an egress session
  never resumes a transcript that held room content.
- **Open (for the egress profile's design, not SL-027):** hippocampus is
  written by room-profile sessions and readable by an egress session — a
  room → memory → egress channel. Whether egress reads only its own memories,
  or memories pass a filter, is undecided.
