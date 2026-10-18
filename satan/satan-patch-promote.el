;;; satan-patch-promote.el --- promote or reject a reviewed patch job -*- lexical-binding: t; -*-

;; SL-023 (DEC-061): the human's verdict on a needs_review job.  Emacs,
;; not the runner, writes the branch in the real repo; the runner only
;; records the disposition (and checks the branch against its receipt).
;;
;;   result RPC          state needs_review, reviewedOid, quarantine,
;;                       quarantineRef, repoPath (all required; a
;;                       missing one refuses before any git runs)
;;   git fetch (async)   <quarantine> +<quarantineRef>:refs/satan/incoming/<id>
;;   rev-parse           incoming == reviewedOid, else refuse
;;   update-ref          refs/heads/satan/patch/<id> <oid> ""  (only if absent)
;;   update-ref -d       incoming, whatever happened after the fetch
;;   report-disposition  promoted, branch satan/patch/<id>
;;
;; A refusal touches nothing outside Emacs's own scratch namespace
;; (refs/satan/incoming/, always cleaned) and reports nothing.  A
;; receipt_mismatch from the runner leaves the branch for the user to
;; inspect.  Reject is one report-disposition; no git.
;;
;; Commands `satan-patch-promote' / `satan-patch-reject' act on the
;; inbox entry at point (its SATAN_PATCH_JOB property) and record the
;; outcome in its STATE property.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'satan-patch-rpc)

(defconst satan-patch-promote--required
  '(:reviewed_oid :quarantine :quarantine_ref :repo_path)
  "Projected `result' fields promotion cannot proceed without.")

(defun satan-patch-promote-branch (job-id)
  "The branch JOB-ID is promoted to: satan/patch/JOB-ID."
  (concat "satan/patch/" job-id))

(defun satan-patch-promote--incoming (job-id)
  "Emacs's scratch ref for JOB-ID's fetched commit."
  (concat "refs/satan/incoming/" job-id))

