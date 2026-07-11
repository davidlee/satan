;;; dl-satan-patch-store-test.el --- patch-store ert -*- lexical-binding: t; -*-

;; Tests for `dl-satan-patch-store'.  Pure helpers exercised directly;
;; DB-touching tests reset patch_jobs + patch_job_events and re-apply
;; migrations against `satan_memory_test'.  Each DB test
;; `skip-unless' the test DB is reachable.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-db)
(require 'dl-satan-patch-store)
(require 'dl-satan-memory-migrate)

(defconst dl-satan-patch-store-test--db "satan_memory_test")

(defun dl-satan-patch-store-test--reachable-p ()
  (pcase (dl-satan-db-psql
          dl-satan-patch-store-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
          (list "-A" "-t" "-c" "SELECT 1"))
    (`(ok . ,_) t)
    (_ nil)))

(defun dl-satan-patch-store-test--truncate ()
  (dl-satan-db-psql
   dl-satan-patch-store-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
   (list "-c" "TRUNCATE patch_job_events, patch_jobs RESTART IDENTITY CASCADE")))

(defmacro dl-satan-patch-store-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (dl-satan-patch-store-test--reachable-p))
     (dl-satan-patch-store-test--truncate)
     (let ((dl-satan-patch-store-database
            dl-satan-patch-store-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-store/job-id-format ()
  (let ((id (dl-satan-patch-store-job-id-new
             "2026-05-20T19:01:22+10:00"
             (lambda () "a13f"))))
    (should (equal id "patch_20260520T190122_a13f"))))

(ert-deftest dl-satan-patch-store/job-id-random-suffix ()
  (let ((id (dl-satan-patch-store-job-id-new
             "2026-05-20T19:01:22+10:00")))
    (should (string-match-p
             "\\`patch_[0-9]\\{8\\}T[0-9]\\{6\\}_[a-z0-9]\\{4\\}\\'"
             id))))

(ert-deftest dl-satan-patch-store/prep-value-plist ()
  ;; dl-satan-jsonl-prepare passes nil through; json-serialize maps it
  ;; to JSON null by default (same end result as the old --prep-value).
  (should (equal (dl-satan-jsonl-prepare
                  (list :a 1 :b "two" :c nil))
                 (list :a 1 :b "two" :c nil))))

(ert-deftest dl-satan-patch-store/prep-value-nested-list ()
  (let ((out (dl-satan-jsonl-prepare
              (list :handles (list (list :handle "a")
                                   (list :handle "b"))))))
    (should (equal (plist-get out :handles)
                   (vector (list :handle "a") (list :handle "b"))))))

;; ---------------------------------------------------------------------
;; insert + get
;; ---------------------------------------------------------------------

(defun dl-satan-patch-store-test--basic-spec (&optional overrides)
  (append overrides
          (list :job-id "patch_20260520T190122_test"
                :mode "self-edit-mech"
                :directive "Add memory canonicalizer tests."
                :repo "/home/david/.emacs.d"
                :base_ref "main"
                :branch "satan/self-edit-mech/20260520T190122-test"
                :worktree_path "/tmp/satan/patch/wt-test"
                :allowed_paths '("satan/" "test/")
                :checks '("emacs --batch ert")
                :source (list :kind "at_satan_directive"
                              :file "/home/david/notes/x.org"
                              :line 42)
                :context (list :note_context "ctx"))))

(ert-deftest dl-satan-patch-store/insert-roundtrip ()
  (dl-satan-patch-store-test--with-db
   (pcase (apply #'dl-satan-patch-store-insert
                 (dl-satan-patch-store-test--basic-spec))
     (`(ok . ,id) (should (equal id "patch_20260520T190122_test")))
     (err (ert-fail (format "insert: %S" err))))
   (pcase (dl-satan-patch-store-get "patch_20260520T190122_test")
     (`(ok . ,row)
      (should row)
      (should (equal (plist-get row :id) "patch_20260520T190122_test"))
      (should (equal (plist-get row :state) "queued"))
      (should (equal (plist-get row :mode) "self-edit-mech"))
      (should (equal (plist-get row :branch)
                     "satan/self-edit-mech/20260520T190122-test"))
      (should (equal (plist-get row :allowed_paths_json)
                     '("satan/" "test/")))
      (should (equal (plist-get row :checks_json)
                     '("emacs --batch ert")))
      (should (equal (plist-get (plist-get row :source_json) :kind)
                     "at_satan_directive"))
      (should (equal (plist-get row :result_json) nil)))
     (other (ert-fail (format "get: %S" other))))))

(ert-deftest dl-satan-patch-store/get-missing ()
  (dl-satan-patch-store-test--with-db
   (pcase (dl-satan-patch-store-get "patch_does_not_exist")
     (`(ok . nil) t)
     (other (ert-fail (format "expected ok+nil, got %S" other))))))

(ert-deftest dl-satan-patch-store/insert-requires-mode ()
  (should-error
   (dl-satan-patch-store-insert
    :directive "x" :repo "/r" :base_ref "main"
    :branch "b" :worktree_path "/wt" :allowed_paths '("/"))))

;; ---------------------------------------------------------------------
;; list
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-store/list-by-state ()
  (dl-satan-patch-store-test--with-db
   (dl-satan-patch-store-insert
    :job-id "patch_a" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b1" :worktree_path "/wt/a"
    :allowed_paths '("/"))
   (dl-satan-patch-store-insert
    :job-id "patch_b" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b2" :worktree_path "/wt/b"
    :allowed_paths '("/") :state "failed")
   (pcase (dl-satan-patch-store-list :state "queued")
     (`(ok . ,rows)
      (should (= 1 (length rows)))
      (should (equal (plist-get (car rows) :id) "patch_a")))
     (err (ert-fail (format "list queued: %S" err))))
   (pcase (dl-satan-patch-store-list)
     (`(ok . ,rows) (should (= 2 (length rows))))
     (err (ert-fail (format "list all: %S" err))))))

;; ---------------------------------------------------------------------
;; update-state
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-store/update-state-with-result ()
  (dl-satan-patch-store-test--with-db
   (apply #'dl-satan-patch-store-insert
          (dl-satan-patch-store-test--basic-spec))
   (pcase (dl-satan-patch-store-update-state
           "patch_20260520T190122_test"
           "needs_review"
           :finished_at "2026-05-20T20:00:00+00:00"
           :result (list :summary "did the thing"
                         :commits (list (list :sha "abc1234"
                                              :subject "x"))))
     (`(ok . ,_) t)
     (err (ert-fail (format "update: %S" err))))
   (pcase (dl-satan-patch-store-get "patch_20260520T190122_test")
     (`(ok . ,row)
      (should (equal (plist-get row :state) "needs_review"))
      (should (equal (plist-get (plist-get row :result_json) :summary)
                     "did the thing"))
      (should (plist-get row :finished_at)))
     (err (ert-fail (format "post-update get: %S" err))))))

(ert-deftest dl-satan-patch-store/update-state-rejects-bad-state ()
  (dl-satan-patch-store-test--with-db
   (apply #'dl-satan-patch-store-insert
          (dl-satan-patch-store-test--basic-spec))
   (pcase (dl-satan-patch-store-update-state
           "patch_20260520T190122_test" "bogus")
     (`(error . ,_) t)
     (other (ert-fail (format "expected error, got %S" other))))))

;; ---------------------------------------------------------------------
;; claim-next
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-patch-store/claim-next-empty ()
  (dl-satan-patch-store-test--with-db
   (pcase (dl-satan-patch-store-claim-next)
     (`(ok . nil) t)
     (other (ert-fail (format "expected ok+nil, got %S" other))))))

(ert-deftest dl-satan-patch-store/claim-next-fifo ()
  (dl-satan-patch-store-test--with-db
   (dl-satan-patch-store-insert
    :job-id "patch_first" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b1" :worktree_path "/wt/1"
    :allowed_paths '("/"))
   ;; small sleep so created_at differs even at sub-second granularity
   (sleep-for 0 50)
   (dl-satan-patch-store-insert
    :job-id "patch_second" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b2" :worktree_path "/wt/2"
    :allowed_paths '("/"))
   (pcase (dl-satan-patch-store-claim-next)
     (`(ok . ,row)
      (should (equal (plist-get row :id) "patch_first"))
      (should (equal (plist-get row :state) "claimed"))
      (should (plist-get row :started_at)))
     (other (ert-fail (format "claim 1: %S" other))))
   (pcase (dl-satan-patch-store-claim-next)
     (`(ok . ,row)
      (should (equal (plist-get row :id) "patch_second")))
     (other (ert-fail (format "claim 2: %S" other))))
   (pcase (dl-satan-patch-store-claim-next)
     (`(ok . nil) t)
     (other (ert-fail (format "claim 3 expected empty, got %S" other))))))

;; ---------------------------------------------------------------------
;; event log
;; ---------------------------------------------------------------------

;; ---------------------------------------------------------------------
;; NOTIFY on insert (queued rows wake satan-patcher daemon LISTEN)
;; ---------------------------------------------------------------------

(defun dl-satan-patch-store-test--listen (channel sleep-sec)
  "Start a backgrounded psql session that LISTENs on CHANNEL for SLEEP-SEC.
Returns (PROC . BUFFER).  stdin is /dev/null so psql does not block on EOF."
  (let* ((buf (generate-new-buffer
               (format "*satan-patch-listen-%s*" channel)))
         (cmd (format "exec %s -h %s -d %s --no-psqlrc -X -c %s -c %s < /dev/null"
                      (shell-quote-argument dl-satan-patch-store-psql-program)
                      (shell-quote-argument (dl-satan-db-resolve-host dl-satan-patch-store-host))
                      (shell-quote-argument dl-satan-patch-store-test--db)
                      (shell-quote-argument
                       (format "LISTEN %s;" channel))
                      (shell-quote-argument
                       (format "SELECT pg_sleep(%s);" sleep-sec))))
         (proc (make-process
                :name "satan-patch-listen"
                :buffer buf
                :stderr buf
                :noquery t
                :command (list shell-file-name "-c" cmd))))
    (cons proc buf)))

(defun dl-satan-patch-store-test--drain (proc buf timeout)
  (with-timeout (timeout nil)
    (while (process-live-p proc) (sit-for 0.05)))
  (with-current-buffer buf (buffer-string)))

(ert-deftest dl-satan-patch-store/insert-fires-notify ()
  (dl-satan-patch-store-test--with-db
   (skip-unless (executable-find "psql"))
   (pcase-let ((`(,proc . ,buf)
                (dl-satan-patch-store-test--listen "patch_jobs_new" 1.5)))
     (unwind-protect
         (progn
           (sleep-for 0.3)
           (apply #'dl-satan-patch-store-insert
                  (dl-satan-patch-store-test--basic-spec))
           (let ((out (dl-satan-patch-store-test--drain proc buf 4)))
             (should (string-match-p
                      "Asynchronous notification.*patch_jobs_new" out))
             (should (string-match-p "patch_20260520T190122_test" out))))
       (when (process-live-p proc) (kill-process proc))
       (kill-buffer buf)))))

(ert-deftest dl-satan-patch-store/insert-non-queued-does-not-notify ()
  ;; Non-queued inserts (e.g. seeded history rows) must not wake the runner.
  (dl-satan-patch-store-test--with-db
   (skip-unless (executable-find "psql"))
   (pcase-let ((`(,proc . ,buf)
                (dl-satan-patch-store-test--listen "patch_jobs_new" 1.2)))
     (unwind-protect
         (progn
           (sleep-for 0.3)
           (dl-satan-patch-store-insert
            :job-id "patch_seeded" :mode "m" :directive "d"
            :repo "/r" :base_ref "main" :branch "b" :worktree_path "/wt/s"
            :allowed_paths '("/") :state "failed")
           (let ((out (dl-satan-patch-store-test--drain proc buf 3)))
             (should-not (string-match-p
                          "Asynchronous notification" out))))
       (when (process-live-p proc) (kill-process proc))
       (kill-buffer buf)))))

(ert-deftest dl-satan-patch-store/events-roundtrip ()
  (dl-satan-patch-store-test--with-db
   (apply #'dl-satan-patch-store-insert
          (dl-satan-patch-store-test--basic-spec))
   (dl-satan-patch-store-event
    "patch_20260520T190122_test" "transition"
    (list :from "queued" :to "claimed"))
   (dl-satan-patch-store-event
    "patch_20260520T190122_test" "log"
    (list :line "harness started"))
   (pcase (dl-satan-patch-store-events "patch_20260520T190122_test")
     (`(ok . ,events)
      (should (= 2 (length events)))
      (should (equal (plist-get (car events) :kind) "transition"))
      (should (equal (plist-get (plist-get (car events) :payload) :to)
                     "claimed"))
      (should (equal (plist-get (cadr events) :kind) "log")))
     (err (ert-fail (format "events: %S" err))))))

(provide 'dl-satan-patch-store-test)
;;; dl-satan-patch-store-test.el ends here
