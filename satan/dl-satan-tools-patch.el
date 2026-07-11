;;; dl-satan-tools-patch.el --- broker tools for patch jobs -*- lexical-binding: t; -*-

;; Phase 1.4 of satan/patch-harness.plan.md.  Five tools exposed to the
;; broker:
;;
;;   patch_job_create     queue a patch job
;;   patch_job_status     read state and bookkeeping
;;   patch_job_result     read commits + diffstat + checks + warnings
;;   patch_job_cancel     transition queued/claimed -> cancelled
;;   patch_job_cleanup    remove worktree (and optionally branch)
;;
;; Tool descriptions live under
;;   `dl-satan-tools-descriptions-dir'/patch_job_<name>.md
;; and are loaded verbatim into the model-facing manifest by the
;; broker.  This file carries mechanism only — schema, validation,
;; handler.
;;
;; In Phase 1 the tools do not execute the harness; they only manage
;; rows + on-disk worktrees.  The runner that drives queued jobs to
;; completion lands in Phase 2.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools)
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-worktree)
(require 'dl-satan-patch-runner)
(require 'dl-satan-intervention)

(defconst dl-satan-tools-patch--known-modes
  '("self-edit-mech" "self-edit-mind"
    "note-rewrite" "tick-agent" "manual")
  "Mode names accepted by `patch_job_create' in v1.")

(defconst dl-satan-tools-patch--cancellable-states
  '("queued" "claimed" "preparing_worktree" "running")
  "States `patch_job_cancel' will transition to `cancelled'.")

(defconst dl-satan-tools-patch--cleanup-states
  '("needs_review" "failed" "cancelled" "accepted_external" "stale")
  "States `patch_job_cleanup' will operate on (terminal only).")

