`doctrine slice phases <ID>` prints "Phases up to date." and leaves existing
`state/slice/<NNN>/phases/phase-NN.md` sheets carrying the OLD objective text after you
edit `plan.toml`. It re-reads phase identity, not authored prose.

To refresh: `rm -rf .doctrine/state/slice/<NNN>/phases && doctrine slice phases <NNN>`.
Safe while every sheet is `status = "planned"` (the sheets are disposable,
gitignored runtime). Once a phase is in_progress or completed, do not delete — it
holds the runtime log.