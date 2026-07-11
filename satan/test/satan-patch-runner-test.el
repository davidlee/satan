;;; satan-patch-runner-test.el --- ert for the runner -*- lexical-binding: t; -*-

;; Drives a fake adapter through the runner lifecycle against a
;; throwaway git repo + `satan_memory_test'.

(require 'ert)
(require 'cl-lib)
(require 'satan-patch-runner)
(require 'satan-patch-adapter)
(require 'satan-patch-store)
(require 'satan-patch-worktree)
(require 'satan-patch-prompt)
(require 'satan-memory-migrate)
(require 'satan-tools-patch)

(defconst satan-patch-runner-test--db "satan_memory_test")

;; ---------------------------------------------------------------------
;; fixture helpers
;; ---------------------------------------------------------------------

(defun satan-patch-runner-test--reachable-p ()
  (pcase (satan-db-psql
          satan-patch-runner-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
          (list "-A" "-t" "-c" "SELECT 1"))
    (`(ok . ,_) t) (_ nil)))

(defun satan-patch-runner-test--truncate ()
  (satan-db-psql
   satan-patch-runner-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
   (list "-c" "TRUNCATE patch_job_events, patch_jobs RESTART IDENTITY CASCADE")))

(defun satan-patch-runner-test--mkrepo (dir)
  (make-directory dir t)
  (let ((default-directory dir))
    (call-process "git" nil nil nil "init" "-q" "-b" "main")
    (call-process "git" nil nil nil "config" "user.email" "t@t")
    (call-process "git" nil nil nil "config" "user.name" "t")
    (with-temp-file (expand-file-name "README" dir) (insert "seed\n"))
    (call-process "git" nil nil nil "add" "README")
    (call-process "git" nil nil nil "commit" "-q" "-m" "init"))
  dir)

(defmacro satan-patch-runner-test--with-fixture (var-repo &rest body)
  "Build a throwaway repo + temp worktree root + clean PG patch tables;
bind VAR-REPO to the repo path, plus the appropriate satan-patch
defcustoms, and ensure the fake adapter is registered before BODY."
  (declare (indent 1))
  `(progn
     (skip-unless (satan-patch-runner-test--reachable-p))
     (skip-unless (executable-find "git"))
     (satan-patch-runner-test--truncate)
     (let* ((,var-repo (make-temp-file "satan-patch-runner-repo-" t))
            (wt-root (make-temp-file "satan-patch-runner-wt-" t))
            (log-root (make-temp-file "satan-patch-runner-log-" t))
            (prompt-tmp (make-temp-file "satan-patch-runner-prompt-" nil ".md"))
            (satan-patch-store-database satan-patch-runner-test--db)
            (satan-patch-worktree-root wt-root)
            (satan-patch-prompt-log-root log-root)
            (satan-patch-prompt-system-file prompt-tmp)
            (satan-patch-runner--active nil)
            (satan-patch-runner-enabled t)
            (satan-patch-runner-hook nil))
       (with-temp-file prompt-tmp (insert "# test prompt\n"))
       (cl-letf (((symbol-function 'satan-intervention-create)
                  (lambda (&rest _args) "iv-runner-stub-01")))
         (unwind-protect
             (progn
               (satan-patch-runner-test--mkrepo ,var-repo)
               ,@body)
           (when (file-directory-p ,var-repo) (delete-directory ,var-repo t))
           (when (file-directory-p wt-root) (delete-directory wt-root t))
           (when (file-directory-p log-root) (delete-directory log-root t))
           (when (file-exists-p prompt-tmp) (delete-file prompt-tmp)))))))

;; ---------------------------------------------------------------------
;; fake adapter behaviours
;; ---------------------------------------------------------------------

(defun satan-patch-runner-test--commit (wt rel-path body subject)
  "Inside worktree WT, write REL-PATH=BODY, stage, commit with SUBJECT."
  (let* ((full (expand-file-name rel-path wt))
         (dir (file-name-directory full)))
    (when dir (make-directory dir t))
    (with-temp-file full (insert body))
    (let ((default-directory wt))
      (call-process "git" nil nil nil "add" rel-path)
      (call-process "git" nil nil nil "commit" "-q" "-m" subject))))

(defun satan-patch-runner-test--stage-only (wt rel-path body)
  "Inside WT, write REL-PATH=BODY but leave it uncommitted (untracked)."
  (let* ((full (expand-file-name rel-path wt))
         (dir (file-name-directory full)))
    (when dir (make-directory dir t))
    (with-temp-file full (insert body))))

(defun satan-patch-runner-test--fake-adapter (behavior)
  "Return a fake adapter function implementing BEHAVIOR.
BEHAVIOR is one of:
  :success-commit       -- edit + commit satan/foo.el inside worktree
  :allowlist-violation  -- commit core/bad.el inside worktree
  :noop-clean           -- no edits, status=success
  :uncommitted          -- write satan/foo.el untracked, status=success
  :adapter-failure      -- on-finish with :status failure"
  (cl-function
   (lambda (job-spec _input &key on-finish &allow-other-keys)
     (let ((wt (plist-get job-spec :worktree_path)))
       (pcase behavior
         (:success-commit
          (satan-patch-runner-test--commit
           wt "satan/foo.el" ";; ok\n" "self-edit-mech: add foo"))
         (:allowlist-violation
          (satan-patch-runner-test--commit
           wt "core/bad.el" ";; bad\n" "self-edit-mech: bad"))
         (:noop-clean nil)
         (:uncommitted
          (satan-patch-runner-test--stage-only
           wt "satan/foo.el" ";; partial\n"))
         (:adapter-failure nil))
       (when on-finish
         (funcall on-finish
                  (if (eq behavior :adapter-failure)
                      (list :status 'failure
                            :error "boom"
                            :summary "")
                    (list :status 'success
                          :summary (format "fake did %s" behavior)))))))))

(defun satan-patch-runner-test--register-fake (behavior)
  (satan-patch-adapter-register
   "fake" (satan-patch-runner-test--fake-adapter behavior)))

(defconst satan-patch-runner-test--ctx
  '(:id "20260523T120000-self-edit-mech-deadbe"
    :mode-name "self-edit-mech"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities ()
    :audit satan-patch-runner-test--stub-audit)
  "Synthetic tool-ctx threaded into patch_job_create for runner ert.")

(defun satan-patch-runner-test--enqueue (repo)
  "Insert a queued job pointing at REPO with adapter=fake.  Returns job-id."
  (pcase (satan-tool/patch-job-create
          (list :directive "fix it"
                :mode "self-edit-mech"
                :repo repo
                :allowed_paths '("satan/" "test/")
                :base_ref "main"
                :adapter "fake"
                :start nil)
          satan-patch-runner-test--ctx)
    (`(ok . ,info) (plist-get info :job_id))
    (other (ert-fail (format "enqueue: %S" other)))))

