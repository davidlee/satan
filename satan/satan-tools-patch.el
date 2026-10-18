;;; satan-tools-patch.el --- broker tools for patch jobs -*- lexical-binding: t; -*-

;; SL-023 (DEC-059, DEC-063): the malebolge patch runner owns patch jobs.
;; Four broker tools, each one control-socket request through
;; `satan-patch-rpc':
;;
;;   patch_job_create   submit a job (one submissionId, never resent)
;;   patch_job_status   the job's summary
;;   patch_job_result   its outcome: class, reviewed commit, quarantine
;;   patch_job_cancel   cancel it, with a reason
;;
;; Review is promote/reject in Emacs (satan-patch-promote), not a tool.
;; Tool descriptions live under `satan-tools-descriptions-dir'/patch_job_<name>.md;
;; this file carries mechanism only: schema, validation, handler.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'satan-tools)
(require 'satan-patch-rpc)
(require 'satan-intervention)

(defcustom satan-tools-patch-modes '("fix")
  "Modes `patch_job_create' offers the model: the runner's configured modes.
Mirrors the runner config's [mode.*] names; the runner refuses any other.
Read when this file loads (the tool schema is built then)."
  :type '(repeat string)
  :group 'satan)

(defconst satan-tools-patch--intervention-window-minutes 120
  "Default `outcome_window_minutes' for patch_job interventions.
Patch jobs need triage time before review (outcome-semantics §3.3).")

(defconst satan-tools-patch--intervention-expected-outcome
  "user reviews or applies the staged patch job within window"
  "Default `expected_outcome' for patch_job interventions.
See outcome-semantics §3.3.")

(defconst satan-tools-patch--cancel-reason "cancelled via patch_job_cancel"
  "The `cancel' reason when the model gives none (the runner requires one).")

;; ---------------------------------------------------------------------
;; patch_job_create
;; ---------------------------------------------------------------------

(defun satan-tools-patch--submit-fields (args)
  "The `submit' request fields for create ARGS, under a fresh submissionId."
  (append
   (list :submissionId (satan-patch-rpc-new-id)
         :mode (plist-get args :mode)
         :directive (plist-get args :directive)
         :repo (plist-get args :repo)
         :allowedPaths (vconcat (plist-get args :allowed_paths)))
   (cl-loop for (arg key array-p) in '((:base_ref :baseRef nil) (:tags :tags t)
                                      (:source :source nil) (:context :context nil))
            for value = (plist-get args arg)
            when value
            append (list key (if array-p (vconcat value) value)))))

(defun satan-tools-patch--announce (job-id directive ctx)
  "Create the patch_job intervention for JOB-ID asked DIRECTIVE under CTX.
Returns `(:intervention_id ID)', or `(:intervention_error MSG)' when the
intervention fails: the job exists either way, and must not be resubmitted."
  (condition-case err
      (list :intervention_id
            (satan-intervention-create
             :ctx ctx
             :kind "patch_job"
             :target-surface job-id
             :message directive
             :expected-outcome satan-tools-patch--intervention-expected-outcome
             :outcome-window-minutes satan-tools-patch--intervention-window-minutes
             :severity "medium"))
    (error (list :intervention_error (error-message-string err)))))

(defun satan-tool/patch-job-create (args ctx)
  "Handler for `patch_job_create'.
ARGS plist: :directive :mode :repo (a runner config name) :allowed_paths,
optional :base_ref :tags :source :context.  Submits once, under one
submissionId; never retried.  On the runner's ok, records a patch_job
intervention targeting the job id and returns `(ok :job_id :state
:intervention_id)', or `:intervention_error' in place of the id."
  (if (seq-empty-p (plist-get args :allowed_paths))
      (cons 'error "allowed_paths must be non-empty")
    (pcase (satan-patch-rpc-call "submit" (satan-tools-patch--submit-fields args))
      (`(ok . ,body)
       (let ((job-id (plist-get body :jobId)))
         (cons 'ok (append (list :job_id job-id :state (plist-get body :state))
                           (satan-tools-patch--announce
                            job-id (plist-get args :directive) ctx)))))
      (err err))))

;; ---------------------------------------------------------------------
;; patch_job_status / patch_job_result / patch_job_cancel
;; ---------------------------------------------------------------------

(defun satan-tools-patch--ask (op args answer)
  "Send OP for ARGS's job; on ok, return `(ok . (funcall ANSWER BODY))'."
  (pcase (satan-patch-rpc-call op (list :jobId (plist-get args :job_id)))
    (`(ok . ,body) (cons 'ok (funcall answer body)))
    (err err)))

(defun satan-tool/patch-job-status (args _ctx)
  "Handler for `patch_job_status': the job's projected summary."
  (satan-tools-patch--ask
   "status" args (lambda (body) (satan-patch-rpc-project (plist-get body :job)))))

(defun satan-tool/patch-job-result (args _ctx)
  "Handler for `patch_job_result': the job's projected outcome."
  (satan-tools-patch--ask "result" args #'satan-patch-rpc-project))

(defun satan-tool/patch-job-cancel (args _ctx)
  "Handler for `patch_job_cancel'; :reason is optional."
  (let ((job-id (plist-get args :job_id)))
    (pcase (satan-patch-rpc-call
            "cancel" (list :jobId job-id
                           :reason (or (plist-get args :reason)
                                       satan-tools-patch--cancel-reason)))
      (`(ok . ,body) (cons 'ok (list :job_id job-id :state (plist-get body :state))))
      (err err))))

;; ---------------------------------------------------------------------
;; registrations
;; ---------------------------------------------------------------------

(satan-tool-register
 (list :name "patch_job_create"
       :risk 'low
       :args-schema
       (list 'directive     (list :type 'string :required t)
             'mode          (list :type 'string :required t
                                  :enum satan-tools-patch-modes)
             'repo          (list :type 'string :required t)
             'allowed_paths (list :type 'array  :required t :items 'string)
             'base_ref      (list :type 'string)
             'tags          (list :type 'array :items 'string)
             'source        (list :type 'object)
             'context       (list :type 'object))
       :handler 'satan-tool/patch-job-create))

(satan-tool-register
 (list :name "patch_job_status"
       :risk 'read
       :args-schema (list 'job_id (list :type 'string :required t))
       :handler 'satan-tool/patch-job-status))

(satan-tool-register
 (list :name "patch_job_result"
       :risk 'read
       :args-schema (list 'job_id (list :type 'string :required t))
       :handler 'satan-tool/patch-job-result))

(satan-tool-register
 (list :name "patch_job_cancel"
       :risk 'low
       :args-schema (list 'job_id (list :type 'string :required t)
                          'reason (list :type 'string))
       :handler 'satan-tool/patch-job-cancel))

(provide 'satan-tools-patch)
;;; satan-tools-patch.el ends here
