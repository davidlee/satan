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
  "Root directory of the notes corpus.
SATAN derives owned paths as ${satan-notes-root}/satan/... and the
standard corpus paths (journal/, weekly/, inbox.org) below it."
  :type 'directory
  :group 'satan)

(defcustom satan-journal-today nil
  "Zero-arg function returning today's journal file path, or nil.
When non-nil, SATAN calls this to include today's journal in context
assembly.  The function must ensure the file exists before returning
its path."
  :type '(choice (const :tag "None" nil) function)
  :group 'satan)

(defun satan-notes-path (&rest segments)
  "Join SEGMENTS below `satan-notes-root'."
  (let ((path (expand-file-name satan-notes-root)))
    (dolist (seg segments path)
      (setq path (expand-file-name seg path)))))

(defun satan-notes-today ()
  "Today's journal path via `satan-journal-today', or nil when unset."
  (and satan-journal-today (funcall satan-journal-today)))

(provide 'satan-custom)
;;; satan-custom.el ends here
