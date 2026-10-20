<!-- doctrine:section sec-1 -->
# 1. Design Problem

The malebolge room daemon (SL-027) runs in a terminal: `just hello-durable`
in `~/notes` starts satan-mcp, then `nix run ~/dev/satan#jailed-malebolge`
in the foreground. Emacs can only attach to a daemon something else started.
Its SATAN tools are read once at startup, so a satan-mcp restart with a
changed tool set needs a daemon restart, and an absent satan-mcp at startup
is fatal (`src/daemon-main.ts:31-35`).

This design makes the daemon a background user unit that Emacs starts, and
makes it keep a current SATAN tool list across satan-mcp restarts. It also
closes the mcp socket bind defect (ISS-042) in every jail.

```
 M-x malebolge-start ──▶ satan-mcp-start (if loaded)
                     ──▶ systemctl --user start malebolge-room
                     ──▶ malebolge-attach (waits ≤10s for the socket)

 malebolge-room.service ─ExecStart─▶ jailed-malebolge ─▶ node daemon-main.ts (live tree)
   claim socket ─▶ refresh SATAN tools ─▶ open store + resume ─▶ serve
   every input, every reconnect ─▶ refresh SATAN tools (empty if unreachable)
```

Decisions: DEC-083..DEC-088. Evidence: `research/research.md`.

<!-- doctrine:section sec-2 -->
# 2. Current State

| Concern | Today | Cite |
|---|---|---|
| Launch | foreground `nix run …#jailed-malebolge` from `~/notes` `hello-durable`, or unjailed `just daemon` in malebolge | `~/notes/justfile:10-18`, `~/dev/malebolge/justfile:20-23` |
| Emacs | `malebolge-attach` only; requires `comint` | `emacs/malebolge.el:14-36` |
| satan-mcp absent | top-level throw, exit 1 | `src/daemon-main.ts:31-35` |
| Tool list | `listTools()` once in `connectSatanTools`; extension `satan` | `src/satan-tools.ts:106-114` |
| Reconnect | lazy, on the next SATAN tool call (IMP-038, done) | `src/satan-tools.ts:42-75` |
| Registry | built and dropped inside `openSession`; daemon is its only caller | `src/session.ts:35` |
| Startup order | store + `Harness.open` + `resume()` before `serve` | `src/daemon-main.ts:42-54` |
| Socket bind | `serveUnix` unlinks whatever is there, then listens | `src/unix-socket.ts:44-45` |
| Live-owner probe | runner only: `refuseIfLive` before `serveUnix` | `src/runner/control.ts:326-338` |
| Stop | SIGINT/SIGTERM → stop daemon, close harness, exit 0 | `src/daemon-main.ts:64-84` |
| mcp binds | file: `~/dev/satan/flake.nix:86`, `~/satan-corpus/flake.nix:57`, `~/.config/emacs/flake.nix:80`; rw directory: `~/notes/flake.nix:71`; ro directory: `jailed-malebolge` (`~/dev/satan/flake.nix:277`) | research C9 |
| Units precedent | `satan-runner` (`features/satan/runner.nix:169-200`); services without `Install` in `harness.nix` | research C14 |

pi-durable 1.3.0: `Registry.install` replaces an extension by name and
publishes at once (`dist/harness/types.d.ts:339-346`); the registry may
change while the Harness runs (`harness.d.ts:14-15`); a call to an
unregistered tool settles as `tool_unavailable` (`dist/harness/tool.js:49-53`).

<!-- doctrine:section sec-3 -->
# 3. Forces & Constraints

- **ADR-017 §4** — with the client absent, daemons degrade, never fall open.
  Drives DEC-085.
- **ADR-017 §3 ledger** — no row moves. Row 2 (tool registry) stays
  `emacs-client`: the daemon mirrors satan-mcp's list. Row 3b (`satan-flake`,
  room jail profile) is untouched: the unit only calls the launcher.
- **ADR-018 D2, SPEC-001 REQ-006/REQ-009** — no daemon-side allowlist, tool
  flag or cached policy. Drives "empty on failure, never stale" (DEC-086).
- **ADR-018 D3** — no Emacs↔unit lifecycle RPC; `systemctl` is service
  management.
- **POL-001** — the start command is an Emacs-client seat; the off switch
  (`systemctl --user stop`/`mask`) is named and is not the SATAN kill switch
  (`satan-mcp-enabled`, row 6a).
