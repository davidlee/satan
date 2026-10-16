`satan/*.elc` exist on purpose: `dl-satan--compile-stale`
(`~/.config/emacs/apps/dl-satan.el`) byte-compiles stale sources at Emacs
startup because interpreted timers stall input. They are gitignored, and
they stay older than whatever you just edited.

Interactive Emacs and `just test` (`dev/satan-test.el`) both set
`load-prefer-newer`. An ad-hoc `emacs --batch -L ./satan …` loads no init, so
`require` takes the stale `.elc` and you test old code. The tell:
"Source file ‘…’ newer than byte-compiled file; using older file".

- Run single suites with
  `emacs --batch --eval '(setq load-prefer-newer t)' -L ./satan -L ./dev -L ./satan/test -l <suite> …`
  (the `--eval` must come before the `-l`).
- Don't delete the `.elc` files; Emacs rebuilds them on its next startup.
- A bare run also skips `satan-test.el`'s production-DB refusal and its
  notification sink. Prefer `just test` for anything that touches the DB or
  notifications.
- The permanent fix (site-start in the Emacs build) is `~/flakes` IMP-025.
