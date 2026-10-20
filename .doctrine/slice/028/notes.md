# Notes SL-028: malebolge room daemon as an Emacs-started user unit, robust to satan-mcp restarts

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: 2026-10-20 · PHASE-05 · satan 9df0cf5

### Produced
- PHASE-01 done — instance lock, `lockPath`, `serveUnix` claim (malebolge
  7b9294a, 3a39d16); § PHASE-01
- PHASE-02 done — satanTools handle, coalesce, reconnecting-client
  (malebolge 460b7c6..298fcd0, pi worker); § PHASE-02
- RV-041 — PHASE-02 code review, 9 findings fixed
- PHASE-03 done — registry-taking openSession, serve(Promise<Session>,
  beforeInput), startDaemon, thin daemon-main (malebolge c0d3264..f44240e,
  pi worker via `--mode json` + pi-run-reduce); § PHASE-03
- RV-042 — PHASE-03 code review (pi reviewer), 2 findings fixed + verified
- PHASE-04 done — attach connect retry, malebolge-start/stop, docs
  (malebolge bb55244..7d7cc08); § PHASE-04
- RV-045 — PHASE-04 code review (pi reviewer), 3 findings fixed + verified
- PHASE-05 done — satanMcpOptions in agents + four consumers, jailed-malebolge
  mcp dir (satan 9df0cf5; ~ d73eddd5; corpus ff80e21; emacs 827fb04; notes
  8f338e9); § PHASE-05
- RV-047 — PHASE-05 code review, F-1 → IMP-047
- DEC-101 — notes jailed-pi bind order (consult); superseded by DEC-102 (bind removed)

### Learned
- mem.fact.malebolge.eslint-ignores-doctrine-state — typed eslint needs
  `.doctrine` ignored after `doctrine install`
- mem.pattern.satan.drive-jailed-pi-worker — chunked jailed-pi worker +
  reviewer sessions; jail gotchas (biome, runner tests, doctrine extension)
- mem.fact.nix.bwrap-bind-order-and-try-skip — parent bind after child hides
  it; `-try` overlays vanish when the source is absent

### Open
- DEC-083..DEC-088 — design decisions binding PHASE-03..06
- RSK-020 — two malebolge revisions in production; REV at reconcile
- IMP-047 — goad backends via satan-runner; drop writable goadBackends bind
- doctrine pi extensions bake one install's doctrine path (malebolge: a host
  /nix/store path, absent in the jail; satan: `/run/doctrine-bin`, absent on the
  host, and a jailed run rewrote satan's boot.md with it) — doctrine install
  concern, unfiled

## Design triage (2026-10-20, exploring)

Evidence: `research/research.md` (C = code fact, G = governance, X = cross-thread).

### Constraining governance
- ADR-017 §4: absent client → degrade, never fall open (G1). Ledger: no row
  moves; row 2 (tool registry) stays `emacs-client`, the daemon mirrors it (G3).
- ADR-018 D2 / SPEC-001 REQ-006, REQ-009: no daemon-side allowlist or tool
  flag (G4). ADR-018 D3: no Emacs↔unit lifecycle RPC (G5).
- POL-001: interactive command is an Emacs-client seat (G2); name an off
  switch distinct from `satan-mcp-enabled` (G6).
- DEC-077: `ExecStart` is the `jailed-malebolge` wrapper (G7). DEC-075 /
  REQ-016: no new binds (G8). SPEC-002 D2: unit facts in `~/flakes/SATAN.md` (G9).

### Open questions (→ design inquiries)
- Emacs command placement: `malebolge.el` vs satan (X5).
- OQ-2 satan-mcp absent at start: degrade to zero SATAN tools (X1).
- **New: zero-tool start + lazy reconnect deadlocks.** Reconnect fires only
  on a SATAN tool call (C3); with no SATAN tools the model cannot call one.
  A refresh trigger independent of tool calls is needed (e.g. per turn).
- IMP-039 refresh trigger and mechanism: keep the `Registry`
  (`session.ts:35`, C5), `install` the `satan` extension by name (C4).
- OQ-3 removed tool: library error result `tool_unavailable` (C6); reword?
- OQ-1 two room daemons: unlink-and-steal + shared sqlite (C1).
- Unit shape: name, restart policy, environment, switch behaviour.
- ISS-042: three file binds (C9), check coverage (C10).
- REQ-015 live-tree split: record, don't leave silently false.

