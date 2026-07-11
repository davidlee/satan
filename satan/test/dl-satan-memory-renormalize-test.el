;;; dl-satan-memory-renormalize-test.el --- renormalize CLI ert -*- lexical-binding: t; -*-

;; Tests for the §7 grammar-bump replay (`dl-satan-memory-renormalize').
;; Drive against a fresh `satan_memory_test' DB seeded with v1 traces;
;; cl-letf the elisp grammar constants up to v2 and the alias map to
;; include `planning -> phase:orientation' (matching 0004 fixture).
;;
;; Each DB-touching test resets and re-applies all migrations via the
;; runner; tests skip-unless the test DB is reachable.

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-memory-migrate)
(require 'dl-satan-memory-store)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-memory-canon)

(defconst dl-satan-memory-renormalize-test--db "satan_memory_test")

(defun dl-satan-memory-renormalize-test--reachable-p ()
  (pcase (let ((dl-satan-memory-migrate-database
                dl-satan-memory-renormalize-test--db))
           (dl-satan-db-psql
            dl-satan-memory-renormalize-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun dl-satan-memory-renormalize-test--reset-and-migrate ()
  (let ((dl-satan-memory-migrate-database
         dl-satan-memory-renormalize-test--db))
    (dl-satan-db-psql
     dl-satan-memory-renormalize-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
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

(defmacro dl-satan-memory-renormalize-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (dl-satan-memory-renormalize-test--reachable-p))
     (dl-satan-memory-renormalize-test--reset-and-migrate)
     (let ((dl-satan-memory-store-database
            dl-satan-memory-renormalize-test--db)
           (dl-satan-memory-migrate-database
            dl-satan-memory-renormalize-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------

(defconst dl-satan-memory-renormalize-test--time
  "2026-05-19T10:00:00+10:00")

(defun dl-satan-memory-renormalize-test--seed-trace (id &optional phase-hint)
  "Canonicalize under v1 and store a trace with ID.  PHASE-HINT, when
supplied, is the raw hints.phase value preserved in metadata_json."
  (let* ((raw-hints (and phase-hint (list :phase phase-hint)))
         (evidence '())
         (ctx (list :current_grammar_version 1
                    :mode_name "motd"
                    :time_now dl-satan-memory-renormalize-test--time
                    :run_id nil
                    :run_started_at nil))
         (canon (dl-satan-memory-canon-canonicalize-from-raw
                 evidence raw-hints ctx))
         (handles (plist-get canon :handles))
         (sources (plist-get canon :handle_sources))
         (result (dl-satan-memory-store-mark
                  :trace-id id
                  :kind "observation"
                  :trace-origin "llm_mark"
                  :source "memory_mark@motd"
                  :observed-start-at "2026-05-19T09:50:00+10:00"
                  :observed-end-at dl-satan-memory-renormalize-test--time
                  :payload "renormalize test"
                  :grammar-version 1
                  :metadata-json (list :evidence evidence
                                       :hints (or raw-hints '())
                                       :ctx ctx)
                  :handles (mapcar
                            (lambda (h)
                              (list :handle h
                                    :source (cdr (assoc h sources))))
                            handles))))
    (pcase result
      (`(ok . ,_) result)
      (err (error "seed-trace %s failed: %S" id err)))))

(defun dl-satan-memory-renormalize-test--handle-rows (trace-id)
  "Return list of (:gv :handle :active) for TRACE-ID, sorted."
  (let* ((sql (format
               (concat "SELECT grammar_version::text, handle, active::text "
                       "FROM trace_handles WHERE trace_id = %s "
                       "ORDER BY grammar_version, handle")
               (dl-satan-memory-migrate--sql-literal trace-id)))
         (result (dl-satan-db-psql
                  dl-satan-memory-renormalize-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "\t" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for parts = (split-string line "\t")
                when (= 3 (length parts))
                collect (list :gv (string-to-number (nth 0 parts))
                              :handle (nth 1 parts)
                              :active (equal (nth 2 parts) "true"))))
      (`(error . ,msg) (error "%s" msg)))))

(defun dl-satan-memory-renormalize-test--active-handles (trace-id)
  (cl-loop for r in (dl-satan-memory-renormalize-test--handle-rows trace-id)
           when (plist-get r :active)
           collect (plist-get r :handle)))

(defun dl-satan-memory-renormalize-test--trace-cols (trace-id)
  "Return alist of (updated_at payload strength metadata_json) for TRACE-ID."
  (let* ((sql (format
               (concat "SELECT updated_at::text, payload, strength::text, "
                       "metadata_json::text "
                       "FROM traces WHERE id = %s")
               (dl-satan-memory-migrate--sql-literal trace-id)))
         (result (dl-satan-db-psql
                  dl-satan-memory-renormalize-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "\t" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (let ((parts (split-string out "\t")))
         (and (= 4 (length parts))
              (list :updated_at    (nth 0 parts)
                    :payload       (nth 1 parts)
                    :strength      (nth 2 parts)
                    :metadata_json (nth 3 parts)))))
      (`(error . ,msg) (error "%s" msg)))))

