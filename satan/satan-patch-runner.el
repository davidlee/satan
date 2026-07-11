;;; satan-patch-runner.el --- async patch-job orchestrator -*- lexical-binding: t; -*-

;; Phase 2.4 of satan/patch-harness.plan.md.  One global runner; picks
;; up `queued' patch_jobs rows, walks them through
;; `claimed' -> `preparing_worktree' -> `running' -> terminal state.
;;
;; Public entry points:
;;
;;   `satan-patch-runner-tick'    -- idempotent; no-op if a job is
;;                                       already in flight in this Emacs.
;;                                       Drives a single job through the
;;                                       full lifecycle, asynchronously.
;;   `satan-patch-runner-kick'    -- alias intended to be called by
;;                                       `patch_job_create' once a row
;;                                       lands; same semantics as tick.
;;   `satan-patch-runner-active-p' -- inspection helper for tests.
;;
;; The orchestrator owns commit policy, allowlist enforcement, and the
;; failure ladder; adapters only edit + commit + report.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-patch-store)
(require 'satan-patch-worktree)
(require 'satan-patch-prompt)
(require 'satan-patch-adapter)

(defcustom satan-patch-runner-idle-seconds 30
  "Idle-timer cadence at which `satan-patch-runner-tick' runs.
The timer is created when `satan-patch-runner-start-timer' is
called; not started automatically at load time."
  :type 'integer :group 'satan-patch)

(defcustom satan-patch-runner-enabled nil
  "When non-nil, the elisp runner picks up queued patch jobs.
Set to nil to hand the queue off to the satan-patcher daemon
(see ~/dev/satan-patcher).  `satan-patch-runner-tick',
`-kick', and `-start-timer' all short-circuit when nil so the
elisp side stops competing for `claim-next' rows."
  :type 'boolean :group 'satan-patch)

(defvar satan-patch-runner--active nil
  "Job id of the job this Emacs is currently running, or nil.")

(defvar satan-patch-runner--idle-timer nil
  "Idle timer that periodically pokes `satan-patch-runner-tick'.")

(defvar satan-patch-runner-hook nil
  "Hook run with one argument (the final ROW plist) when a job reaches
a terminal state.  Used by the SATAN inbox/memory handoff in Phase 3.")

(defun satan-patch-runner-active-p ()
  "Return the job id currently in flight, or nil."
  satan-patch-runner--active)

;; ---------------------------------------------------------------------
;; idle timer
;; ---------------------------------------------------------------------

(defun satan-patch-runner-start-timer ()
  "Start the idle timer that periodically pokes the runner.
No-op when `satan-patch-runner-enabled' is nil."
  (when (and satan-patch-runner-enabled
             (null satan-patch-runner--idle-timer))
    (setq satan-patch-runner--idle-timer
          (run-with-idle-timer
           satan-patch-runner-idle-seconds t
           #'satan-patch-runner-tick))))

(defun satan-patch-runner-stop-timer ()
  "Cancel the runner's idle timer if running."
  (when (timerp satan-patch-runner--idle-timer)
    (cancel-timer satan-patch-runner--idle-timer))
  (setq satan-patch-runner--idle-timer nil))

;; ---------------------------------------------------------------------
;; state transitions (thin wrappers that log to the event table)
;; ---------------------------------------------------------------------

(defun satan-patch-runner--now-iso ()
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun satan-patch-runner--transition (job-id from to &rest fields)
  "Move JOB-ID FROM -> TO with optional FIELDS plist; log event."
  (let ((res (apply #'satan-patch-store-update-state
                    job-id to fields)))
    (pcase res
      (`(ok . ,_)
       (satan-patch-store-event
        job-id "transition" (list :from from :to to))
       res)
      (err err))))

(defun satan-patch-runner--fail (job-id from reason payload)
  "Terminal fail: move JOB-ID FROM -> failed, set error_json, log."
  (satan-patch-runner--transition
   job-id from "failed"
   :finished_at (satan-patch-runner--now-iso)
   :error (append (list :reason reason) payload))
  (satan-patch-store-event
   job-id "log"
   (list :level "error" :reason reason :payload payload)))

;; ---------------------------------------------------------------------
;; result assembly
;; ---------------------------------------------------------------------

(defun satan-patch-runner--review-commands (row commits)
  "Build the review_commands list for the result_json.
ROW is the job row plist; COMMITS the list of (:sha :subject) plists."
  (satan-patch--build-review-commands row commits))

