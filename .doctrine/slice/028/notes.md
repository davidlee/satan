# Notes SL-028: malebolge room daemon as an Emacs-started user unit, robust to satan-mcp restarts

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Harvest
<!-- single-copy: updated in place each harvest; ids only, never restated content -->
fresh-as-of: <yyyy-mm-dd> · <PHASE-NN | stage> · <head-commit>

### Produced

### Learned

### Open

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
