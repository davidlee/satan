;;; dl-satan-patch-inbox.el --- inbox handoff for patch jobs -*- lexical-binding: t; -*-

;; Phase 3.4 of satan/patch-harness.plan.md.  Listens on
;; `dl-satan-patch-runner-hook' and surfaces every terminal job
;; (success or failure) as an inbox headline.  Body follows brief §12.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools-inbox)
(require 'dl-satan-patch-runner)

(defun dl-satan-patch-inbox--render-body (row)
  "Render the inbox body for ROW (terminal job row plist)."
  (let* ((state   (plist-get row :state))
         (mode    (plist-get row :mode))
         (repo    (plist-get row :repo))
         (branch  (plist-get row :branch))
         (result  (plist-get row :result_json))
         (errobj  (plist-get row :error_json))
         (summary (or (plist-get result :summary)
                      (plist-get errobj :message)
                      ""))
         (commits (plist-get result :commits))
         (diffstat (plist-get result :diffstat))
         (checks  (plist-get result :checks))
         (warnings (plist-get result :warnings))
         (review  (plist-get result :review_commands))
         (lines '()))
    (push (format "State: %s" state) lines)
    (push (format "Mode: %s" mode) lines)
    (push (format "Repo: %s" repo) lines)
    (push (format "Branch: %s" branch) lines)
    (push "" lines)
    (unless (string-empty-p (string-trim summary))
      (push summary lines)
      (push "" lines))
    (when (consp commits)
      (push "Commits:" lines)
      (dolist (c commits)
        (push (format "- %s %s"
                      (or (plist-get c :sha) "?")
                      (or (plist-get c :subject) ""))
              lines))
      (push "" lines))
    (when (consp diffstat)
      (push (format "Diffstat: %s files, +%s/-%s"
                    (or (plist-get diffstat :files_changed) 0)
                    (or (plist-get diffstat :insertions) 0)
                    (or (plist-get diffstat :deletions) 0))
            lines)
      (push "" lines))
    (when (consp checks)
      (push "Checks:" lines)
      (dolist (c checks)
        (push (format "- %s: %s"
                      (or (plist-get c :name) "?")
                      (or (plist-get c :status) "?"))
              lines))
      (push "" lines))
    (when (consp warnings)
      (push "Warnings:" lines)
      (dolist (w warnings)
        (push (format "- %s" w) lines))
      (push "" lines))
    (when errobj
      (push (format "Error: %s" (or (plist-get errobj :reason)
                                    (plist-get errobj :error)
                                    errobj))
            lines)
      (push "" lines))
    (when (consp review)
      (push "Review:" lines)
      (push "#+begin_src sh" lines)
      (dolist (cmd review)
        (push cmd lines))
      (push "#+end_src" lines)
      (push "" lines))
    (mapconcat #'identity (nreverse lines) "\n")))

(defun dl-satan-patch-inbox--title (row)
  (let* ((mode (plist-get row :mode))
         (state (plist-get row :state))
         (result (plist-get row :result_json))
         (errobj (plist-get row :error_json))
         (summary (or (plist-get result :summary)
                      (plist-get errobj :reason)
                      "(no summary)"))
         (prefix (pcase state
                   ("needs_review" "Patch ready")
                   ("failed"       "Patch failed")
                   (_              (format "Patch %s" state)))))
    (format "%s: %s — %s" prefix mode
            (string-trim (substring summary 0 (min 80 (length summary)))))))

(defun dl-satan-patch-inbox-handoff (row)
  "Append an inbox headline summarising ROW's terminal patch job.
Hook target for `dl-satan-patch-runner-hook'.  Only fires on
`needs_review' or `failed'; any other state is a no-op so the hook
is safe to add even before a job has reached terminal state."
  (let ((state (plist-get row :state)))
    (when (member state '("needs_review" "failed"))
      (condition-case err
          (dl-satan-tools-inbox-write
           :title (dl-satan-patch-inbox--title row)
           :urgency (if (equal state "failed") "urgent" "normal")
           :body (dl-satan-patch-inbox--render-body row)
           :properties (list :satan_patch_job (plist-get row :id)
                             :branch (plist-get row :branch)
                             :repo (plist-get row :repo)
                             :mode (plist-get row :mode)
                             :state state))
        (error
         (message "dl-satan-patch-inbox: handoff failed: %s"
                  (error-message-string err)))))))

;;;###autoload
(add-hook 'dl-satan-patch-runner-hook #'dl-satan-patch-inbox-handoff)

(provide 'dl-satan-patch-inbox)
;;; dl-satan-patch-inbox.el ends here
