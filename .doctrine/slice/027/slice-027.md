# malebolge daemon vm mode: coding tools in the room

## Context

RFC-019 D1. Malebolge (`~/dev/malebolge`) runs two agents with opposite reach:

```
 interactive daemon (jailed-malebolge)        satan-runner (patch jobs)
 bwrap jail ON THE HOST                       model loop on host, tools IN THE ROOM
 cwd = launch dir (~/notes), rw               room `assistant` over pi-env (ssh)
 network on (specDev profile)                 no uplink
 coding tools on the host                     coding tools via src/runner/env.ts
```

The agent with freedom acts on the host; the agent in SATAN's own machine is
the constrained one. CHR-020 (launch dir `~/notes` bound rw, so the daemon can
write the user's notes) is the live symptom. This slice moves the daemon's
coding tools into the room: **vm mode**. The model loop and gateway key stay on
the host; SATAN MCP tools are unchanged (fixed mode `interactive`).

```
 after:  malebolge daemon (host)
           ├── SATAN MCP tools ── Emacs (unchanged, mode "interactive")
           └── read/write/edit/bash/grep ── pi-env ── room `assistant`
                                                      cwd /home/agent
```

Related state: SL-026 delivered RFC-019 D7 (project context, cwd, grep). Its
project-context pipeline already takes an injected `SourceReader`
(`src/project-context.ts`); the daemon passes node fs, the runner a room shell
(`src/runner/project-context.ts`). D5 (commit timer for `~/notes` and
`~/satan-corpus`) is already live (user, 2026-10-19).

## Scope & Objectives

1. **Shared room environment.** Extract the pi-env connection from
   `src/runner/env.ts` (`JobConnection`, `jobEnv`, `sshTarget`,
   `DaemonConnection`) into a module both the runner and the daemon use. No
   second implementation; the runner's behaviour is unchanged.
2. **Daemon env in the room.** `src/session.ts` stops returning
   `NodeExecutionEnv`; the daemon's coding tools (read, write, edit, bash,
   grep) execute in room `assistant`, cwd `/home/agent`. Loss of the room is
   a tool error the session survives, not a daemon crash.
3. **Project context and cwd from the room.** The daemon's startup
   project-context read uses a room `SourceReader` (D7's constraint: context
   is read in the environment). The cwd section names the room path.
4. **D3 room convention.** vm mode works under `/home/agent`, cloning from
   `/work/<repo>` when it needs a repo; it never edits a `/work` clone. Stated
   in the interactive prompt (`~/satan-corpus/prompts/interactive.txt`);
   `dirty_clone` remains the detector. No new enforcement.
5. **Host reach removed.** `jailed-malebolge` (`flake.nix`) loses host coding
   reach: no rw launch-dir bind, no host network beyond what reaching the
   room and the gateway needs, `devToolPkgs` dropped if nothing host-side
   uses them. Resolves CHR-020.
6. **Execution profile is a per-run choice (CON-005).** The launcher (jail)
   selects the profile; the daemon only builds the environment that jail
   permits. This slice builds the room profile only, but
   the seam must admit two later profiles without redesign: **egress**
   (network, e.g. web search; never with the room attached; writes only its
   own memories) and **host** (interactive only; coding tools in a chosen host
   directory / jail configuration). Egress and room stay mutually exclusive by
   construction, not by convention. Per oubliette RFC-001 P3, a profile is a
   host jail (launcher, binds, network), not a daemon flag; a durable
   conversation is bound to one profile for life (oubliette RV-021 F-1: no
   return channel from room content to an egress session).
7. **OQ-4 deprecation inventory, as far as this jail.** Every host capability
   the jail grants today gets a disposition: the goad backend writes
   (`~/satan-corpus/goad` rw, `goadPkgs`, `MALEBOLGE_SKILLS` goad skill), the
   corpus read bind, the durable state dir, the satan runtime dir. Each one is
   kept (with a reason), moved (to an MCP tool or the room), or removed.

## Non-Goals

- Patch mode SATAN tools and per-mode tool filtering (RFC-019 OQ-2, OQ-3;
  RSK-019).
