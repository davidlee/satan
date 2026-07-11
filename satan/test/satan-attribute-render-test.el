;;; satan-attribute-render-test.el --- Capsule attribute bar block -*- lexical-binding: t; -*-

;; T-attr-1d — tests for the capsule attribute render.
;;
;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-attribute-render-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-attribute-render)

(defconst satan-attribute-render-test--framing
  `(("attributes_block_header" . "# Attributes")
    ("now" . "# Now"))
  "Minimal framing alist for test fixtures.")

(defun satan-attribute-render-test--zero-snapshot ()
  "Return a snapshot with all 8 attributes at 0.0."
  '(("brooding" . 0.0)
    ("curiosity" . 0.0)
    ("doubt" . 0.0)
    ("friction" . 0.0)
    ("hunger" . 0.0)
    ("metamorphosis" . 0.0)
    ("shame" . 0.0)
    ("suspicion" . 0.0)))

(defun satan-attribute-render-test--mixed-snapshot ()
  "Return a snapshot with varied values."
  '(("brooding" . 0.40)
    ("curiosity" . 0.30)
    ("doubt" . 0.30)
    ("friction" . 0.60)
    ("hunger" . 0.70)
    ("metamorphosis" . 0.50)
    ("shame" . 0.30)
    ("suspicion" . 0.50)))

;; ---------------------------------------------------------------------
;; Bar rendering (pure)
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/bar-zero ()
  (should (equal "░░░░░░░░░░"
                 (satan-attribute-render--bar 0.0))))

(ert-deftest satan-attribute-render/bar-full ()
  (should (equal "██████████"
                 (satan-attribute-render--bar 1.0))))

(ert-deftest satan-attribute-render/bar-half ()
  (should (equal "█████░░░░░"
                 (satan-attribute-render--bar 0.50))))

(ert-deftest satan-attribute-render/bar-rounds-half-even ()
  "0.05 → round(0.5) = 0 (banker's rounding). Numeric label carries signal."
  (should (equal "░░░░░░░░░░"
                 (satan-attribute-render--bar 0.05)))
  (should (equal "██░░░░░░░░"
                 (satan-attribute-render--bar 0.15))))

(ert-deftest satan-attribute-render/bar-rounds-to-full ()
  "0.95 rounds to 10 filled cells."
  (should (equal "██████████"
                 (satan-attribute-render--bar 0.95))))

(ert-deftest satan-attribute-render/bar-clamps-above-one ()
  (should (equal "██████████"
                 (satan-attribute-render--bar 1.5))))

(ert-deftest satan-attribute-render/bar-clamps-below-zero ()
  (should (equal "░░░░░░░░░░"
                 (satan-attribute-render--bar -0.1))))

;; ---------------------------------------------------------------------
;; Row formatting
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/row-format ()
  (let ((row (satan-attribute-render--row "Curiosity" 0.30)))
    (should (string-match-p "^  Curiosity " row))
    (should (string-match-p "███░░░░░░░" row))
    (should (string-match-p "0\\.30$" row))))

(ert-deftest satan-attribute-render/row-metamorphosis-alignment ()
  "Longest label (Metamorphosis) still aligns."
  (let ((row (satan-attribute-render--row "Metamorphosis" 0.50)))
    (should (string-match-p "^  Metamorphosis  █████░░░░░  0\\.50$" row))))

;; ---------------------------------------------------------------------
;; Vocabulary order
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/rows-vocabulary-order ()
  "Rows follow design-contract §2 order, not alphabetical DB order."
  (let* ((snapshot (satan-attribute-render-test--mixed-snapshot))
         (rows (satan-attribute-render--rows snapshot)))
    (should (= 8 (length rows)))
    (should (string-match-p "Curiosity" (nth 0 rows)))
    (should (string-match-p "Hunger" (nth 1 rows)))
    (should (string-match-p "Suspicion" (nth 2 rows)))
    (should (string-match-p "Doubt" (nth 3 rows)))
    (should (string-match-p "Cruelty" (nth 4 rows)))
    (should (string-match-p "Shame" (nth 5 rows)))
    (should (string-match-p "Brooding" (nth 6 rows)))
    (should (string-match-p "Metamorphosis" (nth 7 rows)))))

(ert-deftest satan-attribute-render/friction-maps-to-cruelty ()
  ":friction internal name renders as Cruelty public label."
  (let* ((snapshot '(("friction" . 0.60)))
         (rows (satan-attribute-render--rows snapshot)))
    (should (cl-some (lambda (r) (string-match-p "Cruelty" r)) rows))
    (should-not (cl-some (lambda (r) (string-match-p "Friction" r)) rows))))

;; ---------------------------------------------------------------------
;; Block entry point — enabled
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/block-all-zero ()
  (let* ((satan-attribute-updates-enabled t)
         (snapshot (satan-attribute-render-test--zero-snapshot))
         (block (satan-attribute-render-block
                 satan-attribute-render-test--framing snapshot)))
    (should block)
    (should (equal "# Attributes" (car block)))
    (should (= 9 (length block)))
    (dolist (row (cdr block))
      (should (string-match-p "░░░░░░░░░░  0\\.00" row)))))

(ert-deftest satan-attribute-render/block-mixed-values ()
  (let* ((satan-attribute-updates-enabled t)
         (snapshot (satan-attribute-render-test--mixed-snapshot))
         (block (satan-attribute-render-block
                 satan-attribute-render-test--framing snapshot)))
    (should block)
    (should (equal "# Attributes" (car block)))
    (should (= 9 (length block)))
    (let ((hunger-row (nth 2 block)))
      (should (string-match-p "Hunger" hunger-row))
      (should (string-match-p "███████░░░  0\\.70" hunger-row)))))

;; ---------------------------------------------------------------------
;; Block entry point — disabled
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/block-disabled ()
  "Disabled switch → single marker line, not frozen values."
  (let* ((satan-attribute-updates-enabled nil)
         (snapshot (satan-attribute-render-test--mixed-snapshot))
         (block (satan-attribute-render-block
                 satan-attribute-render-test--framing snapshot)))
    (should block)
    (should (equal "# Attributes" (car block)))
    (should (equal "Attributes: disabled" (cadr block)))
    (should (= 2 (length block)))))

(ert-deftest satan-attribute-render/block-disabled-nil-snapshot ()
  "Disabled renders marker even when snapshot is nil."
  (let* ((satan-attribute-updates-enabled nil)
         (block (satan-attribute-render-block
                 satan-attribute-render-test--framing nil)))
    (should block)
    (should (equal "Attributes: disabled" (cadr block)))))

;; ---------------------------------------------------------------------
;; Block entry point — suppression
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/block-nil-snapshot-suppresses ()
  "Nil snapshot with enabled switch → block suppressed (nil return)."
  (let ((satan-attribute-updates-enabled t))
    (should-not (satan-attribute-render-block
                 satan-attribute-render-test--framing nil))))

(ert-deftest satan-attribute-render/block-no-framing-key-suppresses ()
  "Missing framing key → block suppressed."
  (let ((satan-attribute-updates-enabled t))
    (should-not (satan-attribute-render-block
                 '(("now" . "# Now"))
                 (satan-attribute-render-test--zero-snapshot)))))

;; ---------------------------------------------------------------------
;; Snapshot parse (pure)
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/parse-snapshot ()
  (let ((parsed (satan-attribute-render--parse-snapshot
                 "brooding\t0.40\ncuriosity\t0.30")))
    (should (= 2 (length parsed)))
    (should (equal '("brooding" . 0.40) (car parsed)))
    (should (equal '("curiosity" . 0.30) (cadr parsed)))))

(ert-deftest satan-attribute-render/parse-snapshot-empty ()
  (should-not (satan-attribute-render--parse-snapshot "")))

(ert-deftest satan-attribute-render/parse-snapshot-nil ()
  (should-not (satan-attribute-render--parse-snapshot nil)))

;; ---------------------------------------------------------------------
;; Boundary values
;; ---------------------------------------------------------------------

(ert-deftest satan-attribute-render/boundary-values ()
  "Exact boundaries produce correct bar fills."
  (should (equal "░░░░░░░░░░" (satan-attribute-render--bar 0.0)))
  (should (equal "█░░░░░░░░░" (satan-attribute-render--bar 0.1)))
  (should (equal "█████████░" (satan-attribute-render--bar 0.9)))
  (should (equal "██████████" (satan-attribute-render--bar 1.0))))

(provide 'satan-attribute-render-test)
;;; satan-attribute-render-test.el ends here
