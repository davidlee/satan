;;; satan-bough-removal-gate-test.el --- standing gates from SL-002 -*- lexical-binding: t; -*-

;; SL-002 removed the bough integration.  These are the gates that keep it
;; removed, and that keep what was deliberately PRESERVED from being tidied
;; away later by someone who reads a `bough_' token as leftover mess.
;;
;; They are not "did the removal happen" checks — the removal is in the
;; history.  They are standing invariants:
;;
;;   VT-1  no production file carries a `bough' token outside a named,
;;         justified allowlist.  A future accidental bough branch fails here.
;;   VT-2  the two preserved grammar artifacts still declare the vocabulary
;;         whole, so historical bough-attributed data stays legal and
;;         readable until OQ-3 retires it deliberately.
;;   VT-3  no surface claims an enforced/mandatory evidence truncation byte
;;         cap.  There has never been one (ISS-001), and passes 1/4/5 leaving
;;         narrowed the chain further.
;;
;; Run from CLI:
;;   emacs --batch -L ./satan -L ./dev -L ./satan/test \
;;     -l satan-bough-removal-gate-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-memory-grammar)
(require 'satan-motive)

(defconst satan-bough-gate-test--repo-root
  (file-name-directory (directory-file-name satan--root))
  "Repository root, resolved from the package's self-location root (D10).")

(defconst satan-bough-gate-test--allowlist
  '("satan-memory-grammar.el"      ; preserved vocabulary (elisp half)
    "0002_grammar_v1.sql"          ; preserved vocabulary (SQL half)
    "satan-motive.el")             ; satan-motive--admitted-namespaces (D4)
  "Production files permitted to carry a `bough' token, and why.

Each is preserved deliberately, not overlooked.  The grammar is a
version-gated closed-world schema: dropping the namespaces would make
historical handles ungrammatical.  `satan-motive.el' keeps its admitted
namespaces because removing them would flip persisted bough-only motives
to dormant and reject future writes (SL-002 D4 / RN-2).

Retiring all three is SL-002's OQ-3 follow-up: grammar-v2 plus a data
migration, with an operator step.  Until then this list stays exactly
this long — adding to it is a design decision, not a fix.")

(defun satan-bough-gate-test--production-files ()
  "Return every production source file under the package root.
Tests are excluded: bough fixtures live in tests by design (they pin the
preserved substrate boundary, SL-002 §2.D)."
  (let (files)
    (dolist (spec '(("." . "\\.el\\'")
                    ("harness" . "\\.py\\'")
                    ("memory/migrations" . "\\.sql\\'")))
      (let ((dir (expand-file-name (car spec) satan--root)))
        (when (file-directory-p dir)
          (setq files (append files (directory-files dir t (cdr spec)))))))
    (cl-remove-if (lambda (f)
                    (or (string-match-p "/test/" f)
                        (string-match-p "test_.*\\.py\\'" f)))
                  files)))

(defun satan-bough-gate-test--tokens-in (path)
  "Return the lines of PATH carrying a `bough' token, as (LINENO . TEXT)."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (let (hits (n 1))
      (while (not (eobp))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (when (string-match-p "bough" line)
            (push (cons n line) hits)))
        (forward-line 1)
        (setq n (1+ n)))
      (nreverse hits))))

;; ---------------------------------------------------------------------
;; VT-1 — zero-token gate (R1 / RN-14)
;; ---------------------------------------------------------------------

