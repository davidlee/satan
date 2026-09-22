`my/op--cache` (`~/.emacs.d/lisp/dl-secret.el`) is a plain hash table populated
on first successful resolve and **never invalidated** — no TTL, no
rotation hook. It lives as long as the Emacs server, which routinely runs for
days.

So after rotating a credential in 1Password, a long-lived Emacs keeps handing
the **old** value to every child it spawns. SATAN's `motd`/`morning`/`tick`
triggers are `emacsclient` shims into that server, so every scheduled run keeps
failing on the dead key while the vault holds a good one.

    ~/dev/satan/satan/bin/satan-run → emacsclient --eval "(satan-run \"MODE\")"

Observed 2026-09-23: the key was rotated, runs still 401'd, and the cache still
held the pre-rotation value.

**After rotating any `op://` credential, run:**

    emacsclient -e '(my/op-forget)'          ; clears the whole cache
    emacsclient -e '(hash-table-count my/op--cache)'   ; verify → 0

Inspect without triggering a read (safe, non-blocking — a read would risk
[[mem.fact.satan.op-read-blocks-emacs-server]]):

    emacsclient -e '(hash-table-keys my/op--cache)'

Diagnostic trap: the broker's failure message is misleading in both directions.
`my/scrub-op-refs-env` turns a failed resolve into `KEY not set`, which sends
you hunting for a missing env var that is present; and a *successful* resolve
of a stale key yields a provider-side `401 API key expired`. The two errors
alternate by cache state, not by configuration.

Related: [[ISS-012]], [[IMP-021]].
