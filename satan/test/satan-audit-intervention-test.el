;;; satan-audit-intervention-test.el --- intervention audit-event validator -*- lexical-binding: t; -*-

;; T7 PR 1 — validator for the three intervention audit-event kinds
;; defined in docs/satan/attributes/outcome-semantics.md §9.  No
;; callers yet; this file exercises the validator in isolation.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-audit-intervention-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-audit)

(defconst satan-audit-iv-test--run-id
  "20260523T120000-morning-deadbe")

(defconst satan-audit-iv-test--iv-id
  "20260523T120000-morning-deadbe.iv01")

(defconst satan-audit-iv-test--iv-id-2
  "20260523T120000-morning-deadbe.iv02")

(defun satan-audit-iv-test--created (&rest overrides)
  "Build a baseline `intervention.created' payload, applying plist OVERRIDES."
  (let ((base
         (list :intervention_id       satan-audit-iv-test--iv-id
               :run_id                satan-audit-iv-test--run-id
               :ts                    "2026-05-23T12:00:00+1000"
               :mode                  "morning"
               :kind                  "notify"
               :target_surface        "sway-mainbar"
               :message               "kanban needs DONE update"
               :related_motive_id     "morning.kanban-cleanup"
               :cue_handles           '("bough_node:abc" "bough_project:def")
               :percept_handles       '("app:emacs")
               :expected_outcome      "user opens kanban.org and updates DONE column"
               :outcome_window_minutes 30
               :severity              "low")))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(defun satan-audit-iv-test--classified (&rest overrides)
  "Build a baseline `intervention.outcome_classified' payload."
  (let ((base
         (list :intervention_id  satan-audit-iv-test--iv-id
               :classification   "worked"
               :confidence       "medium"
               :evidence         '(:source-events ()
                                   :predicates ("editor_edit_in_window")
                                   :motive-id "morning.kanban-cleanup"
                                   :handle-overlap 3)
               :maturity         "mature"
               :next_revisit_at  "2026-05-23T12:30:00+1000"
               :source           "auto"
               :classified_at    "2026-05-23T12:30:01+1000")))
    (while overrides
      (setq base (plist-put base (pop overrides) (pop overrides))))
    base))

(defun satan-audit-iv-test--revised (&rest overrides)
  "Build a baseline `intervention.outcome_revised' payload."
  (let ((base (apply #'satan-audit-iv-test--classified
                     :revises satan-audit-iv-test--iv-id
                     overrides)))
    base))

(defun satan-audit-iv-test--ids-with (&rest ids)
  "Return a hash-table populated with IDS."
  (let ((h (make-hash-table :test 'equal)))
    (dolist (id ids) (puthash id t h))
    h))


;;; --- valid payloads --------------------------------------------------

(ert-deftest satan-audit-iv/created-minimal-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.created"
    (satan-audit-iv-test--created)
    (make-hash-table :test 'equal))))

(ert-deftest satan-audit-iv/created-null-related-motive-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.created"
    (satan-audit-iv-test--created :related_motive_id :null)
    (make-hash-table :test 'equal))))

(ert-deftest satan-audit-iv/created-empty-cue-handles-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.created"
    (satan-audit-iv-test--created :cue_handles nil)
    (make-hash-table :test 'equal))))

(ert-deftest satan-audit-iv/created-all-kinds-ok ()
  (dolist (kind satan-audit-intervention-kinds)
    (should-not
     (satan-audit-validate-intervention-event
      "intervention.created"
      (satan-audit-iv-test--created :kind kind)
      (make-hash-table :test 'equal)))))

(ert-deftest satan-audit-iv/classified-worked-auto-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.outcome_classified"
    (satan-audit-iv-test--classified)
    (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))

(ert-deftest satan-audit-iv/classified-pending-unknown-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.outcome_classified"
    (satan-audit-iv-test--classified
     :maturity "pending" :classification "unknown" :confidence "low")
    (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))

(ert-deftest satan-audit-iv/classified-harmful-manual-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.outcome_classified"
    (satan-audit-iv-test--classified
     :classification "harmful" :source "manual")
    (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))

(ert-deftest satan-audit-iv/classified-contradicted-manual-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.outcome_classified"
    (satan-audit-iv-test--classified
     :classification "contradicted" :source "manual")
    (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))

(ert-deftest satan-audit-iv/revised-supersedes-prior-ok ()
  (should-not
   (satan-audit-validate-intervention-event
    "intervention.outcome_revised"
    (satan-audit-iv-test--revised :classification "worked")
    (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))


;;; --- invariant violations --------------------------------------------

(ert-deftest satan-audit-iv/classified-harmful-auto-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified
               :classification "harmful" :source "auto")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "harmful" err))
    (should (string-match-p "manual" err))))

(ert-deftest satan-audit-iv/classified-contradicted-auto-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified
               :classification "contradicted" :source "auto")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "contradicted" err))))

(ert-deftest satan-audit-iv/revised-harmful-auto-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_revised"
              (satan-audit-iv-test--revised
               :classification "harmful" :source "auto")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "harmful" err))))

(ert-deftest satan-audit-iv/classified-pending-non-unknown-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified
               :maturity "pending" :classification "worked")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "pending" err))))

(ert-deftest satan-audit-iv/classified-without-prior-created-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified)
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "no prior intervention.created" err))))

