# ISS-048: Room assistant: bun cannot resolve DNS, so doctrine's just web-build fails in the room

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Observed 2026-10-19 by the user while preparing SL-026 PHASE-08. In room
`assistant`, `session doctrine -- just web-build` cannot run because bun
cannot resolve DNS. The room has no network uplink by design, so the web
build's dependency fetch has no path out. Doctrine target's `baseline`
(`just web-build test`, `/srv/fleet/targets/doctrine.nix`) assumes it can.

Not blocking SL-026: the PHASE-08 job needs no build. Options to weigh:
vendor or pre-fetch the bun dependencies into the tool set or a cache on
`/work` (cf. `caches.BUN_INSTALL_CACHE_DIR`), or a narrowly allowed
registry egress.