### Risks
- `home-manager switch` restarts a running unit whose definition changed;
  every satan input bump changes `ExecStart` → interrupts an in-flight run.
  Candidate: `X-RestartIfChanged = false` (UNVERIFIED for HM's sd-switch).
  Memory: mem.fact.nix.home-manager-switch-starts-stopped-units.
- The satan input deploys from GitHub (mem.fact.satan.runtime-jail-deploys-from-github-input):
  the `flake.nix:86` bind fix ships only after push + `nix flake update satan`.
- ~/flakes switches override `malebolge` with the dev checkout
  (mem.fact.flakes.switch-builds-dev-checkouts). The unit itself runs the
  live tree anyway (C11).

### Assumptions
- pi-durable 1.3.0 registry is live-replaceable (C4 ✓). Confirmed.
- systemd user manager supplies `HOME`/`XDG_RUNTIME_DIR` (C8; set explicitly anyway).

### Scope corrections
- ISS-042 covers three flakes, not two (+ `~/.config/emacs/flake.nix:80`).
- IMP-038 already done; drop "close IMP-038".
- `satan-mcp-start` re-listens only on a fresh start (C12).
- Affected surface adds `src/session.ts`, `test/harness-fixture.ts`.

## Design review (2026-10-20, reviewing)

- Human lane: user approved all sections (sec-4..7 re-approval pending after
  RV-040 revisions).
- Adversarial lane: GPT-6-sol, RV-040. F-1 (blocker, socket race) needed
  two rounds: listen-first left a stale-socket race; fixed by a lifetime
  instance lock (node:sqlite exclusive lock, verified empirically 2026-10-20:
  second holder refused, released on SIGKILL). F-2 (blocker, mcp dir absent
  → jail fails before degrade), F-3/F-4/F-5 (major) fixed first round. All
  verified; pass concluded.
- **Further pass: none needed at design.** Remaining risk is implementation
  conformance, not design: startup order (lock → claim → refresh →
  openSession), the coalesced refresh with cancellation, and `serveUnix`'s
  error classification. Those are VT-4/5/9/10/15 and belong to /audit; a
  code review of the PHASE that lands §4.3–4.4 should probe them first.

## Plan (2026-10-20)

- Plan-level refinement beyond design §5: PHASE-03 extracts the startup
  sequence to `src/daemon-start.ts` (`startDaemon`, after
  `src/runner/start.ts`) so §4.4's order is testable; `daemon-main.ts` stays
  the entry. Same behaviour; selector added.
- Pushes gated on the user: `~/flakes` in PHASE-05 (consumers lock agents
  from GitHub), `~/dev/satan` in PHASE-06.
- No home-switch mid-slice (runner shares `serveUnix`; switches build
  malebolge from the dirty checkout).

## PHASE-01 (2026-10-20, done) — malebolge `3a39d16`

- Base fix first: malebolge `just check` was red at base — `doctrine install`
  writes TS under `.doctrine/state/pi/extensions/` and eslint linted it.
  `7b9294a` adds `.doctrine` to eslint ignores.
- `src/instance-lock.ts`: `acquireInstanceLock(path)` mkdirs the parent (the
  profile dir may not exist before the store opens, PHASE-03 order), opens
  `DatabaseSync`, `PRAGMA locking_mode=EXCLUSIVE; BEGIN EXCLUSIVE;`. Only
  `errcode === 5` (SQLITE_BUSY) becomes `InstanceLocked`; e.g. a non-database
  file propagates SQLite's own error. Same-process second acquire is refused
  too (SQLite tracks locks per inode). `release` is not idempotent (a second
  `db.close()` throws) — PHASE-03's stop handler should call it once.
- `serveUnix` → `claimUnix` + `probeUnix` (`"live" | "stale" | "gone"`, other
  errors rethrown). Verified on this host: `listen` on a regular file →
  EADDRINUSE, `connect` to it → ECONNREFUSED, so the runner's "stale regular
  file" test still takes the unlink path. The ENOENT (gone meanwhile) branch
  is a race and stays untested by design (one branch).
- Behaviour change reaching the daemon now (via shared `serveUnix`): a second
  daemon on a live socket gets `SocketInUse` instead of stealing the path.
  No daemon test relied on stealing.
- Runner: `refuseIfLive` deleted; `serveControl` maps `SocketInUse` →
  `StartRefused("a runner already serves …")`.
- Test fixture `childProcess(source)` (`test/fixtures.ts`): runs an ES module
  in a child node, resolves on its first stdout line, `kill()` = SIGKILL.
  Register `onTestFinished(child.kill)` — a failing assertion before `kill`
  otherwise leaves the child alive and vitest hangs (seen once in a mutation
  check).
- Sandbox quirk: `listen` under a missing directory reported EACCES, not
  ENOENT, in this session's sandbox; the test asserts `syscall: "listen"`.
- Not run: no home-switch (runner shares `serveUnix`; see Plan notes).

## PHASE-02 (2026-10-20, done) — malebolge 460b7c6..298fcd0

Executed by jailed pi (deepseek-flash) in 9 chunks, one session (`satan-a`);
orchestrator reviewed each, ran biome + `just check` on the host, committed per
chunk. Per-phase review by a second pi session: RV-041 (9 findings, all
fix-now, verified, concluded). Workflow: mem.pattern.satan.drive-jailed-pi-worker.

Shape landed (PHASE-03 builds on it):
- `src/satan-tools.ts`: `satanTools(socketPath, registry, log, { deadlineMs? })`
  → `{ refresh, close }`. Refresh = `coalesce(read)`; read = get + listTools
  under one `AbortSignal.timeout` (connect raced via `within`), install, or
  install `[]` on unreachable / timeout (→ `reset()`) / pi-durable rejecting
  the list (`satan-mcp tools rejected: …`). Logs once per state
  (`n SATAN tools` | unreachable | rejected). `connectSatanTools` is the thin
  adapter PHASE-03 deletes (its missing-extension throw is unreachable).
- `src/coalesce.ts`: one run in flight, one shared follow-up; a caller resolves
  after a run that started after its request.
- `src/reconnecting-client.ts` (extracted in C5): lazy open; `reset()` abandons
  (late client closed on arrival); `close()` is terminal (get() rejects
  "satan-mcp client is closed"); one connect per failing get (no immediate
  second attempt); `onReconnect` is loss-driven — a drop the handle did not
  cause arms it, the next successful connect announces once; own
  reset/close/abandoned attempts never announce (avoids an announce→read
  chain on a wedged server).
- Test kit: `fakeMcpServer(path, tools, { silent, hangUp })` with `release`,
  `connections`, `requests`, `serve`, `ended`; `openFauxHarness({ registry })`.

Plan-level deviations from design §4.3 (accepted): optional 4th param
`{ deadlineMs }`; refresh cannot reject on a refused list but can if a
registry subscriber throws (only production subscriber, pi-durable `#kick`,
cannot; JSDoc says so); `close()` does not cancel an in-flight read (bounded
by the deadline); a coalesced caller may wait up to two deadlines — PHASE-03's
`beforeInput` inherits that bound (≤ 4 s at the 2 s default).

verify-vt: PHASE-02 VTs report UNATTRIBUTABLE (test files are in malebolge,
outside this repo's diff) — expected, as in SL-027
(mem.pattern … reconcile-selectors-outside-phase-registry); evidence is the
malebolge commits above.

## PHASE-03 (2026-10-20, done) — malebolge c0d3264..f44240e

Executed by jailed pi (deepseek-flash) in 5 chunks, session `satan-b`, driven with
`jailed-pi --mode json` → `bin/pi-run-reduce` (status line + budgeted transcript)
instead of `-p` text; orchestrator reviewed each, ran biome + `just check` on the
host, committed per chunk. Per-phase review: RV-042 by a second pi session
(`satan-b-review`), which also verified the fixes in a follow-on turn.

Shape landed (PHASE-04 builds on it):
- `src/daemon-start.ts` `startDaemon(config, { log, models? })` → `DaemonHandle`
  (`stop` memoised + the facts daemon-main logs). Order: persona, skills, gateway
  check, models (`requireKnownModel`), `daemonEnv`, project context → lock (refusal
  closes env) → `satanTools` → serve (claim) → refresh → openSession → resolve.
  Failure undoes in reverse, lock last. `sessionReady` never rejects.
- `src/daemon-main.ts`: resolveConfig → startDaemon; `InstanceLocked`/`SocketInUse`
  → `refusing to start: …`, exit 1; signals → `handle.stop()`.
- `serve(Promise<Session>, path, beforeInput)`: `attach` registers its close handler
  before awaiting the session; a stream arriving on a destroyed socket is stopped
  (RV-042 F-1 — the startup window otherwise leaked a watch per early client).
- `openSession` takes `registry`; `daemonExtensions` has no `satan`;
  `connectSatanTools` gone.

Evidence and deviations:
- D7 (accepted): plan VT-2's lock/concurrency tests live in
  `test/daemon-start.test.ts`, with every other startDaemon test, not
  `test/daemon.test.ts`.
- VT-3 (session.test.ts): a turn held in its provider request across a close
  resumes on reopen; its pinned `satan` tool call executes against the reopen
  registry, and settles `tool_unavailable` without it. pi-durable pins the
  model-facing tool list at `prepare`; execution resolves against the live
  registry — so refresh-before-openSession is what makes the resumed call work.
- Mutation checks (orchestrator + reviewer): refresh-after-open, no release on
  failure, no server close on failure, no release on stop, un-memoised stop,
  beforeInput removed / added to abort, openSession ignoring the registry — all
  caught. The F-1 test failed 3/3 under the old close-handler ordering.
- Not run: no live daemon start against the real gateway (PHASE-04's VH/VA cover
  the unit path). The worker smoked the refusal path in the jail: exit 1,
  `refusing to start: another daemon holds …`.

pi-driving facts (folded into mem.pattern.satan.drive-jailed-pi-worker):
- `jailed-pi` runs bwrap `--die-with-parent`: a `nohup … &` launch dies when the
  launching shell exits. Run each chunk in the foreground under `timeout`.
- `--session-dir` must be under the bound cwd (jail `/tmp` is a fresh tmpfs);
  follow-on turns with the same `--session-id` then resume across runs.
- The scout profile writes brief files into the repo; delete them after.

## PHASE-04 (2026-10-20, done) — malebolge bb55244..7d7cc08

C1 (attach retry) and C3 (docs) by jailed pi, session `satan-c`; C2 (elisp, verbatim
from design §4.2) written by the orchestrator — reviewing it would have cost as much.
Per-phase review RV-045 by pi session `satan-c-review`; 3 findings fixed + verified.

Landed:
- `src/unix-socket.ts` `connectUnixWaiting(path, { intervalMs, timeoutMs })`: retries
  ENOENT/ECONNREFUSED, throws the last error; other codes throw at once. `codeOf` now
  exported. `attach(…, wait = 200 ms / 10 s)`; on failure prints
  `[cannot connect to <path>: <code>]` and rejects; `attach-main` exits 1 without a
  stack on coded errors only (RV-045 F-1, F-3).
- `emacs/malebolge.el`: `malebolge-unit`, `malebolge--systemctl`, `malebolge-start`,
  `malebolge-stop` as design §4.2; no `require 'satan-mcp`.
- README launch → `M-x malebolge-start`/`-stop`; dev recipes need `MALEBOLGE_PROFILE`
  (F-2); refusal is per profile. internals: unit start path, startup order, per-input
  refresh, residual race; stale "sets no MALEBOLGE_PROFILE" fixed (jail sets `room`).
- Beyond plan (small, in scope): `just daemon`'s `emacsclient -e (satan-mcp-start)`
  is `-`-prefixed, so a failed satan-mcp start no longer aborts the recipe — matches
  the soft dependency the docs state. Socket test helpers (`socketPath`, `rejection`,
  `staleSocket`) moved to `test/fixtures.ts`; daemon-start.test.ts's copies dropped.

Evidence:
- VT-1: `test/attach.test.ts` "attach: waits for the daemon" (ENOENT then served,
  stale then served, bound spent → last code, EACCES fails < 1 s, give-up line).
  Mutations (orchestrator + reviewer): ECONNREFUSED not retried, code filter removed,
  bound removed — each caught.
- VA-1 (host): `emacs --batch -Q` byte-compile with `byte-compile-error-on-warn` →
  exit 0. Stub script (call-process, malebolge-attach, message): unbound satan-mcp →
  "not loaded" + start + attach; `error` → message names cause + start + attach;
  `user-error` → attach; systemctl status 1 → user-error with status and journalctl
  hint, no attach; stop → `stop` verb. 10/10 PASS. Reviewer repeated it in the jail.
- `just check` green: 1655 tests, lines 98.52%.
- Not run: VH-1..3 — need the `malebolge-room` unit (PHASE-05/06).

## PHASE-05 (2026-10-20, done) — satan 9df0cf5; ~ d73eddd5; corpus ff80e21; emacs 827fb04; notes 8f338e9

Done directly by the orchestrator, no worker (small cross-repo nix edits).

Landed:
- `~/flakes/agents` (`~` repo `d73eddd5`, on origin/main): `satanMcpOptions` as design §4.5,
  exported beside `gatewaySocketOptions`, README exports list. `jailed-agents-test.nix`
  fixture `satanMcp` (specDev + the combinator) asserts `--ro-bind-try …/satan/mcp …`,
  both env forwards; refutes `mcp/mcp.sock` and `--bind(-try)? …/satan/mcp`.
- satan `9df0cf5`: `mcpJailOptions = satanMcpOptions ++ [emacs server]`; jailed-malebolge's
  `add-runtime mkdir` adds `/run/user/1000/satan/mcp`; `jailProbes.malebolge.present` asserts it.
- satan-corpus `ff80e21`, emacs `827fb04`: same replacement (emacs keeps its server bind).
  Emacs's lock commit carries the user's pending input updates too (user's call).
- notes `8f338e9`: `jailEnvOptions = satanMcpOptions`; `hello-durable`/`attach-durable` gone.
- All four consumers lock agents at `d73eddd5`. satan not pushed (waits for PHASE-06).

Beyond design (consulted): notes `jailed-pi` also binds `/run/user/1000/satan` writable
for goad's ingress socket (notes `e2965c4`, 2026-10-19), which would hide `mcp/`'s
read-only bind. DEC-101: apply `satanMcpOptions` after it, so `mcp/` is a read-only
overlay. Then, at the user's call, the bind was removed outright (DEC-102 supersedes
DEC-101; notes `16a98a8`): it served only interactive pi's `goad-emit`. IMP-047 keeps the
remaining half (goad backends updated via satan-runner, not a writable bind).

Evidence:
- VT-1: `checks.jailed-agents` red (missing attr) → green; mutation `try-readwrite` → red.
  `just gate` in ~/flakes green (tests + treefmt).
- VT-2: `malebolge-jail-profile` red on the new probe → green; `nix flake check` green
  with the override and again on the bumped lock.
- VA-1: every jail script in each flake's devshell closure grepped — 15 mcp-binding
  launchers clean, notes jailed-pi layered `ro mcp over rw satan`, jailed-malebolge strict
  `--ro-bind` (designed). Run with the agents override and again on the bumped locks.
  The grep matched `mcp/mcp.sock` in an old store launcher, so it can fail.
  EX-2: no `mcp/mcp.sock` literal in the four flake.nix.
- satan `just check` green (1309 tests); the first run aborted on ISS-044 (known flake).
- RV-047 (per-phase code review, done): F-1 minor — notes' overlay only holds when `mcp/`
  exists at jail launch, and the order is guarded by a comment → follow-up IMP-047;
  closed by DEC-102 (notes `16a98a8`). VA-1 re-run: notes jailed-pi binds no
  `/run/user/1000/satan` at all.

Process notes:
- satan-corpus's flake.nix is nixfmt-style; alejandra reformatted the whole file and
  was reverted with nixfmt. Format consumer flakes with their own formatter.
- A consumer edit using a new agents export doesn't evaluate until that consumer's lock
  moves; keep the edit uncommitted until the lock bump lands with it.

## PHASE-06 (2026-10-20, done) — ~ a49c3f0b, 62cebbe5; emacs 08367c7 (all pushed)

Entry: user reported satan pushed and home switched. Observed: satan origin/main = `8b8ea04`;
`~/flakes/flake.lock` dirty, root `satan` re-locked to `8b8ea04` (contains `9df0cf5`).

Landed (`~` a49c3f0b; emacs 08367c7):
- `features/satan/malebolge.nix` as design §4.1; registered in `features/satan.nix`.
- **Beyond design (§4.1/§5 omit it):** a feature is inert until selected. Added
  `feature.satan.malebolge.enable = lib.mkDefault true` to
  `features/profiles/personal-linux.nix`; `features-test.nix` `testSleipnirHomeSelection`
  expects `satan.malebolge#homeManager` (red without the enable → green).
- `SATAN.md`: repos row and daemon-catalog row drop "not a unit" / `hello-durable`; units
  table row; live-tree exception paragraph after the runner's store-build paragraph
  (RSK-020, restart after a wrapper or tree change).

Evidence:
- `just test`, `just gate`, `just home-build` green in ~/flakes.
- EX-1/VA-1: after home-switch the unit is `linked`, `inactive` (the switch did not start
  it); `systemctl --user cat` shows no `[Install]`, `X-RestartIfChanged=false`; no
  `*.wants` link in the generation.
- EX-3: ExecStart `/nix/store/k2ipkm4x…-jailed-malebolge/bin/jailed-malebolge`; its script
  `mkdir -p … /run/user/1000/satan/mcp` and `--ro-bind /run/user/1000/satan/mcp`; no
  `mcp.sock` literal.
- EX-4: unit started (MainPID 3489852, 21:13:05). Switched with RestartSec 10→11 (reloaded:
  `RestartUSec=11s`), then reverted and switched again: same MainPID and
  ActiveEnterTimestamp, NRestarts=0.
- EX-5 / VA-2: started with satan-mcp refusing (`ECONNREFUSED …/mcp.sock`, the mcp dir
  present): journal `0 SATAN tools`, unit stays active. User ran `satan-mcp-start`
  (socket recreated 21:21) and sent an input: journal `37 SATAN tools` at 21:22:08, same
  PID, NRestarts=0. Substitution (proposed, unopposed): satan-mcp refusing rather than the
  mcp dir absent at a fresh login; the absent case is VT-2's.
- VH-2 (user): satan-mcp stopped and restarted; a SATAN tool call then succeeded, no daemon
  restart (PID 3489852 throughout). Emacs-restart variant not run with the daemon up.
- VH-3 (user): `M-x malebolge-stop` at 21:22:55 — systemd "Stopped", no failure result,
  socat exited on SIGTERM. The stop handler logs only on failure (`daemon-main.ts:45`).
- VH-1 (user): first `malebolge-start` (21:23:01, new PID, 37 tools, attached) ran in a
  long-lived Emacs. From a fresh Emacs it failed: **`malebolge-start` not defined**.
  Cause: `~/.config/emacs/apps/dl-satan.el` `use-package malebolge :commands
  malebolge-attach` only; `;;;###autoload` cookies do nothing for a bare `:load-path`
  package. Beyond design (§5 omits the file): `:commands (malebolge-attach
  malebolge-start malebolge-stop)`; macroexpansion shows all three autoloads. Unit
  stopped, `systemctl --user restart emacs` (21:29:01), `M-x malebolge-start`: daemon
  PID 3512714 at 21:29:07, 37 SATAN tools, attached. Pass.
- RV-049 (per-phase code review, done): F-1 nit — SATAN.md credited
  `X-RestartIfChanged=false` with blocking tree edits; fixed in `~` 62cebbe5. Synthesis
  tolerates the `:commands` list duplicating the autoload cookies (the config's idiom).
- Pushed: `~` (a49c3f0b went out by auto-push before this session's push), emacs (6 commits,
  incl. PHASE-05's 827fb04).

For reconcile: design §5 code impact should list `features/profiles/personal-linux.nix`,
`features-test.nix` and `~/.config/emacs/apps/dl-satan.el`.

## Audit (2026-10-20) — RV-050 done

Conformance by hand (slice conformance / verify-vt read only satan's git; F-2 tolerated).
Suites green at HEAD: malebolge 1655, satan 1309 + `nix flake check`, `doctrine check gate`.
Findings: F-1 design §5 omits seven delivered files (design-wrong → design §5 + selectors);
F-2 tooling blind cross-repo (tolerated); F-3 SPEC-002:36 and REQ-015 stale (design-wrong →
REV); F-4 EX-5 run with a refused socket, not an absent dir (tolerated). Brief in RV-050.

Harvest: memories `mem.fact.nix.flakes-feature-needs-profile-enable`,
`mem.fact.emacs.use-package-load-path-autoload-cookies-inert`. Phase sheets swept — nothing
else durable beyond notes § PHASE-06.
