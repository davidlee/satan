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
  "Read-write scratch directory inside the jail."
  :type 'directory :group 'satan)

;; ── Run struct ──────────────────────────────────────────────────────────────

(cl-defstruct satan-run
  "A single SATAN run — used by the broker and MCP session."
  id mode start-time dir bundle-path process
  pending-tool-calls tool-calls-done
  applied-actions staged-actions rejected-actions failed-actions
  final status timeout-timer audit
  stdout-log-path
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
  "Suffix appended to a run directory when its status is not `done'.")

(defun satan-run--date-bucket (run-id)
  "Return the YYYY-MM-DD date bucket parsed from RUN-ID's prefix, or nil."
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
New runs go under `<runs>/<YYYY-MM-DD>/<run-id>/'."
  (let* ((base (or runs-dir satan-runs-dir))
         (bucket (satan-run--date-bucket run-id)))
    (if bucket
        (expand-file-name (concat bucket "/" run-id) base)
      (expand-file-name run-id base))))

;; ── Prepare plist ───────────────────────────────────────────────────────────

(defun satan-run-prepare (mode)
  "Allocate run_id, freeze time_now, return the v0 run_ctx plist for MODE.
Carries the frozen `:time_now', `:run_id', `:start_time' and v0
placeholder slots for later phases."
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
Reads frozen `time_now' from RUN-CTX's prepare plist — one allocation,
reused across all tool calls in the run."
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
