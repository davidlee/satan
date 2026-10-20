# REV REV-010 — reconcile SL-027

Revision — a pending revise-intent against authored governance/spec
truth. The structured `[[change]]` payload lives in the sister `revision-NNN.toml`;
this prose companion carries the rationale and the free-text before/after excerpts
for prose-body section edits.

## Rationale

<!-- Why this revision: what authored truth needs to change and why, the scope of
     the staged delta, and (for ADR/POL/STD/prose rows) the before/after excerpts
     the structured payload only labels. Seeded at `revision new`. -->

The SL-027 audit (RV-039, Reconciliation Brief RB-G1..G3) found the ADR-017
authority ledger, SPEC-002 and SPEC-004 silent on what SL-027 built and
verified live (PHASE-06): the interactive malebolge daemon runs under a room
profile — its coding tools in oubliette room `assistant` as room user `satan`,
its model calls through the gateway client socket, its launcher jail with no
network. Design §4.9 (DEC-082) drafted these revisions for reconcile. No new
decision: each change restates what SL-027 decided (DEC-074..DEC-082) and
delivered (malebolge `ca2e0ae`, satan `a203159`).

## Reconcile narrative

- [RV-039 RB-G1, DEC-082] **ADR-017 authority ledger.**
  - Legend gains `satan-flake` — "The satan flake's launchers
    (`~/dev/satan/flake.nix`)"; the in-use sentence names it.
  - New row 3b (after row 3, which is unchanged):
    `| 3b | Malebolge execution profile | satan-flake | REQ-002 | jailed-malebolge / malebolgeRoomJailOptions (~/dev/satan/flake.nix), enforced at bwrap; checked by the malebolge-jail-profile flake check | SL-027 |`
  - Day-one paragraph: row 3b is new with SL-027, owned by `satan-flake`.
  - Transition log, SL-027 block:
    `row 3b ↳ 2026-10-20  (new) → satan-flake  (SL-027 audit; malebolge's execution profile is a launcher, not an Emacs profile (DEC-082); no prior enforcement to delete; malebolge-jail-profile green)`
- [RV-039 RB-G2] **SPEC-002.**
  - § Containers: new row **Interactive daemon** (`malebolge`, TypeScript;
    `jailed-malebolge`, room profile): owns its durable conversations
    (`durable/room/`); model loop, persona and SATAN MCP on the host; coding
    tools in room `assistant` as room user `satan`. Confinement row: the
    room serves the patch runner's and the daemon's tools.
  - § Current topology: the jails box reads "Interactive agents" (pi,
    malebolge); a sentence states the daemon's three couplings.
  - § Transports: new rows — pi-env over ssh through the door socket
    (daemon → room, control); HTTP over the gateway client socket
    (daemon → gateway, data; its jail has no network).
  - § End-state: SL-027 decided and built the daemon as a room client.
  - `diagrams.py` (context, end-state): node "Interactive agents", one card
    bullet each; HTML regenerated.
- [RV-039 RB-G2] **REQ-016 (SPEC-002 NF-004)** rationale gains a status line:
  the room-profile jail is a consumer class; its binds are the room's door,
  its own state and runtime dirs, and read-only inputs, asserted with their
  absences by the `malebolge-jail-profile` flake check (paths stay in the
  check and `~/flakes/SATAN.md`, per SPEC-002 D2).
- [RV-039 RB-G2, research T4] **REQ-017 (SPEC-002 NF-005)** rationale: room
  writes (room user `satan`'s home) are not host writes and lie outside the
  three roots; they reach the host only as patch jobs.
- [RV-039 RB-G3, DEC-074] **SPEC-004.**
  - § Execution environment: the room session (connection, shell, source
    reader, door table) lives in malebolge `src/room/`, shared with the
    interactive daemon; the runner's per-job env, tools and door values are
    unchanged.
  - § Concerns "One seat": the daemon is a concurrent room client outside the
    seat, as its own room user; it never writes `/work` clones and never
    starts or stops the room.
  - Consequential renames the move made: Components rows (`env.ts`/`guard.ts`
    on `src/room/`; git channel `runner/door.ts`, was `room.ts`) and the
    diagram's `JobConnection` → `ObservedConnection`.
