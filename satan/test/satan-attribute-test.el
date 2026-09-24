;;; satan-attribute-test.el --- broker attribute enqueue + payload -*- lexical-binding: t; -*-

;; T-attr-1c slice 2 — pure-function tests for the broker → daemon
;; outcome payload builder.  Database-touching tests live in
;; `satan-attribute-listener-test.el' (which mocks psql).
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-attribute-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-attribute)

(defmacro satan-attribute-test--with-updates-enabled (value &rest body)
  "Eval BODY with `satan-attribute-updates-enabled' bound to VALUE."
  (declare (indent 1))
  `(let ((satan-attribute-updates-enabled ,value))
     ,@body))

;; ---------------------------------------------------------------------
;; build-outcome-payload — shape
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute/build-payload-first-emit ()
  (satan-attribute-test--with-updates-enabled t
    (let ((p (satan-attribute-build-outcome-payload
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

(ert-deftest satan-attribute/build-payload-revision-carries-pointer ()
  (let ((p (satan-attribute-build-outcome-payload
            :run-id "r1" :ts "2026-05-24T12:01:00Z"
            :intervention-id "r1.iv001"
            :classification "worked"
            :confidence "high"
            :is-revision t
            :revises "intervention.outcome_classified")))
    (should (eq t (plist-get p :is_revision)))
    (should (equal "intervention.outcome_classified"
                   (plist-get p :revises)))))

(ert-deftest satan-attribute/build-payload-disabled-flag-stamped ()
  (satan-attribute-test--with-updates-enabled nil
    (let ((p (satan-attribute-build-outcome-payload
              :run-id "r1" :ts "2026-05-24T12:00:00Z"
              :intervention-id "r1.iv001"
              :classification "neutral"
              :confidence "low")))
      (should (eq :false (plist-get p :enabled))))))

(ert-deftest satan-attribute/build-payload-defaults-empty-cue ()
  ;; cue-handles + related-trace-ids omitted → empty lists, not nil/null.
  (let* ((p (satan-attribute-build-outcome-payload
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

(defun satan-attribute-test--roundtrip-json (payload)
  "Serialise PAYLOAD the wire way (`satan-jsonl-prepare' + `json-serialize'),
then parse it back into a plist — attrd's-eye view of what the broker sent.
Shared by every payload-builder round-trip test in this file."
  (json-parse-string (json-serialize (satan-jsonl-prepare payload))
                      :object-type 'plist
                      :array-type 'list
                      :null-object nil
                      :false-object :false))

(ert-deftest satan-attribute/payload-round-trips-through-json ()
  (let* ((p (satan-attribute-build-outcome-payload
             :run-id "r1" :ts "2026-05-24T12:00:00Z"
             :intervention-id "r1.iv001"
             :classification "harmful"
             :confidence "high"
             :intervention-kind "notify"
             :related-motive-id "m42"
             :cue-handles '("focus:sway:firefox")
             :is-revision t :revises "prior"))
         (parsed (satan-attribute-test--roundtrip-json p)))
    (should (equal "1.0" (plist-get parsed :schema_version)))
    (should (equal "r1.iv001" (plist-get parsed :intervention_id)))
    (should (equal "harmful" (plist-get parsed :classification)))
    (should (eq t (plist-get parsed :is_revision)))
    (should (equal "prior" (plist-get parsed :revises)))
    (should (equal "m42" (plist-get (plist-get parsed :evidence)
                                    :related_motive_id)))))

;; ---------------------------------------------------------------------
;; build-ask-payload — thin wrapper over build-sensor-payload (VT-37)
;; ---------------------------------------------------------------------