(ert-deftest satan-bough-removal/production-is-bough-free ()
  "No production file outside the allowlist carries a `bough' token.

Deliberately whole-file and whole-tree rather than a list of the modules
the removal touched: the content-agnostic substrate (`satan-observer.el',
`satan-intervention.el', `satan-attribute.el', `satan-pattern.el',
`satan-memory-store.el', `satan-broker.el', `satan-context.el',
`satan-audit.el') carries no bough token today and must not acquire one.
A future bough branch there is exactly the regression this catches."
  (let (offenders)
    (dolist (path (satan-bough-gate-test--production-files))
      (let ((base (file-name-nondirectory path)))
        (unless (member base satan-bough-gate-test--allowlist)
          (dolist (hit (satan-bough-gate-test--tokens-in path))
            (push (format "%s:%d: %s" base (car hit) (string-trim (cdr hit)))
                  offenders)))))
    (should (equal '() (nreverse offenders)))))

(ert-deftest satan-bough-removal/allowlist-entries-all-exist-and-are-used ()
  "Every allowlist entry names a real production file that really does
carry a bough token.  Keeps the list from rotting into a set of excuses
for files that no longer need one — when OQ-3 lands, this goes red and
tells you to shorten the list."
  (let ((by-base (let (m)
                   (dolist (p (satan-bough-gate-test--production-files) m)
                     (push (cons (file-name-nondirectory p) p) m)))))
    (dolist (entry satan-bough-gate-test--allowlist)
      (let ((path (cdr (assoc entry by-base))))
        (should path)
        (should (satan-bough-gate-test--tokens-in path))))))

;; ---------------------------------------------------------------------
;; VT-2 — preserved-artifact gate (R2)
;; ---------------------------------------------------------------------

(ert-deftest satan-bough-removal/grammar-vocabulary-preserved-whole ()
  "The elisp grammar still declares the whole bough vocabulary.

Byte-identity against the pre-removal tree was a one-time audit check
(SL-002 notes record the SHA).  The durable invariant is this: the five
namespaces are declared with their original worlds and weights, so a
handle written before the removal is still grammatical after it.  Retire
them via grammar-v2 and a data migration (OQ-3), never by deletion."
  (dolist (pair '((bough_kind . closed) (bough_status . closed)
                  (bough_event . closed) (bough_node . open)
                  (bough_project . open)))
    (should (eq (cdr pair)
                (satan-memory-grammar-namespace-world (car pair)))))
  ;; bough_node = 0 is intentional: admitted for audit, never score-dominant.
  (should (= 0 (satan-memory-grammar-default-weight 'bough_node)))
  (should (= 2 (satan-memory-grammar-default-weight 'bough_event))))

(ert-deftest satan-bough-removal/grammar-sql-mirrors-the-elisp ()
  "The SQL half of the preserved vocabulary is intact too.
`db-sync-*' in `satan-memory-grammar-test.el' is the real drift detector,
but it skips whenever its database is unreachable — which, per ISS-007,
is most of the time.  This is the floor that always runs."
  (let ((sql (expand-file-name "memory/migrations/0002_grammar_v1.sql"
                               satan--root)))
    (should (file-readable-p sql))
    (with-temp-buffer
      (insert-file-contents sql)
      (dolist (ns '("bough_kind" "bough_status" "bough_event"
                    "bough_node" "bough_project"))
        (goto-char (point-min))
        (should (search-forward ns nil t))))))

(ert-deftest satan-bough-removal/motive-namespaces-preserved ()
  "D4 — the motive admitted-namespace vocabulary keeps its bough entries.
Removing them would flip persisted bough-only motives to dormant and
reject future writes (RN-2).  This is the single allowlisted occurrence
in `satan-motive.el', and the reason it is allowlisted."
  (dolist (ns '("bough_event" "bough_node" "bough_project"))
    (should (member ns satan-motive--admitted-namespaces))))

;; ---------------------------------------------------------------------
;; VT-3 — evidence-cap wording gate (D3 / §5.5 sixth-surface risk)
;; ---------------------------------------------------------------------

(defconst satan-bough-gate-test--cap-claim-re
  (concat "\\(?:hard[- ]cap\\|hard byte cap\\|byte cap\\)[^\n]\\{0,80\\}"
          "\\(?:mandatory\\|enforced\\|guaranteed\\|always\\)"
          "\\|\\(?:mandatory\\|enforced\\|guaranteed\\)"
          "[^\n]\\{0,40\\}\\(?:hard[- ]cap\\|byte cap\\)")
  "Matches a claim that the evidence truncation cap is enforced.

It never has been: `--truncate' runs a fixed set of exhaustible passes
and stops, whether or not the result fits.  SL-002 narrowed the chain
further by removing passes 1/4/5.  A behavioural final reducer is
ISS-001; until it lands, no surface may promise one.")

(ert-deftest satan-bough-removal/no-surface-claims-an-enforced-cap ()
  "VT-3 — the repo-wide wording gate that closes the sixth-surface risk.
The design reconciled five known surfaces; this makes a sixth impossible
to add quietly."
  (let (offenders)
    (dolist (path (satan-bough-gate-test--production-files))
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (let ((case-fold-search t))
          (while (re-search-forward satan-bough-gate-test--cap-claim-re nil t)
            (push (format "%s: %s"
                          (file-name-nondirectory path)
                          (string-trim (match-string 0)))
                  offenders)))))
    (should (equal '() (nreverse offenders)))))

(provide 'satan-bough-removal-gate-test)
;;; satan-bough-removal-gate-test.el ends here
