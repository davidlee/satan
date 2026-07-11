;;; dl-satan-patch-runner.el --- async patch-job orchestrator -*- lexical-binding: t; -*-

;; Phase 2.4 of satan/patch-harness.plan.md.  One global runner; picks
;; up `queued' patch_jobs rows, walks them through
;; `claimed' -> `preparing_worktree' -> `running' -> terminal state.
;;
;; Public entry points:
;;
;;   `dl-satan-patch-runner-tick'    -- idempotent; no-op if a job is
;;                                       already in flight in this Emacs.
;;                                       Drives a single job through the
;;                                       full lifecycle, asynchronously.
;;   `dl-satan-patch-runner-kick'    -- alias intended to be called by
;;                                       `patch_job_create' once a row
;;                                       lands; same semantics as tick.
;;   `dl-satan-patch-runner-active-p' -- inspection helper for tests.
;;
;; The orchestrator owns commit policy, allowlist enforcement, and the
;; failure ladder; adapters only edit + commit + report.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-worktree)
(require 'dl-satan-patch-prompt)
(require 'dl-satan-patch-adapter)

(defcustom dl-satan-patch-runner-idle-seconds 30
  "Idle-timer cadence at which `dl-satan-patch-runner-tick' runs.
The timer is created when `dl-satan-patch-runner-start-timer' is
called; not started automatically at load time."
  :type 'integer :group 'dl-satan-patch)

(defcustom dl-satan-patch-runner-enabled nil
  "When non-nil, the elisp runner picks up queued patch jobs.
Set to nil to hand the queue off to the satan-patcher daemon
(see ~/dev/satan-patcher).  `dl-satan-patch-runner-tick',
`-kick', and `-start-timer' all short-circuit when nil so the
elisp side stops competing for `claim-next' rows."
  :type 'boolean :group 'dl-satan-patch)

(defvar dl-satan-patch-runner--active nil
  "Job id of the job this Emacs is currently running, or nil.")

(defvar dl-satan-patch-runner--idle-timer nil
  "Idle timer that periodically pokes `dl-satan-patch-runner-tick'.")

(defvar dl-satan-patch-runner-hook nil
  "Hook run with one argument (the final ROW plist) when a job reaches
a terminal state.  Used by the SATAN inbox/memory handoff in Phase 3.")

(defun dl-satan-patch-runner-active-p ()
  "Return the job id currently in flight, or nil."
  dl-satan-patch-runner--active)

;; ---------------------------------------------------------------------
;; idle timer
;; ---------------------------------------------------------------------

(defun dl-satan-patch-runner-start-timer ()
  "Start the idle timer that periodically pokes the runner.
No-op when `dl-satan-patch-runner-enabled' is nil."
  (when (and dl-satan-patch-runner-enabled
             (null dl-satan-patch-runner--idle-timer))
    (setq dl-satan-patch-runner--idle-timer
          (run-with-idle-timer
           dl-satan-patch-runner-idle-seconds t
           #'dl-satan-patch-runner-tick))))

(defun dl-satan-patch-runner-stop-timer ()
  "Cancel the runner's idle timer if running."
  (when (timerp dl-satan-patch-runner--idle-timer)
    (cancel-timer dl-satan-patch-runner--idle-timer))
  (setq dl-satan-patch-runner--idle-timer nil))

;; ---------------------------------------------------------------------
;; state transitions (thin wrappers that log to the event table)
;; ---------------------------------------------------------------------

(defun dl-satan-patch-runner--now-iso ()
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun dl-satan-patch-runner--transition (job-id from to &rest fields)
  "Move JOB-ID FROM -> TO with optional FIELDS plist; log event."
  (let ((res (apply #'dl-satan-patch-store-update-state
                    job-id to fields)))
    (pcase res
      (`(ok . ,_)
       (dl-satan-patch-store-event
        job-id "transition" (list :from from :to to))
       res)
      (err err))))

(defun dl-satan-patch-runner--fail (job-id from reason payload)
  "Terminal fail: move JOB-ID FROM -> failed, set error_json, log."
  (dl-satan-patch-runner--transition
   job-id from "failed"
   :finished_at (dl-satan-patch-runner--now-iso)
   :error (append (list :reason reason) payload))
  (dl-satan-patch-store-event
   job-id "log"
   (list :level "error" :reason reason :payload payload)))

