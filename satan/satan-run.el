;;; satan-run.el --- Shared SATAN run infrastructure (id, dirs, struct, tool-ctx) -*- lexical-binding: t; -*-

;; Sole owner of run identity, run-directory layout, and DEC-8 run-lifecycle
;; state (SL-013 DEC-001, ADR-018 D4.1).
;;
;; Deliberately a leaf: its requires are exactly cl-lib, subr-x and
;; satan-custom, and must stay that way.  That is what lets satan-mcp mint
;; runs and resolve run directories without pulling in context/percept, the
;; constraint that produced the satan-broker fork this module absorbed.  Every
;; dependant may therefore hard-require it — nothing can cycle through a leaf.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)

;; ── Directories ─────────────────────────────────────────────────────────────

(defcustom satan-runs-dir
  (expand-file-name "satan/runs" satan-notes-root)
  "Directory holding per-run audit bundles."
  :type 'directory :group 'satan)

(defcustom satan-hippocampus-dir
  (expand-file-name "satan/hippocampus" satan-notes-root)
  "Read-write scratch directory inside the jail, holding hippocampus entries.
One directory serving both roles: `satan-run-tool-ctx' hands this
variable to handlers as `:hippocampus-dir', and `satan-tools-hippocampus'
is the handler that writes SATAN's self-curated memory there."
  :type 'directory :group 'satan)

;; ── Run struct ──────────────────────────────────────────────────────────────

(cl-defstruct satan-run
  "A single SATAN run — used by the broker and MCP session."
  id mode start-time dir bundle-path process
  pending-tool-calls tool-calls-done
  applied-actions staged-actions rejected-actions failed-actions
  final status timeout-timer audit
  stdout-log-path
  ;; Phase 0.1: the run_ctx plist built by `satan-run-new-ctx'.
  ;; Carries the frozen `:time_now', `:run_id', `:start_time' and v0
  ;; placeholder slots (`:evidence' `:percept' `:sensor_status'
  ;; `:pre_spawn' `:motive' `:observer') that later phases populate.
  prepare)

;; ── Run ID minting ──────────────────────────────────────────────────────────

(defun satan-run-mint-id (mode-name &optional time)
  "Return a unique run-id like `20260531T221530-interactive-a3f01c'.
Seeds the PRNG from system entropy on first call."
  (random t)
  (format "%s-%s-%06x"
          (format-time-string "%Y%m%dT%H%M%S" time)
          mode-name
          (random (expt 16 6))))

(defconst satan-run--iso-time-format "%Y-%m-%dT%T%:z"
  "ISO-8601 time format stamped onto run_ctx and tool-ctx.")

;; ── Run directory resolution ────────────────────────────────────────────────

