;;; satan-tools-hippocampus-test.el --- file-side + cross-ref tests -*- lexical-binding: t; -*-

;; File-side `satan-tool/hippocampus-write' tests (denote write,
;; capability gate, schema gate) plus the Step 12 cross-ref tests:
;; `hippocampus_write' emits an `auto_rule' observation trace
;; cross-referencing the org file path (§10.7).
;;
;; DB-touching tests skip-unless the `satan_memory_test' DB is
;; reachable; they reset and re-apply migrations 0001-0004.

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-hippocampus)
(require 'satan-memory-migrate)
(require 'satan-memory-store)

(defconst satan-tools-hippocampus-test--db "satan_memory_test")

(defun satan-tools-hippocampus-test--reachable-p ()
  (pcase (let ((satan-memory-migrate-database
                satan-tools-hippocampus-test--db))
           (satan-db-psql
            satan-tools-hippocampus-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun satan-tools-hippocampus-test--reset-and-migrate ()
  (let ((satan-memory-migrate-database
         satan-tools-hippocampus-test--db))
    (satan-db-psql
     satan-tools-hippocampus-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
     (list "-c"
           (concat
            "DROP TABLE IF EXISTS "
            "satan_pattern_outcomes, satan_patterns, "
            "satan_intervention_outcomes, satan_interventions, "
            "patch_job_events, patch_jobs, "
            "trace_links, trace_handles, traces, "
            "handle_aliases, handle_weights, grammar_versions, "
            "schema_migrations CASCADE; "
            "DROP FUNCTION IF EXISTS "
            "memory_mark_trace(jsonb), memory_show_trace(text), "
            "memory_resonate(text[], smallint, double precision, integer, text[]), "
            "handle_weight_for(text, smallint) CASCADE;")))
    (satan-memory-migrate-apply)))

(defmacro satan-tools-hippocampus-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (satan-tools-hippocampus-test--reachable-p))
     (satan-tools-hippocampus-test--reset-and-migrate)
     (let ((satan-memory-store-database
            satan-tools-hippocampus-test--db)
           (satan-memory-migrate-database
            satan-tools-hippocampus-test--db))
       ,@body)))

(defun satan-tools-hippocampus-test--trace-count ()
  (let ((result (satan-db-psql
                 satan-tools-hippocampus-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
                 (list "-A" "-t" "-c" "SELECT COUNT(*) FROM traces"))))
    (pcase result
      (`(ok . ,out) (string-to-number (string-trim out)))
      (_ -1))))

