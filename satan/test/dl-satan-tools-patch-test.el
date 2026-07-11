;;; dl-satan-tools-patch-test.el --- broker-tool ert -*- lexical-binding: t; -*-

;; Exercises the five patch_job_* tools end-to-end against
;; `satan_memory_test'.  Builds a throwaway git repo for the
;; worktree-touching test paths.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tools-patch)
(require 'dl-satan-patch-store)
(require 'dl-satan-patch-worktree)
(require 'dl-satan-memory-migrate)
(require 'dl-satan-intervention)

(defconst dl-satan-tools-patch-test--db "satan_memory_test")

(defconst dl-satan-tools-patch-test--ctx
  '(:id "20260523T120000-self-edit-mech-deadbe"
    :mode-name "self-edit-mech"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities ()
    :audit dl-satan-tools-patch-test--stub-audit)
  "Synthetic tool-ctx threaded into patch_job_create across tests.")

(defvar dl-satan-tools-patch-test--captured nil
  "Per-test list of kwarg plists handed to `dl-satan-intervention-create'.")

(defun dl-satan-tools-patch-test--reachable-p ()
  (pcase (dl-satan-db-psql
          dl-satan-tools-patch-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
          (list "-A" "-t" "-c" "SELECT 1"))
    (`(ok . ,_) t)
    (_ nil)))

(defun dl-satan-tools-patch-test--truncate ()
  (dl-satan-db-psql
   dl-satan-tools-patch-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
   (list "-c" "TRUNCATE patch_job_events, patch_jobs RESTART IDENTITY CASCADE")))

(defun dl-satan-tools-patch-test--mkrepo (dir)
  (make-directory dir t)
  (let ((default-directory dir))
    (call-process "git" nil nil nil "init" "-q" "-b" "main")
    (call-process "git" nil nil nil "config" "user.email" "t@t")
    (call-process "git" nil nil nil "config" "user.name" "t")
    (with-temp-file (expand-file-name "README" dir) (insert "seed\n"))
    (call-process "git" nil nil nil "add" "README")
    (call-process "git" nil nil nil "commit" "-q" "-m" "init"))
  dir)

(defmacro dl-satan-tools-patch-test--with-fixture (var-repo &rest body)
  "Stub Postgres-backed fixture; also stubs `dl-satan-intervention-create'.
Inside BODY the symbol `dl-satan-tools-patch-test--captured' is a list of
keyword-args plists handed to the stub."
  (declare (indent 1))
  `(progn
     (skip-unless (dl-satan-tools-patch-test--reachable-p))
     (skip-unless (executable-find "git"))
     (dl-satan-tools-patch-test--truncate)
     (let* ((,var-repo (make-temp-file "satan-patch-tools-repo-" t))
            (wt-root (make-temp-file "satan-patch-tools-wt-" t))
            (dl-satan-patch-store-database dl-satan-tools-patch-test--db)
            (dl-satan-patch-worktree-root wt-root)
            (dl-satan-tools-patch-test--captured '()))
       (cl-letf (((symbol-function 'dl-satan-intervention-create)
                  (lambda (&rest args)
                    (push args dl-satan-tools-patch-test--captured)
                    "iv-patch-stub-01")))
         (unwind-protect
             (progn
               (dl-satan-tools-patch-test--mkrepo ,var-repo)
               ,@body)
           (when (file-directory-p ,var-repo) (delete-directory ,var-repo t))
           (when (file-directory-p wt-root) (delete-directory wt-root t)))))))

(defun dl-satan-tools-patch-test--create-job (repo &rest overrides)
  "Call the patch_job_create handler against REPO and return the result.
OVERRIDES are merged onto the default args plist.  :start defaults to
nil so the runner is not kicked from Phase-1 tests."
  (let ((args (append overrides
                      (list :directive "fix the thing"
                            :mode "self-edit-mech"
                            :repo repo
                            :allowed_paths '("satan/" "test/")
                            :start nil))))
    (dl-satan-tool/patch-job-create args dl-satan-tools-patch-test--ctx)))

;; ---------------------------------------------------------------------
;; create
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tools-patch/create-success ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (should (string-prefix-p "patch_" (plist-get info :job_id)))
       (should (equal (plist-get info :state) "queued"))
       (should (string-prefix-p "satan/self-edit-mech/"
                                (plist-get info :branch)))
       (should (equal (plist-get info :adapter) "pi"))
       (should (equal (plist-get info :intervention_id) "iv-patch-stub-01"))
       ;; row is persisted
       (pcase (dl-satan-patch-store-get (plist-get info :job_id))
         (`(ok . ,row)
          (should (equal (plist-get row :directive) "fix the thing"))
          (should (equal (plist-get row :allowed_paths_json)
                         '("satan/" "test/"))))
         (e (ert-fail (format "row missing: %S" e)))))
      (err (ert-fail (format "create: %S" err))))))

(ert-deftest dl-satan-tools-patch/create-emits-intervention-args ()
  "patch_job_create threads §3.3 defaults into `dl-satan-intervention-create'."
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((args (car dl-satan-tools-patch-test--captured)))
         (should args)
         (should (equal "patch_job" (plist-get args :kind)))
         (should (equal (plist-get info :job_id)
                        (plist-get args :target-surface)))
         (should (equal "medium"    (plist-get args :severity)))
         (should (equal 120         (plist-get args :outcome-window-minutes)))
         (should (equal "fix the thing" (plist-get args :message)))
         (should (string-match-p "reviews or applies"
                                 (plist-get args :expected-outcome)))))
      (err (ert-fail (format "create: %S" err))))))

(ert-deftest dl-satan-tools-patch/create-rejects-missing-repo ()
  (skip-unless (dl-satan-tools-patch-test--reachable-p))
  (dl-satan-tools-patch-test--truncate)
  (let ((dl-satan-patch-store-database dl-satan-tools-patch-test--db))
    (pcase (dl-satan-tool/patch-job-create
            (list :directive "x" :mode "self-edit-mech"
                  :repo "/nonexistent/repo"
                  :allowed_paths '("/"))
            nil)
      (`(error . ,_) t)
      (other (ert-fail (format "expected error, got %S" other))))))

(ert-deftest dl-satan-tools-patch/create-rejects-bad-mode ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tool/patch-job-create
            (list :directive "x" :mode "bogus"
                  :repo repo :allowed_paths '("/"))
            nil)
      (`(error . ,msg) (should (string-match-p "unknown mode" msg)))
      (other (ert-fail (format "expected error, got %S" other))))))

(ert-deftest dl-satan-tools-patch/create-rejects-empty-allowed ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tool/patch-job-create
            (list :directive "x" :mode "self-edit-mech"
                  :repo repo :allowed_paths '())
            nil)
      (`(error . ,_) t)
      (other (ert-fail (format "expected error, got %S" other))))))

;; ---------------------------------------------------------------------
;; status + result
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tools-patch/status-and-result-round-trip ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((job-id (plist-get info :job_id)))
         (pcase (dl-satan-tool/patch-job-status (list :job_id job-id) nil)
           (`(ok . ,s)
            (should (equal (plist-get s :state) "queued"))
            (should (equal (plist-get s :directive) "fix the thing")))
           (e (ert-fail (format "status: %S" e))))
         (pcase (dl-satan-tool/patch-job-result (list :job_id job-id) nil)
           (`(ok . ,r)
            (should (equal (plist-get r :state) "queued"))
            (should (null (plist-get r :result)))
            (should (equal (plist-get r :review_commands) '())))
           (e (ert-fail (format "result: %S" e))))))
      (err (ert-fail (format "create: %S" err))))))

(ert-deftest dl-satan-tools-patch/status-missing-job ()
  (skip-unless (dl-satan-tools-patch-test--reachable-p))
  (dl-satan-tools-patch-test--truncate)
  (let ((dl-satan-patch-store-database dl-satan-tools-patch-test--db))
    (pcase (dl-satan-tool/patch-job-status (list :job_id "patch_missing") nil)
      (`(error . ,msg) (should (string-match-p "no such job" msg)))
      (other (ert-fail (format "expected error, got %S" other))))))

(ert-deftest dl-satan-tools-patch/result-includes-review-commands ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((job-id (plist-get info :job_id)))
         (dl-satan-patch-store-update-state
          job-id "needs_review"
          :finished_at (format-time-string "%Y-%m-%dT%H:%M:%S%z")
          :result (list :summary "did it"
                        :commits (list (list :sha "abc1234"
                                             :subject "msg"))
                        :diffstat (list :files_changed 1
                                        :insertions 2
                                        :deletions 0)))
         (pcase (dl-satan-tool/patch-job-result (list :job_id job-id) nil)
           (`(ok . ,r)
            (should (equal (plist-get r :state) "needs_review"))
            (let ((cmds (plist-get r :review_commands)))
              (should (= 3 (length cmds)))
              (should (cl-some (lambda (s) (string-match-p "cherry-pick abc1234" s)) cmds))))
           (e (ert-fail (format "result: %S" e))))))
      (err (ert-fail (format "create: %S" err))))))

;; ---------------------------------------------------------------------
;; cancel
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tools-patch/cancel-queued ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((job-id (plist-get info :job_id)))
         (pcase (dl-satan-tool/patch-job-cancel (list :job_id job-id) nil)
           (`(ok . ,r)
            (should (equal (plist-get r :state) "cancelled")))
           (e (ert-fail (format "cancel: %S" e))))))
      (err (ert-fail (format "create: %S" err))))))

