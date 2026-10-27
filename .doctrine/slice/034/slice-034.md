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
 SATAN ── task_schedule{topic, intent, payload?, when?, priority?} ──► task table
                                                                        │
                     decide(tasks, now, policy) → (task, fire_at)  ◄────┘   pure; tuned later
                                                                        │
                     one timer at the earliest fire_at ─────────────────┘
                                │
 fire(task) ── percept ← satan_boot_context{refresh:true}   (degrades: one line if unavailable)
            ── wake entry → topic's conversation:
                 resume fragment (corpus) + intent + payload + percept + fire metadata
            ── turn runs: SATAN's own retrieval, room + satan-mcp tools, maybe task_schedule
            ── turn ends with nothing pending → decider adds a heartbeat at the ceiling
```

Existing seams (read 2026-10-27; to be consolidated in research):

| Seam | Now |
|---|---|
| `src/daemon-extensions.ts` | native tools come from pi-durable extensions; a `tasks` extension sits here |
| `src/daemon-start.ts:107` | the profile's store is `session.sqlite` via pi-durable's node SQLite storage |
| `src/runner/store.ts`, `src/runner/scheduler.ts` | precedent: runner tables share one SQLite file with pi-durable's `pi_` tables; a queue woken on submit (DEC-056). Pattern to copy, not code to share |
| `src/protocol.ts:44-47` | conversations are addressable by topic name |
| `src/conversation-context.ts:28` | `SatanKind = "interactive"` — the satan-mcp pool/identity kind; a wake turn needs its own |
| `src/satan-tools.ts`, `src/satan-pool.ts` | the daemon is an MCP client of satan-mcp; no MCP server of its own |
| `satan/satan-mcp.el:649` (satan repo) | `satan_boot_context`: fresh percept, resonance, motive, sensor status, attributes; partial capsule on backend failure; cached per session unless `refresh` |
| `src/daemon.ts:119` | `conversation.compact(instructions, context)` already reachable |

## Scope & Objectives

1. **Task store:** a task table in the profile's `session.sqlite`, beside
   pi-durable's tables. Row: id, target topic, intent (text), payload (JSON,
   optional), requested time and priority, decided fire time, state
   (`pending | fired | cancelled | failed`), reason, scheduling conversation.
   Firing a task and submitting its turn is one transaction where the store
   allows it.
2. **Tool:** a native `tasks` pi-durable extension — `task_schedule`,
   `task_cancel`, `task_list`. In-process; works with Emacs absent.
3. **Decider:** a pure function `(tasks, now, policy) → next (task, fire_at)`.
   v0 clamps a requested time to `[floor, ceiling]` and orders by fire time,
   then priority. SATAN proposes; the decider disposes.
4. **Heartbeat:** after a wake turn ends, if no task is pending, the decider
   schedules a default `resume` into the default wake topic at the ceiling.
   Also on daemon start with an empty queue.
5. **Timer and fire path:** one timer armed at the earliest fire time, re-armed
   on every store change; overdue tasks on start fire in decided order.
6. **Wake entry:** fetch the percept via `satan_boot_context{refresh:true}`
   under a `wake` pool kind; compose resume fragment
   (`~/satan-corpus/prompts/wake.md`, model-facing, SATAN may edit it) +
   intent + payload + percept + `fired_at`/`scheduled_by`/lateness; deliver it
   so the model can tell it from user input; start a turn.
7. **Visible failure:** a wake that cannot fire or whose turn fails records
   `failed` with its reason and logs it to the journal.
8. **satan side** (this repo): a `wake` mode/kind so satan-mcp's tool
   allowlist and audit distinguish wake calls from interactive ones.

v0 has one task kind: `resume` (a turn in an existing, topic-named
conversation, created if absent).

## Non-Goals

- Spend, rate or concurrency limits (IMP-053) — nothing to limit yet. The
  decider is where they will plug in.
- Fancier routing (attributes, IMP-012 / ADR-002) — v0 decider only.
- Other task kinds: `fresh` (new conversation with a context type), `patch`
  (hand-off to the runner).
- Posting tasks from outside the daemon (a socket `schedule` op; RSK-018
  applies then).
- Modes-as-events for every mode (IDE-009) beyond `resume`.
- The host profile; RFC-019's habitat work.

## Risks, Assumptions, Open Questions

- **OQ-1 wake delivery:** does a custom pi-durable entry kind start a turn
  (IDE-009 claims it queues/steers like input; unverified)? Fallback: ordinary
  input wrapped in a `<wake>` tag. First spike.
- **OQ-2 transactionality:** can the task table share the harness's storage
  adapter in the interactive daemon as the runner's does, so fire + submit is
  atomic? Otherwise: mark-fired-then-submit with idempotent recovery.
- **OQ-3 durable timer:** own table + one process timer (proposed) versus
  pi-durable `sleepUntil` background tasks (IDE-017's shape). Proposed because
  the decider needs every pending task in view and rescheduling a durable
  sleep means abort + recreate.
- **OQ-4 percept size:** `satan_boot_context` is a session-start capsule;
  appending one per wake to a long conversation repeats a lot. v0 accepts it;
  a wake-sized delta capsule is a follow-up (also serves IMP-010).
- **OQ-5 context weight:** measure the conversation's context before a wake
  and compact first if heavy. Wanted; may land in this slice or follow it —
  depends on what pi-durable exposes for context size (research).
- **OQ-6 floor, ceiling, quiet hours:** values and where they live (daemon
  config is host authority, ADR-017 — the model never edits its own clamp).
  Quiet hours come from observation, not a clock (user, 2026-10-27):
  panopticon knows when the user is idle and when the machine is suspended
  (S3). Open: is user-idle a gate or the invitation (the goal is fiddling
  while the user is away)? On resume from S3, do overdue tasks fire at once,
  collapse to one, or re-decide? Whether the decider reads panopticon
  directly or through the percept is a design question.
  - A system timer suspends the machine roughly 23:20–07:00 (user, iirc; rarely
    allowed to run on time). Treat that window as off limits for large jobs.
  - Two episode classes with opposite drivers (user, 2026-10-27):
    **observation/intervention** (user present; attend to them) and
    **seclusion/self-work** (user away; SATAN's own weird work). Presence gates
    one and invites the other. Design input: a task names its class, and the
    decider applies the class's presence rule.
- **ASM-a:** the room daemon is the long-running process; with it down, no
  wakes fire (the existing user unit restarts it, SL-028).
- **Risk:** unattended turns spend tokens with no ceiling. Accepted for v0 by
  the user (2026-10-27); the LLM gateway key's cap is the backstop.

## Summary

Done when, against a running room daemon with a faux or real model:

- SATAN calls `task_schedule` in one conversation; the task fires at the
  decided time into the named topic, with the resume fragment, intent,
  payload and a fresh percept in the wake entry, and a turn runs.
- With satan-mcp unreachable, the wake still fires with a one-line
  percept-unavailable note.
- After a wake turn that schedules nothing, exactly one heartbeat is pending.
- Requested times outside `[floor, ceiling]` are clamped; the decider is
  covered by pure tests.
- A daemon restart with overdue tasks fires each once, in order.
- A failed wake is recorded `failed` with its reason and visible in the journal.
- satan-mcp audit records wake-turn tool calls under the `wake` kind.

## Follow-Ups

- Wake-sized percept delta (OQ-4); pre-compaction if not landed (OQ-5).
- Limits through the decider (IMP-053); attribute-informed routing (IMP-012).
- `fresh` and `patch` task kinds; socket `schedule` op (RSK-018).
- Close IDE-014 and IDE-017 as absorbed once this lands.
