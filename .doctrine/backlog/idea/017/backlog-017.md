# IDE-017: SATAN self-scheduled wakeups in malebolge: a durable wakeup task, a rendered intent entry, and budget backpressure

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

## Context

From a malebolge conversation (2026-10-23) on giving SATAN a higher
autonomy ceiling for multi-step, cross-repo work. Today SATAN acts only
when the user sends a turn: its scheduler is the user's keyboard and cron.
The minimum step towards self-directed attention is a single thread that can
say "resume me at T, for this reason", with no parallelism.

## Evidence (pi source, `~/.local/src/pi` @ `936e5f40a`)

- `TaskRuntime.sleepUntil(until, checkpoint, context)` (`packages/durable/docs/spec.md`
  §5.6, `src/types.ts:330`) durably sleeps a **task** step and resumes it at
  `checkpoint`. Deadlines survive reopens. A sleep can end early only through
  an abort.
- In `src`, only compaction and generation retry/poll call it
  (`harness/compaction.ts:222`, `harness/generation.ts:240,254`). Nothing
  lets a model ask for a sleep.
- `TaskOptions.background`: a conversation-owned background task does not count
  towards the conversation being busy or idle, and is not aborted with it. A
  sleeping wakeup task therefore does not block the conversation.
- `Harness.wake()` / `HarnessOptions.onWake` only report when the next sleep
  falls due. The host must keep a process alive or arm an outside timer.
- Compaction keeps raw history; `findLatestHeadMarker` plus `scanEntries`
  rebuild the context as it stood at an earlier entry.

## Shape (inference, not yet designed)

1. **Wakeup task kind**: a background task owned by the conversation. Step
   `sleep` → `sleepUntil(T, {phase: "wake", intent})`; step `wake` appends the
   intent as a conversation entry, then starts a model turn. The checkpoint is
   the task's private state, so the model sees the intent only through that
   rendered entry.
2. **Intent entry**: a short record the model can cite: what it woke for,
   which plan step, what it is waiting on. This is the same record the
   cross-conversation indexing and drift-ledger threads need.
3. **Tool**: a model-facing tool to schedule (and cancel = abort) a wakeup.
4. **Budget backpressure**: before scheduling, check the remaining spend and
   refuse or defer when the budget is exhausted or the wake rate is too high.
   Enforce the check structurally: run it as a workflow step, or as a ceiling
   the tool cannot bypass, rather than trusting the model to check.
   Self-scheduling without a spend limit can run away.
5. **Audit**: every self-directed interval leaves a record of what it woke
   for, what it did, what it concluded, and what it is waiting on, so the user
   can review autonomous time afterwards.
6. **Host wake integration**: malebolge must honour `wake()`/`onWake` (a
   long-lived daemon, or systemd timers). Process lifetime has not been
   checked yet; this may be the real gap.

## Open questions

- Who owns the budget and the wake-rate ceiling? This is an ADR-017 §3 ledger
  row (one owner for each piece of authority), probably not malebolge itself.
- Is "check budget before scheduling" its own gate, or one row in the
  same ceiling mechanism the patch runner uses for each job (ledger row 5b)?
- How does a wakeup interact with a user message that arrives while the task
  sleeps? It is not blocked, but should the wakeup be aborted or rescheduled
  as superseded?

## Neighbours

IMP-012 (attributes as a stochastic scheduling surface), IMP-014 (budget-breach
sensor alert), ISS-050 (interactive daemon's tool calls reach no append-only
audit, which is relevant to item 5), RSK-018 (daemon socket grants submit/abort
to any local process; a wakeup submits turns).