(defun satan-patch-promote--git (repo &rest args)
  "Run git ARGS in REPO synchronously: (EXIT . OUTPUT), OUTPUT trimmed."
  (with-temp-buffer
    (let ((exit (apply #'call-process "git" nil t nil "-C" repo args)))
      (cons exit (string-trim (buffer-string))))))

(defun satan-patch-promote--report (job-id disposition &optional branch)
  "Report DISPOSITION of JOB-ID (with BRANCH when promoted) to the runner.
Returns `(ok . DISPOSITION)' or `(error . MSG)'."
  (pcase (satan-patch-rpc-call
          "report-disposition"
          (append (list :jobId job-id :disposition disposition)
                  (when branch (list :branch branch))))
    (`(ok . ,_) (cons 'ok disposition))
    (refusal refusal)))

(defun satan-patch-promote--reviewable (job-id)
  "JOB-ID's `result', projected, if it can be promoted.
Returns `(ok . JOB)' or `(error . MSG)'."
  (pcase (satan-patch-rpc-call "result" (list :jobId job-id))
    (`(ok . ,body)
     (let* ((job (satan-patch-rpc-project body t))
            (state (plist-get job :state))
            (missing (seq-remove (lambda (key) (satan-patch-rpc-field job key))
                                 satan-patch-promote--required)))
       (cond
        ((not (equal state "needs_review"))
         (cons 'error (format "job %s is %s, not needs_review" job-id state)))
        (missing
         (cons 'error (format "job %s: the runner's result lacks %s" job-id
                              (mapconcat (lambda (key) (substring (symbol-name key) 1))
                                         missing ", "))))
        (t (cons 'ok job)))))
    (refusal refusal)))

(defun satan-patch-promote--create-branch (job repo fetch-exit fetch-output)
  "Create JOB's branch in REPO from the fetched incoming ref.
FETCH-EXIT and FETCH-OUTPUT are the fetch's.  The incoming ref is
deleted whatever happens.  Returns `(ok . BRANCH)' or `(error . MSG)'."
  (let* ((id (plist-get job :job_id))
         (oid (plist-get job :reviewed_oid))
         (incoming (satan-patch-promote--incoming id))
         (branch (satan-patch-promote-branch id)))
    (unwind-protect
        (if (/= fetch-exit 0)
            (cons 'error (format "git fetch from the quarantine failed (exit %s): %s"
                                 fetch-exit fetch-output))
          (let ((fetched (cdr (satan-patch-promote--git
                               repo "rev-parse" "--verify" "--quiet"
                               (concat incoming "^{commit}")))))
            (if (not (equal fetched oid))
                (cons 'error (format "quarantine ref moved: %s is %s, reviewed %s"
                                     (plist-get job :quarantine_ref)
                                     (if (string-empty-p fetched) "unresolvable" fetched)
                                     oid))
              (pcase (satan-patch-promote--git
                      repo "update-ref" (concat "refs/heads/" branch) oid "")
                (`(0 . ,_) (cons 'ok branch))
                (`(,_ . ,output)
                 (cons 'error (format "cannot create %s: %s" branch output)))))))
      (satan-patch-promote--git repo "update-ref" "-d" incoming))))

(defun satan-patch-promote--land (job repo fetch-exit fetch-output)
  "After JOB's fetch into REPO: create the branch, then report it.
FETCH-EXIT and FETCH-OUTPUT are the fetch's.  Returns the outcome."
  (pcase (satan-patch-promote--create-branch job repo fetch-exit fetch-output)
    (`(ok . ,branch)
     (pcase (satan-patch-promote--report (plist-get job :job_id) "promoted" branch)
       (`(error . ,msg)
        (cons 'error (format "%s; branch %s left in place" msg branch)))
       (reported reported)))
    (refusal refusal)))

(defun satan-patch-promote--fetch (job callback)
  "Fetch JOB's quarantine ref into its incoming ref; then land it.
The fetch is asynchronous; CALLBACK receives the outcome."
  (let* ((id (plist-get job :job_id))
         (repo (expand-file-name (plist-get job :repo_path)))
         (refspec (format "+%s:%s" (plist-get job :quarantine_ref)
                          (satan-patch-promote--incoming id)))
         (buffer (generate-new-buffer " *satan-patch-fetch*")))
    (condition-case err
        (make-process
         :name "satan-patch-fetch" :buffer buffer :noquery t
         :connection-type 'pipe
         :command (list "git" "-C" repo "fetch" "--no-tags" "--no-write-fetch-head"
                        (plist-get job :quarantine) refspec)
         :sentinel
         (lambda (proc _event)
           (when (memq (process-status proc) '(exit signal))
             (let ((output (with-current-buffer buffer
                             (string-trim (buffer-string)))))
               (kill-buffer buffer)
               (funcall callback
                        (satan-patch-promote--land
                         job repo (process-exit-status proc) output))))))
      (error
       (kill-buffer buffer)
       (funcall callback
                (cons 'error (format "git fetch: %s" (error-message-string err))))))))

(defun satan-patch-promote-job (job-id callback)
  "Promote JOB-ID to branch satan/patch/JOB-ID in its real repo.
Asynchronous: CALLBACK receives `(ok . \"promoted\")' or `(error . MSG)'.
Refuses, touching nothing, unless the runner's result says the job is
needs_review with a reviewed commit that its quarantine ref still holds
and that branch does not exist yet."
  (pcase (satan-patch-promote--reviewable job-id)
    (`(ok . ,job) (satan-patch-promote--fetch job callback))
    (refusal (funcall callback refusal))))

(defun satan-patch-reject-job (job-id)
  "Reject JOB-ID: `(ok . \"rejected\")' or `(error . MSG)'.  No git."
  (satan-patch-promote--report job-id "rejected"))

;; ---------------------------------------------------------------------
;; commands, on the inbox entry at point
;; ---------------------------------------------------------------------

(defun satan-patch-promote--job-at-point ()
  "The patch job of the inbox entry at point."
  (or (org-entry-get nil "SATAN_PATCH_JOB")
      (user-error "No patch job at point (no SATAN_PATCH_JOB property)")))

(defun satan-patch-promote--settle (entry job-id outcome)
  "Record OUTCOME for JOB-ID on the inbox ENTRY (a marker) and say so."
  (pcase outcome
    (`(ok . ,state)
     (when (buffer-live-p (marker-buffer entry))
       (org-entry-put entry "STATE" state))
     (message "Patch job %s %s" job-id state))
    (`(error . ,msg)
     (message "Patch job %s unchanged: %s" job-id msg))))

;;;###autoload
(defun satan-patch-promote ()
  "Promote the patch job of the inbox entry at point to its branch."
  (interactive)
  (let ((id (satan-patch-promote--job-at-point)))
    (when (y-or-n-p (format "Promote patch job %s to branch %s? "
                            id (satan-patch-promote-branch id)))
      (message "Promoting patch job %s..." id)
      (satan-patch-promote-job
       id (apply-partially #'satan-patch-promote--settle (point-marker) id)))))

;;;###autoload
(defun satan-patch-reject ()
  "Reject the patch job of the inbox entry at point."
  (interactive)
  (let ((id (satan-patch-promote--job-at-point)))
    (when (y-or-n-p (format "Reject patch job %s? " id))
      (satan-patch-promote--settle (point-marker) id (satan-patch-reject-job id)))))

(provide 'satan-patch-promote)
;;; satan-patch-promote.el ends here