- **DEC-077** — `ExecStart` is the `jailed-malebolge` wrapper.
- **DEC-075, REQ-016** — the room jail gains no binds.
- **SPEC-002 D2, REQ-018** — unit facts go in `~/flakes/SATAN.md`; no host
  literals in malebolge code.
- **CON-005** — room only; nothing here blocks a later host/egress profile.
- **REQ-015** — knowingly not met by the live-tree daemon; RSK-020.
- **Deployment** — the satan input deploys from GitHub
  (mem.fact.satan.runtime-jail-deploys-from-github-input); a home-manager
  switch restarts changed running units
  (mem.fact.nix.home-manager-switch-starts-stopped-units).

<!-- doctrine:section sec-4 -->
# 4. Design

## 4.1 The unit (DEC-083)

New feature module `~/flakes/features/satan/malebolge.nix`, registered after
`runner.nix` in `features/satan.nix:4-8`:

```nix
{lib, ...}: {
  name = "malebolge";
  platforms = lib.platforms.linux;
  homeManager = {inputs, pkgs, config, ...}: let
    jailed = inputs.satan.packages.${pkgs.stdenv.hostPlatform.system}.jailed-malebolge;
    home = config.home.homeDirectory;
  in {
    # On demand: no Install, so nothing starts it at login or on switch.
    systemd.user.services.malebolge-room = {
      Unit = {
        Description = "SATAN interactive daemon, room profile (malebolge)";
        Documentation = "file:${home}/flakes/SATAN.md";
        StartLimitIntervalSec = 300;
        StartLimitBurst = 5;
        # A switch must not kill a live conversation (as home-manager's emacs.nix).
        X-RestartIfChanged = false;
      };
      Service = {
        ExecStart = lib.getExe' jailed "jailed-malebolge";
        Restart = "on-failure";
        RestartSec = 10;
        Environment = ["HOME=%h" "XDG_RUNTIME_DIR=%t"];
      };
    };
  };
}
```

- Logs go to the journal (stderr; the daemon already logs there).
- Stop: systemd's default `KillMode=control-group` sends SIGTERM to every
  process in the cgroup, so node inside bwrap runs its stop handler
  (`src/daemon-main.ts:64-84`) directly.
- A changed wrapper or live tree takes effect only on
  `systemctl --user restart malebolge-room` (consequence of
  `X-RestartIfChanged`; documented in `SATAN.md`).
- Off switch: `systemctl --user stop` (session) or `mask` (durable). This is
  service management, not a SATAN kill switch.

## 4.2 Emacs: start, stop, attach wait (DEC-084)

`emacs/malebolge.el` gains:

```elisp
(defcustom malebolge-unit "malebolge-room.service"
  "The systemd user unit that runs the daemon." :type 'string)

(declare-function satan-mcp-start "satan-mcp")

(defun malebolge--systemctl (verb)
  "Run systemctl --user VERB on `malebolge-unit'; signal on failure."
  (let ((status (call-process "systemctl" nil nil nil "--user" verb malebolge-unit)))
    (unless (eql status 0)
      (user-error "systemctl --user %s %s failed (%s); see journalctl --user -u %s"
                  verb malebolge-unit status malebolge-unit))))

