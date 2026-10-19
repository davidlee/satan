# Notes SL-027: malebolge daemon vm mode: coding tools in the room

Durable per-slice scratchpad — tracked in git. The place to lift anything from a
disposable phase sheet (`.doctrine/state/.../phase-NN.md`) that must survive
`rm -rf` before the slice close-out audit harvests it.

## Design triage (2026-10-19, explore stage, run dr-01a15431)

Evidence: `research/research.md` (X1–X6, deltas 1–9). Ids below are doc-local
to this triage unless prefixed.

### Constraining governance

ADR-017 (protocol boundary; ledger row 3 = jail profiles), ADR-018 (topology;
OQ-1 open), POL-001 (cutover, no parallel impl), SPEC-002 NF-004/005/006,
SPEC-004 §Execution environment + REQ-033, SL-026 DEC-072 (context read in
env), CON-005 (profiles), CON-003 (door as user), flakes DEC-047 (gateway
socket; rejected alternative now applies), oubliette RFC-001 P1/P3 + RV-021 F-1.

### Shaping decisions already taken (user, 2026-10-19)

- Slice D1 + D3 only; two processes (RFC-019 OQ-1); keep mode name
  `interactive` (OQ-6); no web tool (OQ-5 → egress profile, later).
- CON-005: room / egress / host profiles; egress ∦ room by construction;
  profile = host jail.
- Gateway reach via a flakes-side socket listener + in-jail forwarder, as a
  separate flakes slice, landing first; design here proceeds in parallel.

### Open questions (→ design inquiries)

1. Room-profile jail: exact binds/env/pkgs and probes (delta 1, X1, X3).
2. Shared room module: boundary and name (delta 2).
3. Daemon door + room cwd configuration: shape, source, NF-006 naming (delta 3).
4. No-repo launch: how the daemon's pi-env server starts under `/home/agent`
   with the room base on PATH (X6).
5. Room down: at startup (wait vs degrade) and per call (grep error map) (X5).
6. Profile binding: per-profile durable store (X2).
7. Project context through the room: root, `gitRootDirs` in env, DEC-072
   amendment (Thread 2 Q5).
8. OQ-4 inventory dispositions: goad, corpus ro, malebolge tree ro,
   `devToolPkgs`, durable dir, satan runtime dir (X4).
9. Governance outputs: ledger row 3 owner, SPEC-002/SPEC-004 REVs, ADR-018
   OQ-1 note, decision citing flakes DEC-047 (delta 8).
10. Verification: live two-client test, VH session (delta 9).

### Risks

- pi-env server-side concurrency unread (two clients on `agent`).
- Interactive latency over pi-env unmeasured (scope A1).
- Cross-repo prerequisite (flakes slice) could slip; the room profile cannot
  ship without it.
- Room not enabled at boot: an always-on daemon meets a down room routinely.

### Assumptions

- Same pinned pi-env in runner and daemon (no deploy churn in
  `~/.pi/mobile/tools`).
- The daemon runs as the user, so door 0700 dir is reachable once bound.

## flakes:SL-015 handback (2026-10-20)

Adopted into DEC-075 / DEC-077 (user 'yes'): jail renders its own ssh_config
(store-path socat in its closure); door file is data only; oubliette IMP-022
backlogged (room-client bundle, 9127afe there). Verification gains: audit the
interactive SATAN MCP tool set for any tool that carries data off-host (Emacs
has network) — the residual named in DEC-075, flakes:DEC-077's "host sockets
are channels" note.
