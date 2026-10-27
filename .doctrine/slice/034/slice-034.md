# malebolge wakeups: SATAN schedules its own turns in the room daemon

## Context

All paths are in `~/dev/malebolge` unless stated.

SATAN acts in the room daemon (`MALEBOLGE_PROFILE=room`, attached with
`M-x malebolge-attach`) only when the user sends a turn. The goal of this
slice: SATAN can "fiddle around" in its room — ruminate, make tool calls, work
on its own computer — while the user is away. The mechanism is a scheduled
task that resumes a conversation. A periodic wakeup is the degenerate case:
one task always pending, aimed at one thread.

```
 SATAN ── wake_schedule{intent, after_minutes?, topic?, payload?, episode_class}
            │  WakePolicy.schedule: clamp [floor, ceiling] + jitter          (DEC-128)
            ▼
   pi-durable background task `satan.wake`, owned by the target conversation (DEC-127)
            │  sleepUntil(at) — the harness arms the timer; restart-safe
            ▼
   fire phase ── WakePolicy.gate: switch → quiet window → weighted presence  (DEC-128/129/132)
            │        defer → sleepUntil(later)
            ├── beforeInput · percept ← satan_boot_context over `scheduled`  (DEC-133)
            ├── input {entry satan.wake, requestId wake:<task>:<n>, followUp}
            │     wake.md (corpus) + intent + payload + percept + fire metadata
            └── wait → failure: journal + notify_send (→ satan-tank)          (DEC-134)
   heartbeat: one recurring satan.wake in topic `room`, every ceiling when nothing else is pending (DEC-131)
```

Existing seams (read 2026-10-27; to be consolidated in research):

| Seam | Now |
|---|---|
| `src/daemon-extensions.ts` | native tools come from pi-durable extensions; a `tasks` extension sits here |
| `src/daemon-start.ts:107` | the profile's store is `session.sqlite` via pi-durable's node SQLite storage |
| `src/runner/store.ts`, `src/runner/scheduler.ts` | precedent: runner tables share one SQLite file with pi-durable's `pi_` tables; a queue woken on submit (DEC-056). Not used: wakes are pi-durable tasks (DEC-127) |
| `src/protocol.ts:44-47` | conversations are addressable by topic name |
| `src/conversation-context.ts:28` | `SatanKind = "interactive"` — the satan-mcp pool/identity kind; gains `scheduled` (DEC-139) |
| `src/satan-tools.ts`, `src/satan-pool.ts` | the daemon is an MCP client of satan-mcp; no MCP server of its own |
| `satan/satan-mcp.el:649` (satan repo) | `satan_boot_context`: fresh percept, resonance, motive, sensor status, attributes; partial capsule on backend failure; cached per session unless `refresh` |
| `src/daemon.ts:119` | `conversation.compact(instructions, context)` already reachable |

## Scope & Objectives

Decisions: DEC-127 … DEC-139 (design run inquiry, 2026-10-27). Theme: the
cheapest, simplest approach that works.

1. **Wake task** (DEC-127): pi-durable task `satan.wake` v1, background, owned
   by the target conversation; phases `fire` (gate, compose) and `submit`
   (checkpointed before the input is sent), checkpoint `{phase, at, n}`; `n`
   counts occurrences (a defer keeps it, a completed fire bumps it). Input
   `{conversationId, intent, payload?, episodeClass, at, requestedAt?,
   scheduledBy, recurring?}`; the tool decides `at`. pi-durable's task table is
   the store: no host table, no host timer.
2. **Tools** (DEC-130): a native `tasks` extension — `wake_schedule`,
   `wake_cancel`, `wake_list`. Target: the calling conversation, or a known
   topic's latest, resolved at schedule time. `wake_cancel` acts only on a
   sleeping wake, waits for it to settle and answers from its result: never
   `cancelled` with an admitted turn; otherwise "already fired". In-process; works with
   Emacs absent.
3. **WakePolicy** (DEC-128, DEC-129): an async seam with an injected `env`
   (`now`, `random`, `wakes`, `presence`). v0: clamp + jitter at schedule; at
   fire, quiet window (23:20–07:00) defers, episode-class presence rule as a
   weighted chance, unknown presence fires. Presence from satan-mcp
   `activity_read{scope:"current"}`, read from its printed-Lisp result by a
   small adapter. Episode classes `attend` / `seclude`.
4. **Heartbeat** (DEC-131): one perpetual recurring wake into topic `room`,
   ensured at daemon start (a blocked, parked or abort-marked heartbeat is
   replaced; every blocked wake is aborted and its queued inputs withdrawn); fires only when no other wake is sleeping; a stuck input is
   withdrawn after one ceiling, so a heartbeat behind a failed run recovers
   itself.
5. **Fire composition** (DEC-133): gate → `beforeInput` → percept over a
   `scheduled` satan-mcp connection (10 s, degrades to one line) →
   `~/satan-corpus/prompts/wake.md` → input with entry `satan.wake`,
   `requestId wake:<taskId>:<n>`, `whenBusy: followUp`. The gate decides
   admission; a followUp behind a busy turn may start in the quiet window.
6. **Off switch** (DEC-132): `MALEBOLGE_WAKES=on` at start, fail closed; off
   defers, never drops. It stops new admissions; an admitted turn completes;
   `satan-mcp-enabled` stays the hard stop.
