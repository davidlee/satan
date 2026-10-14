# Removing a SATAN tool breaks the live Emacs until modes are reloaded

Mode allowlists (`satan-mode-register`) and tick allowlists
(`satan-tick-register`) are evaluated once, at load. Deleting a tool from
the code and its description from `~/satan-corpus/tools/<name>.md` leaves the
running Emacs with allowlists that still name it, and the manifest build then
fails every such run at spawn:

    spawn failed: SATAN: tool description missing: ~/satan-corpus/tools/<name>.md

Seen 2026-10-14 removing `agenda_read` (tick-agent `20261014T135157`).

After removing (or renaming) a tool, in the live Emacs either restart, or
reload `satan-mode.el` and `satan-tick.el` (both replace by name) and drop the
entry from `satan-tools`. `load-prefer-newer` is `t`, so stale `.elc` files
in `satan/` are skipped on restart — keep it that way.
