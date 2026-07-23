;;; satan-run.el --- Shared SATAN run infrastructure (id, dirs, struct, tool-ctx) -*- lexical-binding: t; -*-

;; Lightweight module with zero heavy deps — required by satan-broker and
;; satan-mcp without pulling in context/percept/denote-journal.
;;
;; Extracted from satan-broker.el so the MCP server can mint runs, resolve
;; run directories, and build tool-ctx plists without transitive broker deps.

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
