# ISS-010: empty XDG_STATE_HOME is treated as set, defeating the state-root fallback

Found during SL-015 PHASE-01 T2 (2026-08-26).

`satan-state-root` (and, before this slice collapsed them, all eight inlined
copies of the same expression) resolves its base as:

    (or (getenv "XDG_STATE_HOME") (expand-file-name ".local/state" "~"))

`getenv` returns `""` — not nil — when the variable is set-but-empty, and `""`
is truthy in elisp. So `XDG_STATE_HOME=` takes the first branch and every state
path resolves relative to `default-directory` instead of `~/.local/state`. For a
long-lived Emacs that is wherever the buffer happened to be; for a batch run it
is the CWD.

Not fixed in SL-015: PHASE-01 is a pure refactor whose acceptance test is that
all 24 resolved paths come out byte-identical (design A1), and this is inherited
behaviour identical in every spelling being collapsed. Fixing it would be a
behaviour change smuggled into a refactor. The consolidation does make the fix a
one-line change in one place, which is the point.

Low likelihood (nothing sets XDG_STATE_HOME empty on purpose), non-trivial blast
radius if it fires (state scattered into arbitrary directories, silently).

Fix sketch: a small `satan-custom--env-or` helper — treat empty as unset:

    (let ((v (getenv name))) (if (and v (not (string-empty-p v))) v default))

The same pattern should be checked for `XDG_RUNTIME_DIR` (`satan-mcp.el:43`) and
any other `getenv`-with-`or` in the tree.

Related: SL-015 design 5.2; `satan-custom-state-root-falls-back-below-home`
documents the current behaviour in a comment.
