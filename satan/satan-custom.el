;;; satan-custom.el --- SATAN self-location + config-root defcustoms -*- lexical-binding: t; -*-

;;; Commentary:
;; Leaf module (zero satan-deps) loaded before every other SATAN module.  It
;; homes the two config-root decouple surfaces the standalone extraction
;; requires (SL-012 D4 + D10):
;;
;;   * `satan--root' — package SELF-LOCATION (Axis-2, D10).  Internal plumbing,
;;     resolved once at load from `load-file-name'.  All package-owned path
;;     resolution (memory/migrations, patterns.eld, source roots) anchors here.
;;     Future modules MUST anchor to `satan--root', never the Emacs config
;;     root — that assumption breaks the moment SATAN ships outside `~/.emacs.d'.
;;
;;   * `satan-notes-root' / `satan-journal-today' / `satan-notes-path' — the
;;     user NOTES corpus decouple (Axis-1, D4).  One root knob; standard corpus
;;     paths (journal/, weekly/, inbox.org) derive below it.
;;
;;   * `satan-corpus-root' / `satan-state-root' and their joins (SL-015 D1) —
;;     the other two ownership classes.  SATAN's paths used to be spelled
;;     `${satan-notes-root}/satan/...' at 16 sites and as an inlined XDG
;;     expression at 8 more, which put content SATAN *authors* and state it
;;     *discards* under a root named for content it only *reads*.  Three
;;     classes, three roots, one name each:
;;
;;       satan-notes-root   the user's notes         SATAN reads
;;       satan-corpus-root  SATAN's own corpus       SATAN reads and writes, versioned
;;       satan-state-root   SATAN's runtime state    discardable
;;
;;     There is deliberately no fourth root for `~/.local/state/behaviour/' —
;;     panopticon authors that; SATAN reads it and does not own it, so it stays
;;     spelled out at its two call sites (SL-015 D1, design 2.2b).
;;
;; `satan-custom' owns `(defgroup satan …)' because it is the first module
;; loaded, so the group exists before any defcustom references it.

;;; Code:

(defgroup satan nil
  "SATAN local agent runtime."
  :group 'tools
  :prefix "satan-")

;; ── Self-location (Axis-2, D10) ─────────────────────────────────────────────

(defconst satan--root
  (file-name-directory
   (or load-file-name buffer-file-name (locate-library "satan-custom")))
  "Directory holding SATAN's elisp and shipped data (memory/migrations, patterns.eld).
Package plumbing — internal, resolved at load; not user-configurable.
Anchor package-owned paths to this, never the Emacs config root: that
points at the user's config tree and dangles once SATAN ships standalone.")

;; ── Notes corpus (Axis-1, D4) ───────────────────────────────────────────────

(defcustom satan-notes-root "~/notes"
  "Root directory of the user's notes corpus, which SATAN only reads.
The standard notes paths (journal/, weekly/, inbox.org) derive below it.
SATAN's own corpus is not here: see `satan-corpus-root'."
  :type 'directory
  :group 'satan)

(defcustom satan-journal-today nil
  "Zero-arg function returning today's journal file path, or nil.
When non-nil, SATAN calls this to include today's journal in context
assembly.  The function must ensure the file exists before returning
its path."
  :type '(choice (const :tag "None" nil) function)
  :group 'satan)

(defun satan--join (root segments)
  "Join SEGMENTS below ROOT, expanding ROOT first.
Expanding the root once up front is what stops a literal tilde reaching a
caller: `expand-file-name' resolves `~' in its DIR argument, but a root that
is itself returned unjoined would keep it.  Shared by the three root joins —
they differ only in which root they read."
  (let ((path (expand-file-name root)))
    (dolist (seg segments path)
      (setq path (expand-file-name seg path)))))

(defun satan-notes-path (&rest segments)
  "Join SEGMENTS below `satan-notes-root' — the user's notes corpus."
  (satan--join satan-notes-root segments))

;; ── SATAN's own corpus (SL-015 D1) ──────────────────────────────────────────

(defcustom satan-corpus-root "~/satan"
  "Root directory of SATAN's own model-facing corpus.
Prompts, system scaffold and framing, tool descriptions, motives,
hippocampus, proposals — content SATAN reads *and writes*, versioned in
its own repo.

Distinct from `satan-notes-root', which is the user's notes corpus and
which SATAN only reads.  Deliberately not derived from it and with no
fallback: one location, so a corpus that is missing fails loudly rather
than resolving somewhere readable but wrong (SL-015 D2)."
  :type 'directory
  :group 'satan)

(defun satan-corpus-path (&rest segments)
  "Join SEGMENTS below `satan-corpus-root' — SATAN's own corpus."
  (satan--join satan-corpus-root segments))

;; ── SATAN's runtime state (SL-015 D1) ───────────────────────────────────────

(defcustom satan-state-root
  (expand-file-name "satan" (or (getenv "XDG_STATE_HOME")
                                (expand-file-name ".local/state" "~")))
  "Root directory of SATAN's runtime state.
Run bundles, sensor cursors, telemetry, patch-agent logs and worktrees.
Discardable: nothing below it is authored or versioned, and deleting it
costs history, not correctness.

Honours XDG_STATE_HOME, falling back to ~/.local/state.  This expression
was inlined at eight call sites in two divergent spellings before SL-015;
it lives here once now."
  :type 'directory
  :group 'satan)

(defun satan-state-path (&rest segments)
  "Join SEGMENTS below `satan-state-root' — SATAN's runtime state."
  (satan--join satan-state-root segments))

(defun satan-notes-today ()
  "Today's journal path via `satan-journal-today', or nil when unset."
  (and satan-journal-today (funcall satan-journal-today)))

(provide 'satan-custom)
;;; satan-custom.el ends here
