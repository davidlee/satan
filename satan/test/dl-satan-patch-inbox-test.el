;;; dl-satan-patch-inbox-test.el --- ert for inbox handoff -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-patch-inbox)
(require 'dl-satan-tools-inbox)

(defmacro dl-satan-patch-inbox-test--with-tmp-inbox (var &rest body)
  "Bind VAR to a fresh empty inbox file path; clean up after BODY."
  (declare (indent 1))
  `(let* ((,var (make-temp-file "satan-patch-inbox-" nil ".org"))
          (dl-satan-inbox-file ,var))
     (unwind-protect (progn ,@body)
       (when (file-exists-p ,var) (delete-file ,var)))))

(defun dl-satan-patch-inbox-test--read (path)
  (with-temp-buffer
    (insert-file-contents path)
    (buffer-string)))

(defun dl-satan-patch-inbox-test--row (overrides)
  "Build a plausible terminal job ROW plist with OVERRIDES."
  (let ((base (list :id "patch_test_001"
                    :state "needs_review"
                    :mode "self-edit-mech"
                    :repo "/tmp/repo"
                    :branch "satan/self-edit-mech/20260520T000000-x"
                    :base_ref "main"
                    :result_json
                    (list :summary "rewrote the bit"
                          :commits (list (list :sha "abc1234"
                                               :subject "msg"))
                          :diffstat (list :files_changed 1
                                          :insertions 5
                                          :deletions 2)
                          :checks (list (list :name "ert" :status "passed"))
                          :warnings '()
                          :review_commands
                          '("git -C /tmp/repo diff main...satan/x"
                            "git -C /tmp/repo cherry-pick abc1234"))
                    :error_json nil)))
    (cl-loop for (k v) on overrides by #'cddr
             do (setq base (plist-put base k v)))
    base))

;; ---------------------------------------------------------------------
;; happy path: needs_review -> inbox item with review commands
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-inbox/success-handoff ()
  (dl-satan-patch-inbox-test--with-tmp-inbox path
    (let ((row (dl-satan-patch-inbox-test--row nil)))
      (dl-satan-patch-inbox-handoff row)
      (let ((text (dl-satan-patch-inbox-test--read path)))
        (should (string-match-p "Patch ready: self-edit-mech" text))
        (should (string-match-p ":SATAN_PATCH_JOB: patch_test_001" text))
        (should (string-match-p ":BRANCH: satan/self-edit-mech" text))
        (should (string-match-p "cherry-pick abc1234" text))
        (should (string-match-p "abc1234 msg" text))
        ;; tags
        (should (string-match-p ":unread:satan:" text))))))

;; ---------------------------------------------------------------------
;; failure path: state=failed -> urgent tag
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-inbox/failure-is-urgent ()
  (dl-satan-patch-inbox-test--with-tmp-inbox path
    (let ((row (dl-satan-patch-inbox-test--row
                (list :state "failed"
                      :result_json nil
                      :error_json (list :reason "allowlist_violation"
                                        :offending_paths '("core/x.el"))))))
      (dl-satan-patch-inbox-handoff row)
      (let ((text (dl-satan-patch-inbox-test--read path)))
        (should (string-match-p "Patch failed: self-edit-mech" text))
        (should (string-match-p ":urgent:" text))
        (should (string-match-p "Error: allowlist_violation" text))))))

;; ---------------------------------------------------------------------
;; non-terminal states: do nothing
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-inbox/queued-is-noop ()
  (dl-satan-patch-inbox-test--with-tmp-inbox path
    (let ((row (dl-satan-patch-inbox-test--row (list :state "queued"))))
      (dl-satan-patch-inbox-handoff row)
      (should (or (not (file-exists-p path))
                  (zerop (file-attribute-size (file-attributes path))))))))

;; ---------------------------------------------------------------------
;; hook is auto-installed
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-inbox/hook-is-registered ()
  (should (memq #'dl-satan-patch-inbox-handoff
                dl-satan-patch-runner-hook)))

;; ---------------------------------------------------------------------
;; smoke: inbox-write helper rejects non-strings cleanly
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-inbox/write-rejects-non-strings ()
  (pcase (dl-satan-tools-inbox-write :title nil :body "body")
    (`(error . ,_) t)
    (other (ert-fail (format "expected error, got %S" other)))))

(provide 'dl-satan-patch-inbox-test)
;;; dl-satan-patch-inbox-test.el ends here
