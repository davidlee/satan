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
(require 'cl-lib)
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

;; ── SL-015 VT-1: corpus / state roots and their joins ───────────────────────
;;
;; Three ownership classes, three roots (SL-015 D1): `satan-notes-root' is the
;; user's notes (read-only to SATAN), `satan-corpus-root' is SATAN's own
;; model-facing corpus, `satan-state-root' is discardable runtime state.  These
;; assert the two new joins have the same contract as `satan-notes-path'.

(ert-deftest satan-custom-corpus-path-joins-below-root ()
  (let ((satan-corpus-root "/tmp/corpus"))
    (should (equal (satan-corpus-path "prompts") "/tmp/corpus/prompts"))
    (should (equal (satan-corpus-path "system" "framing.txt")
                   "/tmp/corpus/system/framing.txt"))))

(ert-deftest satan-custom-corpus-path-expands-tilde-root ()
  (let ((satan-corpus-root "~/satan"))
    (should (equal (satan-corpus-path "prompts")
                   (expand-file-name "prompts" (expand-file-name "~/satan"))))))

(ert-deftest satan-custom-state-path-joins-below-root ()
  (let ((satan-state-root "/tmp/state"))
    (should (equal (satan-state-path "runs") "/tmp/state/runs"))
    (should (equal (satan-state-path "log" "wpm") "/tmp/state/log/wpm"))))

(ert-deftest satan-custom-state-path-expands-tilde-root ()
  (let ((satan-state-root "~/.local/state/satan"))
    (should (equal (satan-state-path "runs")
                   (expand-file-name
                    "runs" (expand-file-name "~/.local/state/satan"))))))

(defun satan-custom-test--default-of (sym)
  "Re-evaluate SYM's `standard-value' under the current environment.
Same idiom as `satan-run-test.el:185' — the one way to test a defcustom
default that derives from another variable or from the environment."
  (eval (car (get sym 'standard-value)) t))

(ert-deftest satan-custom-state-root-honours-xdg-state-home ()
  (let ((process-environment (cons "XDG_STATE_HOME=/tmp/xdg" process-environment)))
    (should (equal (satan-custom-test--default-of 'satan-state-root)
                   "/tmp/xdg/satan"))))

(ert-deftest satan-custom-state-root-honours-xdg-state-home-trailing-slash ()
  ;; Cheap regression guard only.  The two inlined spellings this slice
  ;; collapses differ solely in their *fallback* branch, which is unreachable
  ;; whenever XDG_STATE_HOME is set — so this is not evidence of a latent bug
  ;; (SL-015 D1 corrected rationale, F-4).
  (let ((process-environment (cons "XDG_STATE_HOME=/tmp/xdg/" process-environment)))
    (should (equal (satan-custom-test--default-of 'satan-state-root)
                   "/tmp/xdg/satan"))))

(ert-deftest satan-custom-state-root-falls-back-below-home ()
  ;; A bare name with no `=' marks the variable UNSET for `getenv', which is
  ;; the only case the fallback branch handles.  An *empty* XDG_STATE_HOME
  ;; yields "" — truthy in elisp, so `or' takes it and the path resolves
  ;; relative to `default-directory'.  That is inherited behaviour, identical
  ;; in all eight spellings this slice collapses; PHASE-01 is a pure refactor
  ;; and does not fix it.  See ISS-010.
  (let ((process-environment (cons "XDG_STATE_HOME" process-environment)))
    (should (equal (satan-custom-test--default-of 'satan-state-root)
                   (expand-file-name ".local/state/satan" "~")))))

(ert-deftest satan-custom-corpus-root-defaults-below-notes-root ()
  ;; PHASE-01 is a pure refactor: the corpus root's transitional default must
  ;; reproduce today's on-disk location exactly (SL-015 A1/A2).  PHASE-02 flips
  ;; it to the standalone repo; this assertion is expected to change there.
  (let ((satan-notes-root "/tmp/notes"))
    (should (equal (satan-custom-test--default-of 'satan-corpus-root)
                   "/tmp/notes/satan"))))

;; ── SL-015 VT-2: every dependent default follows its root ───────────────────
;;
;; The point of naming the roots is that one knob moves everything below it.
;; These walk the whole surface — 14 corpus defaults, 8 state defaults — by
;; re-evaluating each `standard-value' under a rebound root, the idiom from
;; `satan-run-test.el'.  Heavy requires sit inside the bodies, per this file's
;; convention, so the pure surface above still runs if a module is mid-decouple.

(defconst satan-custom-test--corpus-vars
  '(satan-prompts-dir satan-motd-path satan-proposals-dir
    satan-motive-file satan-motive-archive-file
    satan-patch-prompt-system-file satan-runs-dir satan-hippocampus-dir
    satan-system-scaffold-file satan-system-framing-file
    satan-self-edit-mind-roots satan-sensor-wpm-log-dir satan-inbox-file
    satan-tools-descriptions-dir)
  "The 14 defaults that must derive from `satan-corpus-root' (16 call sites —
`satan-self-edit-mind-roots' spans three).")

(defconst satan-custom-test--state-vars
  '(satan-patch-worktree-root satan-patch-prompt-log-root
    satan-sensor-state-file satan-sensor-wpm-state-file
    satan-ingest-cursor-state-file satan-sensor-content-state-file
    satan-sensor-curiosity-state-file satan-trace-dir)
  "The 8 defaults that must derive from `satan-state-root'.")

(defun satan-custom-test--require-all ()
  (mapc #'require
        '(satan-mode satan-tools-org satan-motive satan-patch-prompt satan-run
          satan-context satan-sensor-wpm satan-tools-inbox satan-tools
          satan-patch-worktree satan-sensor-alerts satan-ingest-cursor
          satan-sensor-content satan-sensor-curiosity satan-trace
          satan-tools-notes satan-tools-atsatan satan-tools-content)))

(defun satan-custom-test--paths (sym)
  "Every path SYM's default resolves to, as a list of strings.
`satan-self-edit-mind-roots' is a list of three; the rest are single paths."
  (let ((v (satan-custom-test--default-of sym)))
    (if (listp v) v (list v))))

(defun satan-custom-test--follows-root (sym root-var)
  "Assert SYM's default lives below ROOT-VAR and moves with it.
Resolves SYM twice under two different roots: every path must be that root
plus an identical suffix.  That is stronger than a prefix check — it catches a
default that happens to start with the root but bakes in a literal below it."
  (dolist (pair (list (cons "/tmp/root-one" "/tmp/root-two")))
    (let* ((a (eval `(let ((,root-var ,(car pair))) (satan-custom-test--paths ',sym)) t))
           (b (eval `(let ((,root-var ,(cdr pair))) (satan-custom-test--paths ',sym)) t)))
      (should (= (length a) (length b)))
      (cl-mapc (lambda (pa pb)
                 ;; A path may BE the root — `satan-trace-dir' is exactly that,
                 ;; trace files sit directly under the state root — so accept
                 ;; the root itself as well as anything below it.
                 (should (or (equal pa (car pair))
                             (string-prefix-p (concat (car pair) "/") pa)))
                 (should (or (equal pb (cdr pair))
                             (string-prefix-p (concat (cdr pair) "/") pb)))
                 (should (equal (substring pa (length (car pair)))
                                (substring pb (length (cdr pair))))))
               a b))))

(ert-deftest satan-custom-corpus-vars-all-derive-from-corpus-root ()
  (satan-custom-test--require-all)
  (dolist (sym satan-custom-test--corpus-vars)
    (satan-custom-test--follows-root sym 'satan-corpus-root)))

(ert-deftest satan-custom-state-vars-all-derive-from-state-root ()
  (satan-custom-test--require-all)
  (dolist (sym satan-custom-test--state-vars)
    (satan-custom-test--follows-root sym 'satan-state-root)))

(ert-deftest satan-custom-user-notes-roots-stay-on-notes-root ()
  ;; SL-015 A4/EX-5.  These two mean the *user's* notes.  Repointing them at
  ;; the corpus root would compile, pass, and silently move the @satan scan and
  ;; the notes tool to the wrong tree.
  (satan-custom-test--require-all)
  (let ((satan-notes-root "/tmp/nr")
        (satan-corpus-root "/tmp/cr"))
    (should (equal (satan-custom-test--default-of 'satan-tools-notes-root) "/tmp/nr"))
    (should (equal (satan-custom-test--default-of 'satan-tools-atsatan-root) "/tmp/nr"))))

(ert-deftest satan-custom-behaviour-class-is-not-a-satan-root ()
  ;; SL-015 A7/EX-9.  Panopticon authors ~/.local/state/behaviour/; SATAN reads
  ;; it and does not own it, so it gets no root and must not follow one.
  ;; Rewiring these to `satan-state-path' resolves to a nonexistent
  ;; ~/.local/state/satan/behaviour/ and silences the curiosity sensor with no
  ;; error — it just reads zero.
  (satan-custom-test--require-all)
  (let ((satan-state-root "/tmp/sr")
        (satan-corpus-root "/tmp/cr"))
    (dolist (sym '(satan-sensor-curiosity-segments-dir satan-tools-content-dir))
      (let ((path (satan-custom-test--default-of sym)))
        (should (string-match-p "/behaviour/" path))
        (should-not (string-prefix-p "/tmp/sr" path))
        (should-not (string-prefix-p "/tmp/cr" path))))))

;; ── SL-015 VT-3: the recurrence guard ──────────────────────────────────────
;;
;; I1 says the `"satan/"` path segment should not be spelled out in production
;; code once the roots exist — it belongs inside the root defaults, once.  This
;; is that invariant made executable, and it is deliberately WEAKER than I1's
;; letter: it only flags a `"satan/…"` literal used as the NAME argument of an
;; `expand-file-name' whose DIR argument is one of the roots.  Two live path
;; expressions legitimately keep the segment and are named here rather than in
;; a comment, so a future edit that removes one fails loudly (design D10).
;;
;; Not swept in, and not violations: docstrings, the atsatan exclude glob
;; (`satan-tools-atsatan.el', retires in PHASE-03), and the ~50 test literals
;; including the allowed-path and branch-name fixtures.

(defconst satan-custom-test--satan-segment-allowlist
  '(("satan-mcp.el" . "satan/mcp")
    ("satan-patch-worktree.el" . "satan/%s/%s-%s"))
  "Live `\"satan/…\"' path expressions that must survive SL-015.
`satan-mcp.el' resolves the MCP socket under XDG_RUNTIME_DIR — a fourth
location outside all three roots (DEC-10 forbids /tmp).
`satan-patch-worktree.el' builds a job-id/branch prefix which is joined under
`satan-patch-worktree-root' by its caller, so the segment is data, not a root.")

(ert-deftest satan-custom-no-satan-segment-under-a-root ()
  "No `\"satan/…\"' literal is joined onto a satan root in production code."
  (let* ((dir (file-name-directory (locate-library "satan-custom")))
         (files (directory-files dir t "\\.el\\'"))
         (offenders '()))
    (dolist (f files)
      (with-temp-buffer
        (insert-file-contents f)
        (goto-char (point-min))
        ;; (expand-file-name "satan/..." satan-<something>-root)
        (while (re-search-forward
                "(expand-file-name[ \t\n]+\"satan/[^\"]*\"[ \t\n]+satan-[a-z-]*root"
                nil t)
          (push (format "%s:%d" (file-name-nondirectory f)
                        (line-number-at-pos (match-beginning 0)))
                offenders))))
    (should (equal (nreverse offenders) '()))))

(ert-deftest satan-custom-satan-segment-allowlist-is-still-live ()
  "Each allowlisted `\"satan/…\"' expression still exists.
Keeps the allowlist honest: when one of these is finally rewired or deleted,
this fails and the entry gets removed rather than quietly outliving its
subject."
  (let ((dir (file-name-directory (locate-library "satan-custom"))))
    (dolist (entry satan-custom-test--satan-segment-allowlist)
      (let ((file (expand-file-name (car entry) dir)))
        (should (file-exists-p file))
        (with-temp-buffer
          (insert-file-contents file)
          (should (search-forward (concat "\"" (cdr entry) "\"") nil t)))))))

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
