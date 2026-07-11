;;; satan-custom-test.el --- Tests for satan-custom -*- lexical-binding: t; -*-

;;; Commentary:
;; SL-012 PHASE-03 coverage for the config-root decouple surfaces:
;;   VT-1 — notes corpus (Axis-1, D4): `satan-notes-path' derivations,
;;          `satan-journal-today' contract.
;;   VT-2 — self-location (Axis-2, D10): `satan--root' resolution and the
;;          re-anchored package-owned path defaults.
;; Heavy-module requires sit inside the VT-2 test bodies so the pure VT-1
;; surface still runs even while an anchoring module is mid-decouple.

;;; Code:

(require 'ert)
(require 'satan-custom)

;; ── VT-1: notes corpus surface (D4) ─────────────────────────────────────────

(ert-deftest satan-custom-notes-path-joins-below-root ()
  (let ((satan-notes-root "/tmp/notes"))
    (should (equal (satan-notes-path "journal") "/tmp/notes/journal"))
    (should (equal (satan-notes-path "weekly") "/tmp/notes/weekly"))
    (should (equal (satan-notes-path "inbox.org") "/tmp/notes/inbox.org"))
    (should (equal (satan-notes-path "a" "b") "/tmp/notes/a/b"))))

(ert-deftest satan-custom-notes-path-derives-corpus-paths ()
  ;; D4 derivation table: journal/ weekly/ inbox.org below the root.
  (let ((satan-notes-root "~/notes")
        (base (expand-file-name "~/notes")))
    (should (equal (satan-notes-path "journal") (expand-file-name "journal" base)))
    (should (equal (satan-notes-path "weekly") (expand-file-name "weekly" base)))
    (should (equal (satan-notes-path "inbox.org") (expand-file-name "inbox.org" base)))))

(ert-deftest satan-custom-journal-today-nil-yields-no-journal ()
  (let ((satan-journal-today nil))
    (should-not (satan-notes-today)))
  (let ((satan-journal-today (lambda () "/j/today.org")))
    (should (equal (satan-notes-today) "/j/today.org"))))

;; ── VT-2: self-location surface (D10) ───────────────────────────────────────

(ert-deftest satan-custom-root-is-elisp-directory ()
  (should (equal (file-name-nondirectory (directory-file-name satan--root)) "satan"))
  (should (file-exists-p (expand-file-name "satan-custom.el" satan--root))))

(ert-deftest satan-custom-memory-migrate-anchored-to-root ()
  (require 'satan-memory-migrate)
  (should (equal satan-memory-migrate-directory
                 (expand-file-name "memory/migrations/" satan--root))))

(ert-deftest satan-custom-pattern-file-anchored-to-root ()
  (require 'satan-pattern)
  (should (equal satan-pattern-file
                 (expand-file-name "patterns.eld" satan--root))))

(ert-deftest satan-custom-self-edit-mech-anchored-to-root ()
  (require 'satan-context)
  (should (equal satan-self-edit-mech-roots (list satan--root))))

(ert-deftest satan-custom-tools-docs-default-drops-config-docs ()
  (require 'satan-tools-docs)
  (should (equal satan-tools-docs-roots '("docs")))
  ;; Resolves to the package repo-root docs corpus (docs/emacs is config-owned,
  ;; dropped); every resolved root must exist.
  (let ((resolved (satan-tools-docs--resolve-roots)))
    (should (member (expand-file-name "docs" (expand-file-name ".." satan--root))
                    resolved))
    (dolist (r resolved) (should (file-directory-p r)))))

(ert-deftest satan-custom-direnv-dir-is-package-repo-root ()
  (require 'satan-broker)
  (should (equal satan-direnv-dir
                 (file-name-directory (directory-file-name satan--root)))))

(provide 'satan-custom-test)
;;; satan-custom-test.el ends here
