;;; dl-satan-audit-attribute-test.el --- attribute audit-event validator -*- lexical-binding: t; -*-

;; T-attr-1b broker side — validator for `attribute.delta_applied'
;; defined in docs/satan/attributes/design-contract.md §5.1.  The
;; satan-attrd daemon writes the event row + RPCs the event back to
;; the broker for transcript write; this validator gates the
;; transcript-write boundary (see contract §17.4).  No callers yet;
;; this file exercises the validator in isolation.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-audit-attribute-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-audit)

(defconst dl-satan-audit-attr-test--run-id
  "20260523T120000-morning-deadbe")

(defconst dl-satan-audit-attr-test--iv-id
  "20260523T120000-morning-deadbe.iv01")

(defconst dl-satan-audit-attr-test--event-id
  "20260523T120000-morning-deadbe.attr007")

(defun dl-satan-audit-attr-test--delta-applied (&rest overrides)
  "Build a baseline `attribute.delta_applied' payload, applying plist OVERRIDES.

Defaults model the canonical `outcome=contradicted, confidence=medium'
case from contract §5 example: shame ramps from 0.10 to 0.25 (delta
0.15), no caps, not disabled."
  (let ((base
         (list :id           dl-satan-audit-attr-test--event-id
               :scope        "global"
               :name         "shame"
               :old          0.10
               :new          0.25
               :delta        0.15
               :source       "outcome"
               :reason       "contradicted"
               :evidence     (list :intervention_id dl-satan-audit-attr-test--iv-id
                                   :classification  "contradicted"
                                   :confidence      "medium")
               :caps_applied '()
               :disabled     :false)))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

;; ---------- Happy paths ----------

(ert-deftest dl-satan-audit-attribute/accepts-canonical-contradicted ()
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied))))

(ert-deftest dl-satan-audit-attribute/accepts-worked-with-tiny-shame-delta ()
  ;; -0.025 base contract exception; old=0.10 → new=0.075.
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied
     :name "shame" :old 0.10 :new 0.075 :delta -0.025
     :reason "worked"
     :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                     :classification "worked" :confidence "medium")))))

(ert-deftest dl-satan-audit-attribute/accepts-each-outcome-reason ()
  (dolist (reason '("worked" "neutral" "ignored" "contradicted" "harmful"))
    (should-not
     (dl-satan-audit-validate-attribute-event
      "attribute.delta_applied"
      (dl-satan-audit-attr-test--delta-applied
       :reason reason
       :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                       :classification reason
                       :confidence "medium"))))))

(ert-deftest dl-satan-audit-attribute/accepts-each-attribute-name ()
  (dolist (name '("curiosity" "hunger" "suspicion" "doubt"
                  "friction" "shame" "brooding" "metamorphosis"))
    (should-not
     (dl-satan-audit-validate-attribute-event
      "attribute.delta_applied"
      (dl-satan-audit-attr-test--delta-applied :name name)))))

(ert-deftest dl-satan-audit-attribute/accepts-disabled-true ()
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied :disabled t))))

(ert-deftest dl-satan-audit-attribute/accepts-caps-applied ()
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied
     :caps_applied '("range_clamp"))))
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied
     :caps_applied '("friction_cap" "range_clamp")))))

;; ---------- Closed-set rejection ----------

(ert-deftest dl-satan-audit-attribute/rejects-unknown-event ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.something_else"
              (dl-satan-audit-attr-test--delta-applied))))
    (should (stringp err))
    (should (string-match-p "unknown attribute event" err))))

(ert-deftest dl-satan-audit-attribute/rejects-unknown-source ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :source "telepathy"))))
    (should (stringp err))
    (should (string-match-p "unknown source" err))))

(ert-deftest dl-satan-audit-attribute/rejects-reserved-unimplemented-source ()
  ;; `hippocampus' + `sensor' moved to the implemented set in T-attr-1e
  ;; (commits in `~/dev/satan-attrd`); only the remaining four are still
  ;; reserved-but-unimplemented at the broker validator.
  (dolist (src '("percept" "resonance" "tool_error" "manual"))
    (let ((err (dl-satan-audit-validate-attribute-event
                "attribute.delta_applied"
                (dl-satan-audit-attr-test--delta-applied :source src))))
      (should (stringp err))
      (should (string-match-p "reserved but unimplemented" err)))))

(ert-deftest dl-satan-audit-attribute/rejects-unknown-attribute-name ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :name "rage"))))
    (should (stringp err))
    (should (string-match-p "field name must be one of" err))))

(ert-deftest dl-satan-audit-attribute/rejects-unknown-scope ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :scope "episode"))))
    (should (stringp err))
    (should (string-match-p "field scope must be one of" err))))

(ert-deftest dl-satan-audit-attribute/rejects-bad-source-reason-pairing ()
  ;; "shame" is not a valid reason for source=outcome.
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :reason "shame"))))
    (should (stringp err))
    (should (string-match-p "not valid for source=" err))))

(ert-deftest dl-satan-audit-attribute/rejects-unknown-cap-name ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :caps_applied '("range_clamp" "telepathy_cap")))))
    (should (stringp err))
    (should (string-match-p "caps_applied" err))
    (should (string-match-p "not in closed set" err))))

;; ---------- Range + coherence ----------

(ert-deftest dl-satan-audit-attribute/rejects-old-out-of-range ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :old 1.2 :new 0.25 :delta -0.95))))
    (should (stringp err))
    (should (string-match-p "field old must be in \\[0, 1\\]" err))))

(ert-deftest dl-satan-audit-attribute/rejects-new-out-of-range ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :old 0.10 :new -0.05 :delta -0.15))))
    (should (stringp err))
    (should (string-match-p "field new must be in \\[0, 1\\]" err))))

