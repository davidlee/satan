;;; satan-patch-store-test.el --- patch-store ert -*- lexical-binding: t; -*-

;; Tests for `satan-patch-store'.  Pure helpers exercised directly;
;; DB-touching tests reset patch_jobs + patch_job_events and re-apply
;; migrations against `satan_memory_test'.  Each DB test
;; `skip-unless' the test DB is reachable.

(require 'ert)
(require 'cl-lib)
(require 'satan-db)
(require 'satan-patch-store)
(require 'satan-memory-migrate)

(defconst satan-patch-store-test--db "satan_memory_test")

(defun satan-patch-store-test--reachable-p ()
  (pcase (satan-db-psql
          satan-patch-store-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
          (list "-A" "-t" "-c" "SELECT 1"))
    (`(ok . ,_) t)
    (_ nil)))

(defun satan-patch-store-test--truncate ()
  (satan-db-psql
   satan-patch-store-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
   (list "-c" "TRUNCATE patch_job_events, patch_jobs RESTART IDENTITY CASCADE")))

(defmacro satan-patch-store-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (satan-patch-store-test--reachable-p))
     (satan-patch-store-test--truncate)
     (let ((satan-patch-store-database
            satan-patch-store-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-store/job-id-format ()
  (let ((id (satan-patch-store-job-id-new
             "2026-05-20T19:01:22+10:00"
             (lambda () "a13f"))))
    (should (equal id "patch_20260520T190122_a13f"))))

(ert-deftest satan-patch-store/job-id-random-suffix ()
  (let ((id (satan-patch-store-job-id-new
             "2026-05-20T19:01:22+10:00")))
    (should (string-match-p
             "\\`patch_[0-9]\\{8\\}T[0-9]\\{6\\}_[a-z0-9]\\{4\\}\\'"
             id))))

(ert-deftest satan-patch-store/prep-value-plist ()
  ;; satan-jsonl-prepare passes nil through; json-serialize maps it
  ;; to JSON null by default (same end result as the old --prep-value).
  (should (equal (satan-jsonl-prepare
                  (list :a 1 :b "two" :c nil))
                 (list :a 1 :b "two" :c nil))))

(ert-deftest satan-patch-store/prep-value-nested-list ()
  (let ((out (satan-jsonl-prepare
              (list :handles (list (list :handle "a")
                                   (list :handle "b"))))))
    (should (equal (plist-get out :handles)
                   (vector (list :handle "a") (list :handle "b"))))))

;; ---------------------------------------------------------------------
;; insert + get
;; ---------------------------------------------------------------------

(defun satan-patch-store-test--basic-spec (&optional overrides)
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

(ert-deftest satan-patch-store/insert-roundtrip ()
  (satan-patch-store-test--with-db
   (pcase (apply #'satan-patch-store-insert
                 (satan-patch-store-test--basic-spec))
     (`(ok . ,id) (should (equal id "patch_20260520T190122_test")))
     (err (ert-fail (format "insert: %S" err))))
   (pcase (satan-patch-store-get "patch_20260520T190122_test")
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

(ert-deftest satan-patch-store/get-missing ()
  (satan-patch-store-test--with-db
   (pcase (satan-patch-store-get "patch_does_not_exist")
     (`(ok . nil) t)
     (other (ert-fail (format "expected ok+nil, got %S" other))))))

(ert-deftest satan-patch-store/insert-requires-mode ()
  (should-error
   (satan-patch-store-insert
    :directive "x" :repo "/r" :base_ref "main"
    :branch "b" :worktree_path "/wt" :allowed_paths '("/"))))

;; ---------------------------------------------------------------------
;; list
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-store/list-by-state ()
  (satan-patch-store-test--with-db
   (satan-patch-store-insert
    :job-id "patch_a" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b1" :worktree_path "/wt/a"
    :allowed_paths '("/"))
   (satan-patch-store-insert
    :job-id "patch_b" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b2" :worktree_path "/wt/b"
    :allowed_paths '("/") :state "failed")
   (pcase (satan-patch-store-list :state "queued")
     (`(ok . ,rows)
      (should (= 1 (length rows)))
      (should (equal (plist-get (car rows) :id) "patch_a")))
     (err (ert-fail (format "list queued: %S" err))))
   (pcase (satan-patch-store-list)
     (`(ok . ,rows) (should (= 2 (length rows))))
     (err (ert-fail (format "list all: %S" err))))))

;; ---------------------------------------------------------------------
;; update-state
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-store/update-state-with-result ()
  (satan-patch-store-test--with-db
   (apply #'satan-patch-store-insert
          (satan-patch-store-test--basic-spec))
   (pcase (satan-patch-store-update-state
           "patch_20260520T190122_test"
           "needs_review"
           :finished_at "2026-05-20T20:00:00+00:00"
           :result (list :summary "did the thing"
                         :commits (list (list :sha "abc1234"
                                              :subject "x"))))
     (`(ok . ,_) t)
     (err (ert-fail (format "update: %S" err))))
   (pcase (satan-patch-store-get "patch_20260520T190122_test")
     (`(ok . ,row)
      (should (equal (plist-get row :state) "needs_review"))
      (should (equal (plist-get (plist-get row :result_json) :summary)
                     "did the thing"))
      (should (plist-get row :finished_at)))
     (err (ert-fail (format "post-update get: %S" err))))))

(ert-deftest satan-patch-store/update-state-rejects-bad-state ()
  (satan-patch-store-test--with-db
   (apply #'satan-patch-store-insert
          (satan-patch-store-test--basic-spec))
   (pcase (satan-patch-store-update-state
           "patch_20260520T190122_test" "bogus")
     (`(error . ,_) t)
     (other (ert-fail (format "expected error, got %S" other))))))

;; ---------------------------------------------------------------------
;; claim-next
;; ---------------------------------------------------------------------

(ert-deftest satan-patch-store/claim-next-empty ()
  (satan-patch-store-test--with-db
   (pcase (satan-patch-store-claim-next)
     (`(ok . nil) t)
     (other (ert-fail (format "expected ok+nil, got %S" other))))))

(ert-deftest satan-patch-store/claim-next-fifo ()
  (satan-patch-store-test--with-db
   (satan-patch-store-insert
    :job-id "patch_first" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b1" :worktree_path "/wt/1"
    :allowed_paths '("/"))
   ;; small sleep so created_at differs even at sub-second granularity
   (sleep-for 0 50)
   (satan-patch-store-insert
    :job-id "patch_second" :mode "m" :directive "d"
    :repo "/r" :base_ref "main" :branch "b2" :worktree_path "/wt/2"
    :allowed_paths '("/"))
   (pcase (satan-patch-store-claim-next)
     (`(ok . ,row)
      (should (equal (plist-get row :id) "patch_first"))
      (should (equal (plist-get row :state) "claimed"))
      (should (plist-get row :started_at)))
     (other (ert-fail (format "claim 1: %S" other))))
   (pcase (satan-patch-store-claim-next)
     (`(ok . ,row)
      (should (equal (plist-get row :id) "patch_second")))
     (other (ert-fail (format "claim 2: %S" other))))
   (pcase (satan-patch-store-claim-next)
     (`(ok . nil) t)
     (other (ert-fail (format "claim 3 expected empty, got %S" other))))))

;; ---------------------------------------------------------------------
;; event log
;; ---------------------------------------------------------------------

;; ---------------------------------------------------------------------
;; NOTIFY on insert (queued rows wake satan-patcher daemon LISTEN)
;; ---------------------------------------------------------------------

(defun satan-patch-store-test--listen (channel sleep-sec)
  "Start a backgrounded psql session that LISTENs on CHANNEL for SLEEP-SEC.
Returns (PROC . BUFFER).  stdin is /dev/null so psql does not block on EOF."
  (let* ((buf (generate-new-buffer
               (format "*satan-patch-listen-%s*" channel)))
         (cmd (format "exec %s -h %s -d %s --no-psqlrc -X -c %s -c %s < /dev/null"
                      (shell-quote-argument satan-patch-store-psql-program)
                      (shell-quote-argument (satan-db-resolve-host satan-patch-store-host))
                      (shell-quote-argument satan-patch-store-test--db)
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

(defun satan-patch-store-test--drain (proc buf timeout)
  (with-timeout (timeout nil)
    (while (process-live-p proc) (sit-for 0.05)))
  (with-current-buffer buf (buffer-string)))

(ert-deftest satan-patch-store/insert-fires-notify ()
  (satan-patch-store-test--with-db
   (skip-unless (executable-find "psql"))
   (pcase-let ((`(,proc . ,buf)
                (satan-patch-store-test--listen "patch_jobs_new" 1.5)))
     (unwind-protect
         (progn
           (sleep-for 0.3)
           (apply #'satan-patch-store-insert
                  (satan-patch-store-test--basic-spec))
           (let ((out (satan-patch-store-test--drain proc buf 4)))
             (should (string-match-p
                      "Asynchronous notification.*patch_jobs_new" out))
             (should (string-match-p "patch_20260520T190122_test" out))))
       (when (process-live-p proc) (kill-process proc))
       (kill-buffer buf)))))

(ert-deftest satan-patch-store/insert-non-queued-does-not-notify ()
  ;; Non-queued inserts (e.g. seeded history rows) must not wake the runner.
  (satan-patch-store-test--with-db
   (skip-unless (executable-find "psql"))
   (pcase-let ((`(,proc . ,buf)
                (satan-patch-store-test--listen "patch_jobs_new" 1.2)))
     (unwind-protect
         (progn
           (sleep-for 0.3)
           (satan-patch-store-insert
            :job-id "patch_seeded" :mode "m" :directive "d"
            :repo "/r" :base_ref "main" :branch "b" :worktree_path "/wt/s"
            :allowed_paths '("/") :state "failed")
           (let ((out (satan-patch-store-test--drain proc buf 3)))
             (should-not (string-match-p
                          "Asynchronous notification" out))))
       (when (process-live-p proc) (kill-process proc))
       (kill-buffer buf)))))

(ert-deftest satan-patch-store/events-roundtrip ()
  (satan-patch-store-test--with-db
   (apply #'satan-patch-store-insert
          (satan-patch-store-test--basic-spec))
   (satan-patch-store-event
    "patch_20260520T190122_test" "transition"
    (list :from "queued" :to "claimed"))
   (satan-patch-store-event
    "patch_20260520T190122_test" "log"
    (list :line "harness started"))
   (pcase (satan-patch-store-events "patch_20260520T190122_test")
     (`(ok . ,events)
      (should (= 2 (length events)))
      (should (equal (plist-get (car events) :kind) "transition"))
      (should (equal (plist-get (plist-get (car events) :payload) :to)
                     "claimed"))
      (should (equal (plist-get (cadr events) :kind) "log")))
     (err (ert-fail (format "events: %S" err))))))

(provide 'satan-patch-store-test)
;;; satan-patch-store-test.el ends here