(defconst dl-satan-tools-patch--intervention-window-minutes 120
  "Default `outcome_window_minutes' for patch_job interventions (outcome-semantics §3.3).
Patch jobs need triage time before review.")

(defconst dl-satan-tools-patch--intervention-expected-outcome
  "user reviews or applies the staged patch job within window"
  "Default `expected_outcome' for patch_job interventions (outcome-semantics §3.3).")

;; ---------------------------------------------------------------------
;; helpers
;; ---------------------------------------------------------------------

(defun dl-satan-tools-patch--list-of-strings-p (xs)
  (and (listp xs) (cl-every #'stringp xs)))

(defun dl-satan-tools-patch--summarize-row (row)
  "Project a job ROW plist into a public-facing subset."
  (list :job_id (plist-get row :id)
        :state (plist-get row :state)
        :mode (plist-get row :mode)
        :repo (plist-get row :repo)
        :branch (plist-get row :branch)
        :worktree_path (plist-get row :worktree_path)
        :adapter (plist-get row :adapter)
        :created_at (plist-get row :created_at)
        :updated_at (plist-get row :updated_at)
        :started_at (plist-get row :started_at)
        :finished_at (plist-get row :finished_at)
        :allowed_paths (plist-get row :allowed_paths_json)
        :directive (plist-get row :directive)))

(defun dl-satan-tools-patch--review-commands (row)
  "Build a small list of suggested review shell commands for ROW.
Empty list when the job has produced no commits yet."
  (dl-satan-patch--build-review-commands row))

;; ---------------------------------------------------------------------
;; patch_job_create
;; ---------------------------------------------------------------------

(defun dl-satan-tool/patch-job-create (args ctx)
  "Handler for `patch_job_create'.
ARGS plist (keyword keys): :directive :mode :repo :allowed_paths
:base_ref :branch :worktree_path :source :context :checks :adapter.

On successful row insert the handler emits a T7 `intervention.created'
\(kind=patch_job, target_surface=<job_id>) via
`dl-satan-intervention-create' and surfaces the minted id alongside
the existing `:job_id' / `:state' / `:branch' / `:worktree_path' /
`:adapter' result keys."
  (let* ((directive  (plist-get args :directive))
         (mode       (plist-get args :mode))
         (repo       (plist-get args :repo))
         (allowed    (plist-get args :allowed_paths))
         (base       (or (plist-get args :base_ref) "HEAD"))
         (adapter    (or (plist-get args :adapter) "pi"))
         (source     (plist-get args :source))
         (context    (plist-get args :context))
         (checks     (plist-get args :checks))
         (start      (if (plist-member args :start)
                         (plist-get args :start)
                       t)))
    (cond
     ((not (file-directory-p repo))
      (cons 'error (format "repo missing: %s" repo)))
     ((not (member mode dl-satan-tools-patch--known-modes))
      (cons 'error (format "unknown mode: %s (allowed: %S)"
                            mode dl-satan-tools-patch--known-modes)))
     ((not (dl-satan-tools-patch--list-of-strings-p allowed))
      (cons 'error "allowed_paths must be a list of strings"))
     ((null allowed)
      (cons 'error "allowed_paths must be non-empty"))
     (t
      (let* ((now-iso (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
             (job-id (dl-satan-patch-store-job-id-new now-iso))
             (branch (or (plist-get args :branch)
                         (dl-satan-patch-worktree-branch-name
                          mode (or (plist-get source :slug)
                                   (substring directive 0
                                              (min 40 (length directive)))))))
             (wt (or (plist-get args :worktree_path)
                     (dl-satan-patch-worktree-path-for job-id))))
        (pcase (dl-satan-patch-store-insert
                :job-id job-id
                :mode mode
                :directive directive
                :repo repo
                :base_ref base
                :branch branch
                :worktree_path wt
                :adapter adapter
                :source source
                :context context
                :allowed_paths allowed
                :checks checks)
          (`(ok . ,_)
           (dl-satan-patch-store-event
            job-id "transition"
            (list :from nil :to "queued" :reason "created"))
           (condition-case err
               (let ((iv-id (dl-satan-intervention-create
                             :ctx ctx
                             :kind "patch_job"
                             :target-surface job-id
                             :message directive
                             :expected-outcome
                             dl-satan-tools-patch--intervention-expected-outcome
                             :outcome-window-minutes
                             dl-satan-tools-patch--intervention-window-minutes
                             :severity "medium")))
                 (when start
                   (condition-case _err (dl-satan-patch-runner-kick) (error nil)))
                 (cons 'ok (list :job_id job-id
                                 :state "queued"
                                 :branch branch
                                 :worktree_path wt
                                 :adapter adapter
                                 :intervention_id iv-id)))
             (error (cons 'error (error-message-string err)))))
          (err err)))))))

;; ---------------------------------------------------------------------
;; patch_job_status
;; ---------------------------------------------------------------------

(defun dl-satan-tool/patch-job-status (args _ctx)
  (let ((job-id (plist-get args :job_id)))
    (pcase (dl-satan-patch-store-get job-id)
      (`(ok . nil) (cons 'error (format "no such job: %s" job-id)))
      (`(ok . ,row)
       (cons 'ok (dl-satan-tools-patch--summarize-row row)))
      (err err))))

;; ---------------------------------------------------------------------
;; patch_job_result
;; ---------------------------------------------------------------------

(defun dl-satan-tool/patch-job-result (args _ctx)
  (let ((job-id (plist-get args :job_id)))
    (pcase (dl-satan-patch-store-get job-id)
      (`(ok . nil) (cons 'error (format "no such job: %s" job-id)))
      (`(ok . ,row)
       (let* ((result (plist-get row :result_json))
              (error_ (plist-get row :error_json))
              (review (dl-satan-tools-patch--review-commands row)))
         (cons 'ok
               (append
                (dl-satan-tools-patch--summarize-row row)
                (list :base_ref (plist-get row :base_ref)
                      :result result
                      :error error_
                      :review_commands (or review '()))))))
      (err err))))

;; ---------------------------------------------------------------------
;; patch_job_cancel
;; ---------------------------------------------------------------------

(defun dl-satan-tool/patch-job-cancel (args _ctx)
  (let ((job-id (plist-get args :job_id)))
    (pcase (dl-satan-patch-store-get job-id)
      (`(ok . nil) (cons 'error (format "no such job: %s" job-id)))
      (`(ok . ,row)
       (let ((state (plist-get row :state)))
         (cond
          ((not (member state dl-satan-tools-patch--cancellable-states))
           (cons 'error
                 (format "cannot cancel job in state %s" state)))
          (t
           (pcase (dl-satan-patch-store-update-state
                   job-id "cancelled"
                   :finished_at (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
             (`(ok . ,_)
              (dl-satan-patch-store-event
               job-id "transition"
               (list :from state :to "cancelled"))
              (cons 'ok (list :job_id job-id :state "cancelled")))
             (err err))))))
      (err err))))

;; ---------------------------------------------------------------------
;; patch_job_cleanup
;; ---------------------------------------------------------------------

(defun dl-satan-tool/patch-job-cleanup (args _ctx)
  (let ((job-id (plist-get args :job_id))
        (delete-branch (eq t (plist-get args :delete_branch))))
    (pcase (dl-satan-patch-store-get job-id)
      (`(ok . nil) (cons 'error (format "no such job: %s" job-id)))
      (`(ok . ,row)
       (let ((state (plist-get row :state)))
         (cond
          ((not (member state dl-satan-tools-patch--cleanup-states))
           (cons 'error
                 (format "cannot cleanup non-terminal job (state=%s)" state)))
          (t
           (pcase (dl-satan-patch-worktree-cleanup
                   row :delete-branch delete-branch)
             (`(ok . ,info)
              (dl-satan-patch-store-event
               job-id "cleanup"
               (list :removed_worktree (plist-get info :removed-worktree)
                     :deleted_branch (plist-get info :deleted-branch)))
              (cons 'ok (list :job_id job-id
                              :removed_worktree
                              (plist-get info :removed-worktree)
                              :deleted_branch
                              (plist-get info :deleted-branch))))
             (err err))))))
      (err err))))

;; ---------------------------------------------------------------------
;; non-tool helper: prepare a queued job (Phase 1 stub for the runner)
;; ---------------------------------------------------------------------

(defun dl-satan-patch-prepare (job-id)
  "Move JOB-ID through preparing_worktree by creating its worktree.
Phase 1 stub for the Phase 2 runner.  Returns (ok PLIST) or (error MSG)."
  (pcase (dl-satan-patch-store-get job-id)
    (`(ok . nil) (cons 'error (format "no such job: %s" job-id)))
    (`(ok . ,row)
     (pcase (dl-satan-patch-store-update-state
             job-id "preparing_worktree")
       (`(ok . ,_)
        (dl-satan-patch-store-event
         job-id "transition"
         (list :from (plist-get row :state) :to "preparing_worktree"))
        (pcase (dl-satan-patch-worktree-create row)
          (`(ok . ,info)
           (dl-satan-patch-store-update-state job-id "running")
           (dl-satan-patch-store-event
            job-id "transition"
            (list :from "preparing_worktree" :to "running"))
           (cons 'ok info))
          (`(error . ,msg)
           (dl-satan-patch-store-update-state
            job-id "failed"
            :finished_at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
            :error (list :reason "worktree_create_failed"
                         :message msg))
           (cons 'error msg))))
       (err err)))
    (err err)))

;; ---------------------------------------------------------------------
;; registrations
;; ---------------------------------------------------------------------

(dl-satan-tool-register
 (list :name "patch_job_create"
       :risk 'low
       :args-schema
       (list 'directive    (list :type 'string :required t)
             'mode         (list :type 'string :required t
                                 :enum dl-satan-tools-patch--known-modes)
             'repo         (list :type 'string :required t)
             'allowed_paths (list :type 'array  :required t :items 'string)
             'base_ref     (list :type 'string)
             'branch       (list :type 'string)
             'worktree_path (list :type 'string)
             'adapter      (list :type 'string :enum '("pi" "zerostack"))
             'source       (list :type 'object)
             'context      (list :type 'object)
             'checks       (list :type 'array :items 'string)
             'start        (list :type 'boolean))
       :handler 'dl-satan-tool/patch-job-create))

(dl-satan-tool-register
 (list :name "patch_job_status"
       :risk 'read
       :args-schema (list 'job_id (list :type 'string :required t))
       :handler 'dl-satan-tool/patch-job-status))

(dl-satan-tool-register
 (list :name "patch_job_result"
       :risk 'read
       :args-schema (list 'job_id (list :type 'string :required t))
       :handler 'dl-satan-tool/patch-job-result))

(dl-satan-tool-register
 (list :name "patch_job_cancel"
       :risk 'low
       :args-schema (list 'job_id (list :type 'string :required t))
       :handler 'dl-satan-tool/patch-job-cancel))

(dl-satan-tool-register
 (list :name "patch_job_cleanup"
       :risk 'medium
       :args-schema
       (list 'job_id        (list :type 'string  :required t)
             'delete_branch (list :type 'boolean))
       :handler 'dl-satan-tool/patch-job-cleanup))

(provide 'dl-satan-tools-patch)
;;; dl-satan-tools-patch.el ends here
