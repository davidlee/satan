;;; dl-satan-pattern-test.el --- pattern sync + rebuild ert -*- lexical-binding: t; -*-

;; DE-009 Phase 02: tests for dl-satan-pattern.el.
;; Drive against satan_memory_test DB.
;;
;; Run from CLI:
;;   emacs --batch -Q --init-directory=<workspace> \
;;     -L core -L satan -L satan/test \
;;     -l dl-satan-pattern-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-db)
(require 'dl-satan-memory-migrate)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-pattern)
(require 'dl-satan-intervention)
(require 'dl-satan-audit)

(defconst dl-satan-pattern-test--db "satan_memory_test")

;; ── DB helpers ──────────────────────────────────────────────────────────────

(defun dl-satan-pattern-test--reachable-p ()
  (pcase (let ((dl-satan-memory-migrate-database dl-satan-pattern-test--db))
           (dl-satan-db-psql
            dl-satan-pattern-test--db dl-satan-memory-migrate-host
            dl-satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun dl-satan-pattern-test--reset-and-migrate ()
  (let ((dl-satan-memory-migrate-database dl-satan-pattern-test--db))
    (dl-satan-db-psql
     dl-satan-pattern-test--db dl-satan-memory-migrate-host
     dl-satan-memory-migrate-psql-program
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
    (dl-satan-memory-migrate-apply)))

(defmacro dl-satan-pattern-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (dl-satan-pattern-test--reachable-p))
     (dl-satan-pattern-test--reset-and-migrate)
     (let ((dl-satan-memory-migrate-database dl-satan-pattern-test--db))
       ,@body)))

(defun dl-satan-pattern-test--psql-row (sql)
  "Run SQL, return the single trimmed row string, or nil."
  (pcase (dl-satan-db-psql
          dl-satan-pattern-test--db dl-satan-memory-migrate-host
          dl-satan-memory-migrate-psql-program
          (list "-A" "-t" "-c" sql))
    (`(ok . ,out) (let ((trimmed (string-trim out)))
                    (unless (string-empty-p trimmed) trimmed)))
    (_ nil)))

;; ── temp file helpers ───────────────────────────────────────────────────────

(defun dl-satan-pattern-test--write-patterns (definitions)
  "Write DEFINITIONS (list of plists) to a temp patterns.eld file; return path."
  (let ((path (make-temp-file "satan-patterns-" nil ".eld")))
    (with-temp-file path
      (prin1 definitions (current-buffer)))
    path))

;; ── intervention + outcome seed helpers ─────────────────────────────────────

(defun dl-satan-pattern-test--open-audit (root run-id)
  (let* ((bucket (and (string-match
                       "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                       run-id)
                      (format "%s-%s-%s"
                              (match-string 1 run-id)
                              (match-string 2 run-id)
                              (match-string 3 run-id))))
         (run-dir (expand-file-name
                   (concat (or bucket "_legacy") "/" run-id) root)))
    (dl-satan-audit-open run-dir
                         (list :run_id run-id :mode (list :name "morning"))
                         '(:bundle t))))

(defun dl-satan-pattern-test--build-ctx (audit run-id &optional ts percept-handles)
  (list :id run-id
        :mode-name "morning"
        :time-now (or ts "2026-05-23T12:00:00+1000")
        :run-started-at (or ts "2026-05-23T12:00:00+1000")
        :capabilities '(notify)
        :audit audit
        :percept-handles percept-handles))

;; ============================================================================
;; VT-pattern-containment
;; ============================================================================

(ert-deftest dl-satan-pattern/containment-empty-cue-matches-all ()
  "A pattern with empty cue_handles matches every intervention."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-p1")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil '("app:emacs"))))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "catch-all"
                        :label "Catch all"
                        :cue_handles ()
                        :priority 0
                        :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 1 (plist-get res :matched)))
           (let ((row (dl-satan-pattern-test--psql-row
                       "SELECT classification FROM satan_pattern_outcomes")))
             (should (equal "worked" row))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/containment-subset-matches ()
  "A pattern whose cue_handles ⊂ the percept snapshot matches."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-p2")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil
                '("app:emacs" "surface:editor" "artifact:commit"))))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "editor-repo"
                        :label "Editor work with repo"
                        :cue_handles ("app:emacs" "surface:editor")
                        :priority 3 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "ignored" :confidence "medium"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 1 (plist-get res :matched))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/containment-superset-does-not-match ()
  "A pattern whose cue_handles ⊃ the percept snapshot does NOT match."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-p3")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil
                '("app:emacs"))))                         ;; only 1 handle
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "needs-two"
                        :label "Needs two handles"
                        :cue_handles ("app:emacs" "surface:editor")
                        :priority 3 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           ;; Pattern has 2 handles, percept has 1 — no match
           (should (= 0 (plist-get res :matched))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/containment-disjoint-does-not-match ()
  "A pattern with disjoint handles does NOT match."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-p4")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil
                '("app:emacs" "surface:editor"))))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "terminal-only"
                        :label "Terminal only"
                        :cue_handles ("surface:terminal" "event:command_ok")
                        :priority 3 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 0 (plist-get res :matched))))
       (delete-directory root t)))))

;; ============================================================================
;; VT-pattern-sync
;; ============================================================================

(ert-deftest dl-satan-pattern/sync-parses-and-upserts ()
  "dl-satan-pattern-sync reads patterns.eld, validates, and upserts."
  (dl-satan-pattern-test--with-db
   (let* ((file (dl-satan-pattern-test--write-patterns
                 '((:id "test-pat"
                    :label "Test pattern"
                    :cue_handles ("app:emacs")
                    :priority 5 :enabled t))))
          (res (dl-satan-pattern-sync file dl-satan-pattern-test--db)))
     (should (= 1 (plist-get res :upserted)))
     (should (= 0 (plist-get res :retired)))
     (let ((row (dl-satan-pattern-test--psql-row
                 "SELECT id, label, priority FROM satan_patterns")))
       (should (string-match-p "test-pat" (or row ""))))
     (let ((list (dl-satan-pattern-list dl-satan-pattern-test--db)))
       (should (= 1 (length list)))
       (should (equal "test-pat" (plist-get (car list) :id)))))))

(ert-deftest dl-satan-pattern/sync-is-idempotent ()
  "Second sync with same definitions is a no-op."
  (dl-satan-pattern-test--with-db
   (let* ((file (dl-satan-pattern-test--write-patterns
                 '((:id "test-pat"
                    :label "Test pattern"
                    :cue_handles ("app:emacs")
                    :priority 5 :enabled t)))))
     (dl-satan-pattern-sync file dl-satan-pattern-test--db)
     (let ((res2 (dl-satan-pattern-sync file dl-satan-pattern-test--db)))
       (should (= 1 (plist-get res2 :upserted)))
       (should (= 0 (plist-get res2 :retired)))))))

(ert-deftest dl-satan-pattern/sync-soft-retires-absent ()
  "Patterns not in the file get enabled = false."
  (dl-satan-pattern-test--with-db
   (let* ((file1 (dl-satan-pattern-test--write-patterns
                  '((:id "pat-a" :label "A" :cue_handles ("app:emacs")
                     :priority 1 :enabled t)
                    (:id "pat-b" :label "B" :cue_handles ("surface:editor")
                     :priority 1 :enabled t))))
          (file2 (dl-satan-pattern-test--write-patterns
                  '((:id "pat-a" :label "A" :cue_handles ("app:emacs")
                     :priority 1 :enabled t)))))
     (dl-satan-pattern-sync file1 dl-satan-pattern-test--db)
     (let ((res (dl-satan-pattern-sync file2 dl-satan-pattern-test--db)))
       (should (= 1 (plist-get res :upserted)))
       (should (= 1 (plist-get res :retired)))
       (let ((enabled (dl-satan-pattern-test--psql-row
                       "SELECT enabled::text FROM satan_patterns WHERE id = 'pat-b'")))
         (should (equal "false" enabled)))))))

(ert-deftest dl-satan-pattern/sync-rejects-ungrammatical-handle ()
  "Sync rejects a handle with an unknown namespace."
  (dl-satan-pattern-test--with-db
   (let ((file (dl-satan-pattern-test--write-patterns
                '((:id "bad-pat"
                   :label "Bad pattern"
                   :cue_handles ("app:emacs" "not_a_namespace:foo")
                   :priority 1 :enabled t)))))
     (should-error (dl-satan-pattern-sync file dl-satan-pattern-test--db)
                   :type 'user-error))))

(ert-deftest dl-satan-pattern/sync-rejects-bad-closed-value ()
  "Sync rejects a handle with an invalid closed-world value."
  (dl-satan-pattern-test--with-db
   (let ((file (dl-satan-pattern-test--write-patterns
                '((:id "bad-val"
                   :label "Bad value"
                   :cue_handles ("surface:nonexistent")
                   :priority 1 :enabled t)))))
     (should-error (dl-satan-pattern-sync file dl-satan-pattern-test--db)
                   :type 'user-error))))

;; ============================================================================
;; VT-pattern-rebuild
;; ============================================================================

(ert-deftest dl-satan-pattern/rebuild-populates-from-seeded-data ()
  "Rebuild populates satan_pattern_outcomes + stats from seeded interventions."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r1")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs" "surface:editor"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "editor-work"
                        :label "Editor work"
                        :cue_handles ("app:emacs" "surface:editor")
                        :priority 3 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv1 (dl-satan-intervention-create
                      :ctx ctx :kind "notify"
                      :target-surface "dbus" :message "one"
                      :expected-outcome "x" :outcome-window-minutes 30
                      :severity "low"))
                (iv2 (dl-satan-intervention-create
                      :ctx ctx :kind "inbox"
                      :target-surface "editor" :message "two"
                      :expected-outcome "x" :outcome-window-minutes 30
                      :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv1
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv2
                    :classification "ignored" :confidence "medium"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:02+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 2 (plist-get res :matched)))
           (let ((stats (dl-satan-pattern-stats dl-satan-pattern-test--db)))
             (should (= 1 (length stats)))
             (should (equal "editor-work"
                            (plist-get (car stats) :pattern_id)))
             (should (equal "1"
                            (plist-get (car stats) :success_count)))
             (should (equal "1"
                            (plist-get (car stats) :ignored_count)))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/rebuild-excludes-immature ()
  "Interventions with pending maturity are excluded from the projection."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r2")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "test" :label "T"
                        :cue_handles ("app:emacs")
                        :priority 1 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "unknown" :confidence "low"
                    :evidence '(:source-events ())
                    :maturity "pending"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 0 (plist-get res :matched))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/rebuild-excludes-unknown ()
  "Mature outcomes with classification=unknown are excluded."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r3")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "test" :label "T"
                        :cue_handles ("app:emacs")
                        :priority 1 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "unknown" :confidence "low"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 0 (plist-get res :matched))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/rebuild-disabled-still-attributed ()
  "A disabled pattern still gets outcome rows (enabled gates action, not attribution)."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r4")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "disabled-pat"
                        :label "Disabled"
                        :cue_handles ("app:emacs")
                        :priority 1 :enabled nil)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (res (dl-satan-pattern-rebuild dl-satan-pattern-test--db)))
           (should (= 1 (plist-get res :matched))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/rebuild-revised-away-drops-scar ()
  "When an outcome is revised away from contradicted, it drops on next rebuild."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r5")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "test" :label "T"
                        :cue_handles ("app:emacs")
                        :priority 1 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                ;; First: classify as contradicted (manual)
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "contradicted" :confidence "medium"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "manual"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (_ (dl-satan-pattern-rebuild dl-satan-pattern-test--db))
                (scars1 (dl-satan-pattern-scars
                         "test" dl-satan-pattern-test--db)))
           (should (= 1 (length scars1)))
           ;; Revise away from contradicted to worked
           (dl-satan-intervention-classify
            :ctx ctx :intervention-id iv-id
            :classification "worked" :confidence "high"
            :evidence '(:source-events ())
            :maturity "mature"
            :next-revisit-at "2026-05-23T12:30:00+1000"
            :source "auto"
            :classified-at "2026-05-23T13:00:00+1000")
           (dl-satan-pattern-rebuild dl-satan-pattern-test--db)
           (let ((scars2 (dl-satan-pattern-scars
                          "test" dl-satan-pattern-test--db)))
             (should (= 0 (length scars2)))))
       (delete-directory root t)))))

(ert-deftest dl-satan-pattern/rebuild-is-idempotent ()
  "Second rebuild yields identical rows."
  (dl-satan-pattern-test--with-db
   (dl-satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-pat-" t))
          (run-id "20260523T120000-morning-r6")
          (audit (dl-satan-pattern-test--open-audit root run-id))
          (handles '("app:emacs"))
          (ctx (dl-satan-pattern-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let* ((_ (dl-satan-pattern-sync
                    (dl-satan-pattern-test--write-patterns
                     '((:id "test" :label "T"
                        :cue_handles ("app:emacs")
                        :priority 1 :enabled t)))
                    dl-satan-pattern-test--db))
                (iv-id (dl-satan-intervention-create
                        :ctx ctx :kind "notify"
                        :target-surface "dbus" :message "test"
                        :expected-outcome "x" :outcome-window-minutes 30
                        :severity "low"))
                (_ (dl-satan-intervention-classify
                    :ctx ctx :intervention-id iv-id
                    :classification "worked" :confidence "high"
                    :evidence '(:source-events ())
                    :maturity "mature"
                    :next-revisit-at "2026-05-23T12:30:00+1000"
                    :source "auto"
                    :classified-at "2026-05-23T12:30:01+1000"))
                (_ (dl-satan-pattern-rebuild dl-satan-pattern-test--db))
                (rows1 (dl-satan-pattern-test--psql-row
                        "SELECT pattern_id, intervention_id, classification
                         FROM satan_pattern_outcomes ORDER BY 1,2"))
                (_ (dl-satan-pattern-rebuild dl-satan-pattern-test--db))
                (rows2 (dl-satan-pattern-test--psql-row
                        "SELECT pattern_id, intervention_id, classification
                         FROM satan_pattern_outcomes ORDER BY 1,2")))
           (should (equal rows1 rows2)))
       (delete-directory root t)))))

;; ============================================================================
;; Real patterns.eld parses to every curated seed (no DB)
;; ============================================================================

(ert-deftest dl-satan-pattern/real-eld-parses-all-seeds ()
  "The checked-in `satan/patterns.eld' must parse to all of its seed entries.
Guards against the multi-top-level-form footgun: a `read'-once parser
silently drops every form after the first, so a file written as N separate
`((..))' forms only yields its first pattern."
  (let* ((file (expand-file-name
                "satan/patterns.eld"
                (or (and (boundp 'user-emacs-directory) user-emacs-directory)
                    default-directory)))
         (defs (dl-satan-pattern--read-file file))
         (ids (mapcar (lambda (e) (plist-get e :id)) defs)))
    (should (member "docs-after-error" ids))
    (should (member "terminal-coding" ids))
    (should (member "editor-commit" ids))
    ;; every entry must validate (id + label + grammatical cue_handles)
    (dolist (e defs)
      (should (dl-satan-pattern--validate-definition e)))))

(provide 'dl-satan-pattern-test)
;;; dl-satan-pattern-test.el ends here