(ert-deftest dl-satan-tools-patch/cancel-refuses-terminal ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((job-id (plist-get info :job_id)))
         (dl-satan-patch-store-update-state
          job-id "failed"
          :finished_at (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
         (pcase (dl-satan-tool/patch-job-cancel (list :job_id job-id) nil)
           (`(error . ,_) t)
           (other (ert-fail (format "expected error, got %S" other))))))
      (err (ert-fail (format "create: %S" err))))))

;; ---------------------------------------------------------------------
;; prepare-stub + cleanup
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tools-patch/prepare-and-cleanup ()
  (dl-satan-tools-patch-test--with-fixture repo
    (pcase (dl-satan-tools-patch-test--create-job repo :base_ref "main")
      (`(ok . ,info)
       (let ((job-id (plist-get info :job_id)))
         (pcase (dl-satan-patch-prepare job-id)
           (`(ok . ,wt-info)
            (should (file-directory-p (plist-get wt-info :worktree-path)))
            (pcase (dl-satan-patch-store-get job-id)
              (`(ok . ,row)
               (should (equal (plist-get row :state) "running"))))
            ;; cleanup refuses non-terminal
            (pcase (dl-satan-tool/patch-job-cleanup
                    (list :job_id job-id) nil)
              (`(error . ,_) t)
              (other (ert-fail (format "expected refuse, got %S" other))))
            ;; advance to terminal, then cleanup
            (dl-satan-patch-store-update-state job-id "failed")
            (pcase (dl-satan-tool/patch-job-cleanup
                    (list :job_id job-id :delete_branch t) nil)
              (`(ok . ,r)
               (should (plist-get r :removed_worktree))
               (should (plist-get r :deleted_branch)))
              (e (ert-fail (format "cleanup: %S" e)))))
           (e (ert-fail (format "prepare: %S" e))))))
      (err (ert-fail (format "create: %S" err))))))

;; ---------------------------------------------------------------------
;; description files all present
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tools-patch/descriptions-resolvable ()
  (dolist (name '("patch_job_create"
                  "patch_job_status"
                  "patch_job_result"
                  "patch_job_cancel"
                  "patch_job_cleanup"))
    (let ((p (expand-file-name (concat name ".md")
                               dl-satan-tools-descriptions-dir)))
      (should (file-readable-p p)))))

(provide 'dl-satan-tools-patch-test)
;;; dl-satan-tools-patch-test.el ends here