;;;###autoload
(defun malebolge-start ()
  "Start satan-mcp if available, start the daemon unit, and attach."
  (interactive)
  (if (not (fboundp 'satan-mcp-start))
      (message "malebolge: satan-mcp not loaded; the daemon has no SATAN tools")
    (condition-case err (satan-mcp-start)
      (error (message "malebolge: satan-mcp not started (%s); the daemon has no SATAN tools"
                      (error-message-string err)))))
  (malebolge--systemctl "start")
  (malebolge-attach))

;;;###autoload
(defun malebolge-stop ()
  "Stop the daemon unit."
  (interactive)
  (malebolge--systemctl "stop"))
```

`satan-mcp-start` failing for any reason — `user-error` (disabled, a
scheduled run live) or `error` (missing tool description, socket directory;
`satan/satan-mcp.el:114,142`) — is not fatal (RV-040 F-4):
the daemon degrades (4.3) and fills in on a later input. `malebolge.el` keeps
no hard dependency on satan.

Attach wait: `Type=simple` returns before the daemon listens. `attach()`
(`src/attach.ts:33-34`) connects through a bounded retry — every 200 ms for
up to 10 s on `ENOENT` or `ECONNREFUSED`, then the last error. Any other error
fails at once. A stopped unit leaves a stale socket (`close` does not unlink),
so `ECONNREFUSED` must be retried too.

## 4.3 SATAN tools: degrade and refresh (DEC-085, DEC-086)

`src/satan-tools.ts` replaces `connectSatanTools` with a handle that never
throws at construction:

```ts
export interface SatanTools {
  /** Re-list satan-mcp's tools and install them as the `satan` extension. */
  refresh: () => Promise<void>;
  close: () => Promise<void>;
}

export function satanTools(socketPath: string, registry: Registry, log: Log): SatanTools
```

- **refresh** = `connection.get()` then `listTools()`, then
  `registry.install(defineExtension({name: "satan", tools}))`, under one
  deadline (2 s) carried as an `AbortSignal`: `listTools` takes it (pi-mcp
  requests accept `signal`, `dist/client.d.ts:18-19`; pagination runs inside
  the same request options, `dist/client.js:218-230`), and the connection
  attempt races it. On any failure or timeout it installs the extension with
  `tools: []` and logs once per state change (`n SATAN tools` /
  `satan-mcp unreachable: …`). The list is satan-mcp's last answer or
  nothing — never a stale copy (REQ-006).
- **A timeout discards the connection** (RV-040 F-3): `reconnectingClient`
  gains `reset()`, which closes the current client (or abandons a pending
  `open()`, closing it if it later resolves) and makes the next `get()` open
  a fresh one. A refresh that times out calls `reset()`, so a hung connect or
  a wedged server never becomes the `current` every later call awaits, and a
  late response lands on a closed client and is dropped.
- **Coalesced:** at most one read in flight (a timed-out read is cancelled,
  above, so it no longer counts). A request made while a read is running
  gets one more read that starts after it, so a caller never gets a list
  older than its request, and installs happen in order.
- **Reconnect:** `reconnectingClient` gains an `onReconnect` callback; the
  handle passes `() => void refresh()`. The lazy reconnect path is otherwise
  unchanged (`src/satan-tools.ts:52-69`). The initial connection is no longer
  special: `first` goes away and every use goes through `get()`.
- **Removed tool:** no code. pi-durable settles the call as
  `tool_unavailable` (`dist/harness/tool.js:49-53`), and the next request's
  tool list omits it.

Callers:

- `src/session.ts`: `SessionOptions.extensions` becomes `registry: Registry`;
  `openSession` uses it as given. The daemon is the only caller.
- `src/daemon-main.ts` (order in 4.4): builds the registry with
  `registryOf(daemonExtensions(…))` minus `satan`, creates `satanTools`, and
  runs `refresh()` **before** `openSession`, so a turn resumed by
  `harness.resume()` already has the SATAN tools. The throw at `31-35` goes;
  the startup log reports the count from the first refresh.
- `src/daemon.ts`: `serve` takes a `beforeInput: () => Promise<void>` and
  `act` awaits it before `conversation.submit` for `input` only (not
  `abort`/`compact`). The daemon passes `satan.refresh`. This breaks the
  zero-tools deadlock: a degraded daemon picks up tools at the next input
  without any SATAN tool call.
- `src/daemon-extensions.ts`: the `satan` field leaves its options; the
  extension is installed by the handle.

## 4.4 One daemon per profile (DEC-087)

**Instance lock** (RV-040 F-1). New `src/instance-lock.ts`:

```ts
/** Held for the process's life; the kernel releases it if the process dies. */
export function acquireInstanceLock(path: string): { release: () => void }
```

It opens `path` with `node:sqlite` (`DatabaseSync`) and runs
`PRAGMA locking_mode=EXCLUSIVE; BEGIN EXCLUSIVE;`, keeping the handle open.
A holder elsewhere makes it throw `InstanceLocked(path)`. The path is
`daemon.lock` beside the store (`config.lockPath`, derived in
`src/config.ts` next to `storagePath`): `<state>/satan/durable/<profile>/`.
That directory is bound read-write into the room jail
(`~/dev/satan/flake.nix:284-286`), so jailed and unjailed room daemons contend
for the same file. Verified 2026-10-20 (node 24): a second process is
refused while the first holds the lock, and acquires it once the first is
killed with SIGKILL. The stop handler releases it last.

Only the lock holder reaches the socket, so its stale-socket unlink cannot
race another daemon of the profile.

**Socket claim.** Listening is the claim. `serveUnix` (`src/unix-socket.ts`)
stops unlinking blindly and becomes, for both servers:

```
listen(path)
  ok           ─▶ claimed
  EADDRINUSE   ─▶ probe: connect(path)
                    connects      ─▶ throw SocketInUse(path)      (live owner)
                    ECONNREFUSED  ─▶ unlink(path); listen again once  (stale)
                    ENOENT        ─▶ listen again once            (gone meanwhile)
                    other error   ─▶ throw it                     (RV-040 F-5)
  other error  ─▶ throw it
```

The runner's `refuseIfLive` (`src/runner/control.ts:326-338`) goes; the
runner maps `SocketInUse` to its `StartRefused` wording. One implementation,
and no error other than `ECONNREFUSED` authorises an unlink. For the daemon
this guards against a non-daemon listener or a hand-removed socket; mutual
exclusion is the lock's job.

Daemon startup order in `src/daemon-main.ts`:

```
config, gateway, models, env, persona, skills    (unchanged; no store yet)
acquireInstanceLock(lockPath)                     InstanceLocked ─▶ exit 1
serve(sessionReady, daemonSocket, satan.refresh)  claim; SocketInUse ─▶ exit 1
satan.refresh()                                   SATAN tools, or none
openSession(storage, {registry, …})               store open + resume
sessionReady.resolve(session)                     connections proceed
```

`serve` takes `Promise<Session>`; each connection awaits it before
`watchEvents`. If `openSession` rejects, the daemon closes the server and
exits 1. A refused daemon never opens the store or touches the socket.

The runner keeps one instance through systemd and its own checks; it does
not take the lock (out of scope).

`~/notes/justfile` loses `hello-durable` (and `attach-durable`, which
`M-x malebolge-attach` covers). Malebolge's `just daemon` stays the unjailed
dev path.

## 4.5 satan-mcp client binds (DEC-088)

`~/flakes/agents/jailed-agents.nix` exports, next to
`gatewaySocketOptions` (`:169`, export `:820`):

```nix
  # A satan-mcp client: the socket's directory, read-only. A file bind pins
  # the inode satan-mcp-start replaces (ISS-042); a writable directory lets
  # the jail replace the socket and impersonate satan-mcp.
  satanMcpOptions = with jail.combinators; [
    (try-readonly "/run/user/1000/satan/mcp")
    (try-fwd-env "XDG_RUNTIME_DIR")
    (try-fwd-env "SATAN_MCP_SOCKET")
  ];
```

`jailed-agents-test.nix` builds a launcher with `extraOptions =
agents.satanMcpOptions` and asserts it carries the read-only directory bind
and never `mcp/mcp.sock` or a writable bind of `/run/user/1000/satan/mcp`.

Consumers replace their own lines with `jailLib.satanMcpOptions`:
`~/dev/satan/flake.nix:84-91` (`mcpJailOptions` keeps its emacs server
bind), `~/satan-corpus/flake.nix:57`, `~/.config/emacs/flake.nix:80`,
`~/notes/flake.nix:69-73`. `jailed-malebolge` keeps its own explicit
`readonly` bind (`~/dev/satan/flake.nix:277`), which its
`malebolge-jail-profile` check already asserts; it forwards none of the env.

That bind is strict, and only `satan-mcp-start` creates the directory
(`satan/satan-mcp.el:444`, after its disabled check at `:432`), so on a
fresh login without satan-mcp bwrap would fail before the daemon could
degrade (RV-040 F-2). The launcher's existing pre-start `add-runtime
"mkdir -p …"` (`~/dev/satan/flake.nix:284`) also creates
`/run/user/1000/satan/mcp`. Emacs still sets it to 0700 on start
(`satan-mcp--check-socket-dir`). The directory bind then sees satan-mcp's
socket whenever it appears.

Deploy order: `~/flakes/agents` first (the other flakes consume it as
`inputs.agents`), then each consumer's lock; satan's needs push +
`nix flake update satan` in `~/flakes`.

## 4.6 Docs and governance (drafted here, applied at reconcile)

- `~/flakes/SATAN.md`: units table gains `malebolge-room` (on demand,
  `jailed-malebolge`, `X-RestartIfChanged=false`, `M-x malebolge-start`);
  lines 22 and 80 drop "not a unit"; beside the runner's "store build, never
  the working tree" (171-174), the live-tree exception, citing RSK-020.
- `~/dev/malebolge/README.md:80-105`: launch via `M-x malebolge-start`;
  `just daemon` for dev.
- `~/dev/malebolge/docs/internals.md:63-64, 90-92`: start path; tool list
  refreshed per input and reconnect; residual socket race.
- REV at reconcile: REQ-015 rationale "Tracked gaps" adds RSK-020; SPEC-002
  daemon row (`spec-002.md:36`) says "on-demand user service" without
  naming the unit (SPEC-002 D2).
- Backlog: IMP-045, IMP-039, ISS-042 resolved at close; RSK-020 stays open.

<!-- doctrine:section sec-5 -->
# 5. Code Impact

| Repo | File | Change |
|---|---|---|
| malebolge | `src/satan-tools.ts` | `satanTools` handle: coalesced refresh under one deadline, empty on failure, `onReconnect`; `reconnectingClient.reset()` |
| malebolge | `src/session.ts` | `registry` replaces `extensions` |
| malebolge | `src/daemon-extensions.ts` | drop the `satan` option |
| malebolge | `src/daemon.ts` | `serve(Promise<Session>, path, beforeInput)` |
| malebolge | `src/daemon-main.ts` | startup order (4.4): lock, claim, refresh, open; no throw on absent satan-mcp; release lock on stop |
| malebolge | `src/instance-lock.ts` (new) | `acquireInstanceLock` over `node:sqlite` |
| malebolge | `src/config.ts` | `lockPath` beside `storagePath` |
| malebolge | `src/unix-socket.ts` | `serveUnix` claims by listening; probe on `EADDRINUSE`; `SocketInUse` |
| malebolge | `src/runner/control.ts` | drop `refuseIfLive`; map `SocketInUse` to `StartRefused` |
| malebolge | `src/attach.ts` | bounded connect retry |
| malebolge | `src/coalesce.ts` (new), `src/reconnecting-client.ts` (new) | one refresh in flight with one shared follow-up; lazy connect with `reset()` (extracted in PHASE-02) |
| malebolge | `src/attach-main.ts`, `justfile` | exit 1 when attach gives up; `daemon` recipe notes satan-mcp is optional |
| malebolge | `emacs/malebolge.el` | `malebolge-start`, `malebolge-stop`, `malebolge-unit` |
| malebolge | `test/satan-tools.test.ts`, `test/daemon.test.ts`, `test/session.test.ts`, `test/attach.test.ts`, `test/harness-fixture.ts`, `test/unix-socket.test.ts` (new), `test/instance-lock.test.ts` (new), `test/config.test.ts` | see §6 |
| malebolge | `README.md`, `docs/internals.md` | §4.6 |
| flakes | `features/satan/malebolge.nix` (new), `features/satan.nix` | unit |
| flakes | `agents/jailed-agents.nix`, `agents/jailed-agents-test.nix`, `agents/README.md` | `satanMcpOptions` + test |
| flakes | `SATAN.md` | §4.6 |
| flakes | `features/profiles/personal-linux.nix`, `features-test.nix` | enable `satan.malebolge`; expect it in the Sleipnir selection |
| satan | `flake.nix` | `mcpJailOptions` uses `satanMcpOptions`; `jailed-malebolge` pre-creates `/run/user/1000/satan/mcp` |
| satan-corpus | `flake.nix` | uses `satanMcpOptions` |
| emacs | `flake.nix` | uses `satanMcpOptions` |
| emacs | `apps/dl-satan.el` | `:commands` lists `malebolge-start`, `malebolge-stop` |
| notes | `flake.nix`, `justfile` | uses `satanMcpOptions`; `hello-durable`, `attach-durable` removed |

<!-- doctrine:section sec-6 -->
# 6. Verification

VT (by test):

| id | Test | Where |
|---|---|---|
| VT-1 | refresh installs satan-mcp's current list; after a restart with a changed tool set, the next input sees the new set | `test/satan-tools.test.ts` |
| VT-2 | satan-mcp absent at start: daemon starts, zero SATAN tools, no throw | `test/satan-tools.test.ts`, `test/daemon.test.ts` |
| VT-3 | degraded daemon gains tools on the next input once satan-mcp is up (no tool call needed) | `test/daemon.test.ts` |
| VT-4 | hung `listTools` and a stalled connect each time out → empty set, connection reset; the next refresh reconnects; a late response is dropped | `test/satan-tools.test.ts` |
| VT-5 | coalescing: a refresh requested during a read gets a read started after it; installs in order | `test/satan-tools.test.ts` |
| VT-6 | removed tool: a call settles as `tool_unavailable`, model sees an error result | `test/satan-tools.test.ts` |
| VT-7 | satan-mcp lost and recovered mid-turn: the reconnect refreshes; later calls succeed | `test/satan-tools.test.ts` |
| VT-8 | concurrent inputs each await one refresh and submit | `test/daemon.test.ts` |
| VT-9 | a second daemon on a live socket refuses before opening the store (store file untouched); two concurrent starters (free or stale socket): exactly one serves, the other exits on `InstanceLocked` without opening the store | `test/daemon.test.ts` |
| VT-10 | `serveUnix`: free path listens; live owner → `SocketInUse`, socket untouched; stale (`ECONNREFUSED`) → replaced; probe error other than `ECONNREFUSED`/`ENOENT` propagates, nothing unlinked; runner tests stay green | `test/unix-socket.test.ts` (new), runner tests |
| VT-15 | `acquireInstanceLock`: second acquire throws `InstanceLocked`; acquire succeeds after release and after the holder process is killed (child process) | `test/instance-lock.test.ts` (new) |
| VT-16 | `config.lockPath` sits beside `storagePath` in the profile directory | `test/config.test.ts` |
| VT-11 | in-flight turn resumed after restart has SATAN tools (refresh before `openSession`) | `test/session.test.ts` |
| VT-12 | attach retries `ENOENT`/`ECONNREFUSED` up to its bound, fails fast on others | `test/attach.test.ts` |
| VT-13 | `satanMcpOptions` launcher binds the directory read-only, never `mcp/mcp.sock` | `~/flakes/agents/jailed-agents-test.nix` |
| VT-14 | `malebolge-jail-profile` asserts the launcher pre-creates `/run/user/1000/satan/mcp`; other satan flake checks stay green | `nix flake check ~/dev/satan` |

VA (by agent):

- VA-1: grep every jail launcher built by the four flakes for `mcp/mcp.sock`
  and a writable `satan/mcp` bind: none.
- VA-2: `systemctl --user cat malebolge-room` shows no `[Install]`,
  `X-RestartIfChanged=false`; `home-switch` with the unit running does not
  restart it.
- VA-3: with `/run/user/1000/satan/mcp` absent (fresh login, satan-mcp
  never started), the unit starts, logs zero SATAN tools and stays up; after
  `satan-mcp-start`, the next input lists them.

- VA-4: `malebolge-start` with satan-mcp signalling an `error` still starts
  the unit and attaches, with the message.

VH (by user):

- VH-1: from a fresh Emacs, `M-x malebolge-start` brings the daemon up with
  no terminal and attaches.
- VH-2: restart satan-mcp (or Emacs); a SATAN tool call then succeeds with
  no daemon restart.
- VH-3: `M-x malebolge-stop` stops cleanly (journal shows the stop handler).

`just check` in malebolge (format, lint, typecheck, vitest with coverage gate) green; byte-compile `malebolge.el`
without warnings.

<!-- doctrine:section sec-7 -->
# 7. Risks & Open Edges

- **RSK-020** — two malebolge revisions in production (pinned runner,
  live-tree daemon). Accepted; tracked against REQ-015.
- **Instance lock relies on POSIX advisory locks** (via SQLite) on a local
  filesystem; `~/.local/state` is local. A process that ignores the lock (an
  older daemon build) is not excluded; only builds with this change contend.
- **Deploy ordering** — `~/flakes/agents` before its consumers; satan's
  bind change needs push + `nix flake update satan`. A consumer still on the
  old agents lock keeps its old bind until bumped; VA-1 catches it.
- **`X-RestartIfChanged=false`** — a running daemon can lag the deployed
  wrapper until restarted. Visible in `systemctl --user status` (unit file
  changed); documented.
- **Refresh latency** — one local `listTools` per input; bounded at 2 s when
  Emacs is hung, then the connection is reset. A hung Emacs delays an input
  by at most that bound.
- **RSK-018** unchanged: the attach socket now exists for longer, same
  threat.
- Open edge: socket activation and a `malebolge@<profile>` template remain
  non-goals (slice).