;; ---------------------------------------------------------------------
;; result assembly
;; ---------------------------------------------------------------------

(defun dl-satan-patch-runner--review-commands (row commits)
  "Build the review_commands list for the result_json.
ROW is the job row plist; COMMITS the list of (:sha :subject) plists."
  (dl-satan-patch--build-review-commands row commits))

(defun dl-satan-patch-runner--assemble-result (row adapter-result commits diffstat)
  "Build the final result_json plist for the job."
  (list :summary (or (plist-get adapter-result :summary) "")
        :commits (or commits '())
        :diffstat (or diffstat '(:files_changed 0 :insertions 0 :deletions 0))
        :checks (or (plist-get adapter-result :checks) '())
        :warnings (or (plist-get adapter-result :warnings) '())
        :review_commands (dl-satan-patch-runner--review-commands row commits)
        :raw_output (plist-get adapter-result :raw-output)
        :elapsed_seconds (plist-get adapter-result :elapsed-seconds)))

;; ---------------------------------------------------------------------
;; on-finish (called when adapter exits)
;; ---------------------------------------------------------------------

(defun dl-satan-patch-runner--finish (job-id adapter-result)
  "Handle adapter completion for JOB-ID.  ADAPTER-RESULT is the plist
described in `dl-satan-patch-adapter'."
  (unwind-protect
      (pcase (dl-satan-patch-store-get job-id)
        (`(ok . nil)
         (dl-satan-patch-store-event
          job-id "log"
          (list :level "error" :reason "job_row_vanished")))
        (`(ok . ,row)
         (dl-satan-patch-runner--finish-with-row row adapter-result))
        (`(error . ,msg)
         (dl-satan-patch-store-event
          job-id "log"
          (list :level "error" :reason "store_get_failed"
                :message msg))))
    (when (equal dl-satan-patch-runner--active job-id)
      (setq dl-satan-patch-runner--active nil))
    (let ((row (pcase (dl-satan-patch-store-get job-id)
                 (`(ok . ,r) r) (_ nil))))
      (when row (run-hook-with-args 'dl-satan-patch-runner-hook row)))))

(defun dl-satan-patch-runner--finish-with-row (row adapter-result)
  "Inner half of `--finish' with ROW already fetched."
  (let* ((job-id (plist-get row :id))
         (adapter-status (plist-get adapter-result :status)))
    (cond
     ;; 1. adapter itself reported failure.
     ((eq adapter-status 'failure)
      (dl-satan-patch-runner--fail
       job-id (plist-get row :state) "adapter_failed"
       (list :error (plist-get adapter-result :error)
             :summary (plist-get adapter-result :summary)
             :raw_output (plist-get adapter-result :raw-output)
             :elapsed_seconds (plist-get adapter-result :elapsed-seconds))))
     ;; 2. inspect what landed in git.
     (t
      (dl-satan-patch-runner--finish-success-path row adapter-result)))))

(defun dl-satan-patch-runner--finish-success-path (row adapter-result)
  "Process a non-failure adapter result: inspect git, verify allowlist,
record terminal state."
  (let* ((job-id (plist-get row :id))
         (changed
          (pcase (dl-satan-patch-worktree-changed-files row)
            (`(ok . ,c) c)
            (_ nil)))
         (commits
          (pcase (dl-satan-patch-worktree-commits row)
            (`(ok . ,xs) xs) (_ nil)))
         (diffstat
          (pcase (dl-satan-patch-worktree-diffstat row)
            (`(ok . ,d) d) (_ nil)))
         (clean (dl-satan-patch-worktree-status-clean-p row))
         (warnings (or (plist-get adapter-result :warnings) '())))
    (cond
     ;; allowlist violation: refuse, do not commit further, fail.
     ((let ((verify (dl-satan-patch-worktree-verify-allowlist row changed)))
        (when (eq 'error (car verify))
          (dl-satan-patch-runner--fail
           job-id (plist-get row :state)
           "allowlist_violation"
           (list :offending_paths (cdr verify)
                 :raw_output (plist-get adapter-result :raw-output)))
          t)))
     ;; no commits + worktree dirty: adapter left uncommitted changes;
     ;; treat as failure so the user can inspect or rerun.
     ((and (null commits) (not clean))
      (dl-satan-patch-runner--fail
       job-id (plist-get row :state)
       "uncommitted_changes"
       (list :summary (plist-get adapter-result :summary)
             :raw_output (plist-get adapter-result :raw-output))))
     ;; no commits + clean worktree: legitimate no-op; needs_review with
     ;; a note in warnings.  No commit.
     ((and (null commits) clean)
      (let* ((noop-warnings (append warnings (list "no changes produced")))
             (adapter-with-warnings
              (plist-put (copy-sequence adapter-result) :warnings noop-warnings))
             (result-json (dl-satan-patch-runner--assemble-result
                           row adapter-with-warnings nil diffstat)))
        (dl-satan-patch-runner--transition
         job-id (plist-get row :state) "needs_review"
         :finished_at (dl-satan-patch-runner--now-iso)
         :result result-json)))
     ;; happy path: at least one commit on the branch.
     (t
      (let* ((result-json (dl-satan-patch-runner--assemble-result
                           row adapter-result commits diffstat)))
        (dl-satan-patch-runner--transition
         job-id (plist-get row :state) "needs_review"
         :finished_at (dl-satan-patch-runner--now-iso)
         :result result-json))))))

;; ---------------------------------------------------------------------
;; tick
;; ---------------------------------------------------------------------

(defun dl-satan-patch-runner--prepare-worktree (row)
  "Move ROW into `preparing_worktree' and create its worktree on disk.
Returns (ok . ROW') with the row reloaded after transition, or
\(error . MSG) after marking the row failed."
  (let ((job-id (plist-get row :id)))
    (pcase (dl-satan-patch-runner--transition
            job-id (plist-get row :state) "preparing_worktree")
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,_)
       (pcase (dl-satan-patch-worktree-create row)
         (`(error . ,msg)
          (dl-satan-patch-runner--fail
           job-id "preparing_worktree" "worktree_create_failed"
           (list :message msg))
          (cons 'error msg))
         (`(ok . ,_info)
          (pcase (dl-satan-patch-runner--transition
                  job-id "preparing_worktree" "running"
                  :started_at (dl-satan-patch-runner--now-iso))
            (`(ok . ,_) (dl-satan-patch-store-get job-id))
            (err err))))))))

(defun dl-satan-patch-runner-tick ()
  "Drive one queued patch job through to a terminal state.
Idempotent: no-op when another job is already in flight in this
Emacs, or when `dl-satan-patch-runner-enabled' is nil.
Returns the claimed job-id, or nil if nothing was picked up."
  (when (and dl-satan-patch-runner-enabled
             (null dl-satan-patch-runner--active))
    (pcase (dl-satan-patch-store-claim-next)
      (`(ok . nil) nil)
      (`(error . ,msg)
       (message "dl-satan-patch-runner: claim-next failed: %s" msg)
       nil)
      (`(ok . ,claimed-row)
       (let ((job-id (plist-get claimed-row :id)))
         (setq dl-satan-patch-runner--active job-id)
         (dl-satan-patch-store-event
          job-id "transition" (list :from "queued" :to "claimed"))
         (condition-case err
             (pcase (dl-satan-patch-runner--prepare-worktree claimed-row)
               (`(error . ,_) nil)
               (`(ok . ,row)
                (let* ((input (dl-satan-patch-prompt-build row))
                       (adapter (or (plist-get row :adapter) "pi")))
                  (dl-satan-patch-adapter-invoke
                   adapter row input
                   :on-finish
                   (lambda (result)
                     (dl-satan-patch-runner--finish job-id result))))))
           (error
            (dl-satan-patch-runner--fail
             job-id (plist-get claimed-row :state) "runner_exception"
             (list :message (error-message-string err)))
            (setq dl-satan-patch-runner--active nil)))
         job-id)))))

(defalias 'dl-satan-patch-runner-kick 'dl-satan-patch-runner-tick)

(provide 'dl-satan-patch-runner)
;;; dl-satan-patch-runner.el ends here
