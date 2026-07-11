;;; satan-patch-adapter.el --- patch-agent adapter protocol -*- lexical-binding: t; -*-

;; Phase 2.1 of satan/patch-harness.plan.md.  A patch-job runner
;; delegates the actual editing work to an "adapter" — a thin elisp
;; shim that knows how to drive one coding harness (jailed-pi,
;; jailed-zerostack, a test fake, …) inside a prepared worktree.
;;
;; The contract:
;;
;;   adapter-fn  ::  (JOB-SPEC INPUT &key on-finish on-log) -> PROCESS-OR-NIL
;;
;;   JOB-SPEC    ::  the row plist returned by `satan-patch-store-get'.
;;                   `:worktree_path' is already on disk; the adapter must
;;                   set `default-directory' to it and never wander out.
;;   INPUT       ::  the plist produced by `satan-patch-prompt-build':
;;                     :system-prompt-file PATH
;;                     :directive STR
;;                     :timeout-seconds N
;;                     :max-output-bytes N
;;                     :log-path PATH
;;                     :provider STR (optional)
;;                     :model STR    (optional)
;;   on-finish   ::  (lambda (RESULT-PLIST))  invoked exactly once
;;                   when the process terminates (success, failure, or
;;                   timeout).  RESULT-PLIST keys:
;;                     :status        success|failure
;;                     :summary       STR     -- terse human-readable
;;                     :changed-files LIST    -- adapter self-report
;;                     :checks        LIST    -- (:name STR :status STR :output-path PATH)
;;                     :warnings      LIST    -- strings
;;                     :raw-output    PATH    -- jsonl/text log
;;                     :exit-code     N
;;                     :elapsed-seconds N
;;                     :error         STR (optional, when :status=failure)
;;   on-log      ::  (lambda (LINE))  optional per-line streaming hook
;;
;; Adapters register themselves at load time via
;; `satan-patch-adapter-register'.  The runner dispatches by name.

(require 'cl-lib)
(require 'subr-x)

(defvar satan-patch-adapters nil
  "Alist of (NAME . FN) registered patch-agent adapters.
NAME is a string matching the `adapter' column of a `patch_jobs' row.
FN is the adapter function described in the file header.")

(defun satan-patch-adapter-register (name fn)
  "Register adapter FN under NAME, replacing any prior entry."
  (setq satan-patch-adapters
        (cons (cons name fn)
              (cl-remove name satan-patch-adapters
                         :key #'car :test #'equal))))

(defun satan-patch-adapter-lookup (name)
  "Return the adapter function registered under NAME, or nil."
  (cdr (assoc name satan-patch-adapters)))

(cl-defun satan-patch-adapter-invoke
    (name job-spec input &key on-finish on-log)
  "Dispatch INPUT to adapter NAME running against JOB-SPEC.
Errors if NAME is not registered.  Returns the adapter's process
handle (or nil for synchronous adapters).  ON-FINISH and ON-LOG
are forwarded to the adapter; see the module commentary."
  (let ((fn (satan-patch-adapter-lookup name)))
    (unless fn
      (error "satan-patch-adapter: no adapter registered for %S" name))
    (funcall fn job-spec input
             :on-finish on-finish
             :on-log on-log)))

;; ---------------------------------------------------------------------
;; result-plist helpers (used by adapters + runner)
;; ---------------------------------------------------------------------

(defun satan-patch-adapter-result-success (&rest fields)
  "Build a :status success result-plist from FIELDS plist."
  (apply #'list :status 'success fields))

(defun satan-patch-adapter-result-failure (reason &rest fields)
  "Build a :status failure result-plist with :error REASON and FIELDS."
  (apply #'list :status 'failure :error reason fields))

(provide 'satan-patch-adapter)
;;; satan-patch-adapter.el ends here
