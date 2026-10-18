;;; satan-memory-migrate-test.el --- migrate runner tests -*- lexical-binding: t; -*-

;; Run from CLI, at the repo root:
;;   emacs --batch \
;;     -L satan -L dev -L satan/test \
;;     -l satan-memory-migrate-test.el -f ert-run-tests-batch-and-exit
;;
;; Requires a writable `satan_memory_test' PG database accessible via
;; the socket at `satan-memory-migrate-host'.

(require 'ert)
(require 'cl-lib)
(require 'satan-db)
(require 'satan-memory-migrate)

(defconst satan-memory-migrate-test--db "satan_memory_test")

(defun satan-memory-migrate-test--db-available-p ()
  "Non-nil when the migrate test DB is reachable (delegates to the shared predicate)."
  (satan-db-test-db-available-p satan-memory-migrate-test--db))

(defun satan-memory-migrate-test--reset-db ()
  "Drop every table in the test DB.  Best-effort, idempotent."
  (let ((satan-memory-migrate-database satan-memory-migrate-test--db))
    (satan-db-psql
     satan-memory-migrate-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
     (list "-c"
           (concat "DROP TABLE IF EXISTS "
                   "satan_pattern_outcomes, satan_patterns, "
                   "satan_intervention_outcomes, satan_interventions, "
                   "patch_job_events, patch_jobs, "
                   "trace_links, trace_handles, traces, "
                   "handle_aliases, handle_weights, grammar_versions, "
                   "schema_migrations CASCADE;")))))

(defun satan-memory-migrate-test--with-tempdir (fn)
  "Call FN with a fresh temp migrations directory bound."
  (let* ((tmp (make-temp-file "satan-migrate-test-" t))
         (satan-memory-migrate-directory tmp)
         (satan-memory-migrate-database  satan-memory-migrate-test--db))
    (unwind-protect
        (progn (satan-memory-migrate-test--reset-db)
               (funcall fn tmp))
      (delete-directory tmp t))))

(defun satan-memory-migrate-test--write (dir name contents)
  (let ((p (expand-file-name name dir)))
    (with-temp-file p (insert contents))
    p))

;; ---------- filename parsing ----------

(ert-deftest satan-memory-migrate/parse-ok ()
  (should (= 1 (satan-memory-migrate--parse-filename "0001_init.sql")))
  (should (= 42 (satan-memory-migrate--parse-filename "0042_add_foo.sql"))))

(ert-deftest satan-memory-migrate/parse-rejects-bad-form ()
  (dolist (bad '("init.sql" "1_x.sql" "0001-init.sql" "0001_INIT.sql"
                 "0001_init.SQL" "0001_init"))
    (should-error (satan-memory-migrate--parse-filename bad)
                  :type 'user-error)))

;; ---------- list-files ----------

(ert-deftest satan-memory-migrate/list-detects-duplicate-version ()
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (satan-memory-migrate-test--write dir "0001_a.sql" "SELECT 1;")
     (satan-memory-migrate-test--write dir "0001_b.sql" "SELECT 2;")
     (should-error (satan-memory-migrate--list-files)
                   :type 'user-error))))

(ert-deftest satan-memory-migrate/list-sorts-ascending ()
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (satan-memory-migrate-test--write dir "0003_c.sql" "SELECT 3;")
     (satan-memory-migrate-test--write dir "0001_a.sql" "SELECT 1;")
     (satan-memory-migrate-test--write dir "0002_b.sql" "SELECT 2;")
     (let ((rows (satan-memory-migrate--list-files)))
       (should (equal '(1 2 3) (mapcar (lambda (r) (plist-get r :version)) rows)))))))

;; ---------- end-to-end against the real migrations ----------

(ert-deftest satan-memory-migrate/applies-real-migrations ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--reset-db)
  (let ((satan-memory-migrate-database satan-memory-migrate-test--db))
    (let ((applied (satan-memory-migrate-apply)))
      (should (equal (quote (1 2 3 4 5 6 7 8 9)) applied)))
    (let ((status (satan-memory-migrate-status)))
      (should (cl-every (lambda (e) (eq 'applied (plist-get e :status)))
                        status))
      (should (= 9 (length status))))))

(ert-deftest satan-memory-migrate/re-apply-is-noop ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--reset-db)
  (let ((satan-memory-migrate-database satan-memory-migrate-test--db))
    (satan-memory-migrate-apply)
    (should (null (satan-memory-migrate-apply)))))

;; ---------- tampering detection ----------

(ert-deftest satan-memory-migrate/refuses-tampered-file ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (let ((p (satan-memory-migrate-test--write
               dir "0001_seed.sql"
               "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")))
       (should (equal '(1) (satan-memory-migrate-apply)))
       ;; tamper
       (with-temp-file p
         (insert "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL); -- changed"))
       (let ((status (satan-memory-migrate-status)))
         (should (eq 'tampered (plist-get (car status) :status))))
       (should-error (satan-memory-migrate-apply) :type 'user-error)))))

;; ---------- version-skip refusal ----------

(ert-deftest satan-memory-migrate/refuses-version-skip ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (satan-memory-migrate-test--write
      dir "0001_seed.sql"
      "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")
     (satan-memory-migrate-test--write
      dir "0003_skip.sql"
      "CREATE TABLE skip_marker ();")
     (should-error (satan-memory-migrate-apply) :type 'user-error))))

;; ---------- missing recorded file ----------

(ert-deftest satan-memory-migrate/refuses-missing-recorded-file ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (let ((p (satan-memory-migrate-test--write
               dir "0001_seed.sql"
               "CREATE TABLE schema_migrations (version INTEGER PRIMARY KEY, filename TEXT NOT NULL, applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), checksum TEXT NOT NULL);")))
       (satan-memory-migrate-apply)
       (delete-file p)
       (let ((status (satan-memory-migrate-status)))
         (should (eq 'missing (plist-get (car status) :status))))
       (should-error (satan-memory-migrate-apply) :type 'user-error)))))

;; ---------- 0009: drop patch_jobs (SL-023 EX-5) ----------

(defconst satan-memory-migrate-test--real-dir satan-memory-migrate-directory
  "The package's real migrations directory, captured before any rebinding.")

(defun satan-memory-migrate-test--copy-real (dir upto)
  "Copy the real migrations 0001..UPTO into DIR."
  (dolist (row (satan-memory-migrate--list-files
                satan-memory-migrate-test--real-dir))
    (when (<= (plist-get row :version) upto)
      (copy-file (plist-get row :path)
                 (expand-file-name (plist-get row :filename) dir) t))))

(defun satan-memory-migrate-test--sql (sql)
  "Run SQL against the test DB; return (ok . OUT) or (error . MSG)."
  (satan-db-psql satan-memory-migrate-test--db satan-memory-migrate-host
                 satan-memory-migrate-psql-program
                 (list "-A" "-t" "-c" sql)))

(defun satan-memory-migrate-test--scalar (sql)
  "Trimmed single-value result of SQL; fails the test on a psql error."
  (let ((r (satan-memory-migrate-test--sql sql)))
    (should (eq 'ok (car r)))
    (string-trim (cdr r))))

(defun satan-memory-migrate-test--insert-patch-job (state)
  "Insert one minimal patch_jobs row in STATE (columns per 0005)."
  (satan-memory-migrate-test--sql
   (format "INSERT INTO patch_jobs (id, state, mode, directive, repo, base_ref, branch, worktree_path, allowed_paths_json) VALUES ('pj-test', '%s', 'fix', 'd', 'r', 'HEAD', 'b', '/w', '[]');"
           state)))

(defun satan-memory-migrate-test--table-exists-p (name)
  (equal "t" (satan-memory-migrate-test--scalar
              (format "SELECT to_regclass('%s') IS NOT NULL;" name))))

(ert-deftest satan-memory-migrate/0009-refuses-while-a-job-is-non-terminal ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (satan-memory-migrate-test--copy-real dir 8)
     (should (equal '(1 2 3 4 5 6 7 8) (satan-memory-migrate-apply)))
     (should (eq 'ok (car (satan-memory-migrate-test--insert-patch-job "running"))))
     (satan-memory-migrate-test--copy-real dir 9)
     (should-error (satan-memory-migrate-apply) :type 'user-error)
     ;; Refusal is atomic: tables stay, version 9 is not recorded.
     (should (satan-memory-migrate-test--table-exists-p "patch_jobs"))
     (should (satan-memory-migrate-test--table-exists-p "patch_job_events"))
     (should (equal "8" (satan-memory-migrate-test--scalar
                         "SELECT max(version) FROM schema_migrations;"))))))

(ert-deftest satan-memory-migrate/0009-drops-tables-when-all-jobs-are-terminal ()
  (skip-unless (satan-memory-migrate-test--db-available-p))
  (satan-memory-migrate-test--with-tempdir
   (lambda (dir)
     (satan-memory-migrate-test--copy-real dir 8)
     (satan-memory-migrate-apply)
     (should (eq 'ok (car (satan-memory-migrate-test--insert-patch-job "failed"))))
     (satan-memory-migrate-test--copy-real dir 9)
     (should (equal '(9) (satan-memory-migrate-apply)))
     (should-not (satan-memory-migrate-test--table-exists-p "patch_jobs"))
     (should-not (satan-memory-migrate-test--table-exists-p "patch_job_events"))
     (should (equal "0" (satan-memory-migrate-test--scalar
                         "SELECT count(*) FROM pg_proc WHERE proname = 'patch_jobs_set_updated_at';"))))))

(provide 'satan-memory-migrate-test)
;;; satan-memory-migrate-test.el ends here
