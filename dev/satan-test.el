;;; satan-test.el --- Run the SATAN ERT suite -*- lexical-binding: t; -*-

;; Drives the SATAN package's ERT suites in its own repo.  Two paths:
;;
;;   `just check'             — batch (emacs --batch), the default.
;;   `just check-interactive' — live Emacs server (emacsclient),
;;                              let-binds satan-db-host-override
;;                              so DB tests hit the test DB without
;;                              disturbing the production broker.
;;
;; The runner returns a one-line summary string; the Justfile recipes
;; grep it for PASS/FAIL.  Per-test detail lands in *Messages*
;; (the server's stderr) for check-interactive, or stdout for check.
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
;;     --eval '(satan-test-run-batch)'

;;; Code:

(require 'ert)

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

In batch mode without SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB,
errors loudly before loading any test files — never touches the
production database from a test run."
  ;; Pre-flight: refuse to run batch tests against the production socket.
  (when (and noninteractive
             (not (getenv "SATAN_DB_HOST"))
             (not (getenv "SATAN_FAILOVER_TO_SYSTEM_DB")))
    (error "satan-test: refusing to run batch tests against production socket; set SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB"))
  (ert-delete-all-tests)
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
                unexpected total skipped (or loaderr ""))))))

(provide 'satan-test)
;;; satan-test.el ends here
