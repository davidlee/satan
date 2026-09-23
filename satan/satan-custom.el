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

;; ── SATAN's runtime state (SL-015 D1, DEC-027) ──────────────────────────────

(defun satan-state-home ()
  "Return the state home: `XDG_STATE_HOME' when non-empty, else `~/.local/state'.
A pure function of the environment — no `satan-*' state.  An empty
`XDG_STATE_HOME' counts as unset (DEC-027: the XDG Base Directory spec's
\"either not set or empty\", matching goad's `backend.py' `queue_path').
Every state-home reader (`satan-state-root',
`satan-sensor-curiosity-segments-dir', `satan-tools-content-dir') resolves
through this one helper rather than inlining the same expression."
  (let ((xdg (getenv "XDG_STATE_HOME")))
    (if (and xdg (not (string= xdg "")))
        (expand-file-name xdg)
      (expand-file-name ".local/state" "~"))))

(defcustom satan-state-root
  (expand-file-name "satan" (satan-state-home))
  "Root directory of SATAN's runtime state.
Run bundles, sensor cursors, telemetry, patch-agent logs and worktrees.
Discardable: nothing below it is authored or versioned, and deleting it
costs history, not correctness.

Honours `XDG_STATE_HOME' through `satan-state-home' (DEC-027): an empty
value counts as unset, falling back to ~/.local/state, the same as an
unset value.  This expression was inlined at eight call sites in two
divergent spellings before SL-015; it lives here once now."
  :type 'directory
  :group 'satan)

(defun satan-state-path (&rest segments)
  "Join SEGMENTS below `satan-state-root' — SATAN's runtime state."
  (satan--join satan-state-root segments))

;; ── goad, SATAN's elicitation surface (SL-016) ──────────────────────────────

(defcustom satan-goad-queue-file (satan-state-path "goad/queue.json")
  "SATAN's queue of outstanding asks, which goad's `backend.py' reads.
SATAN owns it: a projection of its open ask interventions, rewritten
whole and discardable, so it is runtime state.  goad resolves the same
path on its side (`queue_path' in the corpus's `goad/backend.py')."
  :type 'file
  :group 'satan)

(defcustom satan-goad-data-dir (satan-corpus-path "goad/data")
  "goad's day records, one `YYYY-MM-DD.json' per local date.
goad's `backend.py' owns and writes them; they are corpus-tracked.
SATAN only reads them, to perceive what the keeper did with its asks."
  :type 'directory
  :group 'satan)

(defcustom satan-goad-enabled nil
  "Non-nil enables the goad ask path.
The governed kill switch (design sec-7, \"the governed idiom, ledger
row 6\"): off by default, so goad ships dark until deliberately
switched on."
  :type 'boolean
  :group 'satan)

(defcustom satan-goad-quiet-hours '(22 . 9)
  "goad's own emission window, as (START-HOUR . END-HOUR) — same shape as
`satan-tick-quiet-hours'.  No ask from 22:00 through 08:59 by default
\(design sec-7, \"A goad-specific emission window, not global quiet
hours\"): passed to `satan-tick-quiet-p' as its WINDOW argument rather
than reusing the global, so disabling goad's window never silences
tick's other ambient surfaces."
  :type '(choice (cons (integer :tag "Start hour")
                   (integer :tag "End hour"))
           (const :tag "Disabled" nil))
  :group 'satan)

(defcustom satan-goad-emit-program "goad-emit"
  "Program name for goad's emit step, resolved on `PATH'.
Passed to `satan-trace-call' as PROGRAM (design sec-5)."
  :type 'string
  :group 'satan)

(defcustom satan-goad-emit-timeout 10
  "Timeout in seconds for goad's emit step.
Passed to `satan-trace-call' as TIMEOUT-SECS (design sec-5, \"The
timeout is mandatory\") — never nil, so a hung emit cannot wedge a
run."
  :type 'integer
  :group 'satan)

(defun satan-notes-today ()
  "Today's journal path via `satan-journal-today', or nil when unset."
  (and satan-journal-today (funcall satan-journal-today)))

(provide 'satan-custom)
;;; satan-custom.el ends here
