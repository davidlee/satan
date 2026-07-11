;;; dl-satan-memory-store-test.el --- store backend ert -*- lexical-binding: t; -*-

;; Tests for step 7 of memory.design.md.  Drive mark / resonate / show
;; against a fresh `satan_memory_test' DB.  Pure helpers (id minting,
;; pg-array round-trip) exercised directly.
;;
;; Each DB-touching test resets and re-applies all migrations via the
;; runner so the schema + grammar seed + memory_* functions are
;; in-place.  Tests skip-unless the test DB is reachable.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-memory-store)
(require 'dl-satan-memory-migrate)

(defconst dl-satan-memory-store-test--db "satan_memory_test")

(defun dl-satan-memory-store-test--reachable-p ()
  (pcase (let ((dl-satan-memory-migrate-database
                dl-satan-memory-store-test--db))
           (dl-satan-db-psql
            dl-satan-memory-store-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
            (list "-A" "-t" "-c" "SELECT 1")))
    (`(ok . ,_) t)
    (_ nil)))

(defun dl-satan-memory-store-test--reset-and-migrate ()
  (let ((dl-satan-memory-migrate-database dl-satan-memory-store-test--db))
    (dl-satan-db-psql
     dl-satan-memory-store-test--db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
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

(defmacro dl-satan-memory-store-test--with-db (&rest body)
  (declare (indent 0))
  `(progn
     (skip-unless (dl-satan-memory-store-test--reachable-p))
     (dl-satan-memory-store-test--reset-and-migrate)
     (let ((dl-satan-memory-store-database
            dl-satan-memory-store-test--db))
       ,@body)))

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-store/trace-id-format ()
  (let* ((id (dl-satan-memory-store-trace-id-new
              "2026-05-19T10:00:00+10:00"
              (lambda () "abc123"))))
    (should (equal id "20260519T100000-abc123"))))

(ert-deftest dl-satan-memory-store/trace-id-random-suffix-length ()
  (let* ((id (dl-satan-memory-store-trace-id-new
              "2026-05-19T10:00:00+10:00")))
    (should (string-match-p "\\`[0-9]\\{8\\}T[0-9]\\{6\\}-[a-z0-9]\\{6\\}\\'" id))))

(ert-deftest dl-satan-memory-store/parse-pg-array-empty ()
  (should (null (dl-satan-db-parse-pg-array nil)))
  (should (null (dl-satan-db-parse-pg-array "")))
  (should (null (dl-satan-db-parse-pg-array "{}"))))

(ert-deftest dl-satan-memory-store/parse-pg-array-simple ()
  (should (equal (dl-satan-db-parse-pg-array "{app:firefox,mode:motd}")
                 '("app:firefox" "mode:motd"))))

(ert-deftest dl-satan-memory-store/format-pg-array ()
  (should (equal (dl-satan-memory-store--format-pg-array
                  '("app:firefox" "mode:motd"))
                 "{app:firefox,mode:motd}")))

;; ---------------------------------------------------------------------
;; Mark + show round trip
;; ---------------------------------------------------------------------

(defun dl-satan-memory-store-test--basic-mark (&optional id)
  (dl-satan-memory-store-mark
   :trace-id (or id "20260519T100000-test01")
   :kind "observation"
   :trace-origin "llm_mark"
   :source "memory_mark@motd"
   :observed-start-at "2026-05-19T09:50:00+10:00"
   :observed-end-at   "2026-05-19T10:00:00+10:00"
   :payload "user pivoted from terminal to docs"
   :valence "neutral"
   :grammar-version 1
   :metadata-json (list :evidence (list :note "fixture"))
   :handles
   (list (list :handle "app:firefox"
               :source (list :rule_id "panopticon.current.app"
                             :origin "observed"))
         (list :handle "surface:browser"
               :source (list :rule_id "panopticon.current.app"
                             :origin "derived"))
         (list :handle "mode:motd"
               :source (list :rule_id "ctx.mode"
                             :origin "ctx")))))

(ert-deftest dl-satan-memory-store/mark-returns-trace-id ()
  (dl-satan-memory-store-test--with-db
   (pcase (dl-satan-memory-store-test--basic-mark)
     (`(ok . ,tid) (should (equal tid "20260519T100000-test01")))
     (err (ert-fail (format "mark failed: %S" err))))))

(ert-deftest dl-satan-memory-store/show-round-trip ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-test--basic-mark)
   (pcase (dl-satan-memory-store-show "20260519T100000-test01")
     (`(ok . ,payload)
      (let* ((trace (plist-get payload :trace))
             (handles (plist-get payload :handles))
             (links (plist-get payload :links))
             (handle-strs (mapcar (lambda (h) (plist-get h :handle)) handles)))
        (should (equal (plist-get trace :id) "20260519T100000-test01"))
        (should (equal (plist-get trace :kind) "observation"))
        (should (equal (plist-get trace :trace_origin) "llm_mark"))
        (should (equal (plist-get trace :payload)
                       "user pivoted from terminal to docs"))
        (should (member "app:firefox" handle-strs))
        (should (member "surface:browser" handle-strs))
        (should (member "mode:motd" handle-strs))
        (should (equal links '()))))
     (err (ert-fail (format "show failed: %S" err))))))

(ert-deftest dl-satan-memory-store/show-missing-trace-id ()
  (dl-satan-memory-store-test--with-db
   (pcase (dl-satan-memory-store-show "20260519T100000-absent")
     (`(ok . nil) t)
     (other (ert-fail (format "expected ok+nil, got %S" other))))))

;; ---------------------------------------------------------------------
;; Resonate
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-store/resonate-empty-cue ()
  (dl-satan-memory-store-test--with-db
   (should (equal (dl-satan-memory-store-resonate :cue-handles nil)
                  (cons 'ok nil)))))

(ert-deftest dl-satan-memory-store/resonate-finds-mark ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-test--basic-mark)
   (pcase (dl-satan-memory-store-resonate :cue-handles '("app:firefox"))
     (`(ok . ,matches)
      (should (= 1 (length matches)))
      (let ((m (car matches)))
        (should (equal (plist-get m :trace_id) "20260519T100000-test01"))
        (should (> (plist-get m :score) 0))
        (should (equal (plist-get m :matched_handles) '("app:firefox")))))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/resonate-returns-payload ()
  "Each match carries the trace's own payload text inline, so the model
recognises the recalled context without a `memory_show_trace' round-trip."
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-test--basic-mark)
   (pcase (dl-satan-memory-store-resonate :cue-handles '("app:firefox"))
     (`(ok . ,matches)
      (let ((m (car matches)))
        (should (equal (plist-get m :payload)
                       "user pivoted from terminal to docs"))))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/resonate-collapses-payload-whitespace ()
  "Payload newlines/tabs collapse to spaces server-side so the inline
payload stays single-line and the tab-split row parser cannot misframe."
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-multi1"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "line one\n\twith tab" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (pcase (dl-satan-memory-store-resonate :cue-handles '("app:firefox"))
     (`(ok . ,matches)
      (should (equal (plist-get (car matches) :payload)
                     "line one  with tab")))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/resonate-orders-by-score ()
  (dl-satan-memory-store-test--with-db
   ;; t1: matches "app:firefox" only (weight 1)
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-low001"
    :kind "observation" :trace-origin "llm_mark" :source "test"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "a" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r1" :origin "observed"))))
   ;; t2: matches "app:firefox" + "artifact:commit" (default weight 3)
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-high01"
    :kind "observation" :trace-origin "llm_mark" :source "test"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "b" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r1" :origin "observed"))
                   (list :handle "artifact:commit"
                         :source (list :rule_id "r2" :origin "derived"))))
   (pcase (dl-satan-memory-store-resonate
           :cue-handles '("app:firefox" "artifact:commit"))
     (`(ok . ,matches)
      (should (= 2 (length matches)))
      (should (equal (plist-get (nth 0 matches) :trace_id)
                     "20260519T100000-high01"))
      (should (> (plist-get (nth 0 matches) :score)
                 (plist-get (nth 1 matches) :score))))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/resonate-respects-limit ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-aaaaa1"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "a" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-aaaaa2"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "b" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (pcase (dl-satan-memory-store-resonate
           :cue-handles '("app:firefox") :limit 1)
     (`(ok . ,matches) (should (= 1 (length matches))))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/resonate-kind-filter ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-obs001"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "a" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-pre001"
    :kind "prediction" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "b" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (pcase (dl-satan-memory-store-resonate
           :cue-handles '("app:firefox") :kinds '("prediction"))
     (`(ok . ,matches)
      (should (= 1 (length matches)))
      (should (equal (plist-get (car matches) :trace_id)
                     "20260519T100000-pre001")))
     (err (ert-fail (format "resonate failed: %S" err))))))

(ert-deftest dl-satan-memory-store/bough-node-zero-weight ()
  "§9.11: zero-weight bough_node handles must not dominate score."
  (dl-satan-memory-store-test--with-db
   ;; t1: matches "bough_node:N1" only (weight 0)
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-bn0001"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "a" :grammar-version 1
    :handles (list (list :handle "bough_node:NANO01"
                         :source (list :rule_id "r" :origin "observed"))))
   ;; t2: matches "mode:motd" (weight 1)
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-mode01"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "b" :grammar-version 1
    :handles (list (list :handle "mode:motd"
                         :source (list :rule_id "r" :origin "ctx"))))
   (pcase (dl-satan-memory-store-resonate
           :cue-handles '("bough_node:NANO01" "mode:motd"))
     (`(ok . ,matches)
      ;; mode:motd trace ranks strictly above bough_node:NANO01 trace
      (let* ((mode-idx (cl-position "20260519T100000-mode01" matches
                                    :key (lambda (m) (plist-get m :trace_id))
                                    :test #'equal))
             (bn-idx (cl-position "20260519T100000-bn0001" matches
                                  :key (lambda (m) (plist-get m :trace_id))
                                  :test #'equal)))
        (should mode-idx)
        ;; t1's score is 0; min-score default is 0 so it's still returned,
        ;; but ordered last.
        (when bn-idx (should (< mode-idx bn-idx)))))
     (err (ert-fail (format "resonate failed: %S" err))))))

;; ---------------------------------------------------------------------
;; Outcome invariant (§9.12) + origin admission (§9.14)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-store/outcome-invariant-rejects ()
  (dl-satan-memory-store-test--with-db
   (let ((result (dl-satan-memory-store-mark
                  :trace-id "20260519T100000-bad001"
                  :kind "outcome"
                  :trace-origin "auto_rule"
                  :source "test"
                  :observed-start-at "2026-05-19T09:50:00+10:00"
                  :observed-end-at   "2026-05-19T10:00:00+10:00"
                  :payload "missing handle"
                  :outcome "returned_to_editing"
                  :grammar-version 1
                  :handles (list (list :handle "mode:motd"
                                       :source (list :rule_id "ctx"))))))
     (should (eq 'error (car result))))))

(ert-deftest dl-satan-memory-store/outcome-invariant-accepts-when-handle-present ()
  (dl-satan-memory-store-test--with-db
   (pcase (dl-satan-memory-store-mark
           :trace-id "20260519T100000-out001"
           :kind "outcome"
           :trace-origin "auto_rule"
           :source "test"
           :observed-start-at "2026-05-19T09:50:00+10:00"
           :observed-end-at   "2026-05-19T10:00:00+10:00"
           :payload "with handle"
           :outcome "returned_to_editing"
           :grammar-version 1
           :handles (list
                     (list :handle "outcome:returned_to_editing"
                           :source (list :rule_id "ctx" :origin "ctx"))
                     (list :handle "mode:motd"
                           :source (list :rule_id "ctx" :origin "ctx"))))
     (`(ok . ,_) t)
     (err (ert-fail (format "expected ok, got %S" err))))))

(ert-deftest dl-satan-memory-store/origin-admission ()
  "§9.14: schema admits trace_origin values auto_rule and external."
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-auto01"
    :kind "observation" :trace-origin "auto_rule" :source "rule"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "auto" :grammar-version 1
    :handles (list (list :handle "mode:motd"
                         :source (list :rule_id "ctx"))))
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-ext001"
    :kind "observation" :trace-origin "external" :source "import"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "ext" :grammar-version 1
    :handles (list (list :handle "mode:motd"
                         :source (list :rule_id "ctx"))))
   (pcase (dl-satan-memory-store-resonate :cue-handles '("mode:motd"))
     (`(ok . ,matches)
      (should (= 2 (length matches))))
     (err (ert-fail (format "resonate failed: %S" err))))))

;; ---------------------------------------------------------------------
;; Links
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-store/links-round-trip ()
  (dl-satan-memory-store-test--with-db
   ;; predecessor trace
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-pred01"
    :kind "prediction" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "p" :grammar-version 1
    :handles (list (list :handle "mode:motd"
                         :source (list :rule_id "ctx"))))
   ;; outcome that supports the prediction
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-link01"
    :kind "outcome" :trace-origin "auto_rule" :source "t"
    :observed-start-at "2026-05-19T09:55:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "o" :grammar-version 1
    :outcome "returned_to_editing"
    :handles (list (list :handle "outcome:returned_to_editing"
                         :source (list :rule_id "ctx")))
    :links (list (list :relation "supports"
                       :target_trace_id "20260519T100000-pred01")))
   (pcase (dl-satan-memory-store-show "20260519T100000-link01")
     (`(ok . ,payload)
      (let ((links (plist-get payload :links)))
        (should (= 1 (length links)))
        (should (equal (plist-get (car links) :relation) "supports"))
        (should (equal (plist-get (car links) :target_trace_id)
                       "20260519T100000-pred01"))))
     (err (ert-fail (format "show failed: %S" err))))))

;; ---------------------------------------------------------------------
;; Recent
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-memory-store/recent-empty ()
  (dl-satan-memory-store-test--with-db
   (should (equal (dl-satan-memory-store-recent) (cons 'ok nil)))))

(ert-deftest dl-satan-memory-store/recent-orders-newest-first ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-old001"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "first line\nsecond line" :valence "neutral" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (dl-satan-memory-store-mark
    :trace-id "20260519T110000-new001"
    :kind "intervention" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T10:50:00+10:00"
    :observed-end-at   "2026-05-19T11:00:00+10:00"
    :payload "second trace" :valence "positive" :grammar-version 1
    :handles (list (list :handle "app:emacs"
                         :source (list :rule_id "r" :origin "observed"))
                   (list :handle "mode:motd"
                         :source (list :rule_id "ctx" :origin "ctx"))))
   (pcase (dl-satan-memory-store-recent)
     (`(ok . ,rows)
      (should (= 2 (length rows)))
      (let ((newest (nth 0 rows))
            (oldest (nth 1 rows)))
        (should (equal (plist-get newest :trace_id) "20260519T110000-new001"))
        (should (equal (plist-get newest :kind) "intervention"))
        (should (equal (plist-get newest :valence) "positive"))
        (should (equal (plist-get newest :payload) "second trace"))
        (should (member "app:emacs" (plist-get newest :handles)))
        (should (member "mode:motd" (plist-get newest :handles)))
        (should (equal (plist-get oldest :trace_id) "20260519T100000-old001"))
        (should (equal (plist-get oldest :valence) "neutral"))
        ;; newline collapsed to space so tab-parser stays single-line
        (should (equal (plist-get oldest :payload) "first line second line"))))
     (err (ert-fail (format "recent failed: %S" err))))))

(ert-deftest dl-satan-memory-store/recent-respects-limit ()
  (dl-satan-memory-store-test--with-db
   (dotimes (i 3)
     (dl-satan-memory-store-mark
      :trace-id (format "20260519T1000%02d-rec%03d" i i)
      :kind "observation" :trace-origin "llm_mark" :source "t"
      :observed-start-at (format "2026-05-19T09:50:%02d+10:00" i)
      :observed-end-at   (format "2026-05-19T10:00:%02d+10:00" i)
      :payload (format "trace %d" i) :grammar-version 1
      :handles (list (list :handle "app:firefox"
                           :source (list :rule_id "r" :origin "observed")))))
   (pcase (dl-satan-memory-store-recent :limit 2)
     (`(ok . ,rows) (should (= 2 (length rows))))
     (err (ert-fail (format "recent failed: %S" err))))))

(ert-deftest dl-satan-memory-store/recent-kind-filter ()
  (dl-satan-memory-store-test--with-db
   (dl-satan-memory-store-mark
    :trace-id "20260519T100000-obs001"
    :kind "observation" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:00:00+10:00"
    :payload "o" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (dl-satan-memory-store-mark
    :trace-id "20260519T100100-int001"
    :kind "intervention" :trace-origin "llm_mark" :source "t"
    :observed-start-at "2026-05-19T09:50:00+10:00"
    :observed-end-at   "2026-05-19T10:01:00+10:00"
    :payload "i" :grammar-version 1
    :handles (list (list :handle "app:firefox"
                         :source (list :rule_id "r" :origin "observed"))))
   (pcase (dl-satan-memory-store-recent :kinds '("intervention"))
     (`(ok . ,rows)
      (should (= 1 (length rows)))
      (should (equal (plist-get (car rows) :kind) "intervention")))
     (err (ert-fail (format "recent failed: %S" err))))))

(ert-deftest dl-satan-memory-store/recent-returns-full-payload ()
  "Payload > 200 chars must round-trip unhewn — the tank wraps in elisp,
so SQL must not LEFT()-truncate."
  (dl-satan-memory-store-test--with-db
   (let ((long (make-string 400 ?x)))
     (dl-satan-memory-store-mark
      :trace-id "20260519T120000-long01"
      :kind "observation" :trace-origin "llm_mark" :source "t"
      :observed-start-at "2026-05-19T11:50:00+10:00"
      :observed-end-at   "2026-05-19T12:00:00+10:00"
      :payload long :grammar-version 1
      :handles (list (list :handle "app:firefox"
                           :source (list :rule_id "r" :origin "observed"))))
     (pcase (dl-satan-memory-store-recent :limit 1)
       (`(ok . ,rows)
        (should (= 400 (length (plist-get (car rows) :payload))))
        (should (equal long (plist-get (car rows) :payload))))
       (err (ert-fail (format "recent failed: %S" err)))))))

(provide 'dl-satan-memory-store-test)
;;; dl-satan-memory-store-test.el ends here
