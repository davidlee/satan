# IMP-045: malebolge room daemon as a systemd user unit, started from Emacs

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

User idea, 2026-10-20. Today the room daemon is a foreground process:
`just hello-durable` in `~/notes` runs `(satan-mcp-start)` then
`nix run ~/dev/satan#jailed-malebolge`, and the terminal must stay open.
`malebolge-attach` (`~/dev/malebolge/emacs/malebolge.el`) can only attach
to a daemon something else started.

## Sketch

```
 Emacs: malebolge-start
   1. (satan-mcp-start)                     ; Emacs owns satan-mcp
   2. systemctl --user start malebolge-room ; idempotent
   3. malebolge-attach                      ; comint, as today

 ~/flakes features/satan/malebolge.nix (beside runner.nix)
   malebolge-room.service: ExecStart = jailed-malebolge (store wrapper; JS from ~/dev/malebolge)
   no WantedBy (on demand); Restart=on-failure; logs to the journal
   SIGTERM -> daemon's existing stop handler
```

- Emacs initiates, so it orders satan-mcp before the daemon; no
  `emacsclient` call from inside a unit.
- Plain unit, not `malebolge@.service`: only the room profile has a jail
  (CON-005). Template when a second profile exists.

## Consequences / open points

- **Live tree, no extra work.** `jailed-malebolge` (`~/dev/satan/flake.nix`
  `malebolgeDaemon`) execs node on the literal path
  `/home/david/dev/malebolge/src/daemon-main.ts`, so the unit runs the live
  tree; only the jail wrapper (binds, env) is fixed at `home-switch`. A
  restart picks up malebolge edits. Cost: impure and dirty-tree-sensitive
  (the RSK-016 shape), unlike `satan-runner`, which runs the pin.
- `just daemon` (unjailed, live tree) and the unit share one socket path;
  check what a second daemon does on bind before leaving both available.
- A long-lived daemon makes satan-mcp churn matter more: IMP-038 (lazy
  reconnect, done in malebolge `9126b0c`, item still `started`),
  IMP-039 (tool-list refresh), ISS-042 (jails bind the mcp socket as a
  file; fix in `~/notes/flake.nix`).
- ADR-017: lifecycle moves out of a terminal into a unit; Emacs stays the
  human surface that starts it. RSK-018 (socket grants submit/abort to
  any local process) is unchanged.
- Update `~/flakes/SATAN.md` (units table; "daemon is not a unit").

Related: RFC-019, SL-027, CON-005, IMP-038, IMP-039, ISS-042, RSK-018.