(defun satan-tools-hippocampus-test--all-trace-ids ()
  (let ((result (satan-db-psql
                 satan-tools-hippocampus-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
                 (list "-A" "-t" "-c"
                       "SELECT id FROM traces ORDER BY id"))))
    (pcase result
      (`(ok . ,out) (split-string (string-trim out) "\n" t))
      (_ nil))))

;; ---------------------------------------------------------------------
;; Cross-ref tests
;; ---------------------------------------------------------------------

(ert-deftest satan-tools-hippocampus/no-cross-ref-without-memory-write ()
  "Absent `memory-write' capability: org file is written but no trace
is emitted."
  (satan-tools-hippocampus-test--with-db
   (let* ((tmp (make-temp-file "satan-hippo-" t))
          (satan-hippocampus-dir tmp))
     (unwind-protect
         (let ((res (satan-tool/hippocampus-write
                     '(:title "no-cross-ref" :body "body")
                     '(:id "r-no-mw" :mode-name "morning"
                       :capabilities (hippocampus-write)))))
           (should (eq (car res) 'ok))
           (should (= 0 (satan-tools-hippocampus-test--trace-count))))
       (delete-directory tmp t)))))

(ert-deftest satan-tools-hippocampus/cross-ref-with-memory-write ()
  "`memory-write' present: org file is written and an `auto_rule'
trace is emitted carrying `:hippocampus_path' in metadata_json."
  (satan-tools-hippocampus-test--with-db
   (let* ((tmp (make-temp-file "satan-hippo-" t))
          (satan-hippocampus-dir tmp))
     (unwind-protect
         (let* ((res (satan-tool/hippocampus-write
                      '(:title "Avoid mocking the DB"
                        :body "User burned by mock/prod divergence.")
                      '(:id "r-mw" :mode-name "morning"
                        :capabilities (hippocampus-write memory-write))))
                (path (plist-get (cdr res) :path)))
           (should (eq (car res) 'ok))
           (should (= 1 (satan-tools-hippocampus-test--trace-count)))
           (let* ((tid (car (satan-tools-hippocampus-test--all-trace-ids)))
                  (show (satan-memory-store-show tid))
                  (trace (plist-get (cdr show) :trace))
                  (md (plist-get trace :metadata_json)))
             (should (eq (car show) 'ok))
             (should (equal (plist-get trace :trace_origin) "auto_rule"))
             (should (equal (plist-get trace :kind) "observation"))
             (should (string-prefix-p "hippocampus_write@"
                                      (plist-get trace :source)))
             (should (stringp (plist-get md :hippocampus_path)))
             (should (string-match-p "satan_hippocampus\\.org$"
                                     (plist-get md :hippocampus_path)))))
       (delete-directory tmp t)))))

(ert-deftest satan-tools-hippocampus/cross-ref-soft-fail-on-bad-db ()
  "When the substrate cannot reach a DB, the org write still
succeeds and the handler returns ok."
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (satan-memory-store-database "satan_memory_unreachable_dbz"))
    (unwind-protect
        (let ((res (satan-tool/hippocampus-write
                    '(:title "soft-fail" :body "still ok")
                    '(:id "r-fail" :mode-name "morning"
                      :capabilities (hippocampus-write memory-write)))))
          (should (eq (car res) 'ok))
          (should (file-exists-p (plist-get (cdr res) :path))))
      (delete-directory tmp t))))

;; ---------------------------------------------------------------------
;; hippocampus_list tests
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/list-empty-dir ()
  (let ((satan-hippocampus-dir (make-temp-file "satan-hippo-" t)))
    (unwind-protect
        (let ((res (satan-tool/hippocampus-list nil nil)))
          (should (eq (car res) 'ok))
          (should (eq (plist-get (cdr res) :count) 0))
          (should (null (plist-get (cdr res) :entries))))
      (delete-directory satan-hippocampus-dir t))))

(ert-deftest satan-hippocampus/list-nonexistent-dir ()
  (let ((satan-hippocampus-dir "/tmp/satan-hippo-nonexistent-xyz"))
    (let ((res (satan-tool/hippocampus-list nil nil)))
      (should (eq (car res) 'ok))
      (should (eq (plist-get (cdr res) :count) 0)))))

(ert-deftest satan-hippocampus/list-returns-entries ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name
                           "20260524T091500--user-prefers-terse__satan_hippocampus.org" tmp)
            (insert "#+title: user prefers terse\n\nbody"))
          (let* ((res (satan-tool/hippocampus-list nil nil))
                 (entries (plist-get (cdr res) :entries)))
            (should (eq (car res) 'ok))
            (should (= 1 (plist-get (cdr res) :count)))
            (should (equal (plist-get (car entries) :title)
                           "user prefers terse"))))
      (delete-directory tmp t))))

;; ---------------------------------------------------------------------
;; hippocampus_read tests
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/read-existing-file ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--test-entry__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (with-temp-file (expand-file-name fname tmp)
            (insert "#+title: test entry\n\nbody content"))
          (let ((res (satan-tool/hippocampus-read
                      (list :filename fname) nil)))
            (should (eq (car res) 'ok))
            (should (string-match-p "body content"
                                    (plist-get (cdr res) :body)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/read-rejects-traversal ()
  (let ((res (satan-tool/hippocampus-read
              '(:filename "../etc/passwd") nil)))
    (should (eq (car res) 'error))
    (should (string-match-p "plain basename" (cdr res)))))

(ert-deftest satan-hippocampus/read-rejects-path-separator ()
  (let ((res (satan-tool/hippocampus-read
              '(:filename "foo/bar.org") nil)))
    (should (eq (car res) 'error))
    (should (string-match-p "plain basename" (cdr res)))))

(ert-deftest satan-hippocampus/read-missing-file ()
  (let ((satan-hippocampus-dir (make-temp-file "satan-hippo-" t)))
    (unwind-protect
        (let ((res (satan-tool/hippocampus-read
                    '(:filename "nonexistent.org") nil)))
          (should (eq (car res) 'error))
          (should (string-match-p "not found" (cdr res))))
      (delete-directory satan-hippocampus-dir t))))

;; ---------------------------------------------------------------------
;; hippocampus_overwrite tests
;; ---------------------------------------------------------------------

(defun satan-tools-hippocampus-test--write-entry (dir filename body)
  "Write a minimal org hippocampus entry for testing."
  (with-temp-file (expand-file-name filename dir)
    (insert "#+title:      test\n")
    (insert "#+date:       [2026-05-24 Sat 09:15]\n")
    (insert "#+filetags:   :satan:hippocampus:\n")
    (insert "#+identifier: 20260524T091500\n\n")
    (insert ":PROPERTIES:\n:RUN_ID: r1\n:MODE: morning\n:END:\n\n")
    (insert body "\n")))

(ert-deftest satan-hippocampus/overwrite-replaces-body ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--test__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (satan-tools-hippocampus-test--write-entry tmp fname "old body")
          (let ((res (satan-tool/hippocampus-overwrite
                      (list :filename fname :body "new body")
                      '(:capabilities (hippocampus-write)))))
            (should (eq (car res) 'ok))
            (let ((text (with-temp-buffer
                          (insert-file-contents
                           (expand-file-name fname tmp))
                          (buffer-string))))
              (should (string-match-p "new body" text))
              (should-not (string-match-p "old body" text))
              (should (string-search "#+title:      test" text)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/overwrite-capability-required ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "hippocampus_overwrite"
                :args (:filename "x.org" :body "b"))
              '("hippocampus_overwrite")
              '(:capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "hippocampus-write" (plist-get res :error)))))

(ert-deftest satan-hippocampus/overwrite-missing-file ()
  (let ((satan-hippocampus-dir (make-temp-file "satan-hippo-" t)))
    (unwind-protect
        (let ((res (satan-tool/hippocampus-overwrite
                    '(:filename "nope.org" :body "b")
                    '(:capabilities (hippocampus-write)))))
          (should (eq (car res) 'error))
          (should (string-match-p "not found" (cdr res))))
      (delete-directory satan-hippocampus-dir t))))

;; ---------------------------------------------------------------------
;; hippocampus_delete tests
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/delete-removes-file ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--delete-me__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (satan-tools-hippocampus-test--write-entry tmp fname "body")
          (should (file-exists-p (expand-file-name fname tmp)))
          (let ((res (satan-tool/hippocampus-delete
                      (list :filename fname)
                      '(:capabilities (hippocampus-write)))))
            (should (eq (car res) 'ok))
            (should-not (file-exists-p (expand-file-name fname tmp)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/delete-capability-required ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "hippocampus_delete"
                :args (:filename "x.org"))
              '("hippocampus_delete")
              '(:capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "hippocampus-write" (plist-get res :error)))))

(ert-deftest satan-hippocampus/delete-rejects-traversal ()
  (let ((res (satan-tool/hippocampus-delete
              '(:filename "../etc/shadow")
              '(:capabilities (hippocampus-write)))))
    (should (eq (car res) 'error))
    (should (string-match-p "plain basename" (cdr res)))))

;; ---------------------------------------------------------------------
;; hippocampus_grep tests
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/grep-finds-match ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--grep-test__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (satan-tools-hippocampus-test--write-entry
           tmp fname "unique-needle-xyz")
          (let* ((res (satan-tool/hippocampus-grep
                       '(:query "unique-needle-xyz") nil))
                 (matches (plist-get (cdr res) :matches)))
            (should (eq (car res) 'ok))
            (should (> (plist-get (cdr res) :count) 0))
            (should (string-match-p "unique-needle-xyz"
                                    (plist-get (car matches) :text)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/grep-no-match ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--grep-test__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (satan-tools-hippocampus-test--write-entry tmp fname "body")
          (let ((res (satan-tool/hippocampus-grep
                      '(:query "zzz-no-match-zzz") nil)))
            (should (eq (car res) 'ok))
            (should (= 0 (plist-get (cdr res) :count)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/grep-empty-query ()
  (let ((res (satan-tool/hippocampus-grep '(:query "") nil)))
    (should (eq (car res) 'error))
    (should (string-match-p "non-empty" (cdr res)))))

;; ---------------------------------------------------------------------
;; hippocampus_rename tests
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/rename-updates-filename-and-title ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp)
         (fname "20260524T091500--old-name__satan_hippocampus.org"))
    (unwind-protect
        (progn
          (satan-tools-hippocampus-test--write-entry tmp fname "body")
          (let* ((res (satan-tool/hippocampus-rename
                       (list :filename fname :title "Better Name")
                       '(:capabilities (hippocampus-write))))
                 (new-fname (plist-get (cdr res) :new_filename)))
            (should (eq (car res) 'ok))
            (should (string-match-p "better-name" new-fname))
            (should (string-prefix-p "20260524T091500--" new-fname))
            (should-not (file-exists-p (expand-file-name fname tmp)))
            (should (file-exists-p (expand-file-name new-fname tmp)))
            (let ((text (with-temp-buffer
                          (insert-file-contents
                           (expand-file-name new-fname tmp))
                          (buffer-string))))
              (should (string-search "#+title:      Better Name" text)))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/rename-capability-required ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "hippocampus_rename"
                :args (:filename "x.org" :title "t"))
              '("hippocampus_rename")
              '(:capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "hippocampus-write" (plist-get res :error)))))

(ert-deftest satan-hippocampus/rename-missing-file ()
  (let ((satan-hippocampus-dir (make-temp-file "satan-hippo-" t)))
    (unwind-protect
        (let ((res (satan-tool/hippocampus-rename
                    '(:filename "nope.org" :title "t")
                    '(:capabilities (hippocampus-write)))))
          (should (eq (car res) 'error))
          (should (string-match-p "not found" (cdr res))))
      (delete-directory satan-hippocampus-dir t))))

;; ---------------------------------------------------------------------
;; File-side tests (relocated from satan-test.el monolith)
;; ---------------------------------------------------------------------

(ert-deftest satan-hippocampus/handler-writes-denote-file ()
  (let* ((tmp (make-temp-file "satan-hippo-" t))
         (satan-hippocampus-dir tmp))
    (unwind-protect
        (let* ((res (satan-tool/hippocampus-write
                     '(:title "Avoid mocking the DB"
                       :body "User burned by a mock/prod divergence in 2026 Q1.")
                     '(:id "r1" :mode-name "morning"
                       :capabilities (hippocampus-write)))))
          (should (eq (car res) 'ok))
          (let* ((path (plist-get (cdr res) :path))
                 (text (with-temp-buffer
                         (insert-file-contents path)
                         (buffer-string))))
            (should (string-match-p "__satan_hippocampus\\.org$" path))
            (should (string-match-p ":satan:hippocampus:" text))
            (should (string-match-p ":RUN_ID: r1" text))
            (should (string-match-p "mock/prod divergence" text))))
      (delete-directory tmp t))))

(ert-deftest satan-hippocampus/capability-required ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "hippocampus_write"
                :args (:title "t" :body "b"))
              '("hippocampus_write")
              '(:capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "hippocampus-write" (plist-get res :error)))))

(ert-deftest satan-hippocampus/schema-required ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "m1" :name "hippocampus_write"
                :args (:body "x"))
              '("hippocampus_write")
              '(:capabilities (hippocampus-write)))))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "title" (plist-get res :error)))))

(provide 'satan-tools-hippocampus-test)
;;; satan-tools-hippocampus-test.el ends here