7. **Visible failure** (DEC-134): a failed fire or unanswered wake → journal
   line + best-effort `notify_send` over `scheduled` (lands in satan-tank's
   RECENT EVENTS); the heartbeat survives its failures. Every wake waits at
   most one ceiling for its turn; an input still queued then (e.g. behind a
   failed run) is withdrawn and reported, a running turn is waited on.
8. **Daemon wiring** (DEC-139): late-bound `tasks` extension; `SatanKind`
   gains `scheduled`; heartbeat ensured after `resume()`; env keys
   room profile only (host refuses wake keys; CON-005); `beforeResume(session)`
   binds deps before `resume()`; `MALEBOLGE_WAKES`, `_WAKE_FLOOR_MS`, `_WAKE_CEILING_MS`, `_WAKE_QUIET`,
   `_WAKE_TOPIC`, set in the room jail options in this repo's `flake.nix` and
   pinned by the launcher probes (row 3b, `satan-flake`). No `~/flakes` change.
9. **Governance** (DEC-136, DEC-137, DEC-138): ledger token `room-daemon`,
   rows 7b/6d/4d (4d: a journal line per gate decision and terminal outcome),
   row 3b evidence; no-limits v0; shared interactive allowlist; SPEC-002 REV;
   one sentence in `docs/architecture.md` and `docs/governance.md`.

No satan-side code: satan-mcp already accepts kind `scheduled` (DEC-121), and
wake turns share the interactive allowlist (DEC-138).

v0 has one task kind: `resume` (a turn in an existing conversation).

## Non-Goals

- Spend, rate or concurrency limits (DEC-137, IMP-053) — WakePolicy's `env` is
  where they plug in.
- Fancier routing (attributes, IMP-012 / ADR-002); recent-wake damping; max
  lateness.
- Other task kinds: `fresh`, `patch`.
- Posting tasks from outside the daemon (a socket `schedule` op; RSK-018).
- Modes-as-events for every mode (IDE-009) beyond `resume`.
- The host profile; RFC-019's habitat work.
- Pre-compaction before a wake (DEC-135, IMP-056).
- A live (no-restart) off switch; a tank recent-wakes section (IMP-057);
  `scheduled` attribution of in-turn tool calls (IMP-058).
- Creating topics from the tool.

## Risks, Assumptions, Open Questions

Settled by research and the inquiry: ASM-c (model failures settle `unanswered`/`model_error`, pi-durable `generation.ts:376`), OQ-1 (input with an application entry
starts a turn, spike S1), OQ-2 (no shared transaction; `requestId` dedupes),
OQ-3 (pi-durable sleeping tasks), OQ-5 (DEC-135), OQ-6 (DEC-128/129/139).

- **OQ-4 percept size:** a full boot capsule per wake; accepted for v0, delta
  capsule is a follow-up (IMP-010).
- **ASM-a:** the room daemon is long-running; with it down, no wakes fire.
- **ASM-b:** pi-durable 1.4.0 semantics as spiked hold for the pinned version.
- **Risk:** unattended turns spend tokens with no owned ceiling (DEC-137); the
  gateway key cap is the backstop.
- **Risk:** a topic-targeted wake misses a newer conversation started in that
  topic after scheduling; the heartbeat stays with its creation conversation.
- **Risk:** presence needs Emacs; with Emacs absent the presence rule is inert
  and failures reach only the journal.

## Summary

Done when, against a running room daemon with a faux or real model:

- SATAN calls `wake_schedule`; the wake fires at the decided time into its
  target with the fragment, intent, payload and a fresh percept, and a turn
  runs; the result reports the decided `at`.
- With satan-mcp unreachable, the wake still fires with a one-line
  percept-unavailable note, and presence is `unknown`.
- Exactly one heartbeat exists after any number of restarts.
- WakePolicy is covered by deterministic tests (seeded `random`, fixed clock):
  clamp, jitter bounds, quiet-window defer, weighted presence.
- A daemon restart with overdue wakes fires each once (no duplicate turn),
  including a crash right after admission followed by a restart into quiet
  hours.
- `wake_cancel` racing a fire: either the wake is cancelled or it answers
  "already fired"; never a cancelled wake with a queued turn.
- `MALEBOLGE_WAKES` unset: nothing fires; wakes are kept.
- A failed wake is reported in the journal and via `notify_send`.
- A wake input stuck behind a failed run is withdrawn after one ceiling and
  reported, in any target conversation; a wake whose turn started before the
  bound is not. The heartbeat's next input then releases the inputs queued
  behind the failed run, about two ceilings after the stuck input's
  admission, absent gate defers, restarts or other input.
- A crash between preparing and admitting a wake input never fires it while
  wakes are off or inside the quiet window.
- Host profile: wake keys refuse start; no `tasks` extension, no heartbeat.
- Ledger rows 7b/6d/4d, row 3b evidence and token `room-daemon` land with the
  code.

## Follow-Ups

- IMP-056 pre-compaction; IMP-057 tank recent-wakes; IMP-058 in-turn
  `scheduled` attribution; wake-sized percept delta (IMP-010).
- Limits through WakePolicy (IMP-053); attribute-informed routing (IMP-012).
- `fresh` and `patch` task kinds; socket `schedule` op (RSK-018).
- Close IDE-014 and IDE-017 as absorbed once this lands.