- Merging daemon and runner into one process (OQ-1: stay two).
- Renaming mode `interactive` (OQ-6: keep).
- Building the egress or host profiles (CON-005); only the seam for them.
- A host-side web tool for the room profile (OQ-5); web access is the
  egress profile's job, later.
- Moving SATAN tools out of Emacs (D6, OQ-8); the state-read tool (D2/D4).
- Retiring pi's `jailed-pi` / `~/notes/.pi/extensions/satan.ts` profile;
  that waits on the OQ-9 evals.
- Room provisioning fixes already tracked: ISS-048 (bun DNS), ISS-049 (git
  author identity), IDE-012 (per-repo setup step).

## Affected surface

- `~/dev/malebolge/src/runner/env.ts` → shared module; `src/session.ts`,
  `src/daemon-main.ts`, `src/config.ts`, `src/cwd.ts`, `src/project-context.ts`,
  `src/daemon-extensions.ts`; runner callers of `env.ts`.
- `~/dev/satan/flake.nix` (`jailed-malebolge`, `malebolgeJailOptions`, jail
  probes).
- `~/satan-corpus/prompts/interactive.txt` (D3 convention).
- `~/notes/justfile` `hello-durable` (launch dir, if still relevant).
- Possibly `~/dev/oubliette` (room access for a second host client).

## Risks, assumptions, open questions

- **Q1: how the jailed daemon reaches the room.** The runner is an unjailed
  unit. What does the daemon need bound or forwarded (ssh key, known hosts,
  oubliette room connection data, network to the guest) to reach `assistant`,
  and does that weaken the jail elsewhere?
  *Lead (research raw/flakes-gateway.md):* the door is a unix socket, so the
  room needs no IP network; the gateway is the only TCP dependency. Room
  profile jail = `--unshare-net` with exactly two bound sockets (room door,
  gateway client) and an in-jail forwarder; needs a flakes-side second relay
  listener (user-owned 0600 socket), revisiting flakes DEC-047's rejected
  alternative. Cross-repo prerequisite: a flakes slice.
- **Q2: two clients, one room.** The runner and the daemon would share room
  user `agent` and its pi-env daemon. Does pi-env tolerate two concurrent
  connections; does the runner's room readiness / clean step (`room.ts`,
  `prepare.ts`) assume it owns the room?
- **Q3: room lifecycle.** Who starts room `assistant` when the daemon needs it
  and no job is running; what the daemon does while it is down.
- **Q4: goad.** The goad backend writes `~/satan-corpus/goad` from the host
  jail today. Does it keep that bind (a host write not via a coding tool), move
  behind an MCP tool, or run in the room?
- **Q5: profile binding.** Where a conversation records its profile, and what
  refuses resuming it under another (session store keyed per profile, or a
  stamped field checked at resume).
- **A1:** pi-env's `RemoteExecutionEnv` serves the daemon's interactive
  latency adequately (it already serves jobs).
- **Risk:** losing host network removes web access from interactive SATAN's
  coding tools (OQ-5). Accepted as a non-goal unless design finds otherwise.

## Verification / closure intent

- Tests (malebolge): the shared env module covered once; the runner's suite
  green unchanged; daemon session builds a room env; project context read
  through a room reader.
- Flake checks: jail probes assert no launch-dir rw bind and no
  `/workspace/notes` (CHR-020's check); runner-socket-unjailed still passes.
- VH (by human): a live interactive session where `bash pwd` reports
  `/home/agent`, a file written lands in the room, `~/notes` is unchanged, and
  SATAN MCP tools still answer.

## Summary

One change: the interactive daemon's coding tools move from the host jail into
room `assistant`, reusing the runner's pi-env connection, and the jail loses
the host reach that made that unsafe.

## Follow-Ups

- RFC-019 OQ-2/OQ-3: patch mode SATAN tools; mode transport to satan-mcp.
- RFC-019 D2/D4: state-read tool over `~/.local/state/satan`.
- RFC-019 OQ-7: ADR-018 amendment / SPEC-002 revision, if design finds D1
  changes topology as recorded.
