;;; satan-patch-promote.el --- show, promote or reject a reviewed patch job -*- lexical-binding: t; -*-

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
;; Show (IMP-043) takes the same fetch and check, needs baseOid too,
;; and stops there: it deletes the incoming ref, reports nothing, and
;; diffs baseOid..reviewedOid in the real repo (magit when available).
;; The fetched objects outlive the ref until git prunes them.  Git
;; never runs inside the quarantine, whose config is not Emacs's.
;;
;; Commands `satan-patch-show' / `satan-patch-promote' /
;; `satan-patch-reject' act on the inbox entry at point (its
;; SATAN_PATCH_JOB property).  A verdict records the outcome in its
;; STATE property and marks the entry read (drops its `:unread:' tag,
;; saves the inbox); show leaves the entry alone.

;;; Code:

(require 'cl-lib)
(require 'seq)
(require 'subr-x)
(require 'org)
(require 'satan-patch-rpc)

(declare-function magit-diff-range "magit-diff" (rev-or-range &optional args files))

(defconst satan-patch-promote--required
  '(:reviewed_oid :quarantine :quarantine_ref :repo_path)
  "Projected `result' fields promotion cannot proceed without.")

(defconst satan-patch-show--required
  (cons :base_oid satan-patch-promote--required)
  "Projected `result' fields showing a job cannot proceed without.")

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

(defun satan-patch-promote--reviewable (job-id required)
  "JOB-ID's `result', projected, if it is needs_review with REQUIRED fields.
Returns `(ok . JOB)' or `(error . MSG)'."
  (pcase (satan-patch-rpc-call "result" (list :jobId job-id))
    (`(ok . ,body)
     (let* ((job (satan-patch-rpc-project body t))
            (state (plist-get job :state))
            (missing (seq-remove (lambda (key) (satan-patch-rpc-field job key))
                                 required)))
       (cond
        ((not (equal state "needs_review"))
         (cons 'error (format "job %s is %s, not needs_review" job-id state)))
        (missing
         (cons 'error (format "job %s: the runner's result lacks %s" job-id
                              (mapconcat (lambda (key) (substring (symbol-name key) 1))
                                         missing ", "))))
        (t (cons 'ok job)))))
    (refusal refusal)))

(defun satan-patch-promote--verify-incoming (job repo fetch-exit fetch-output)
  "Whether the fetch into REPO brought JOB's reviewed commit.
FETCH-EXIT and FETCH-OUTPUT are the fetch's.  Returns `(ok . OID)' or
`(error . MSG)'."
  (let ((oid (plist-get job :reviewed_oid)))
    (if (/= fetch-exit 0)
        (cons 'error (format "git fetch from the quarantine failed (exit %s): %s"
                             fetch-exit fetch-output))
      (let ((fetched (cdr (satan-patch-promote--git
                           repo "rev-parse" "--verify" "--quiet"
                           (concat (satan-patch-promote--incoming
                                    (plist-get job :job_id))
                                   "^{commit}")))))
        (if (equal fetched oid)
            (cons 'ok oid)
          (cons 'error (format "quarantine ref moved: %s is %s, reviewed %s"
                               (plist-get job :quarantine_ref)
                               (if (string-empty-p fetched) "unresolvable" fetched)
                               oid)))))))

(defun satan-patch-promote--create-branch (job repo)
  "Create JOB's branch in REPO at its verified reviewed commit.
Returns `(ok . BRANCH)' or `(error . MSG)'."
  (let ((branch (satan-patch-promote-branch (plist-get job :job_id))))
    (pcase (satan-patch-promote--git
            repo "update-ref" (concat "refs/heads/" branch)
            (plist-get job :reviewed_oid) "")
      (`(0 . ,_) (cons 'ok branch))
      (`(,_ . ,output)
       (cons 'error (format "cannot create %s: %s" branch output))))))

(defun satan-patch-promote--report-branch (job outcome)
  "Report JOB promoted when OUTCOME, a branch creation's, succeeded.
Returns the final outcome."
  (pcase outcome
    (`(ok . ,branch)
     (pcase (satan-patch-promote--report (plist-get job :job_id) "promoted" branch)
       (`(error . ,msg)
        (cons 'error (format "%s; branch %s left in place" msg branch)))
       (reported reported)))
    (refusal refusal)))

(defun satan-patch-promote--with-incoming (job then callback)
  "Fetch JOB's quarantine ref into its incoming ref; verify it; call THEN.
THEN takes JOB and the real repo and returns an outcome, which CALLBACK
receives; a failed fetch or check reaches CALLBACK instead.  The
incoming ref is deleted whatever happens.  The fetch is asynchronous."
  (let* ((id (plist-get job :job_id))
         (repo (expand-file-name (plist-get job :repo_path)))
         (incoming (satan-patch-promote--incoming id))
         (refspec (format "+%s:%s" (plist-get job :quarantine_ref) incoming))
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
                        (unwind-protect
                            (pcase (satan-patch-promote--verify-incoming
                                    job repo (process-exit-status proc) output)
                              (`(ok . ,_) (funcall then job repo))
                              (refusal refusal))
                          (satan-patch-promote--git
                           repo "update-ref" "-d" incoming)))))))
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
  (pcase (satan-patch-promote--reviewable job-id satan-patch-promote--required)
    (`(ok . ,job)
     (satan-patch-promote--with-incoming
      job #'satan-patch-promote--create-branch
      (lambda (outcome)
        (funcall callback (satan-patch-promote--report-branch job outcome)))))
    (refusal (funcall callback refusal))))

(defun satan-patch-show-job (job-id callback)
  "Bring JOB-ID's reviewed commit into its real repo, to be diffed.
Asynchronous: CALLBACK receives `(ok . JOB)', the projected `result'
whose :base_oid..:reviewed_oid is now resolvable in :repo_path, or
`(error . MSG)'.  Creates no ref and reports nothing."
  (pcase (satan-patch-promote--reviewable job-id satan-patch-show--required)
    (`(ok . ,job)
     (satan-patch-promote--with-incoming
      job (lambda (job _repo) (cons 'ok job)) callback))
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
  "Record OUTCOME for JOB-ID on the inbox ENTRY (a marker) and say so.
A verdict also marks the entry read, saving the inbox so the
file-reading `satan-inbox-unread-count' sees it."
  (pcase outcome
    (`(ok . ,state)
     (when (buffer-live-p (marker-buffer entry))
       (org-with-point-at entry
         (org-entry-put nil "STATE" state)
         (org-toggle-tag "unread" 'off)
         (when buffer-file-name (save-buffer))))
     (message "Patch job %s %s" job-id state))
    (`(error . ,msg)
     (message "Patch job %s unchanged: %s" job-id msg))))

;; The magit test is its own function so tests can take the plain path.
(defun satan-patch-promote--magit-p ()
  "Whether magit can show the diff."
  (require 'magit nil t))

(defun satan-patch-promote--display (job)
  "Show JOB's base_oid..reviewed_oid diff from its real repo."
  (let* ((repo (file-name-as-directory
                (expand-file-name (plist-get job :repo_path))))
         (range (format "%s..%s" (plist-get job :base_oid)
                        (plist-get job :reviewed_oid))))
    (if (satan-patch-promote--magit-p)
        (let ((default-directory repo))
          (magit-diff-range range))
      (let ((buffer (get-buffer-create
                     (format "*satan-patch %s*" (plist-get job :job_id)))))
        (with-current-buffer buffer
          (let ((inhibit-read-only t))
            (erase-buffer)
            (call-process "git" nil t nil "-C" repo "diff" "--stat" "--patch" range))
          (goto-char (point-min))
          (diff-mode)
          (setq buffer-read-only t))
        (display-buffer buffer)))))

(defun satan-patch-promote--shown (job-id outcome)
  "Display OUTCOME of showing JOB-ID, or say why not."
  (pcase outcome
    (`(ok . ,job) (satan-patch-promote--display job))
    (`(error . ,msg) (message "Patch job %s not shown: %s" job-id msg))))

;;;###autoload
(defun satan-patch-show ()
  "Show the diff of the patch job of the inbox entry at point."
  (interactive)
  (let ((id (satan-patch-promote--job-at-point)))
    (message "Fetching patch job %s..." id)
    (satan-patch-show-job id (apply-partially #'satan-patch-promote--shown id))))

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
