;;; satan-credential.el --- Credential seam: recognise, acquire, scrub -*- lexical-binding: t; -*-

;; Governed by DEC-021 (SL-018 design.md sec-2).  SATAN owns the seam; a
;; backend (the keeper's config supplies one over 1Password) answers four
;; operations through `satan-credential-function':
;;
;;   lookup REF          cached plaintext or nil; never prompts
;;   session-p           non-nil when a session is live; never prompts
;;   read REF CONTEXT    plaintext, or signals; MAY prompt (CONTEXT labels it)
;;   forget REF          evict REF from the backend's cache
;;
;; Every public function takes ENV, the environment list the child will
;; receive, and never calls `getenv'.  A var whose value matches
;; `satan-credential-ref-regexp' is a reference, never a literal key.
;;
;; Error boundary: no backend signal escapes this module.  `acquire' turns
;; one into `(:unavailable ERR)', `ready-p' into nil, `resolve' into a
;; per-var failure, `forget' into its return value.
;;
;; No backend (nil): lookup and session-p read as nil and read signals
;; `satan-credential-no-backend', so a ref defers or is unavailable and
;; never reaches a child (fail closed, REQ-010).

;;; Code:

(require 'cl-lib)
(require 'satan-custom)

(defcustom satan-credential-ref-regexp "\\`op://"
  "A value matching this is a credential reference, never a literal key."
  :type 'regexp :group 'satan)

(defcustom satan-credential-function nil
  "Credential backend, called as (OP &rest ARGS); nil means no backend.
See the commentary of `satan-credential' for the four operations."
  :type '(choice (const :tag "None" nil) function) :group 'satan)

(define-error 'satan-credential-no-backend "No credential backend configured")

(defun satan-credential--call (op &rest args)
  "Call the backend's OP with ARGS.  May signal; callers own the boundary."
  (cond
   (satan-credential-function (apply satan-credential-function op args))
   ((eq op 'read) (signal 'satan-credential-no-backend (list (car args))))))

(defun satan-credential--value (env var)
  "VAR's value in ENV, as `getenv' would find it (first entry wins)."
  (let ((prefix (concat var "=")))
    (cl-loop for kv in env
             when (and (stringp kv) (string-prefix-p prefix kv))
             return (substring kv (length prefix)))))

(defun satan-credential--ref-p (value)
  "Non-nil when VALUE is a credential reference."
  (and (stringp value) (string-match-p satan-credential-ref-regexp value)))

(defun satan-credential--partition (env vars)
  "Look up each ref-valued var of VARS in ENV against the backend cache.
Returns (:env RESOLVED :refs REFS :pending PENDING :failed FAILED):
RESOLVED lists \"VAR=plaintext\" for cached refs, REFS every
\(VAR . REF) that is a reference, PENDING the uncached (VAR . REF),
FAILED each (VAR . ERR) whose lookup signalled.  Unset and literal
vars are skipped: the child already gets them from ENV."
  (let (resolved refs pending failed)
    (dolist (var vars)
      (let ((ref (satan-credential--value env var)))
        (when (satan-credential--ref-p ref)
          (push (cons var ref) refs)
          (condition-case err
              (let ((val (satan-credential--call 'lookup ref)))
                (if val
                    (push (concat var "=" val) resolved)
                  (push (cons var ref) pending)))
            (error (push (cons var err) failed))))))
    (list :env (nreverse resolved) :refs (nreverse refs)
          :pending (nreverse pending) :failed (nreverse failed))))

(defun satan-credential--session-p ()
  "Non-nil when the backend reports a live session; nil if it signals."
  (ignore-errors (satan-credential--call 'session-p)))

(defun satan-credential--read (var ref context)
  "\"VAR=plaintext\" for REF, read under CONTEXT.  May signal."
  (concat var "=" (satan-credential--call 'read ref context)))

(defun satan-credential-ready-p (env vars)
  "Non-nil when VARS in ENV can be resolved without a prompt.
True when no ref is uncached, or a session is live.  Never reads."
  (let ((part (satan-credential--partition env vars)))
    (and (null (plist-get part :failed))
         (or (null (plist-get part :pending))
             (satan-credential--session-p)))))

(defun satan-credential-acquire (env vars policy context)
  "Strictly resolve the refs among VARS in ENV under POLICY.
POLICY is `prompt' or `defer'; CONTEXT labels any read.  Returns
\(:env (\"VAR=v\" …) :refs ((VAR . REF) …)) when every ref resolves,
\(:deferred) when refs are uncached, no session is live and POLICY is
`defer', else (:unavailable ERR).  Never signals."
  (condition-case err
      (let* ((part (satan-credential--partition env vars))
             (pending (plist-get part :pending))
             (failed (plist-get part :failed)))
        (cond
         (failed (list :unavailable (cdar failed)))
         ((and pending
               (not (satan-credential--call 'session-p))
               (eq policy 'defer))
          '(:deferred))
         (t (list :env (append (plist-get part :env)
                               (mapcar (lambda (p)
                                         (satan-credential--read
                                          (car p) (cdr p) context))
                                       pending))
                  :refs (plist-get part :refs)))))
    (error (list :unavailable err))))

(defun satan-credential-resolve (env vars context)
  "Leniently resolve the refs among VARS in ENV, reading under CONTEXT.
Returns (:env (\"VAR=v\" …) :failed ((VAR . ERR) …)): a var whose
lookup or read signals is recorded and the rest still resolve.  Does
not probe the session: call `satan-credential-ready-p' first.  Never
signals."
  (let* ((part (satan-credential--partition env vars))
         (failed (plist-get part :failed))
         (read-ok nil))
    (dolist (p (plist-get part :pending))
      (condition-case err
          (push (satan-credential--read (car p) (cdr p) context) read-ok)
        (error (push (cons (car p) err) failed))))
    (list :env (append (plist-get part :env) (nreverse read-ok))
          :failed failed)))

(defun satan-credential-scrub (env)
  "ENV without its \"VAR=ref\" entries, so no reference reaches a child."
  (cl-remove-if (lambda (kv)
                  (and (stringp kv)
                       (when-let* ((eq (string-search "=" kv)))
                         (satan-credential--ref-p (substring kv (1+ eq))))))
                env))

(defun satan-credential-forget (ref)
  "Evict REF from the backend's cache.  Nil on success, else the error.
Never signals; with no backend there is nothing to evict."
  (condition-case err
      (progn (satan-credential--call 'forget ref) nil)
    (error err)))

(provide 'satan-credential)
;;; satan-credential.el ends here