(ert-deftest dl-satan-audit-attribute/rejects-delta-mismatch ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :old 0.10 :new 0.25 :delta 0.50))))
    (should (stringp err))
    (should (string-match-p "delta .* does not match new - old" err))))

(ert-deftest dl-satan-audit-attribute/accepts-delta-with-float-epsilon ()
  ;; Float round-trip via DOUBLE PRECISION shouldn't be a rejection trigger.
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--delta-applied
     :old 0.10 :new 0.30 :delta 0.20000000000000001))))

;; ---------- Required-key enforcement ----------

(ert-deftest dl-satan-audit-attribute/rejects-missing-id ()
  (let* ((payload (dl-satan-audit-attr-test--delta-applied))
         (without-id (cl-loop for (k v) on payload by #'cddr
                              unless (eq k :id)
                              append (list k v)))
         (err (dl-satan-audit-validate-attribute-event
               "attribute.delta_applied" without-id)))
    (should (stringp err))
    (should (string-match-p "missing required field: id" err))))

(ert-deftest dl-satan-audit-attribute/rejects-missing-disabled ()
  (let* ((payload (dl-satan-audit-attr-test--delta-applied))
         (without-disabled (cl-loop for (k v) on payload by #'cddr
                                    unless (eq k :disabled)
                                    append (list k v)))
         (err (dl-satan-audit-validate-attribute-event
               "attribute.delta_applied" without-disabled)))
    (should (stringp err))
    (should (string-match-p "missing required field: disabled" err))))

(ert-deftest dl-satan-audit-attribute/rejects-missing-evidence-confidence ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                               :classification "contradicted")))))
    (should (stringp err))
    (should (string-match-p "missing required field: confidence" err))))

(ert-deftest dl-satan-audit-attribute/rejects-missing-evidence-intervention-id ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :evidence (list :classification "contradicted"
                               :confidence "medium")))))
    (should (stringp err))
    (should (string-match-p "missing required field: intervention_id" err))))

(ert-deftest dl-satan-audit-attribute/rejects-missing-evidence-classification ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                               :confidence "medium")))))
    (should (stringp err))
    (should (string-match-p "missing required field: classification" err))))

(ert-deftest dl-satan-audit-attribute/rejects-bad-evidence-confidence ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                               :classification "contradicted"
                               :confidence "very-high")))))
    (should (stringp err))
    (should (string-match-p "field confidence must be one of" err))))

(ert-deftest dl-satan-audit-attribute/rejects-bad-evidence-classification ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied
               :evidence (list :intervention_id dl-satan-audit-attr-test--iv-id
                               :classification "miraculous"
                               :confidence "medium")))))
    (should (stringp err))
    (should (string-match-p "field classification must be one of" err))))

(ert-deftest dl-satan-audit-attribute/rejects-bad-disabled-type ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :disabled "no"))))
    (should (stringp err))
    (should (string-match-p "field disabled must be boolean" err))))

(ert-deftest dl-satan-audit-attribute/rejects-non-array-caps-applied ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--delta-applied :caps_applied "range_clamp"))))
    (should (stringp err))
    (should (string-match-p "field caps_applied must be array" err))))

;; ---------- Hippocampus source (§6H) ----------

(defun dl-satan-audit-attr-test--hippocampus-delta (&rest overrides)
  "Build a baseline `attribute.delta_applied' payload for source=hippocampus.
Defaults model `reason=written' reducing brooding by 0.025."
  (let ((base
         (list :id           dl-satan-audit-attr-test--event-id
               :scope        "global"
               :name         "brooding"
               :old          0.50
               :new          0.475
               :delta        -0.025
               :source       "hippocampus"
               :reason       "written"
               :evidence     (list :tool_name "hippocampus_write"
                                   :filename "20260524T100000--test__satan_hippocampus.org")
               :caps_applied '()
               :disabled     :false)))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(ert-deftest dl-satan-audit-attribute/accepts-hippocampus-written ()
  (should-not
   (dl-satan-audit-validate-attribute-event
    "attribute.delta_applied"
    (dl-satan-audit-attr-test--hippocampus-delta))))

(ert-deftest dl-satan-audit-attribute/accepts-each-hippocampus-reason ()
  (dolist (reason '("written" "overwritten" "deleted" "renamed" "searched"))
    (should-not
     (dl-satan-audit-validate-attribute-event
      "attribute.delta_applied"
      (dl-satan-audit-attr-test--hippocampus-delta :reason reason)))))

(ert-deftest dl-satan-audit-attribute/rejects-unknown-hippocampus-reason ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--hippocampus-delta :reason "pondered"))))
    (should (stringp err))
    (should (string-match-p "not valid for source=" err))))

(ert-deftest dl-satan-audit-attribute/rejects-hippocampus-missing-tool-name ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--hippocampus-delta
               :evidence (list :filename "test.org")))))
    (should (stringp err))
    (should (string-match-p "missing required field: tool_name" err))))

(ert-deftest dl-satan-audit-attribute/rejects-hippocampus-missing-filename ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--hippocampus-delta
               :evidence (list :tool_name "hippocampus_write")))))
    (should (stringp err))
    (should (string-match-p "missing required field: filename" err))))

(ert-deftest dl-satan-audit-attribute/rejects-outcome-reason-for-hippocampus ()
  (let ((err (dl-satan-audit-validate-attribute-event
              "attribute.delta_applied"
              (dl-satan-audit-attr-test--hippocampus-delta :reason "worked"))))
    (should (stringp err))
    (should (string-match-p "not valid for source=" err))))

(provide 'dl-satan-audit-attribute-test)
;;; dl-satan-audit-attribute-test.el ends here
