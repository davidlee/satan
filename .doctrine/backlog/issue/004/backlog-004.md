
# DE-008 follow-ups: retarget git_state :dirty + canon cwd.project to active-project root; relax observer :crosses_midnight guard (Q3)

Deferred work explicitly carved out of DE-008 (§4 Out of Scope, §7 Follow-ups,
risk R3) and IP-008 §8 / Q3. Promised as a backlog item at planning time; filed
here per AUD-005 finding F-004 (it was never created).

## Scope

1. **`git_state :dirty` retarget.** `:dirty` (uncommitted-work signal) currently
   reads the daemon's incidental `default-directory`, not the user's active
   project. Retarget to the active-project root. Needs an active-project signal
   that does not yet exist. `:dirty` plumbing is left in place but unwired by
   DE-008.
2. **Canon `cwd.project` source.** Same root cause: `cwd.project`'s
   `git_state.remote` source should follow the active-project root, not the
   incidental cwd.
3. **Relax `:crosses_midnight` guard (Q3).** The observer's `:crosses_midnight`
   guard is conservative; revisit once the 24h git window (DE-008) is bedded in.
   Predicate behaviour unaffected, so deferred.

## Dependency

Items 1–2 are blocked on an **active-project signal** primitive. Item 3 is
independent and small.

## Provenance

- DE-008, AUD-005 (F-004).

