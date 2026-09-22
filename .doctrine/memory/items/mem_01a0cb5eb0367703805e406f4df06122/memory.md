`my/op-read` (`~/.emacs.d/lisp/dl-secret.el`) resolves a secret with a
synchronous `call-process`. Emacs is single-threaded, so while 1Password is
deciding whether to prompt — and while the prompt sits unanswered — **the whole
Emacs server is wedged**. `emacsclient -e '(+ 1 1)'` hangs.

Observed 2026-09-23: a diagnostic `(my/op-read … t)` left `op read` (child of
the Emacs PID) blocked for 60s+ with Emacs in `anon_pipe_read`, until the user
authorized the dialog.

Why it bites: the failure presents as **"Emacs has hung"** with nothing on
screen connecting it to a credential read. The 1Password dialog attests only
the requesting desktop app, never the code path (see [[IMP-021]]), and it may
surface minutes after the call.

Consequences for design:
- Any unattended path that can reach a cache-cold `op read` can wedge the
  editor, not merely fail its own run.
- This is the argument against "just make the read work headlessly" (a service
  account token): a token fixes the *failure* but not the *blocking*. Deferring
  when the vault is locked addresses both.

Diagnose it with: `ps -eo pid,ppid,etimes,args | grep '[o]p read'` — the parent
PID is the Emacs server.

Related: [[mem.fact.satan.op-cache-has-no-invalidation]], [[ISS-012]].