(defun satan-attribute-test--attrd-sensor-contract-errors (parsed)
  "Return the list of ways PARSED violates attrd's sensor payload contract
\(mirrors `parse_sensor_payload', satan-attrd `src/run_loop.rs:298').
Empty list means PARSED would be accepted."
  (let (errs)
    (dolist (key '(:run_id :ts :reason :sensor_type :metric_unit))
      (unless (stringp (plist-get parsed key))
        (push (format "%s must be a string" key) errs)))
    (unless (numberp (plist-get parsed :metric_value))
      (push "metric_value must be a number" errs))
    (unless (memq (plist-get parsed :enabled) '(t :false))
      (push "enabled must be a boolean (t or :false)" errs))
    (nreverse errs)))

(ert-deftest satan-attribute/build-ask-payload-meets-attrd-sensor-contract ()
  (dolist (reason '("ask_suppressed" "ask_uncorrelated"))
    (let* ((p (satan-attribute-build-ask-payload
               :run-id "r1" :ts "2026-09-24T12:00:00Z" :reason reason))
           (parsed (satan-attribute-test--roundtrip-json p)))
      (should (equal '() (satan-attribute-test--attrd-sensor-contract-errors parsed)))
      (should (equal "sensor" (plist-get parsed :source)))
      (should (equal reason (plist-get parsed :reason)))
      (should (eq :false (plist-get parsed :is_revision))))))

(ert-deftest satan-attribute/build-ask-payload-fixes-sensor-fields ()
  (let ((p (satan-attribute-build-ask-payload
            :run-id "r1" :ts "2026-09-24T12:00:00Z" :reason "ask_suppressed")))
    (should (equal "goad_ask" (plist-get p :sensor_type)))
    (should (equal 0 (plist-get p :metric_value)))
    (should (equal "correlating_motives" (plist-get p :metric_unit)))))

(ert-deftest satan-attribute/build-ask-payload-rejects-unknown-reason ()
  (should-error
   (satan-attribute-build-ask-payload
    :run-id "r1" :ts "2026-09-24T12:00:00Z" :reason "clairvoyance")))

;; ---------------------------------------------------------------------
;; --prep-value normalisation
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute/prep-value-null-list-symbol ()
  ;; satan-jsonl-prepare passes nil/t/:null/:false through;
  ;; json-serialize handles them correctly.
  (should (eq nil (satan-jsonl-prepare nil)))
  ;; Plist → object-shaped plist (preserved).
  (let ((p (satan-jsonl-prepare '(:a 1 :b nil))))
    (should (equal 1 (plist-get p :a)))
    (should (eq nil (plist-get p :b))))
  ;; List → vector.
  (should (equal [1 2 3] (satan-jsonl-prepare '(1 2 3))))
  ;; Symbol → string.
  (should (equal "foo" (satan-jsonl-prepare 'foo))))

;; ---------------------------------------------------------------------
;; satan_attribute_settings write surface (T-attr-2d Q7=A)
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute/write-enabled-setting-binds-true ()
  ;; `--write-enabled-setting' should bind JSON `true' on a t input,
  ;; `false' on nil — verified by intercepting `--query'.
  (let (captured-sql captured-vars)
    (cl-letf (((symbol-function 'satan-db-query)
               (lambda (_db _host _program sql vars)
                 (setq captured-sql sql captured-vars vars)
                 '(ok . ""))))
      (satan-attribute--write-enabled-setting t)
      (should (string-match-p "satan_attribute_settings" captured-sql))
      (should (string-match-p "ON CONFLICT (name) DO UPDATE" captured-sql))
      (should (equal "true" (cdr (assoc "value" captured-vars))))
      (satan-attribute--write-enabled-setting nil)
      (should (equal "false" (cdr (assoc "value" captured-vars)))))))

(ert-deftest satan-attribute/on-enabled-change-only-fires-on-set ()
  ;; The watcher must ignore non-`set' operations (e.g. `let' bindings).
  (let (called)
    (cl-letf (((symbol-function 'satan-attribute--write-enabled-setting)
               (lambda (val &optional _db) (setq called val) '(ok . ""))))
      (satan-attribute--on-enabled-change
       'satan-attribute-updates-enabled nil 'let nil)
      (should (eq called nil))     ; sentinel untouched
      (satan-attribute--on-enabled-change
       'satan-attribute-updates-enabled t 'set nil)
      (should (eq called t))
      (satan-attribute--on-enabled-change
       'satan-attribute-updates-enabled nil 'set nil)
      (should (eq called nil)))))

(ert-deftest satan-attribute/on-enabled-change-swallows-errors ()
  ;; A DB write failure must not propagate out of the watcher — that
  ;; would block `customize-set-value'.
  (cl-letf (((symbol-function 'satan-attribute--write-enabled-setting)
             (lambda (_val &optional _db) (error "psql exit 1"))))
    ;; should NOT signal
    (satan-attribute--on-enabled-change
     'satan-attribute-updates-enabled t 'set nil)
    (should t)))

;; ---------------------------------------------------------------------
;; PRESERVED-BOUNDARY PIN — SL-002 §5.3 / §9.  Do not prune with the bough
;; integration: this asserts the *preserved* content-agnostic substrate.
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute/outcome-payload-forwards-bough-cue-handles ()
  "Outcome forwarding copies a bough-bearing intervention's cue handles verbatim.
The payload builder is content-agnostic: it neither derives nor filters
bough handles.  Removing the bough integration removes derivation, not
this copy (RN-9/RN-11) — historical bough-attributed interventions keep
reaching the attribute daemon intact until OQ-3 scrubs the vocabulary."
  (satan-attribute-test--with-updates-enabled t
    (let ((p (satan-attribute-build-outcome-payload
              :run-id "r9" :ts "2026-05-24T12:00:00Z"
              :intervention-id "r9.iv001"
              :classification "worked"
              :confidence "high"
              :intervention-kind "notify"
              :cue-handles '("app:emacs" "bough_node:abc" "bough_project:def")
              :related-trace-ids '("t9")
              :is-revision nil
              :revises nil)))
      (should (equal '("app:emacs" "bough_node:abc" "bough_project:def")
                     (plist-get (plist-get p :evidence) :cue_handles))))))

(provide 'satan-attribute-test)
;;; satan-attribute-test.el ends here
