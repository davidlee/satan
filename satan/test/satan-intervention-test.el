;;; satan-intervention-test.el --- intervention rebuild ert -*- lexical-binding: t; -*-

;; T7 PR 2 — rebuild idempotency against the satan_memory_test DB.
;; Tests skip-unless the test DB is reachable.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-intervention-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-audit)
(require 'satan-jsonl)
(require 'satan-memory-migrate)
(require 'satan-intervention)

(defconst satan-intervention-test--db "satan_memory_test")

(defun satan-intervention-test--reachable-p ()
  (pcase (let ((satan-memory-migrate-database
                satan-intervention-test--db))
           (satan-db-psql
            satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun satan-intervention-test--reset-and-migrate ()
  "Drop everything in the test DB and re-run migrations through 0006."
  (let ((satan-memory-migrate-database satan-intervention-test--db))
    (satan-db-psql
     satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
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

(defmacro satan-intervention-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (satan-intervention-test--reachable-p))
     (satan-intervention-test--reset-and-migrate)
     (let ((satan-memory-migrate-database satan-intervention-test--db))
       ,@body)))

;; ---------- fixture builders ----------

(defun satan-intervention-test--write-transcript (runs-root run-id records)
  "Create runs-root/<bucket>/<run-id>/transcript.jsonl with RECORDS.
The bucket is parsed from run-id's leading YYYYMMDD."
  (let* ((date (and (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                                  run-id)
                    (format "%s-%s-%s"
                            (match-string 1 run-id)
                            (match-string 2 run-id)
                            (match-string 3 run-id))))
         (bucket-dir (expand-file-name (or date "_legacy") runs-root))
         (run-dir (expand-file-name run-id bucket-dir))
         (path (expand-file-name "transcript.jsonl" run-dir)))
    (make-directory run-dir t)
    (with-temp-file path
      (dolist (rec records)
        (insert (json-serialize (satan-jsonl-prepare rec)
                                :null-object :null :false-object :false))
        (insert "\n")))
    path))

(defun satan-intervention-test--ev-record (ts event payload)
  "Build a transcript record matching `satan-audit-record' shape."
  (list :ts ts :dir "broker" :event event :payload payload))

(defun satan-intervention-test--created (run-id iv-id &rest overrides)
  (let ((p (list :intervention_id        iv-id
                 :run_id                 run-id
                 :ts                     "2026-05-23T12:00:00+1000"
                 :mode                   "morning"
                 :kind                   "notify"
                 :target_surface         "sway-mainbar"
                 :message                "do the thing"
                 :related_motive_id      "morning.kanban-cleanup"
                 :cue_handles            '("bough_node:abc")
                 :percept_handles        '()
                 :expected_outcome       "user opens kanban.org"
                 :outcome_window_minutes 30
                 :severity               "low")))
    (while overrides
      (setq p (plist-put p (pop overrides) (pop overrides))))
    p))

(defun satan-intervention-test--classified (iv-id &rest overrides)
  (let ((p (list :intervention_id  iv-id
                 :classification   "worked"
                 :confidence       "medium"
                 :evidence         '(:source-events ()
                                     :predicates ("editor_edit_in_window"))
                 :maturity         "mature"
                 :next_revisit_at  "2026-05-23T12:30:00+1000"
                 :source           "auto"
                 :classified_at    "2026-05-23T12:30:01+1000")))
    (while overrides
      (setq p (plist-put p (pop overrides) (pop overrides))))
    p))

(defun satan-intervention-test--revised (iv-id revises-id &rest overrides)
  (apply #'satan-intervention-test--classified iv-id
         :revises revises-id overrides))

;; ---------- query helpers ----------

(defun satan-intervention-test--rows (table)
  "Return a sorted list of pipe-joined row strings from TABLE."
  (let* ((sql (concat "SELECT * FROM " table " ORDER BY 1"))
         (result (satan-db-psql
                  satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (split-string (string-trim out) "\n" t))
      (`(error . ,msg) (user-error "%s" msg)))))

(defun satan-intervention-test--count (table)
  (let* ((sql (concat "SELECT COUNT(*) FROM " table))
         (result (satan-db-psql
                  satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
                  (list "-A" "-t" "-c" sql))))
    (pcase result
      (`(ok . ,out) (string-to-number (string-trim out)))
      (`(error . ,msg) (user-error "%s" msg)))))

;; ---------- transcript discovery (no DB) -------------------------------

(ert-deftest satan-intervention/transcript-files-discovers-nested ()
  (let* ((root (make-temp-file "satan-iv-runs-" t)))
    (unwind-protect
        (progn
          (satan-intervention-test--write-transcript
           root "20260523T120000-morning-aaaaaa"
           (list (satan-intervention-test--ev-record
                  "2026-05-23T12:00:00+1000" "intervention.created"
                  (satan-intervention-test--created
                   "20260523T120000-morning-aaaaaa"
                   "20260523T120000-morning-aaaaaa.iv01"))))
          (satan-intervention-test--write-transcript
           root "20260524T130000-morning-bbbbbb"
           (list (satan-intervention-test--ev-record
                  "2026-05-24T13:00:00+1000" "intervention.created"
                  (satan-intervention-test--created
                   "20260524T130000-morning-bbbbbb"
                   "20260524T130000-morning-bbbbbb.iv01"))))
          (let ((paths (satan-intervention--transcript-files root)))
            (should (= 2 (length paths)))
            (should (cl-every (lambda (p)
                                (string-match-p "transcript\\.jsonl\\'" p))
                              paths))))
      (delete-directory root t))))

(ert-deftest satan-intervention/collect-events-skips-non-intervention ()
  (let ((root (make-temp-file "satan-iv-runs-" t)))
    (unwind-protect
        (progn
          (satan-intervention-test--write-transcript
           root "20260523T120000-morning-aaaaaa"
           (list
            (satan-intervention-test--ev-record
             "2026-05-23T12:00:00+1000" "tool-call"
             '(:id "c1" :name "notify_send"))
            (satan-intervention-test--ev-record
             "2026-05-23T12:00:01+1000" "intervention.created"
             (satan-intervention-test--created
              "20260523T120000-morning-aaaaaa"
              "20260523T120000-morning-aaaaaa.iv01"))
            (satan-intervention-test--ev-record
             "2026-05-23T12:00:02+1000" "log"
             '(:kind "usage"))))
          (let ((events (satan-intervention--collect-events root)))
            (should (= 1 (length events)))
            (should (equal "intervention.created"
                           (plist-get (car events) :event)))))
      (delete-directory root t))))

(ert-deftest satan-intervention/sort-events-by-ts-then-runid-then-seq ()
  (let* ((events
          (list (list :ts "2026-05-23T12:00:01+1000"
                      :event "intervention.created" :payload nil
                      :run_id "b" :seq 0)
                (list :ts "2026-05-23T12:00:00+1000"
                      :event "intervention.created" :payload nil
                      :run_id "z" :seq 0)
                (list :ts "2026-05-23T12:00:00+1000"
                      :event "intervention.created" :payload nil
                      :run_id "a" :seq 5)
                (list :ts "2026-05-23T12:00:00+1000"
                      :event "intervention.created" :payload nil
                      :run_id "a" :seq 1)))
         (sorted (satan-intervention--sort-events events)))
    (should (equal '("a" "a" "z" "b")
                   (mapcar (lambda (e) (plist-get e :run_id)) sorted)))
    (should (equal '(1 5 0 0)
                   (mapcar (lambda (e) (plist-get e :seq)) sorted)))))


;; ---------- rebuild against test DB ----------------------------------

(ert-deftest satan-intervention/rebuild-empty-runs-yields-zero-rows ()
  (satan-intervention-test--with-db
   (let ((root (make-temp-file "satan-iv-runs-" t)))
     (unwind-protect
         (let ((res (satan-intervention-rebuild
                     satan-intervention-test--db root)))
           (should-not (plist-get res :validation-error))
           (should (= 0 (plist-get res :total)))
           (should (= 0 (satan-intervention-test--count
                         "satan_interventions")))
           (should (= 0 (satan-intervention-test--count
                         "satan_intervention_outcomes"))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/rebuild-projects-created-and-classified ()
  (satan-intervention-test--with-db
   (let* ((root (make-temp-file "satan-iv-runs-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (iv-id (concat run-id ".iv01")))
     (unwind-protect
         (progn
           (satan-intervention-test--write-transcript
            root run-id
            (list
             (satan-intervention-test--ev-record
              "2026-05-23T12:00:00+1000" "intervention.created"
              (satan-intervention-test--created run-id iv-id))
             (satan-intervention-test--ev-record
              "2026-05-23T12:30:00+1000" "intervention.outcome_classified"
              (satan-intervention-test--classified iv-id))))
           (let ((res (satan-intervention-rebuild
                       satan-intervention-test--db root)))
             (should-not (plist-get res :validation-error))
             (should (= 2 (plist-get res :total)))
             (should (= 1 (plist-get res :created)))
             (should (= 1 (plist-get res :outcomes))))
           (should (= 1 (satan-intervention-test--count "satan_interventions")))
           (should (= 1 (satan-intervention-test--count "satan_intervention_outcomes"))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/rebuild-is-idempotent ()
  (satan-intervention-test--with-db
   (let* ((root (make-temp-file "satan-iv-runs-" t))
          (run1 "20260523T120000-morning-aaaaaa")
          (run2 "20260524T130000-morning-bbbbbb")
          (iv1 (concat run1 ".iv01"))
          (iv2 (concat run2 ".iv01")))
     (unwind-protect
         (progn
           (satan-intervention-test--write-transcript
            root run1
            (list
             (satan-intervention-test--ev-record
              "2026-05-23T12:00:00+1000" "intervention.created"
              (satan-intervention-test--created run1 iv1))
             (satan-intervention-test--ev-record
              "2026-05-23T12:30:00+1000" "intervention.outcome_classified"
              (satan-intervention-test--classified
               iv1 :classification "ignored" :confidence "medium"))
             (satan-intervention-test--ev-record
              "2026-05-23T13:00:00+1000" "intervention.outcome_revised"
              (satan-intervention-test--revised
               iv1 iv1
               :classification "worked" :confidence "high"))))
           (satan-intervention-test--write-transcript
            root run2
            (list
             (satan-intervention-test--ev-record
              "2026-05-24T13:00:00+1000" "intervention.created"
              (satan-intervention-test--created
               run2 iv2 :ts "2026-05-24T13:00:00+1000" :kind "inbox"))
             (satan-intervention-test--ev-record
              "2026-05-24T14:00:00+1000" "intervention.outcome_classified"
              (satan-intervention-test--classified
               iv2 :classification "harmful" :source "manual"
               :next_revisit_at "2026-05-24T13:30:00+1000"
               :classified_at   "2026-05-24T14:00:00+1000"))))
           (satan-intervention-rebuild
            satan-intervention-test--db root)
           (let ((first-iv (satan-intervention-test--rows "satan_interventions"))
                 (first-out (satan-intervention-test--rows
                             "satan_intervention_outcomes")))
             (should (= 2 (length first-iv)))
             (should (= 2 (length first-out)))
             (satan-intervention-rebuild
              satan-intervention-test--db root)
             (let ((second-iv (satan-intervention-test--rows "satan_interventions"))
                   (second-out (satan-intervention-test--rows
                                "satan_intervention_outcomes")))
               (should (equal first-iv second-iv))
               (should (equal first-out second-out)))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/rebuild-head-reflects-latest-revision ()
  (satan-intervention-test--with-db
   (let* ((root (make-temp-file "satan-iv-runs-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (iv-id (concat run-id ".iv01")))
     (unwind-protect
         (progn
           (satan-intervention-test--write-transcript
            root run-id
            (list
             (satan-intervention-test--ev-record
              "2026-05-23T12:00:00+1000" "intervention.created"
              (satan-intervention-test--created run-id iv-id))
             (satan-intervention-test--ev-record
              "2026-05-23T12:30:00+1000" "intervention.outcome_classified"
              (satan-intervention-test--classified
               iv-id :classification "ignored"))
             (satan-intervention-test--ev-record
              "2026-05-23T13:00:00+1000" "intervention.outcome_revised"
              (satan-intervention-test--revised
               iv-id iv-id
               :classification "worked" :confidence "high"
               :classified_at "2026-05-23T13:00:00+1000"))))
           (satan-intervention-rebuild
            satan-intervention-test--db root)
           (let* ((result (satan-db-psql
                           satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
                           (list "-A" "-t" "-F" "|" "-c"
                                 "SELECT classification, confidence FROM satan_intervention_outcomes")))
                  (row (and (eq (car result) 'ok)
                            (string-trim (cdr result)))))
             (should (equal "worked|high" row))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/rebuild-refuses-on-validation-failure ()
  (satan-intervention-test--with-db
   (let* ((root (make-temp-file "satan-iv-runs-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (iv-id (concat run-id ".iv01")))
     (unwind-protect
         (progn
           ;; outcome before created → replay-safety violation
           (satan-intervention-test--write-transcript
            root run-id
            (list
             (satan-intervention-test--ev-record
              "2026-05-23T12:30:00+1000" "intervention.outcome_classified"
              (satan-intervention-test--classified iv-id))
             (satan-intervention-test--ev-record
              "2026-05-23T13:00:00+1000" "intervention.created"
              (satan-intervention-test--created run-id iv-id))))
           (let ((res (satan-intervention-rebuild
                       satan-intervention-test--db root)))
             (should (plist-get res :validation-error))
             (should (string-match-p "no prior intervention.created"
                                     (plist-get (plist-get res :validation-error)
                                                :reason))))
           ;; projection untouched
           (should (= 0 (satan-intervention-test--count "satan_interventions")))
           (should (= 0 (satan-intervention-test--count "satan_intervention_outcomes"))))
       (delete-directory root t)))))

;; ---------- write/read API (PR 3) ------------------------------------

(defun satan-intervention-test--open-audit (root run-id)
  "Open a fresh audit handle under ROOT/<bucket>/RUN-ID/."
  (let* ((bucket (and (string-match
                       "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                       run-id)
                      (format "%s-%s-%s"
                              (match-string 1 run-id)
                              (match-string 2 run-id)
                              (match-string 3 run-id))))
         (run-dir (expand-file-name
                   (concat (or bucket "_legacy") "/" run-id) root)))
    (satan-audit-open run-dir
                         (list :run_id run-id :mode (list :name "morning"))
                         '(:bundle t))))

(defun satan-intervention-test--build-ctx (audit run-id &optional ts percept-handles)
  (list :id run-id
        :mode-name "morning"
        :time-now (or ts "2026-05-23T12:00:00+1000")
        :run-started-at (or ts "2026-05-23T12:00:00+1000")
        :capabilities '(notify)
        :audit audit
        :percept-handles percept-handles))

(defun satan-intervention-test--transcript-events (audit)
  "Return all parsed transcript records appended to AUDIT."
  (let ((path (satan-audit-handle-transcript-path audit)))
    (satan-jsonl-read-file path :null-object :null)))

(ert-deftest satan-intervention/create-emits-audit-and-projects ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id)))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx
                       :kind "notify"
                       :target-surface "dbus"
                       :message "morning kanban — clean DONE"
                       :expected-outcome "user opens kanban.org"
                       :outcome-window-minutes 30
                       :severity "low"
                       :related-motive-id "morning.kanban-cleanup"
                       :cue-handles '("bough_node:abc"))))
           ;; Stable id shape: <run-id>.iv001
           (should (equal (concat run-id ".iv001") iv-id))
           ;; Audit log carries the created event.
           (let* ((events (satan-intervention-test--transcript-events audit))
                  (created (cl-find "intervention.created" events
                                    :key (lambda (r) (plist-get r :event))
                                    :test #'equal)))
             (should created)
             (should (equal iv-id
                            (plist-get (plist-get created :payload)
                                       :intervention_id))))
           ;; Projection holds the row.
           (let ((row (satan-intervention-lookup iv-id)))
             (should row)
             (should (equal iv-id (plist-get (plist-get row :intervention)
                                             :intervention_id)))
             (should (equal "notify" (plist-get (plist-get row :intervention) :kind)))
             (should (equal "low"    (plist-get (plist-get row :intervention) :severity)))
             (should (equal '("bough_node:abc")
                            (plist-get (plist-get row :intervention) :cue_handles)))
             (should-not (plist-get row :outcome))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/create-mints-monotonic-counter ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id)))
     (unwind-protect
         (let* ((id1 (satan-intervention-create
                      :ctx ctx :kind "notify"
                      :target-surface "dbus" :message "one"
                      :expected-outcome "x" :outcome-window-minutes 30
                      :severity "low"))
                (id2 (satan-intervention-create
                      :ctx ctx :kind "notify"
                      :target-surface "dbus" :message "two"
                      :expected-outcome "x" :outcome-window-minutes 30
                      :severity "low")))
           (should (equal (concat run-id ".iv001") id1))
           (should (equal (concat run-id ".iv002") id2))
           (should (= 2 (satan-intervention-test--count "satan_interventions"))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/classify-emits-classified-then-revised ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id)))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "m"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low")))
           ;; First classify → outcome_classified.
           (should (equal "intervention.outcome_classified"
                          (satan-intervention-classify
                           :ctx ctx :intervention-id iv-id
                           :classification "ignored" :confidence "medium"
                           :evidence '(:source-events ()
                                        :no-positive-predicates t)
                           :maturity "mature"
                           :next-revisit-at "2026-05-23T12:30:00+1000"
                           :source "auto"
                           :classified-at "2026-05-23T12:30:01+1000")))
           ;; Second classify → outcome_revised (with :revises auto-set).
           (should (equal "intervention.outcome_revised"
                          (satan-intervention-classify
                           :ctx ctx :intervention-id iv-id
                           :classification "worked" :confidence "high"
                           :evidence '(:source-events ()
                                        :predicates ("editor_edit_in_window"))
                           :maturity "mature"
                           :next-revisit-at "2026-05-23T12:30:00+1000"
                           :source "auto"
                           :classified-at "2026-05-23T13:00:00+1000")))
           ;; Projection reflects the latest verdict.
           (let* ((row (satan-intervention-lookup iv-id))
                  (outcome (plist-get row :outcome)))
             (should outcome)
             (should (equal "worked" (plist-get outcome :classification)))
             (should (equal "high"   (plist-get outcome :confidence)))
             (should (equal iv-id    (plist-get outcome :revises))))
           ;; Audit log carries both events.
           (let* ((events (satan-intervention-test--transcript-events audit))
                  (names (mapcar (lambda (r) (plist-get r :event)) events)))
             (should (member "intervention.outcome_classified" names))
             (should (member "intervention.outcome_revised" names))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/classify-rejects-auto-harmful ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id)))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "m"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low")))
           (should-error
            (satan-intervention-classify
             :ctx ctx :intervention-id iv-id
             :classification "harmful" :confidence "high"
             :evidence '(:source-events ())
             :maturity "mature"
             :next-revisit-at "2026-05-23T12:30:00+1000"
             :source "auto"
             :classified-at "2026-05-23T12:30:01+1000")
            :type 'user-error))
       (delete-directory root t)))))

(ert-deftest satan-intervention/pending-returns-only-matured-no-outcome ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit-old (satan-intervention-test--open-audit
                      root run-id))
          (audit-new (satan-intervention-test--open-audit
                      root "20260523T130000-morning-bbbbbb"))
          (ctx-old (satan-intervention-test--build-ctx
                    audit-old run-id "2026-05-23T11:00:00+1000"))
          (ctx-new (satan-intervention-test--build-ctx
                    audit-new "20260523T130000-morning-bbbbbb"
                    "2026-05-23T13:00:00+1000")))
     (unwind-protect
         (let* ((iv-old (satan-intervention-create
                         :ctx ctx-old :kind "notify"
                         :target-surface "dbus" :message "old"
                         :expected-outcome "x" :outcome-window-minutes 30
                         :severity "low"))
                (_iv-new (satan-intervention-create
                          :ctx ctx-new :kind "notify"
                          :target-surface "dbus" :message "fresh"
                          :expected-outcome "x" :outcome-window-minutes 30
                          :severity "low"))
                ;; Probe time: window-elapsed for old, not for new.
                (pending (satan-intervention-pending
                          "2026-05-23T12:00:00+1000")))
           (should (= 1 (length pending)))
           (should (equal iv-old
                          (plist-get (car pending) :intervention_id)))
           ;; Classifying iv-old removes it from pending.
           (satan-intervention-classify
            :ctx ctx-old :intervention-id iv-old
            :classification "ignored" :confidence "medium"
            :evidence '(:source-events ())
            :maturity "mature"
            :next-revisit-at "2026-05-23T11:30:00+1000"
            :source "auto"
            :classified-at "2026-05-23T11:30:01+1000")
           (should-not (satan-intervention-pending
                        "2026-05-23T12:00:00+1000")))
       (delete-directory root t)))))

(ert-deftest satan-intervention/lookup-missing-returns-nil ()
  (satan-intervention-test--with-db
   (should-not (satan-intervention-lookup
                "20260523T120000-morning-zzzzzz.iv999"))))

;; ---------- manual override writer (T1.5b PR 4) ---------------------

(defun satan-intervention-test--capturing-mark-fn (captures)
  "Return a memory-mark-fn that pushes its kw args onto CAPTURES (a
symbol whose value is a list).  Stub returns `(ok . \"trace_test\")'."
  (lambda (&rest kvs)
    (set captures (cons kvs (symbol-value captures)))
    (cons 'ok "trace_test")))

(ert-deftest satan-intervention/manual-writer-rejects-bad-classification ()
  (should-error
   (satan-intervention-write-manual-outcome
    :ctx nil :intervention-id "x"
    :classification "worked" :confidence "medium"
    :reason "r" :evidence-pointer "p:1" :marked-by "interactive-command"
    :maturity "mature" :next-revisit-at "2026-05-23T12:30:00+1000"
    :classified-at "2026-05-23T12:30:01+1000")
   :type 'user-error))

(ert-deftest satan-intervention/manual-writer-rejects-bad-marked-by ()
  (should-error
   (satan-intervention-write-manual-outcome
    :ctx nil :intervention-id "x"
    :classification "harmful" :confidence "medium"
    :reason "r" :evidence-pointer "p:1" :marked-by "telegram"
    :maturity "mature" :next-revisit-at "2026-05-23T12:30:00+1000"
    :classified-at "2026-05-23T12:30:01+1000")
   :type 'user-error))

(ert-deftest satan-intervention/manual-writer-harmful-first-emit ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id))
          (captures-sym (make-symbol "captures"))
          (mark-fn (progn (set captures-sym nil)
                          (satan-intervention-test--capturing-mark-fn
                           captures-sym))))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "m"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low"
                       :cue-handles '("bough_node:abc" "bough_project:def"))))
           (should (equal "intervention.outcome_classified"
                          (satan-intervention-write-manual-outcome
                           :ctx ctx :intervention-id iv-id
                           :classification "harmful" :confidence "high"
                           :reason "interrupted focus"
                           :evidence-pointer "/notes/x.org:88"
                           :marked-by "interactive-command"
                           :maturity "mature"
                           :next-revisit-at "2026-05-23T12:30:00+1000"
                           :classified-at "2026-05-23T12:30:01+1000"
                           :notes "deep work"
                           :memory-mark-fn mark-fn)))
           (let* ((row (satan-intervention-lookup iv-id))
                  (outcome (plist-get row :outcome)))
             (should (equal "harmful" (plist-get outcome :classification)))
             (should (equal "high"    (plist-get outcome :confidence)))
             (should (equal "manual"  (plist-get outcome :source)))
             (should (equal "interactive-command"
                            (plist-get outcome :marked_by)))
             (should (equal "deep work" (plist-get outcome :notes)))
             (let ((ev (plist-get outcome :evidence)))
               (should (equal "interrupted focus" (plist-get ev :reason)))
               (should (equal "/notes/x.org:88"
                              (plist-get ev :evidence_pointer)))
               (should (equal "interactive-command"
                              (plist-get ev :marked_by)))))
           ;; Counter-memory trace written via stubbed mark-fn.
           (let* ((calls (symbol-value captures-sym))
                  (kvs (car calls)))
             (should (= 1 (length calls)))
             (should (equal "observation" (plist-get kvs :kind)))
             (should (equal "auto_rule"   (plist-get kvs :trace-origin)))
             (should (equal "negative"    (plist-get kvs :valence)))
             (should (string-match-p "harmful intervention"
                                     (plist-get kvs :payload)))
             (let* ((md (plist-get kvs :metadata-json)))
               (should (equal iv-id        (plist-get md :intervention_id)))
               (should (equal "harmful"    (plist-get md :classification)))
               (should (equal "interactive-command"
                              (plist-get md :marked_by))))
             (let* ((handles (plist-get kvs :handles))
                    (raw (mapcar (lambda (h) (plist-get h :handle)) handles)))
               (should (equal '("bough_node:abc" "bough_project:def") raw)))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/manual-writer-contradicted-revises-auto ()
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (ctx (satan-intervention-test--build-ctx audit run-id))
          (captures-sym (make-symbol "captures"))
          (mark-fn (progn (set captures-sym nil)
                          (satan-intervention-test--capturing-mark-fn
                           captures-sym))))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "m"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low")))
           ;; auto-emit :ignored first
           (satan-intervention-classify
            :ctx ctx :intervention-id iv-id
            :classification "ignored" :confidence "medium"
            :evidence '(:source-events () :no_positive_predicates t)
            :maturity "mature"
            :next-revisit-at "2026-05-23T12:30:00+1000"
            :source "auto"
            :classified-at "2026-05-23T12:30:01+1000")
           ;; user contradicts
           (should (equal "intervention.outcome_revised"
                          (satan-intervention-write-manual-outcome
                           :ctx ctx :intervention-id iv-id
                           :classification "contradicted" :confidence "medium"
                           :reason "drift-on-X"
                           :evidence-pointer "/notes/x.org:42"
                           :marked-by "notes-directive"
                           :maturity "mature"
                           :next-revisit-at "2026-05-23T12:30:00+1000"
                           :classified-at "2026-05-23T13:00:00+1000"
                           :memory-mark-fn mark-fn)))
           (let* ((row (satan-intervention-lookup iv-id))
                  (outcome (plist-get row :outcome))
                  (ev (plist-get outcome :evidence)))
             (should (equal "contradicted" (plist-get outcome :classification)))
             (should (equal "manual"       (plist-get outcome :source)))
             (should (equal iv-id          (plist-get outcome :revises)))
             (should (equal "drift-on-X"   (plist-get ev :prior_suspicion)))
             (should (equal "/notes/x.org:42"
                            (plist-get ev :user_artifact))))
           ;; Counter-memory trace — §3.4 contradicted template.
           (let* ((calls (symbol-value captures-sym))
                  (kvs (car calls)))
             (should (= 1 (length calls)))
             (should (string-match-p "SATAN suspected drift-on-X"
                                     (plist-get kvs :payload)))
             (should (string-match-p "user produced /notes/x.org:42"
                                     (plist-get kvs :payload)))))
       (delete-directory root t)))))

;; ---------------------------------------------------------------------
;; pg timestamptz normalization (no DB) — regression for the cold
;; outcome pipeline.  `psql -A' renders a `timestamptz' as
;; `YYYY-MM-DD HH:MM:SS+00' (space separator); Emacs `date-to-time'
;; cannot parse that form (the space confuses `parse-time-string',
;; which then drops the time-of-day and mis-shifts the date ~1.5 days
;; into the past).  Every prior fixture used the `T'-separated ISO
;; form, so the suite was green while production never classified a
;; single intervention.
;; ---------------------------------------------------------------------

(ert-deftest satan-intervention/normalize-pg-timestamp-space-form ()
  "psql space-form becomes a `date-to-time'-parseable instant."
  (let ((out (satan-intervention--normalize-pg-timestamp
              "2026-05-28 23:22:32+00")))
    ;; parses to the same instant as the explicit `T'-separated form
    (should (equal (date-to-time out)
                   (date-to-time "2026-05-28T23:22:32+00")))
    ;; and not to the garbage `date-to-time' yields for the raw space form
    (should-not (equal (date-to-time out)
                       (date-to-time "2026-05-28 23:22:32+00")))))

(ert-deftest satan-intervention/normalize-pg-timestamp-idempotent ()
  "Already-`T' strings pass through unchanged."
  (dolist (s '("2026-05-28T23:22:32+00"
               "2026-05-28T23:22:32+10:00"
               "2026-05-28T23:22:32+1000"))
    (should (equal s (satan-intervention--normalize-pg-timestamp s)))))

(ert-deftest satan-intervention/normalize-pg-timestamp-empty ()
  "nil and empty pass through unchanged (absent timestamptz cells)."
  (should (null (satan-intervention--normalize-pg-timestamp nil)))
  (should (equal "" (satan-intervention--normalize-pg-timestamp ""))))

(ert-deftest satan-intervention/row-to-intervention-ts-parses ()
  "A psql-shaped row yields a `:ts' that parses to the right instant.
Regression: the unparseable space-form made every intervention read
as `:stale', so no outcome row was ever written."
  (let* ((cells (list "20260529T092232-tick-pulse-094281.iv001"
                      "20260529T092232-tick-pulse-094281"
                      "2026-05-28 23:22:32+00" ; ts, psql space-form
                      "tick-pulse" "inbox" "editor" "msg"
                      "" "{}" "expected" "30" "medium"))
         (iv (satan-intervention--row-to-intervention cells)))
    (should (equal (date-to-time (plist-get iv :ts))
                   (date-to-time "2026-05-28T23:22:32+00")))
    (should (= 30 (plist-get iv :outcome_window_minutes)))))

;; ---------- DE-009 Phase 01 — percept-handle snapshot -------------------

(ert-deftest satan-intervention/percept-snapshot-stamps-from-ctx ()
  "VT-intervention-percept-snapshot: intervention.created stamps
percept_handles_json from ctx :percept-handles."
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-aaaaaa")
          (audit (satan-intervention-test--open-audit root run-id))
          (handles '("app:emacs" "surface_transition:browser->editor"))
          (ctx (satan-intervention-test--build-ctx
                audit run-id nil handles)))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "test"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low")))
           ;; Audit payload carries percept_handles.
           (let* ((events (satan-intervention-test--transcript-events audit))
                  (created (cl-find "intervention.created" events
                                    :key (lambda (r) (plist-get r :event))
                                    :test #'equal)))
             (should created)
             (should (equal handles
                            (plist-get (plist-get created :payload)
                                       :percept_handles))))
           ;; Projection row carries percept_handles_json.
           (let ((row (satan-intervention-lookup iv-id)))
             (should row)
             ;; percept_handles_json is not in the lookup columns yet
             ;; (Phase 02 reads it via its own SQL); verify via raw psql.
             (let* ((sql (concat "SELECT percept_handles_json::text FROM "
                                "satan_interventions WHERE id = "
                                (satan-intervention--quote-text iv-id)))
                    (result (satan-db-psql
                             satan-intervention-test--db
                             satan-memory-migrate-host
                             satan-memory-migrate-psql-program
                             (list "-A" "-t" "-c" sql))))
               (should (eq (car result) 'ok))
               (let ((parsed (json-parse-string (string-trim (cdr result))
                                                :object-type 'plist
                                                :array-type 'list
                                                :null-object :null
                                                :false-object :false)))
                 (should (equal handles parsed))))))
       (delete-directory root t)))))

(ert-deftest satan-intervention/percept-snapshot-nil-ctx-yields-empty ()
  "VT-intervention-percept-snapshot: nil :percept-handles → []."
  (satan-intervention-test--with-db
   (satan-intervention--reset-counters)
   (let* ((root (make-temp-file "satan-iv-run-" t))
          (run-id "20260523T120000-morning-bbbbbb")
          (audit (satan-intervention-test--open-audit root run-id))
          ;; No :percept-handles in ctx (nil).
          (ctx (satan-intervention-test--build-ctx
                audit run-id nil nil)))
     (unwind-protect
         (let ((iv-id (satan-intervention-create
                       :ctx ctx :kind "notify"
                       :target-surface "dbus" :message "test"
                       :expected-outcome "x" :outcome-window-minutes 30
                       :severity "low")))
           ;; Audit payload carries [] for percept_handles (may be
           ;; nil after json-parse-string with :array-type 'list).
           (let* ((events (satan-intervention-test--transcript-events audit))
                  (created (cl-find "intervention.created" events
                                    :key (lambda (r) (plist-get r :event))
                                    :test #'equal)))
             (should created)
             (let ((ph (plist-get (plist-get created :payload) :percept_handles)))
               (should (or (null ph) (equal ph '())))))
           ;; Projection backfills to [] (verify via raw psql).
           (let* ((sql (concat "SELECT percept_handles_json::text FROM "
                              "satan_interventions WHERE id = "
                              (satan-intervention--quote-text iv-id)))
                  (result (satan-db-psql
                           satan-intervention-test--db
                           satan-memory-migrate-host
                           satan-memory-migrate-psql-program
                           (list "-A" "-t" "-c" sql))))
             (should (eq (car result) 'ok))
             (should (equal "[]" (string-trim (cdr result)))))))
       (delete-directory root t))))

(ert-deftest satan-intervention/percept-snapshot-migration-backfills-legacy ()
  "VT-intervention-percept-snapshot: migration backfills pre-existing rows to []."
  (satan-intervention-test--with-db
   ;; Insert a row via raw SQL (bypassing the create API) to simulate a
   ;; pre-migration legacy intervention.
   (let ((legacy-id "20260523T120000-morning-legacy.iv01"))
     (satan-db-psql
      satan-intervention-test--db satan-memory-migrate-host satan-memory-migrate-psql-program
      (list "-c"
            (concat
             "INSERT INTO satan_interventions ("
             "id, run_id, ts, mode, kind, target_surface, message, "
             "cue_handles_json, expected_outcome, "
             "outcome_window_minutes, severity) VALUES ("
             (satan-intervention--quote-text legacy-id) ", "
             (satan-intervention--quote-text "20260523T120000-morning-legacy") ", "
             (format "%s::timestamptz"
                     (satan-intervention--quote-text
                      "2026-05-23T12:00:00+1000")) ", "
             (satan-intervention--quote-text "morning") ", "
             (satan-intervention--quote-text "notify") ", "
             (satan-intervention--quote-text "dbus") ", "
             (satan-intervention--quote-text "legacy") ", "
             (format "%s::jsonb" (satan-intervention--quote-text "[]")) ", "
             (satan-intervention--quote-text "x") ", "
             "30, "
             (satan-intervention--quote-text "low") ")")))
     ;; The INSERT doesn't include percept_handles_json, so it gets the default '[]'.
     (let* ((sql (concat "SELECT percept_handles_json::text FROM "
                        "satan_interventions WHERE id = "
                        (satan-intervention--quote-text legacy-id)))
            (result (satan-db-psql
                     satan-intervention-test--db
                     satan-memory-migrate-host
                     satan-memory-migrate-psql-program
                     (list "-A" "-t" "-c" sql))))
       (should (eq (car result) 'ok))
       (should (equal "[]" (string-trim (cdr result))))))))

(provide 'satan-intervention-test)
;;; satan-intervention-test.el ends here
