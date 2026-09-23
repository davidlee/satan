`my/op-read` (`~/.emacs.d/lisp/dl-secret.el`) resolves a secret with a
synchronous `call-process`. Emacs is single-threaded, so while `op` waits on a
1Password authorization dialog **the whole Emacs server is blocked** —
`emacsclient -e '(+ 1 1)'` hangs until the dialog is answered.

Only a read that must *establish* a session prompts; a read inside a live
session is silent (see [[mem.fact.satan.op-prompts-on-session-not-read]]).

**Updated 2026-09-23 — the hazard is smaller than first recorded.** When this
was first observed the dialog could open on a hidden sway scratchpad layer, so
the block presented as "Emacs has hung" with nothing on screen. The keeper has
since fixed that at the window-manager level: the dialog now takes focus and
is pinned, interrupting whatever is on screen; accept/dismiss is one keystroke.
A blocking read is now a *visible interruption*, not a silent wedge.

Do not reach for a timeout to bound it: killing `op` leaves the dialog up and
orphans the prompt (same memory as above).

Design consequence (superseding the original note, which argued against a
service-account token on wedge grounds — the token was rejected by the keeper
on 2026-09-23 regardless): unattended callers should not *start* a session
unasked. Probe with `op whoami` first; decide prompt-vs-defer by policy.

Diagnose a live block with: `ps -eo pid,ppid,etimes,args | grep '[o]p read'` —
the parent PID is the Emacs server.

Related: [[mem.fact.satan.op-cache-has-no-invalidation]], [[ISS-012]].