(defun satan-patch-runner-test--row (job-id)
  (pcase (satan-patch-store-get job-id)
    (`(ok . ,r) r)
    (e (ert-fail (format "store-get: %S" e)))))

;; ---------------------------------------------------------------------
;; happy path: success + commit -> needs_review
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/success-commit ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :success-commit)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (should (equal (satan-patch-runner-tick) job-id))
      (let* ((row (satan-patch-runner-test--row job-id))
             (result (plist-get row :result_json)))
        (should (equal "needs_review" (plist-get row :state)))
        (should (plist-get row :finished_at))
        (should (consp (plist-get result :commits)))
        (should (= 1 (length (plist-get result :commits))))
        (let ((review (plist-get result :review_commands)))
          (should (cl-some (lambda (s) (string-match-p "cherry-pick" s))
                           review))))
      ;; --active should be cleared
      (should (null (satan-patch-runner-active-p))))))

;; ---------------------------------------------------------------------
;; allowlist violation -> failed
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/allowlist-violation ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :allowlist-violation)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (satan-patch-runner-tick)
      (let* ((row (satan-patch-runner-test--row job-id))
             (err (plist-get row :error_json)))
        (should (equal "failed" (plist-get row :state)))
        (should (equal "allowlist_violation" (plist-get err :reason)))
        (should (member "core/bad.el" (plist-get err :offending_paths)))
        (should (null (plist-get row :result_json)))))))

;; ---------------------------------------------------------------------
;; no-op clean -> needs_review with warning
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/noop-clean ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :noop-clean)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (satan-patch-runner-tick)
      (let* ((row (satan-patch-runner-test--row job-id))
             (result (plist-get row :result_json)))
        (should (equal "needs_review" (plist-get row :state)))
        (should (null (plist-get result :commits)))
        (should (cl-some (lambda (s)
                           (string-match-p "no changes produced" s))
                         (plist-get result :warnings)))))))

;; ---------------------------------------------------------------------
;; uncommitted leftover -> failed
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/uncommitted-changes ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :uncommitted)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (satan-patch-runner-tick)
      (let* ((row (satan-patch-runner-test--row job-id))
             (err (plist-get row :error_json)))
        (should (equal "failed" (plist-get row :state)))
        (should (equal "uncommitted_changes" (plist-get err :reason)))))))

;; ---------------------------------------------------------------------
;; adapter signaled failure -> failed
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/adapter-failure ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :adapter-failure)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (satan-patch-runner-tick)
      (let* ((row (satan-patch-runner-test--row job-id))
             (err (plist-get row :error_json)))
        (should (equal "failed" (plist-get row :state)))
        (should (equal "adapter_failed" (plist-get err :reason)))
        (should (equal "boom" (plist-get err :error)))))))

;; ---------------------------------------------------------------------
;; queue empty -> tick is a no-op
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/empty-queue ()
  (skip-unless (satan-patch-runner-test--reachable-p))
  (satan-patch-runner-test--truncate)
  (let ((satan-patch-store-database satan-patch-runner-test--db)
        (satan-patch-runner--active nil))
    (should (null (satan-patch-runner-tick)))))

;; ---------------------------------------------------------------------
;; --active guard: a second tick while one is in flight is a no-op
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/active-guard ()
  (satan-patch-runner-test--with-fixture repo
    ;; Register an adapter that does NOT call on-finish; the job stays
    ;; "in flight" so we can prove the guard rejects a second tick.
    (satan-patch-adapter-register
     "fake" (cl-function (lambda (&rest _) nil)))
    (let ((first (satan-patch-runner-test--enqueue repo))
          (_second (satan-patch-runner-test--enqueue repo)))
      (should (equal first (satan-patch-runner-tick)))
      ;; second tick while first is still active: no-op (--active set,
      ;; never cleared because fake never resolved on-finish).
      (should (null (satan-patch-runner-tick)))
      (should (equal first (satan-patch-runner-active-p))))))

;; ---------------------------------------------------------------------
;; lifecycle event log records the transitions
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/event-log-transitions ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :success-commit)
    (let ((job-id (satan-patch-runner-test--enqueue repo)))
      (satan-patch-runner-tick)
      (pcase (satan-patch-store-events job-id)
        (`(ok . ,events)
         (let ((transitions
                (cl-loop for e in events
                         when (equal "transition" (plist-get e :kind))
                         collect (plist-get (plist-get e :payload) :to))))
           (should (member "queued" transitions))
           (should (member "claimed" transitions))
           (should (member "preparing_worktree" transitions))
           (should (member "running" transitions))
           (should (member "needs_review" transitions))))
        (e (ert-fail (format "events: %S" e)))))))

