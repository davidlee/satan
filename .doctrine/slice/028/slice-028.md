# malebolge room daemon as an Emacs-started user unit, robust to satan-mcp restarts

## Context

The malebolge room daemon (SL-027; `~/dev/malebolge` `src/daemon-main.ts`) is
a foreground process. `just hello-durable` in `~/notes` runs
`(satan-mcp-start)` then `nix run ~/dev/satan#jailed-malebolge`, and the
terminal must stay open. Emacs can only attach (`malebolge-attach`,
`~/dev/malebolge/emacs/malebolge.el`) to a daemon something else started.

A daemon that outlives terminals also outlives Emacs restarts of satan-mcp
(a fresh `satan-mcp-start` deletes and re-listens on its socket; on a live
server it is a no-op). These items cover that seam:

| item | state | gap |
|---|---|---|
| IMP-045 | open | daemon is not a unit; no start from Emacs |
| IMP-039 | open | tool list fixed at daemon start; a changed Emacs tool set needs a restart |
| ISS-042 | started | `~/dev/satan/flake.nix:86`, `~/satan-corpus/flake.nix:57`, `~/.config/emacs/flake.nix:80` bind the mcp socket **file**; `~/notes/flake.nix:71` binds the directory read-write |
| IMP-038 | done | lazy reconnect, malebolge `9126b0c` |

```
 Emacs  M-x malebolge-start
   1. (satan-mcp-start) if loaded             Emacs owns satan-mcp
   2. systemctl --user start malebolge-room   idempotent
   3. malebolge-attach                        comint; attach retries ~10s

 malebolge-room.service (~/flakes, features/satan/)
   ExecStart = jailed-malebolge  (store wrapper; JS from ~/dev/malebolge live tree)
   on demand (no Install) · Restart=on-failure · X-RestartIfChanged=false
   journal · SIGTERM → stop handler

 daemon: claim socket ─▶ open store ─▶ serve      (DEC-087)
 every input / reconnect ─▶ refresh SATAN tools   (DEC-086; empty if unreachable)
```

## Scope & Objectives

Decisions: DEC-083..DEC-088 (design run, 2026-10-20).

1. **Unit** (IMP-045, DEC-083): `malebolge-room`, a home-manager user service
   in `~/flakes/features/satan/malebolge.nix` running `jailed-malebolge` from
   the satan flake input. On demand, never restarted by a switch. Logs to the
   journal.
2. **Emacs start/stop** (IMP-045, DEC-084): `malebolge-start` /
   `malebolge-stop` in `malebolge.el`, with a soft dependency on
   `satan-mcp-start`; `attach-main.ts` waits briefly for the socket.
3. **Degrade without satan-mcp** (DEC-085): the daemon starts with zero SATAN
   tools instead of throwing.
4. **Tool refresh** (IMP-039, DEC-086): re-list and reinstall the `satan`
   extension before every input and after every reconnect; single-flight,
   bounded, empty on failure. A removed tool returns pi-durable's
   `tool_unavailable` error.
5. **One daemon per profile** (DEC-087): a lifetime instance lock
   (`daemon.lock` beside the store) taken first, then the socket claimed by
   listening, both before the store opens; `serveUnix` unlinks only a
   verified stale socket, for the daemon and the runner.
6. **Socket binds** (ISS-042, DEC-088): a read-only directory-bind combinator
   `satanMcpClient` in `~/flakes/agents`, asserted in its test; all four jails
   use it.
7. **Docs/backlog:** `~/flakes/SATAN.md` (units table, live-tree exception),
   malebolge `README.md` and `docs/internals.md`, remove `hello-durable` from
   `~/notes/justfile`. RSK-020 records the REQ-015 gap (REV at reconcile adds
   it to REQ-015's tracked gaps).

## Non-Goals

- Socket activation (`.socket` unit passing an fd): the daemon binds its own
  socket today; revisit only if on-demand start-at-attach is wanted.
- A `malebolge@<profile>` template: only the room profile has a jail
  (CON-005). Template when a second profile exists.
- Running the runner's pin instead of the live tree (user, 2026-10-20: live
  tree is fine for the interactive daemon).
- RSK-018 (daemon socket grants submit/abort to any local process),
  ISS-050 (no append-only audit of coding tools): unchanged.
- Native Emacs client (IDE-010).

## Affected surface

- `~/dev/malebolge`: `src/satan-tools.ts`, `src/daemon-main.ts`,
  `src/session.ts`, `src/unix-socket.ts`, `src/daemon.ts`, `src/attach*.ts`,
  `emacs/malebolge.el`, `README.md`, `docs/internals.md`; tests under `test/`
  (incl. `harness-fixture.ts`).
- `~/flakes`: `features/satan/malebolge.nix` (new), `features/satan.nix`,
  `agents/` (combinator + test), `SATAN.md`.
- `~/dev/satan`: `flake.nix` (bind → combinator).
- `~/satan-corpus`, `~/.config/emacs`, `~/notes`: `flake.nix` (bind →
  combinator); `~/notes/justfile` (`hello-durable` removed).

## Risks, assumptions, open questions

Open questions OQ-1..OQ-4 resolved in design: OQ-1 → DEC-087, OQ-2 →
DEC-085, OQ-3 → library error (DEC-086), OQ-4 → unit sets `HOME` and
`XDG_RUNTIME_DIR` (DEC-083). The pi-durable assumption is confirmed
(`research/research.md` C4).

- **RSK-020:** malebolge runs two revisions (pinned runner, live-tree daemon).
- **Instance lock** (DEC-087): POSIX advisory lock via SQLite on a local
  filesystem; closes the two-starter race RV-040 F-1 found.
- **Deploy order:** the satan flake change ships only after push +
  `nix flake update satan` (mem.fact.satan.runtime-jail-deploys-from-github-input).
- **ADR-017:** no authority-ledger row changes; the unit's off switch is
  service management, not a SATAN kill switch.

## Verification / closure intent

- Tests (malebolge, vitest): tool list refreshes after a satan-mcp restart
  with a changed tool set; removed-tool behaviour; zero-tool start; MCP lost
  and recovered mid-turn; hung refresh; concurrent inputs; second daemon
  refused before the store opens (instance lock); in-flight turn resumed
  after restart.
- Flake checks: the agents test asserts `satanMcpClient` binds the directory
  read-only and never `mcp.sock`; every jail uses it (grep sweep at audit).
- Live (VA by agent, VH by user): from a fresh Emacs, `M-x malebolge-start`
  brings the daemon up with no terminal; `systemctl --user restart emacs`
  (or `satan-mcp-start`) then a SATAN tool call succeeds without a daemon
  restart; `systemctl --user stop malebolge-room` stops cleanly.
- `SATAN.md`, malebolge docs and backlog items (IMP-045, IMP-039, ISS-042, RSK-020) current.

## Summary

Make the room daemon a background user unit Emacs starts, and make it survive
satan-mcp restarts with a current tool list.

## Follow-Ups

- RFC-019 D5 (hourly commit timer in `~/flakes`), same composition area.
- RFC-019 D2/D4 (state read tool).