(defun satan-patch-runner--assemble-result (row adapter-result commits diffstat)
  "Build the final result_json plist for the job."
  (list :summary (or (plist-get adapter-result :summary) "")
        :commits (or commits '())
        :diffstat (or diffstat '(:files_changed 0 :insertions 0 :deletions 0))
        :checks (or (plist-get adapter-result :checks) '())
        :warnings (or (plist-get adapter-result :warnings) '())
        :review_commands (satan-patch-runner--review-commands row commits)
        :raw_output (plist-get adapter-result :raw-output)
        :elapsed_seconds (plist-get adapter-result :elapsed-seconds)))

;; ---------------------------------------------------------------------
;; on-finish (called when adapter exits)
;; ---------------------------------------------------------------------

(defun satan-patch-runner--finish (job-id adapter-result)
  "Handle adapter completion for JOB-ID.  ADAPTER-RESULT is the plist
described in `satan-patch-adapter'."
  (unwind-protect
      (pcase (satan-patch-store-get job-id)
        (`(ok . nil)
         (satan-patch-store-event
          job-id "log"
          (list :level "error" :reason "job_row_vanished")))
        (`(ok . ,row)
         (satan-patch-runner--finish-with-row row adapter-result))
        (`(error . ,msg)
         (satan-patch-store-event
          job-id "log"
          (list :level "error" :reason "store_get_failed"
                :message msg))))
    (when (equal satan-patch-runner--active job-id)
      (setq satan-patch-runner--active nil))
    (let ((row (pcase (satan-patch-store-get job-id)
                 (`(ok . ,r) r) (_ nil))))
      (when row (run-hook-with-args 'satan-patch-runner-hook row)))))

(defun satan-patch-runner--finish-with-row (row adapter-result)
  "Inner half of `--finish' with ROW already fetched."
  (let* ((job-id (plist-get row :id))
         (adapter-status (plist-get adapter-result :status)))
    (cond
     ;; 1. adapter itself reported failure.
     ((eq adapter-status 'failure)
      (satan-patch-runner--fail
       job-id (plist-get row :state) "adapter_failed"
       (list :error (plist-get adapter-result :error)
             :summary (plist-get adapter-result :summary)
             :raw_output (plist-get adapter-result :raw-output)
             :elapsed_seconds (plist-get adapter-result :elapsed-seconds))))
     ;; 2. inspect what landed in git.
     (t
      (satan-patch-runner--finish-success-path row adapter-result)))))

(defun satan-patch-runner--finish-success-path (row adapter-result)
  "Process a non-failure adapter result: inspect git, verify allowlist,
record terminal state."
  (let* ((job-id (plist-get row :id))
         (changed
          (pcase (satan-patch-worktree-changed-files row)
            (`(ok . ,c) c)
            (_ nil)))
         (commits
          (pcase (satan-patch-worktree-commits row)
            (`(ok . ,xs) xs) (_ nil)))
         (diffstat
          (pcase (satan-patch-worktree-diffstat row)
            (`(ok . ,d) d) (_ nil)))
         (clean (satan-patch-worktree-status-clean-p row))
         (warnings (or (plist-get adapter-result :warnings) '())))
    (cond
     ;; allowlist violation: refuse, do not commit further, fail.
     ((let ((verify (satan-patch-worktree-verify-allowlist row changed)))
        (when (eq 'error (car verify))
          (satan-patch-runner--fail
           job-id (plist-get row :state)
           "allowlist_violation"
           (list :offending_paths (cdr verify)
                 :raw_output (plist-get adapter-result :raw-output)))
          t)))
     ;; no commits + worktree dirty: adapter left uncommitted changes;
     ;; treat as failure so the user can inspect or rerun.
     ((and (null commits) (not clean))
      (satan-patch-runner--fail
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
             (result-json (satan-patch-runner--assemble-result
                           row adapter-with-warnings nil diffstat)))
        (satan-patch-runner--transition
         job-id (plist-get row :state) "needs_review"
         :finished_at (satan-patch-runner--now-iso)
         :result result-json)))
     ;; happy path: at least one commit on the branch.
     (t
      (let* ((result-json (satan-patch-runner--assemble-result
                           row adapter-result commits diffstat)))
        (satan-patch-runner--transition
         job-id (plist-get row :state) "needs_review"
         :finished_at (satan-patch-runner--now-iso)
         :result result-json))))))

;; ---------------------------------------------------------------------
;; tick
;; ---------------------------------------------------------------------

(defun satan-patch-runner--prepare-worktree (row)
  "Move ROW into `preparing_worktree' and create its worktree on disk.
Returns (ok . ROW') with the row reloaded after transition, or
\(error . MSG) after marking the row failed."
  (let ((job-id (plist-get row :id)))
    (pcase (satan-patch-runner--transition
            job-id (plist-get row :state) "preparing_worktree")
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,_)
       (pcase (satan-patch-worktree-create row)
         (`(error . ,msg)
          (satan-patch-runner--fail
           job-id "preparing_worktree" "worktree_create_failed"
           (list :message msg))
          (cons 'error msg))
         (`(ok . ,_info)
          (pcase (satan-patch-runner--transition
                  job-id "preparing_worktree" "running"
                  :started_at (satan-patch-runner--now-iso))
            (`(ok . ,_) (satan-patch-store-get job-id))
            (err err))))))))

(defun satan-patch-runner-tick ()
  "Drive one queued patch job through to a terminal state.
Idempotent: no-op when another job is already in flight in this
Emacs, or when `satan-patch-runner-enabled' is nil.
Returns the claimed job-id, or nil if nothing was picked up."
  (when (and satan-patch-runner-enabled
             (null satan-patch-runner--active))
    (pcase (satan-patch-store-claim-next)
      (`(ok . nil) nil)
      (`(error . ,msg)
       (message "satan-patch-runner: claim-next failed: %s" msg)
       nil)
      (`(ok . ,claimed-row)
       (let ((job-id (plist-get claimed-row :id)))
         (setq satan-patch-runner--active job-id)
         (satan-patch-store-event
          job-id "transition" (list :from "queued" :to "claimed"))
         (condition-case err
             (pcase (satan-patch-runner--prepare-worktree claimed-row)
               (`(error . ,_) nil)
               (`(ok . ,row)
                (let* ((input (satan-patch-prompt-build row))
                       (adapter (or (plist-get row :adapter) "pi")))
                  (satan-patch-adapter-invoke
                   adapter row input
                   :on-finish
                   (lambda (result)
                     (satan-patch-runner--finish job-id result))))))
           (error
            (satan-patch-runner--fail
             job-id (plist-get claimed-row :state) "runner_exception"
             (list :message (error-message-string err)))
            (setq satan-patch-runner--active nil)))
         job-id)))))

(defalias 'satan-patch-runner-kick 'satan-patch-runner-tick)

(provide 'satan-patch-runner)
;;; satan-patch-runner.el ends here
