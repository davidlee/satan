;;; dl-satan-attribute-test.el --- broker attribute enqueue + payload -*- lexical-binding: t; -*-

;; T-attr-1c slice 2 — pure-function tests for the broker → daemon
;; outcome payload builder.  Database-touching tests live in
;; `dl-satan-attribute-listener-test.el' (which mocks psql).
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-attribute-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-attribute)

(defmacro dl-satan-attribute-test--with-updates-enabled (value &rest body)
  "Eval BODY with `dl-satan-attribute-updates-enabled' bound to VALUE."
  (declare (indent 1))
  `(let ((dl-satan-attribute-updates-enabled ,value))
     ,@body))

;; ---------------------------------------------------------------------
;; build-outcome-payload — shape
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-attribute/build-payload-first-emit ()
  (dl-satan-attribute-test--with-updates-enabled t
    (let ((p (dl-satan-attribute-build-outcome-payload
              :run-id "r1" :ts "2026-05-24T12:00:00Z"
              :intervention-id "r1.iv001"
              :classification "contradicted"
              :confidence "medium"
              :intervention-kind "ask"
              :cue-handles '("focus:tab-loss")
              :related-trace-ids '("t1")
              :is-revision nil
              :revises nil)))
      (should (equal "1.0" (plist-get p :schema_version)))
      (should (equal "r1" (plist-get p :run_id)))
      (should (equal "r1.iv001" (plist-get p :intervention_id)))
      (should (equal "contradicted" (plist-get p :classification)))
      (should (equal "medium" (plist-get p :confidence)))
      (should (eq :false (plist-get p :is_revision)))
      (should (eq :null (plist-get p :revises)))
      (should (eq t (plist-get p :enabled)))
      (let ((ev (plist-get p :evidence)))
        (should (equal "ask" (plist-get ev :intervention_kind)))
        (should (eq :null (plist-get ev :related_motive_id)))
        (should (equal '("focus:tab-loss") (plist-get ev :cue_handles)))
        (should (equal '("t1") (plist-get ev :related_trace_ids)))))))

(ert-deftest dl-satan-attribute/build-payload-revision-carries-pointer ()
  (let ((p (dl-satan-attribute-build-outcome-payload
            :run-id "r1" :ts "2026-05-24T12:01:00Z"
            :intervention-id "r1.iv001"
            :classification "worked"
            :confidence "high"
            :is-revision t
            :revises "intervention.outcome_classified")))
    (should (eq t (plist-get p :is_revision)))
    (should (equal "intervention.outcome_classified"
                   (plist-get p :revises)))))

(ert-deftest dl-satan-attribute/build-payload-disabled-flag-stamped ()
  (dl-satan-attribute-test--with-updates-enabled nil
    (let ((p (dl-satan-attribute-build-outcome-payload
              :run-id "r1" :ts "2026-05-24T12:00:00Z"
              :intervention-id "r1.iv001"
              :classification "neutral"
              :confidence "low")))
      (should (eq :false (plist-get p :enabled))))))

(ert-deftest dl-satan-attribute/build-payload-defaults-empty-cue ()
  ;; cue-handles + related-trace-ids omitted → empty lists, not nil/null.
  (let* ((p (dl-satan-attribute-build-outcome-payload
             :run-id "r1" :ts "2026-05-24T12:00:00Z"
             :intervention-id "r1.iv001"
             :classification "ignored"
             :confidence "low"))
         (ev (plist-get p :evidence)))
    (should (equal '() (plist-get ev :cue_handles)))
    (should (equal '() (plist-get ev :related_trace_ids)))))

;; ---------------------------------------------------------------------
;; JSON serialisation round-trip
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-attribute/payload-round-trips-through-json ()
  (let* ((p (dl-satan-attribute-build-outcome-payload
             :run-id "r1" :ts "2026-05-24T12:00:00Z"
             :intervention-id "r1.iv001"
             :classification "harmful"
             :confidence "high"
             :intervention-kind "notify"
             :related-motive-id "m42"
             :cue-handles '("focus:sway:firefox")
             :is-revision t :revises "prior"))
         (json (json-serialize (dl-satan-jsonl-prepare p)))
         (parsed (json-parse-string json
                                    :object-type 'plist
                                    :array-type 'list
                                    :null-object nil
                                    :false-object :false)))
    (should (equal "1.0" (plist-get parsed :schema_version)))
    (should (equal "r1.iv001" (plist-get parsed :intervention_id)))
    (should (equal "harmful" (plist-get parsed :classification)))
    (should (eq t (plist-get parsed :is_revision)))
    (should (equal "prior" (plist-get parsed :revises)))
    (should (equal "m42" (plist-get (plist-get parsed :evidence)
                                    :related_motive_id)))))

;; ---------------------------------------------------------------------
;; --prep-value normalisation
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-attribute/prep-value-null-list-symbol ()
  ;; dl-satan-jsonl-prepare passes nil/t/:null/:false through;
  ;; json-serialize handles them correctly.
  (should (eq nil (dl-satan-jsonl-prepare nil)))
  ;; Plist → object-shaped plist (preserved).
  (let ((p (dl-satan-jsonl-prepare '(:a 1 :b nil))))
    (should (equal 1 (plist-get p :a)))
    (should (eq nil (plist-get p :b))))
  ;; List → vector.
  (should (equal [1 2 3] (dl-satan-jsonl-prepare '(1 2 3))))
  ;; Symbol → string.
  (should (equal "foo" (dl-satan-jsonl-prepare 'foo))))

;; ---------------------------------------------------------------------
;; satan_attribute_settings write surface (T-attr-2d Q7=A)
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-attribute/write-enabled-setting-binds-true ()
  ;; `--write-enabled-setting' should bind JSON `true' on a t input,
  ;; `false' on nil — verified by intercepting `--query'.
  (let (captured-sql captured-vars)
    (cl-letf (((symbol-function 'dl-satan-db-query)
               (lambda (_db _host _program sql vars)
                 (setq captured-sql sql captured-vars vars)
                 '(ok . ""))))
      (dl-satan-attribute--write-enabled-setting t)
      (should (string-match-p "satan_attribute_settings" captured-sql))
      (should (string-match-p "ON CONFLICT (name) DO UPDATE" captured-sql))
      (should (equal "true" (cdr (assoc "value" captured-vars))))
      (dl-satan-attribute--write-enabled-setting nil)
      (should (equal "false" (cdr (assoc "value" captured-vars)))))))

(ert-deftest dl-satan-attribute/on-enabled-change-only-fires-on-set ()
  ;; The watcher must ignore non-`set' operations (e.g. `let' bindings).
  (let (called)
    (cl-letf (((symbol-function 'dl-satan-attribute--write-enabled-setting)
               (lambda (val &optional _db) (setq called val) '(ok . ""))))
      (dl-satan-attribute--on-enabled-change
       'dl-satan-attribute-updates-enabled nil 'let nil)
      (should (eq called nil))     ; sentinel untouched
      (dl-satan-attribute--on-enabled-change
       'dl-satan-attribute-updates-enabled t 'set nil)
      (should (eq called t))
      (dl-satan-attribute--on-enabled-change
       'dl-satan-attribute-updates-enabled nil 'set nil)
      (should (eq called nil)))))

(ert-deftest dl-satan-attribute/on-enabled-change-swallows-errors ()
  ;; A DB write failure must not propagate out of the watcher — that
  ;; would block `customize-set-value'.
  (cl-letf (((symbol-function 'dl-satan-attribute--write-enabled-setting)
             (lambda (_val &optional _db) (error "psql exit 1"))))
    ;; should NOT signal
    (dl-satan-attribute--on-enabled-change
     'dl-satan-attribute-updates-enabled t 'set nil)
    (should t)))

(provide 'dl-satan-attribute-test)
;;; dl-satan-attribute-test.el ends here