(defconst satan-run--failed-suffix ".FAILED"
  "Suffix appended to a run directory when its status is not `done'.
Lets `ls' / glob users see failures at a glance without opening the
`status' file.  The layout helpers strip the suffix when deriving the
run-id from a leaf directory name.")

(defun satan-run--date-bucket (run-id)
  "Return the YYYY-MM-DD date bucket parsed from RUN-ID's prefix.
Returns nil if RUN-ID does not start with a YYYYMMDDT date stamp."
  (when (and (stringp run-id)
             (string-match
              "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
              run-id))
    (format "%s-%s-%s"
            (match-string 1 run-id)
            (match-string 2 run-id)
            (match-string 3 run-id))))

(defun satan-run-dir-for-id (run-id &optional runs-dir)
  "Return the absolute dir path where RUN-ID's bucket lives.
New runs go under `<runs>/<YYYY-MM-DD>/<run-id>/'.  If RUN-ID lacks
a parsable date prefix (shouldn't happen for minted ids), falls back
to the legacy flat layout."
  (let* ((base (or runs-dir satan-runs-dir))
         (bucket (satan-run--date-bucket run-id)))
    (if bucket
        (expand-file-name (concat bucket "/" run-id) base)
      (expand-file-name run-id base))))

;; ── Prepare plist ───────────────────────────────────────────────────────────

(defun satan-run-new-ctx (mode)
  "Allocate run_id, freeze time_now, return the v0 run_ctx plist for MODE.
The plist is the single source of truth for the run's identity and
the frozen `time_now' that the percept builder, observer, and tool
handlers all read.  Phase-1+ slots (`:evidence' `:percept'
`:sensor_status' `:pre_spawn' `:motive' `:observer') are present-with-
nil so later phases can `plist-put' without keyword-arg ordering
surprises."
  (let* ((name (plist-get mode :name))
         (start (current-time))
         (run-id (satan-run-mint-id name start))
         (time-now (format-time-string satan-run--iso-time-format start)))
    (list :run_id run-id
          :mode_name name
          :time_now time-now
          :start_time start
          :evidence nil
          :percept nil
          :sensor_status nil
          :pre_spawn nil
          :motive nil
          :observer nil)))

;; ── Run directory layout ────────────────────────────────────────────────────

(defun satan-run--bucket-name-p (name)
  "Return non-nil when NAME matches the YYYY-MM-DD bucket-dir pattern."
  (and (stringp name)
       (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" name)))

(defun satan-run--legacy-run-name-p (name)
  "Return non-nil when NAME matches the pre-bucket flat run-id layout.
Pre-bucket runs sit directly under `satan-runs-dir' with names like
`20260520T163446-tick-pulse-5e8018'."
  (and (stringp name)
       (string-match-p "\\`[0-9]\\{8\\}T[0-9]\\{6\\}-" name)))

(defun satan-run--id-from-leaf (name)
  "Strip the trailing `.FAILED' suffix (if any) from a leaf dir NAME."
  (if (and (stringp name)
           (string-suffix-p satan-run--failed-suffix name))
      (substring name 0 (- (length name)
                           (length satan-run--failed-suffix)))
    name))

(defun satan-run-locate-dir (run-id &optional runs-dir)
  "Return the on-disk dir for RUN-ID, or nil if no candidate exists.
Probes (in order): bucketed/<run-id>, bucketed/<run-id>.FAILED,
legacy flat <run-id>, legacy flat <run-id>.FAILED.  Used by readers
that need to find a run regardless of layout migration or terminal
status."
  (let* ((base (or runs-dir satan-runs-dir))
         (bucket (satan-run--date-bucket run-id))
         (failed satan-run--failed-suffix)
         (candidates (delq nil
                           (list
                            (and bucket
                                 (expand-file-name
                                  (concat bucket "/" run-id) base))
                            (and bucket
                                 (expand-file-name
                                  (concat bucket "/" run-id failed) base))
                            (expand-file-name run-id base)
                            (expand-file-name (concat run-id failed) base)))))
    (cl-find-if #'file-directory-p candidates)))

(defun satan-run-list-dirs (runs-dir)
  "Return absolute paths of every run dir under RUNS-DIR.
Walks both the bucketed layout (`<runs>/<YYYY-MM-DD>/<run-id>') and
the legacy flat layout (`<runs>/<run-id>'), with or without the
`.FAILED' suffix.  Non-run entries (the `most-recent' symlink, stray
files, malformed names) are skipped.  Order is unspecified."
  (let (acc)
    (when (file-directory-p runs-dir)
      (dolist (entry (directory-files runs-dir nil "\\`[^.]" t))
        (let ((path (expand-file-name entry runs-dir)))
          (when (file-directory-p path)
            (cond
             ((satan-run--bucket-name-p entry)
              (dolist (child (directory-files path nil "\\`[^.]" t))
                (let ((cpath (expand-file-name child path)))
                  (when (and (file-directory-p cpath)
                             (satan-run--legacy-run-name-p
                              (satan-run--id-from-leaf child)))
                    (push cpath acc)))))
             ((satan-run--legacy-run-name-p
               (satan-run--id-from-leaf entry))
              (push path acc)))))))
    acc))

(defun satan-run-dirs-for-date (runs-dir date-prefix)
  "Return absolute paths of run dirs under RUNS-DIR dated DATE-PREFIX.
DATE-PREFIX is YYYYMMDDT (matching the run-id's stem).  Matches both
the bucketed layout (looks under `<runs>/YYYY-MM-DD/') and the legacy
flat layout (filters by prefix on the leaf name)."
  (let ((iso-bucket
         (and (stringp date-prefix)
              (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                            date-prefix)
              (format "%s-%s-%s"
                      (match-string 1 date-prefix)
                      (match-string 2 date-prefix)
                      (match-string 3 date-prefix)))))
    (cl-remove-if-not
     (lambda (path)
       (let* ((leaf (file-name-nondirectory path))
              (run-id (satan-run--id-from-leaf leaf))
              (parent (file-name-nondirectory (directory-file-name
                                               (file-name-directory path)))))
         (or (and iso-bucket (equal parent iso-bucket))
             (string-prefix-p date-prefix run-id))))
     (satan-run-list-dirs runs-dir))))

;; ── Lifecycle state (DEC-8) ─────────────────────────────────────────────────
;; DEC-8 is a two-flag mutual-exclusion protocol between a scheduled broker
;; run and an interactive MCP session: each side refuses to start while the
;; other's flag is truthy.  Both flags live here so neither module has to
;; reach into the other to read or write its counterpart (D6).

(defvar satan-run--spawn-running nil
  "Truthy while a scheduled broker run is live.
MCP reads this to refuse a new interactive session while a scheduled
run is in progress.")

(defvar satan-run--session-active nil
  "Truthy while an interactive MCP session is open.
The broker's scheduler reads this to refuse spawning a scheduled run
while a session is active.")

;; ── Tool context plist ──────────────────────────────────────────────────────

(defun satan-run-tool-ctx (run-ctx)
  "Return the tool-ctx plist handlers see.
Reads frozen `time_now' from RUN-CTX's prepare plist (allocated once
by `satan-run-new-ctx') rather than calling `format-time-string'
per tool call.  `run-started-at' aliases the same frozen value — a run
has exactly one starting moment.

`:audit' carries the live audit handle so the intervention write API
\(T7 PR 3) can emit `intervention.created' into transcript.jsonl on
the handler's behalf.  Handlers must not invoke `satan-audit-record'
directly with arbitrary event names; the only sanctioned route is
through `satan-intervention-create' (and the matching classify /
lookup APIs)."
  (let* ((mode (satan-run-mode run-ctx))
         (prepare (satan-run-prepare run-ctx))
         (time-now (plist-get prepare :time_now))
         (percept (plist-get prepare :percept)))
    (list :id (satan-run-id run-ctx)
          :mode-name (plist-get mode :name)
          :capabilities (plist-get mode :capabilities)
          :run-dir (satan-run-dir run-ctx)
          :hippocampus-dir satan-hippocampus-dir
          :run-started-at time-now
          :time-now time-now
          :audit (satan-run-audit run-ctx)
          :percept-handles (and percept (plist-get percept :handles)))))

(provide 'satan-run)
;;; satan-run.el ends here
