;;; satan-test.el --- Run the SATAN ERT suite -*- lexical-binding: t; -*-

;; Drives the SATAN package's ERT suites in its own repo.  Two paths:
;;
;;   `satan-test-run-batch-and-exit' — batch (`just test'): prints the
;;                              summary, exits non-zero on FAIL.
;;   `satan-test-run-batch'   — returns the one-line PASS/FAIL summary
;;                              string; for a live Emacs (emacsclient),
;;                              let-binding satan-db-host-override so DB
;;                              tests hit the test DB without disturbing
;;                              the production broker.
;;
;; Per-test detail lands in *Messages* (the server's stderr) for a live
;; Emacs, or stdout in batch.
;;
;; Side-effect policy lives in the suites, not here: DB-touching tests
;; isolate to a dedicated test database (satan_memory_test / trace_test /
;; patch_live_test) and `skip-unless' it is reachable; pure suites mock
;; the psql subprocess.  So this runner just loads everything — do NOT
;; re-add a subsystem exclusion list (see memory
;; mem.fact.satan.test-db-isolation).
;;
;; Suite dirs are resolved relative to the REPO ROOT (this file's parent
;; directory's parent — dev/ sits under the root), NOT
;; `user-emacs-directory', which in batch would resolve to the wrong
;; repo (RV-010 F-1).
;;
;; CLI shape (see ../justfile):
;;   emacs --batch -L ./satan -L ./dev -l satan-test \
;;     -f satan-test-run-batch-and-exit

;;; Code:

(require 'ert)
(require 'satan-announce)
(require 'satan-credential)
(require 'satan-db)

(defconst satan-test--repo-root
  (file-name-directory
   (directory-file-name
    (file-name-directory
     (or load-file-name buffer-file-name default-directory))))
  "Repository root, resolved from this file's location (dev/satan-test.el).
Suite directories expand under this, not `user-emacs-directory'.")

(defvar satan-test-suite-dirs '("satan/test")
  "Directories (relative to `satan-test--repo-root') scanned for ERT files.
A file is a test file when its name ends in \"-test.el\" or begins
with \"test-\".")

(defun satan-test--file-p (name)
  "Non-nil when NAME (a basename) is an ERT test file."
  (and (string-suffix-p ".el" name)
       (or (string-suffix-p "-test.el" name)
           (string-prefix-p "test-" name))))

(defun satan-test--suite-files ()
  "Absolute paths of every ERT test file under `satan-test-suite-dirs'."
  (let (files)
    (dolist (dir satan-test-suite-dirs)
      (let ((abs (expand-file-name dir satan-test--repo-root)))
        (when (file-directory-p abs)
          (dolist (f (directory-files abs t "\\.el\\'"))
            (when (satan-test--file-p (file-name-nondirectory f))
              (push f files))))))
    (nreverse files)))

(defun satan-test-run-batch ()
  "Load and run the ERT suites, returning a one-line summary string.
Clears previously-defined tests first so only freshly-loaded files
run.  DB-backed tests `skip-unless' their test database is reachable.

In batch mode, unless SATAN_FAILOVER_TO_SYSTEM_DB is set, errors
loudly before loading any test files when SATAN_DB_HOST is unset or
names the production host (in any spelling: see
`satan-db-production-host-p') — never touches the production database
from a test run."
  ;; Pre-flight: refuse to run batch tests against the production host.
  (let ((host (getenv "SATAN_DB_HOST")))
    (when (and noninteractive
               (not (getenv "SATAN_FAILOVER_TO_SYSTEM_DB"))
               (or (null host) (string-empty-p host)
                   (satan-db-production-host-p host)))
      (error "satan-test: refusing to run batch tests against the production host; set SATAN_DB_HOST to a test host (see justfile) or SATAN_FAILOVER_TO_SYSTEM_DB")))
  (ert-delete-all-tests)
  ;; Hermeticity floor (design.md sec-2): the whole load-and-run happens
  ;; under the recording sink, so nothing any test forgets to stub can
  ;; still reach D-Bus or the journal.  A `let', not a `setq' — running
  ;; this from a live Emacs (check-interactive) never silences its real
  ;; alerts once the run ends.  Likewise no credential backend (SL-018):
  ;; a live Emacs wires `satan-credential-function' to 1Password, and no
  ;; test may reach it; suites that need one bind the fake fixture.
  (let ((satan-announce-sink #'satan-announce-record)
        (satan-credential-function nil))
    (let ((load-errors '()))
      (dolist (f (satan-test--suite-files))
        ;; A sibling suite file may `require' this one for its fixture
        ;; macros, which loads it (and defines its tests) before the loop
        ;; reaches it.  Loading again re-runs every `ert-deftest', which
        ;; errors in batch ("redefined (or loaded twice)").  Skip files
        ;; whose feature is already provided.
        (unless (featurep (intern (file-name-base f)))
          (condition-case err
              (load f nil t)
            (error (push (format "%s: %s" (file-name-base f)
                                 (error-message-string err))
                         load-errors)))))
      (let* ((stats (ert-run-tests-batch t))
             (total (ert-stats-total stats))
             (unexpected (ert-stats-completed-unexpected stats))
             (expected (ert-stats-completed-expected stats))
             (skipped (if (fboundp 'ert-stats-skipped)
                          (ert-stats-skipped stats) 0))
             (loaderr (when load-errors
                        (format " | LOADERR %d: %s"
                                (length load-errors)
                                (string-join (nreverse load-errors) "; ")))))
        (if (and (zerop unexpected) (null load-errors))
            (format "PASS %d/%d passed (%d skipped)" expected total skipped)
          (format "FAIL %d unexpected / %d total (%d skipped)%s"
                  unexpected total skipped (or loaderr "")))))))

(defun satan-test-run-batch-and-exit ()
  "Run `satan-test-run-batch', print its summary, and exit Emacs.
Exit status is 0 on PASS and 1 otherwise, so `just check' fails when
a test does.  Errors (e.g. the production-socket refusal) propagate
and exit non-zero as usual."
  (let ((summary (satan-test-run-batch)))
    (message "%s" summary)
    (kill-emacs (if (string-prefix-p "PASS" summary) 0 1))))

(provide 'satan-test)
;;; satan-test.el ends here