(defun dl-satan-memory-renormalize-test--v2-aliases ()
  (cons '("planning" . "phase:orientation")
        dl-satan-memory-grammar-aliases))

(defmacro dl-satan-memory-renormalize-test--as-v2 (&rest body)
  "Execute BODY with grammar constants rebound to v2 + planning alias."
  (declare (indent 0))
  `(cl-letf (((symbol-value 'dl-satan-memory-grammar-current-version) 2)
             ((symbol-value 'dl-satan-memory-grammar-aliases)
              (dl-satan-memory-renormalize-test--v2-aliases)))
     ,@body))

;; ---------------------------------------------------------------------
;; Tests
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-renormalize/no-op-when-current ()
  "Renormalize at the same version as the trace's existing rows must
not touch any rows."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-noop01" nil)
   (let* ((before (dl-satan-memory-renormalize-test--handle-rows
                   "20260519T100000-noop01"))
          (result (dl-satan-memory-renormalize nil 1))
          (after (dl-satan-memory-renormalize-test--handle-rows
                  "20260519T100000-noop01")))
     (should (= 0 (plist-get result :updated)))
     (should (= 1 (plist-get result :skipped)))
     (should (null (plist-get result :failed)))
     (should (equal before after)))))

(ert-deftest dl-satan-memory-renormalize/single-trace-bump ()
  "v2 bump must flip v1 rows to inactive and insert v2 rows including
the alias-resolved phase handle; traces row is untouched."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-bump01" "planning")
   (let ((cols-before (dl-satan-memory-renormalize-test--trace-cols
                       "20260519T100000-bump01")))
     (dl-satan-memory-renormalize-test--as-v2
      (let ((result (dl-satan-memory-renormalize nil 2)))
        (should (= 1 (plist-get result :updated)))
        (should (null (plist-get result :failed)))))
     (let* ((rows (dl-satan-memory-renormalize-test--handle-rows
                   "20260519T100000-bump01"))
            (v1 (cl-remove-if-not (lambda (r) (= 1 (plist-get r :gv))) rows))
            (v2 (cl-remove-if-not (lambda (r) (= 2 (plist-get r :gv))) rows))
            (v2-active-handles
             (cl-loop for r in v2
                      when (plist-get r :active)
                      collect (plist-get r :handle))))
       (should v1)
       (should (cl-every (lambda (r) (not (plist-get r :active))) v1))
       (should v2)
       (should (cl-every (lambda (r) (plist-get r :active)) v2))
       (should (member "phase:orientation" v2-active-handles)))
     (let ((cols-after (dl-satan-memory-renormalize-test--trace-cols
                        "20260519T100000-bump01")))
       (should (equal (plist-get cols-before :payload)
                      (plist-get cols-after :payload)))
       (should (equal (plist-get cols-before :strength)
                      (plist-get cols-after :strength)))
       (should (equal (plist-get cols-before :metadata_json)
                      (plist-get cols-after :metadata_json)))
       (should (equal (plist-get cols-before :updated_at)
                      (plist-get cols-after :updated_at)))))))

(ert-deftest dl-satan-memory-renormalize/idempotent ()
  "A second pass after a successful bump must touch zero rows."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-idem01" "planning")
   (dl-satan-memory-renormalize-test--as-v2
    (let ((first (dl-satan-memory-renormalize nil 2)))
      (should (= 1 (plist-get first :updated))))
    (let* ((before (dl-satan-memory-renormalize-test--handle-rows
                    "20260519T100000-idem01"))
           (second (dl-satan-memory-renormalize nil 2))
           (after (dl-satan-memory-renormalize-test--handle-rows
                   "20260519T100000-idem01")))
      (should (= 0 (plist-get second :updated)))
      (should (= 1 (plist-get second :skipped)))
      (should (null (plist-get second :failed)))
      (should (equal before after))))))

(ert-deftest dl-satan-memory-renormalize/per-trace-tx ()
  "Errors on one trace must roll back that trace only; other traces
must still commit."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-tx0001" "planning")
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-tx0002" "planning")
   (let ((calls 0)
         (real-fn (symbol-function
                   'dl-satan-memory-canon-canonicalize-from-raw)))
     (dl-satan-memory-renormalize-test--as-v2
      (cl-letf (((symbol-function
                  'dl-satan-memory-canon-canonicalize-from-raw)
                 (lambda (ev hints ctx)
                   (cl-incf calls)
                   (if (= calls 2)
                       (error "poisoned trace #2")
                     (funcall real-fn ev hints ctx)))))
        (let ((result (dl-satan-memory-renormalize nil 2)))
          (should (= 1 (plist-get result :updated)))
          (should (= 1 (length (plist-get result :failed))))
          (should (equal "20260519T100000-tx0002"
                         (plist-get (car (plist-get result :failed))
                                    :trace_id)))))))
   (let* ((r1 (dl-satan-memory-renormalize-test--handle-rows
               "20260519T100000-tx0001"))
          (r1-v2-active
           (cl-loop for r in r1
                    when (and (= 2 (plist-get r :gv))
                              (plist-get r :active))
                    collect (plist-get r :handle))))
     (should (member "phase:orientation" r1-v2-active)))
   (let* ((r2 (dl-satan-memory-renormalize-test--handle-rows
               "20260519T100000-tx0002"))
          (r2-v1-active
           (cl-loop for r in r2
                    when (and (= 1 (plist-get r :gv))
                              (plist-get r :active))
                    collect r))
          (r2-v2-rows
           (cl-loop for r in r2 when (= 2 (plist-get r :gv)) collect r)))
     (should r2-v1-active)
     (should (null r2-v2-rows)))))

(ert-deftest dl-satan-memory-renormalize-status/counts ()
  "Status reports (gv -> count) and stale-trace count under the
current elisp grammar version."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-sta001")
   ;; second trace inserted with grammar_version = 2 directly
   (let* ((ctx (list :current_grammar_version 2
                     :mode_name "motd"
                     :time_now dl-satan-memory-renormalize-test--time))
          (canon (dl-satan-memory-canon-canonicalize '() nil ctx))
          (handles (plist-get canon :handles))
          (sources (plist-get canon :handle_sources)))
     (dl-satan-memory-store-mark
      :trace-id "20260519T100000-sta002"
      :kind "observation" :trace-origin "llm_mark"
      :source "memory_mark@motd"
      :observed-start-at "2026-05-19T09:50:00+10:00"
      :observed-end-at dl-satan-memory-renormalize-test--time
      :payload "v2 trace" :grammar-version 2
      :metadata-json (list :evidence '() :hints '() :ctx ctx)
      :handles (mapcar (lambda (h)
                         (list :handle h
                               :source (cdr (assoc h sources))))
                       handles)))
   (dl-satan-memory-renormalize-test--as-v2
    (let* ((status (dl-satan-memory-renormalize-status))
           (by-version (plist-get status :by-version)))
      (should (equal 1 (cdr (assoc 1 by-version))))
      (should (equal 1 (cdr (assoc 2 by-version))))
      (should (= 1 (plist-get status :stale-traces)))))))

(ert-deftest dl-satan-memory-renormalize/acceptance-9-8 ()
  "Acceptance §9.8: a grammar bump + renormalize flips v1 rows
inactive, inserts v2 rows active, and trace row remains intact."
  (dl-satan-memory-renormalize-test--with-db
   (dl-satan-memory-renormalize-test--seed-trace
    "20260519T100000-acc001" "planning")
   (dl-satan-memory-renormalize-test--as-v2
    (dl-satan-memory-renormalize nil 2))
   (let* ((sql
           (format
            (concat "SELECT grammar_version::text FROM trace_handles "
                    "WHERE trace_id = %s AND active "
                    "ORDER BY grammar_version")
            (dl-satan-memory-migrate--sql-literal
             "20260519T100000-acc001")))
          (result (dl-satan-db-psql
                   dl-satan-memory-renormalize-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                   (list "-A" "-t" "-c" sql))))
     (pcase result
       (`(ok . ,out)
        (let ((gvs (split-string (string-trim out) "\n" t)))
          (should gvs)
          (should (cl-every (lambda (s) (equal s "2")) gvs))))
       (err (ert-fail (format "select failed: %S" err)))))))

(provide 'dl-satan-memory-renormalize-test)
;;; dl-satan-memory-renormalize-test.el ends here