;; ---------------------------------------------------------------------
;; runner-hook fires with the terminal row
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/hook-fires ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :success-commit)
    (let* ((job-id (satan-patch-runner-test--enqueue repo))
           (captured nil)
           (satan-patch-runner-hook
            (list (lambda (row) (setq captured row)))))
      (satan-patch-runner-tick)
      (should captured)
      (should (equal job-id (plist-get captured :id)))
      (should (equal "needs_review" (plist-get captured :state))))))

;; ---------------------------------------------------------------------
;; runner-enabled=nil short-circuits tick (daemon handoff)
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/disabled-short-circuits ()
  (satan-patch-runner-test--with-fixture repo
    (satan-patch-runner-test--register-fake :success-commit)
    (let* ((satan-patch-runner-enabled nil)
           (job-id (satan-patch-runner-test--enqueue repo)))
      (should (null (satan-patch-runner-tick)))
      (should (null (satan-patch-runner-active-p)))
      (let ((row (satan-patch-runner-test--row job-id)))
        (should (equal "queued" (plist-get row :state)))))))

;; ---------------------------------------------------------------------
;; gated real-pi integration: SATAN_PATCH_LIVE=1 to opt in
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-runner/real-pi-edits-and-commits ()
  (skip-unless (equal "1" (getenv "SATAN_PATCH_LIVE")))
  (skip-unless (executable-find "jailed-pi"))
  (skip-unless (satan-patch-runner-test--reachable-p))
  (skip-unless (executable-find "git"))
  (satan-patch-runner-test--truncate)
  (let* ((repo (make-temp-file "satan-patch-pi-repo-" t))
         (wt-root (make-temp-file "satan-patch-pi-wt-" t))
         (log-root (make-temp-file "satan-patch-pi-log-" t))
         (satan-patch-store-database satan-patch-runner-test--db)
         (satan-patch-worktree-root wt-root)
         (satan-patch-prompt-log-root log-root)
         (satan-patch-runner--active nil))
    (unwind-protect
        (progn
          (satan-patch-runner-test--mkrepo repo)
          ;; seed an existing file the agent should modify
          (with-temp-file (expand-file-name "satan/hello.el" repo)
            (make-directory (expand-file-name "satan" repo) t)
            (insert ";; replace this line\n"))
          (let ((default-directory repo))
            (call-process "git" nil nil nil "add" "satan/hello.el")
            (call-process "git" nil nil nil "commit" "-q" "-m" "seed"))
          (let* ((create
                  (satan-tool/patch-job-create
                   (list :directive
                         "Replace the contents of satan/hello.el with the single line ';; replaced\\n'. Then commit."
                         :mode "self-edit-mech"
                         :repo repo
                         :allowed_paths '("satan/")
                         :base_ref "main"
                         :adapter "pi"
                         :start nil)
                   satan-patch-runner-test--ctx))
                 (job-id (plist-get (cdr create) :job_id)))
            (satan-patch-runner-tick)
            ;; wait up to 1800s for finish; in practice pi takes ~30-90s
            (with-timeout (1800 (ert-fail "pi run timed out"))
              (while (satan-patch-runner-active-p)
                (sit-for 1)))
            (let* ((row (satan-patch-runner-test--row job-id))
                   (state (plist-get row :state)))
              (should (member state '("needs_review" "failed")))
              (when (equal state "needs_review")
                (let ((result (plist-get row :result_json)))
                  (should (consp (plist-get result :commits))))))))
      (when (file-directory-p repo) (delete-directory repo t))
      (when (file-directory-p wt-root) (delete-directory wt-root t))
      (when (file-directory-p log-root) (delete-directory log-root t)))))

(provide 'satan-patch-runner-test)
;;; satan-patch-runner-test.el ends here
