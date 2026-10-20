# IDE-013: Interactive executor profiles: user-picked jailed executors for pi-durable sessions, with a taint rule

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

User idea, 2026-10-20 (after SL-027 PHASE-06). This is the **host profile**
that CON-005 reserves ("coding tools in a chosen host directory / jail
configuration"), generalised to a menu of profiles.

## Mechanism (cheap; verified)

pi-env's `Connection` takes `command: string[]` and speaks its protocol over
stdio. Today the command is `ssh … <daemon>` (malebolge
`src/room/connection.ts:228`, `daemonCommand`). A bwrap'd executor is the
same thing with `bwrap <binds> <daemon>` as the argv, so SL-027's seams
(`ObservedConnection`, fault rewording, `daemonEnv`) carry over unchanged.

```
 daemon (model loop, persona, MCP; offline jail)   executor (coding tools)
 ┌───────────────────────────┐  stdio  ┌──────────────────────────────┐
 │ ObservedConnection        │────────▶│ ssh → room       (room)      │
 │   command: string[]       │         │ bwrap → host dir (host:<p>)  │
 └───────────────────────────┘         └──────────────────────────────┘
```

## Shape (user direction)

- **Central definitions; the user picks, never the agent.** Executor profiles
  are defined centrally (Nix-built, each probed by a flake check like
  `malebolge-jail-profile`), not assembled at runtime from free-form config. A
  runtime argv builder would make its parser the sandbox and escape the flake
  checks. A profile is an ADR-017 authority item: the human surface (attach
  client / Emacs) selects it, and no tool call can.
- **Read-only adjacency is normal.** Coding agents already get read-only
  access to neighbouring repos to integrate (e.g. jailed SATAN agents read
  malebolge). A profile is therefore "rw: X; ro: an adjacency set", and the
  taint rule must reason over both.
- **Separate sessions and threads by an adjacency rubric.** A conversation is
  bound to a compatibility class. Narrowing permissions is always allowed.
  Widening is allowed only within the class and never adds egress (CON-005:
  egress and the room never combined; oubliette RV-021 F-1: a shared
  transcript is a return channel). The rubric that defines a class (which
  repos/content may share a thread) is the open design question.
- **Git-carried text as the context boundary.** Content crosses between room
  and local sessions only as reviewable text in git: doctrine memories
  (persisted via git, reviewable in quarantine, with trust levels), and other
  committed text. Not transcripts. This makes the boundary inspectable,
  unlike a shared conversation.
- **The model is told on swap.** The persona env file
  (`prompts/env/<profile>.txt`) is chosen at startup; a mid-session swap
  injects a notice naming the new executor and its permissions.

## Open questions

- The adjacency rubric: what makes two profiles compatible in one thread
  (same rw root? ro sets nested? taint from private roots like ~/notes?).
- Where taint is recorded (session store metadata) and who enforces the swap
  check (daemon vs launcher).
- Relation to CON-005's open item: an egress profile reading hippocampus
  written by room sessions (room → memory → egress).
- Does the room become one entry in the same menu, with `ssh` as its argv?

Related: CON-005, RFC-019, ADR-017 (authority ledger), SL-027 (room profile;
`src/room/` seams), RSK-019 (per-mode tool filtering).

## Sequencing

User, 2026-10-20: **after RFC-019.** RFC-019 D1 makes the room the default
(host coding tools removed); host executor profiles are a later exception on
top of it, not a competing default. (`doctrine after` cannot target an RFC, so
this is a `references --role concerns` edge.)
