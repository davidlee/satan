;;; dl-satan-run.el --- Shared SATAN run infrastructure (id, dirs, struct, tool-ctx) -*- lexical-binding: t; -*-

;; Lightweight module with zero heavy deps — required by dl-satan-broker and
;; dl-satan-mcp without pulling in context/percept/denote-journal.
;;
;; Extracted from dl-satan-broker.el so the MCP server can mint runs, resolve
;; run directories, and build tool-ctx plists without transitive broker deps.

(require 'cl-lib)
(require 'subr-x)

;; ── Directories ─────────────────────────────────────────────────────────────

(defcustom dl-satan-runs-dir
  (expand-file-name "satan/runs" (or (bound-and-true-p dl-notes-root)
                                     (expand-file-name "~/notes")))
  "Directory holding per-run audit bundles."
  :type 'directory :group 'dl-satan)

(defcustom dl-satan-hippocampus-dir
  (expand-file-name "satan/hippocampus" (or (bound-and-true-p dl-notes-root)
                                            (expand-file-name "~/notes")))
  "Read-write scratch directory inside the jail."
  :type 'directory :group 'dl-satan)

;; ── Run struct ──────────────────────────────────────────────────────────────

(cl-defstruct dl-satan-run
  "A single SATAN run — used by the broker and MCP session."
  id mode start-time dir bundle-path process
  pending-tool-calls tool-calls-done
  applied-actions staged-actions rejected-actions failed-actions
  final status timeout-timer audit
  stdout-log-path
  prepare)

;; ── Run ID minting ──────────────────────────────────────────────────────────

(defun dl-satan-run-mint-id (mode-name &optional time)
  "Return a unique run-id like `20260531T221530-interactive-a3f01c'.
Seeds the PRNG from system entropy on first call."
  (random t)
  (format "%s-%s-%06x"
          (format-time-string "%Y%m%dT%H%M%S" time)
          mode-name
          (random (expt 16 6))))

(defconst dl-satan-run--iso-time-format "%Y-%m-%dT%T%:z"
  "ISO-8601 time format stamped onto run_ctx and tool-ctx.")

;; ── Run directory resolution ────────────────────────────────────────────────

(defconst dl-satan-run--failed-suffix ".FAILED"
  "Suffix appended to a run directory when its status is not `done'.")

(defun dl-satan-run--date-bucket (run-id)
  "Return the YYYY-MM-DD date bucket parsed from RUN-ID's prefix, or nil."
  (when (and (stringp run-id)
             (string-match
              "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
              run-id))
    (format "%s-%s-%s"
            (match-string 1 run-id)
            (match-string 2 run-id)
            (match-string 3 run-id))))

(defun dl-satan-run-dir-for-id (run-id &optional runs-dir)
  "Return the absolute dir path where RUN-ID's bucket lives.
New runs go under `<runs>/<YYYY-MM-DD>/<run-id>/'."
  (let* ((base (or runs-dir dl-satan-runs-dir))
         (bucket (dl-satan-run--date-bucket run-id)))
    (if bucket
        (expand-file-name (concat bucket "/" run-id) base)
      (expand-file-name run-id base))))

;; ── Prepare plist ───────────────────────────────────────────────────────────

(defun dl-satan-run-prepare (mode)
  "Allocate run_id, freeze time_now, return the v0 run_ctx plist for MODE.
Carries the frozen `:time_now', `:run_id', `:start_time' and v0
placeholder slots for later phases."
  (let* ((name (plist-get mode :name))
         (start (current-time))
         (run-id (dl-satan-run-mint-id name start))
         (time-now (format-time-string dl-satan-run--iso-time-format start)))
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

(defun dl-satan-run-tool-ctx (run-ctx)
  "Return the tool-ctx plist handlers see.
Reads frozen `time_now' from RUN-CTX's prepare plist — one allocation,
reused across all tool calls in the run."
  (let* ((mode (dl-satan-run-mode run-ctx))
         (prepare (dl-satan-run-prepare run-ctx))
         (time-now (plist-get prepare :time_now))
         (percept (plist-get prepare :percept)))
    (list :id (dl-satan-run-id run-ctx)
          :mode-name (plist-get mode :name)
          :capabilities (plist-get mode :capabilities)
          :run-dir (dl-satan-run-dir run-ctx)
          :hippocampus-dir dl-satan-hippocampus-dir
          :run-started-at time-now
          :time-now time-now
          :audit (dl-satan-run-audit run-ctx)
          :percept-handles (and percept (plist-get percept :handles)))))

(provide 'dl-satan-run)
;;; dl-satan-run.el ends here
