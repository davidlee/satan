;;; dl-satan-attribute-render.el --- Capsule attribute bar block -*- lexical-binding: t; -*-

;; T-attr-1d — broker-side capsule render for the attribute layer.
;;
;; Two entry points:
;;
;;   (dl-satan-attribute-snapshot)               -> alist ((name . value) ...)
;;   (dl-satan-attribute-render-block FRAMING S) -> list-of-lines | nil
;;
;; Run from CLI (tests):
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-attribute-render-test.el -f ert-run-tests-batch-and-exit

(require 'cl-lib)
(require 'dl-satan-attribute)

(defconst dl-satan-attribute-render--framing-key "attributes_block_header"
  "Framing.txt key for the attribute block header.")

(defconst dl-satan-attribute-render--bar-width 10
  "Total cells per bar. Each cell = 0.10 of [0, 1].")

(defconst dl-satan-attribute-render--filled-glyph "█"
  "Filled bar glyph (FULL BLOCK).")

(defconst dl-satan-attribute-render--empty-glyph "░"
  "Empty bar glyph (LIGHT SHADE).")

(defconst dl-satan-attribute-render--vocabulary
  '((:curiosity      . "Curiosity")
    (:hunger         . "Hunger")
    (:suspicion      . "Suspicion")
    (:doubt          . "Doubt")
    (:friction       . "Cruelty")
    (:shame          . "Shame")
    (:brooding       . "Brooding")
    (:metamorphosis  . "Metamorphosis"))
  "Ordered alist mapping internal keyword → public label (design-contract §2).
Row order in the capsule follows this list order.")

(defconst dl-satan-attribute-render--label-width 13
  "Column width for labels (length of \"Metamorphosis\").")

(defconst dl-satan-attribute-render--snapshot-sql
  "SELECT name, value FROM satan_attributes WHERE scope = 'global' ORDER BY name"
  "SQL for the attribute snapshot query.")

;; ---------------------------------------------------------------------
;; Snapshot
;; ---------------------------------------------------------------------

(defun dl-satan-attribute-snapshot ()
  "Return current attribute values as an alist ((name-string . value) ...).
Returns nil on query failure (block suppresses)."
  (let ((result (dl-satan-db-query
                 dl-satan-attribute-database
                 dl-satan-attribute-host
                 dl-satan-attribute-psql-program
                 dl-satan-attribute-render--snapshot-sql
                 nil)))
    (pcase result
      (`(ok . ,stdout)
       (dl-satan-attribute-render--parse-snapshot stdout))
      (`(error . ,msg)
       (display-warning 'dl-satan-attribute
                        (format "Attribute snapshot query failed: %s" msg)
                        :warning)
       nil))))

(defun dl-satan-attribute-render--parse-snapshot (stdout)
  "Parse tab-separated psql output into ((name . value) ...).
Returns nil if STDOUT is empty."
  (when (and stdout (not (string-empty-p stdout)))
    (let (rows)
      (dolist (line (split-string stdout "\n" t))
        (let ((fields (split-string line "\t")))
          (when (= (length fields) 2)
            (push (cons (car fields)
                        (string-to-number (cadr fields)))
                  rows))))
      (nreverse rows))))

;; ---------------------------------------------------------------------
;; Bar rendering
;; ---------------------------------------------------------------------

(defun dl-satan-attribute-render--bar (value)
  "Return the 10-cell bar string for VALUE in [0, 1]."
  (let* ((filled (max 0 (min dl-satan-attribute-render--bar-width
                              (round (* value dl-satan-attribute-render--bar-width)))))
         (empty (- dl-satan-attribute-render--bar-width filled)))
    (concat (make-string filled (string-to-char dl-satan-attribute-render--filled-glyph))
            (make-string empty (string-to-char dl-satan-attribute-render--empty-glyph)))))

(defun dl-satan-attribute-render--row (label value)
  "Return one formatted row: \"  Label         ██░░░░░░░░  0.30\"."
  (format "  %-13s  %s  %0.2f" label (dl-satan-attribute-render--bar value) value))

(defun dl-satan-attribute-render--rows (snapshot)
  "Return list of bar-row strings from SNAPSHOT alist, in vocabulary order."
  (let (lines)
    (dolist (entry dl-satan-attribute-render--vocabulary)
      (let* ((internal (car entry))
             (label (cdr entry))
             (name-str (substring (symbol-name internal) 1))
             (value (or (cdr (assoc name-str snapshot)) 0.0)))
        (push (dl-satan-attribute-render--row label value) lines)))
    (nreverse lines)))

;; ---------------------------------------------------------------------
;; Block entry point
;; ---------------------------------------------------------------------

(defun dl-satan-attribute-render-block (framing snapshot)
  "Return the rendered `# Attributes' block as a list of lines, or nil.
FRAMING is the parsed framing alist.  SNAPSHOT is the result of
`dl-satan-attribute-snapshot' (alist of (name . value) pairs).

When `dl-satan-attribute-updates-enabled' is nil, renders a single
disabled marker line (design-contract §9).  When SNAPSHOT is nil,
returns nil (block suppressed)."
  (let ((header (cdr (assoc dl-satan-attribute-render--framing-key framing))))
    (cond
     ((not header) nil)
     ((not dl-satan-attribute-updates-enabled)
      (list header "Attributes: disabled"))
     ((not snapshot) nil)
     (t
      (cons header (dl-satan-attribute-render--rows snapshot))))))

(provide 'dl-satan-attribute-render)
;;; dl-satan-attribute-render.el ends here