(ert-deftest satan-audit-iv/revised-missing-revises-rejected ()
  (let* ((payload (satan-audit-iv-test--classified))
         (err (satan-audit-validate-intervention-event
               "intervention.outcome_revised"
               payload
               (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "revises" err))))

(ert-deftest satan-audit-iv/revised-revises-no-prior-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_revised"
              (satan-audit-iv-test--revised
               :revises "20260523T000000-morning-ffffff.iv99")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "revises" err))
    (should (string-match-p "no prior intervention.created" err))))


;;; --- payload shape violations ----------------------------------------

(ert-deftest satan-audit-iv/unknown-event-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.bogus"
              '(:intervention_id "x")
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "unknown intervention event" err))))

(ert-deftest satan-audit-iv/created-missing-field-rejected ()
  (let* ((payload (satan-audit-iv-test--created))
         (without-id (cl-loop for (k v) on payload by #'cddr
                              unless (eq k :intervention_id)
                              append (list k v)))
         (err (satan-audit-validate-intervention-event
               "intervention.created" without-id
               (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "missing required field: intervention_id" err))))

(ert-deftest satan-audit-iv/created-bad-kind-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.created"
              (satan-audit-iv-test--created :kind "bogus")
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "kind" err))))

(ert-deftest satan-audit-iv/created-bad-severity-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.created"
              (satan-audit-iv-test--created :severity "huge")
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "severity" err))))

(ert-deftest satan-audit-iv/created-negative-window-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.created"
              (satan-audit-iv-test--created :outcome_window_minutes -5)
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "outcome_window_minutes" err))))

(ert-deftest satan-audit-iv/created-non-integer-window-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.created"
              (satan-audit-iv-test--created :outcome_window_minutes "30")
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "outcome_window_minutes" err))))

(ert-deftest satan-audit-iv/created-bad-related-motive-type-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.created"
              (satan-audit-iv-test--created :related_motive_id 42)
              (make-hash-table :test 'equal))))
    (should err)
    (should (string-match-p "related_motive_id" err))))

(ert-deftest satan-audit-iv/classified-bad-classification-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified :classification "bogus")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "classification" err))))

(ert-deftest satan-audit-iv/classified-bad-confidence-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified :confidence "very-high")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "confidence" err))))

(ert-deftest satan-audit-iv/classified-bad-maturity-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified :maturity "ripe")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "maturity" err))))

(ert-deftest satan-audit-iv/classified-bad-source-rejected ()
  (let ((err (satan-audit-validate-intervention-event
              "intervention.outcome_classified"
              (satan-audit-iv-test--classified :source "system")
              (satan-audit-iv-test--ids-with satan-audit-iv-test--iv-id))))
    (should err)
    (should (string-match-p "source" err))))


;;; --- stream validator -----------------------------------------------

(ert-deftest satan-audit-iv/stream-ok-created-then-classified ()
  (should-not
   (satan-audit-validate-intervention-stream
    (list
     (cons "intervention.created"            (satan-audit-iv-test--created))
     (cons "intervention.outcome_classified" (satan-audit-iv-test--classified))))))

(ert-deftest satan-audit-iv/stream-ok-created-classified-revised ()
  (should-not
   (satan-audit-validate-intervention-stream
    (list
     (cons "intervention.created"            (satan-audit-iv-test--created))
     (cons "intervention.outcome_classified"
           (satan-audit-iv-test--classified :classification "ignored"))
     (cons "intervention.outcome_revised"
           (satan-audit-iv-test--revised :classification "worked"))))))

(ert-deftest satan-audit-iv/stream-detects-classified-before-created ()
  (let ((res (satan-audit-validate-intervention-stream
              (list
               (cons "intervention.outcome_classified"
                     (satan-audit-iv-test--classified))
               (cons "intervention.created"
                     (satan-audit-iv-test--created))))))
    (should res)
    (should (= 0 (plist-get res :idx)))
    (should (string-match-p "no prior intervention.created"
                            (plist-get res :reason)))))

(ert-deftest satan-audit-iv/stream-detects-second-record-violation ()
  (let ((res (satan-audit-validate-intervention-stream
              (list
               (cons "intervention.created"
                     (satan-audit-iv-test--created))
               (cons "intervention.outcome_classified"
                     (satan-audit-iv-test--classified
                      :classification "harmful" :source "auto"))))))
    (should res)
    (should (= 1 (plist-get res :idx)))
    (should (string-match-p "harmful" (plist-get res :reason)))))

(ert-deftest satan-audit-iv/stream-multi-intervention-isolated ()
  (let* ((iv2-created (satan-audit-iv-test--created
                       :intervention_id satan-audit-iv-test--iv-id-2))
         (iv2-classified (satan-audit-iv-test--classified
                          :intervention_id satan-audit-iv-test--iv-id-2
                          :classification "ignored")))
    (should-not
     (satan-audit-validate-intervention-stream
      (list
       (cons "intervention.created"            (satan-audit-iv-test--created))
       (cons "intervention.created"            iv2-created)
       (cons "intervention.outcome_classified" (satan-audit-iv-test--classified))
       (cons "intervention.outcome_classified" iv2-classified))))))

(provide 'satan-audit-intervention-test)
;;; satan-audit-intervention-test.el ends here
