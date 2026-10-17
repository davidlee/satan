# IMP-040: speak tool: SATAN speaks aloud via say(1)

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Give SATAN a voice: a `speak` tool that runs `say` (`~/flakes/features/audio/say`,
installed at `~/.local/bin/say` by the flakes `speech` feature). Agreed sketch
(user, 2026-10-17):

- A separate `speak` tool with its own `speak` capability, not a flag on
  `notify_send`. Enabled on modes morning, motd and tick.
- First refactor `notify_send`'s record → deliver → project/undelivered flow
  into one shared helper; both tools wrap it (no parallel implementation).
- Deliver through the `satan-announce` seam: a new `:speech` key, sent by the
  production sink to an async `say` process. Tests use the recorder sink.
- Takes text only. Engine and voice come from `say`'s env defaults
  (`SAY_ENGINE`, `PIPER_VOICE`).
- `satan-speak-program` defcustom (nil disables); a text length cap.
- "Delivered" means `say` started. A non-zero exit from `say` writes a journal
  line and does not change the verdict.
- Tool description: `~/satan-corpus/tools/speak.md`.

## Progress (2026-10-17)

Implemented, uncommitted; `just check` green (1367 pass, 6 existing skips).

- `satan-intervention-emit` (`satan-intervention.el`): the shared record →
  emit → project / mark-undelivered flow. `notify_send` now wraps it. Change:
  notify's undelivered result no longer carries `:id :null`; nothing read it.
  goad's ask does not use it, because its emit also projects and rings.
- `satan-announce` takes `:speech`. The production sink starts
  `satan-speak-program` (defcustom, default `"say"`, nil disables) as
  `PROGRAM -- TEXT` via `make-process`. `--` keeps text that starts with `-`
  from being read as an option. The sentinel journals a non-zero exit with
  the program's output. A start failure signals, so the result is undelivered.
- `satan-tools-speak.el`: the `speak` tool, `speak` capability, 300-char cap
  (refused, not truncated), refused when disabled or the text is blank.
- **Deviation from sketch (user, 2026-10-17):** recorded as kind `notify`,
  surface `audio`, not a new kind. The kind set is closed in three places
  (`satan-audit-intervention-kinds`, `satan-observer-user-facing-kinds`, the
  0006 CHECK constraint). Speech is a notification on another channel.
- Voice: `satan-speak-environment` (default `PIPER_VOICE=en_GB-alan-medium`,
  user's pick) is added to the speech process environment, so SATAN's voice
  stays separate from the user's `say` default.
- Modes: morning, motd, tick defaults (tick-pulse) and tick-agent.
- Corpus: `~/satan-corpus/tools/speak.md` (uncommitted there).
- Live: the seam spoke through the real `say` (exit 0); the live Emacs
  resolves `say` on its exec-path.

Pending: reload satan in the live Emacs; first real use by a run.
Design note: `satan-mode-check-tool-references` could also check that each
listed tool's `:capability` is among the mode's capabilities. Today a missing
capability fails only at dispatch.
