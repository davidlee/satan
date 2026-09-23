# ISS-024: satan-state-root treats an empty XDG_STATE_HOME as a directory

<!-- Backlog item body — context, detail, links. The structured, queried fields
     live in the sister `backlog-NNN.toml`; this prose is free-form and is never
     structurally parsed (the storage rule). -->

Found during SL-016 PHASE-02/PHASE-03 (2026-09-23/24). **Overlaps ISS-010**,
which records the root cause; this item adds the goad divergence. Consider
closing one as a duplicate of the other.

## The divergence

`satan-state-root` (`satan/satan-custom.el:106`) resolves its base as

    (or (getenv "XDG_STATE_HOME") (expand-file-name ".local/state" "~"))

`getenv` returns `""` when the variable is set but empty, and `""` is truthy,
so the first branch wins. `(expand-file-name "satan" "")` then resolves
against `default-directory`: the CWD of a batch run, or wherever the current
buffer happens to be in a live Emacs.

goad's `backend.py` (`queue_path`, corpus repo `~/satan`, `goad/`) treats an
empty `XDG_STATE_HOME` as unset and falls back to `~/.local/state`.

So when the variable is set but empty, SATAN writes `satan-goad-queue-file`
(`(satan-state-path "goad/queue.json")`, SL-016 PHASE-03) in one place and
the backend reads it from another. Neither side reports anything: SATAN's asks
never reach goad. The agent shell this was found in had `XDG_STATE_HOME`
empty.

## Scope

Not goad-specific. Every `satan-state-path` join inherits the misresolution:
run bundles, sensor cursors, telemetry (`satan-trace-dir`), patch-agent logs
and worktrees, and the goad queue. The goad queue is only the first consumer
that has a second, independent resolver to disagree with.

## Fix sketch

Treat empty as unset in `satan-state-root` (ISS-010's `satan-custom--env-or`
helper), which makes elisp agree with `backend.py`. One line in one place;
out of scope for SL-016.
