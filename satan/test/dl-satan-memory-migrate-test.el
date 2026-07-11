;;; dl-satan-memory-migrate-test.el --- migrate runner tests -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-memory-migrate-test.el -f ert-run-tests-batch-and-exit
;;
;; Requires a writable `satan_memory_test' PG database accessible via
;; the socket at `dl-satan-memory-migrate-host'.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-db)
(require 'dl-satan-memory-migrate)

(defconst dl-satan-memory-migrate-test--db "satan_memory_test")

(defun dl-satan-memory-migrate-test--db-available-p ()
  "Non-nil when the migrate test DB is reachable (delegates to the shared predicate)."
  (dl-satan-db-test-db-available-p dl-satan-memory-migrate-test--db))

(defun dl-satan-memory-migrate-test--reset-db ()
  "Drop every table in the test DB.  Best-effort, idempotent."
  (let ((dl-satan-memory-migrate-database dl-satan-memory-migrate-test--db))
    (dl-satan-db-psql
     dl-satan-memory-migrate-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
     (list "-c"
           (concat "DROP TABLE IF EXISTS "
                   "satan_pattern_outcomes, satan_patterns, "
                   "satan_intervention_outcomes, satan_interventions, "
                   "patch_job_events, patch_jobs, "
                   "trace_links, trace_handles, traces, "
                   "handle_aliases, handle_weights, grammar_versions, "
                   "schema_migrations CASCADE;")))))

(defun dl-satan-memory-migrate-test--with-tempdir (fn)
  "Call FN with a fresh temp migrations directory bound."
  (let* ((tmp (make-temp-file "satan-migrate-test-" t))
         (dl-satan-memory-migrate-directory tmp)
         (dl-satan-memory-migrate-database  dl-satan-memory-migrate-test--db))
    (unwind-protect
        (progn (dl-satan-memory-migrate-test--reset-db)
               (funcall fn tmp))
      (delete-directory tmp t))))

(defun dl-satan-memory-migrate-test--write (dir name contents)
  (let ((p (expand-file-name name dir)))
    (with-temp-file p (insert contents))
    p))

;; ---------- filename parsing ----------

(ert-deftest dl-satan-memory-migrate/parse-ok ()
  (should (= 1 (dl-satan-memory-migrate--parse-filename "0001_init.sql")))
  (should (= 42 (dl-satan-memory-migrate--parse-filename "0042_add_foo.sql"))))

(ert-deftest dl-satan-memory-migrate/parse-rejects-bad-form ()
  (dolist (bad '("init.sql" "1_x.sql" "0001-init.sql" "0001_INIT.sql"
                 "0001_init.SQL" "0001_init"))
    (should-error (dl-satan-memory-migrate--parse-filename bad)
                  :type 'user-error)))

;; ---------- list-files ----------

(ert-deftest dl-satan-memory-migrate/list-detects-duplicate-version ()
  (dl-satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (dl-satan-memory-migrate-test--write dir "0001_a.sql" "SELECT 1;")
     (dl-satan-memory-migrate-test--write dir "0001_b.sql" "SELECT 2;")
     (should-error (dl-satan-memory-migrate--list-files)
                   :type 'user-error))))

(ert-deftest dl-satan-memory-migrate/list-sorts-ascending ()
  (dl-satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (dl-satan-memory-migrate-test--write dir "0003_c.sql" "SELECT 3;")
     (dl-satan-memory-migrate-test--write dir "0001_a.sql" "SELECT 1;")
     (dl-satan-memory-migrate-test--write dir "0002_b.sql" "SELECT 2;")
     (let ((rows (dl-satan-memory-migrate--list-files)))
       (should (equal '(1 2 3) (mapcar (lambda (r) (plist-get r :version)) rows)))))))

;; ---------- end-to-end against the real migrations ----------

(ert-deftest dl-satan-memory-migrate/applies-real-migrations ()
  (skip-unless (dl-satan-memory-migrate-test--db-available-p))
  (dl-satan-memory-migrate-test--reset-db)
  (let ((dl-satan-memory-migrate-database dl-satan-memory-migrate-test--db))
    (let ((applied (dl-satan-memory-migrate-apply)))
      (should (equal '(1 2 3 4 5 6 7) applied)))
    (let ((status (dl-satan-memory-migrate-status)))
      (should (cl-every (lambda (e) (eq 'applied (plist-get e :status)))
                        status))
      (should (= 7 (length status))))))

(ert-deftest dl-satan-memory-migrate/re-apply-is-noop ()
  (skip-unless (dl-satan-memory-migrate-test--db-available-p))
  (dl-satan-memory-migrate-test--reset-db)
  (let ((dl-satan-memory-migrate-database dl-satan-memory-migrate-test--db))
    (dl-satan-memory-migrate-apply)
    (should (null (dl-satan-memory-migrate-apply)))))

;; ---------- tampering detection ----------

(ert-deftest dl-satan-memory-migrate/refuses-tampered-file ()
  (skip-unless (dl-satan-memory-migrate-test--db-available-p))
  (dl-satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (let ((p (dl-satan-memory-migrate-test--write
               dir "0001_seed.sql"
               "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")))
       (should (equal '(1) (dl-satan-memory-migrate-apply)))
       ;; tamper
       (with-temp-file p
         (insert "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL); -- changed"))
       (let ((status (dl-satan-memory-migrate-status)))
         (should (eq 'tampered (plist-get (car status) :status))))
       (should-error (dl-satan-memory-migrate-apply) :type 'user-error)))))

;; ---------- version-skip refusal ----------

(ert-deftest dl-satan-memory-migrate/refuses-version-skip ()
  (skip-unless (dl-satan-memory-migrate-test--db-available-p))
  (dl-satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (dl-satan-memory-migrate-test--write
      dir "0001_seed.sql"
      "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")
     (dl-satan-memory-migrate-test--write
      dir "0003_skip.sql"
      "CREATE TABLE skip_marker ();")
     (should-error (dl-satan-memory-migrate-apply) :type 'user-error))))

;; ---------- missing recorded file ----------

(ert-deftest dl-satan-memory-migrate/refuses-missing-recorded-file ()
  (skip-unless (dl-satan-memory-migrate-test--db-available-p))
  (dl-satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (let ((p (dl-satan-memory-migrate-test--write
               dir "0001_seed.sql"
               "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")))
       (dl-satan-memory-migrate-apply)
       (delete-file p)
       (let ((status (dl-satan-memory-migrate-status)))
         (should (eq 'missing (plist-get (car status) :status))))
       (should-error (dl-satan-memory-migrate-apply) :type 'user-error)))))

(provide 'dl-satan-memory-migrate-test)
;;; dl-satan-memory-migrate-test.el ends here
