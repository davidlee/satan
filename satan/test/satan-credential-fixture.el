;;; satan-credential-fixture.el --- fake credential backend for tests -*- lexical-binding: t; -*-

;; A scripted stand-in for `satan-credential-function' (design.md sec-9 "Test
;; seam").  No test calls `op'.  Not a suite file (no -test suffix): suites
;; `require' it.

;;; Code:

(require 'cl-lib)
(require 'satan-credential)

(cl-defun satan-credential-fixture-backend
    (log &key cache session read signal quit)
  "Return a fake backend closure that pushes each call onto LOG's car.
LOG is a cons cell (a one-slot box).  CACHE and READ are alists of
REF → plaintext answering `lookup' and `read'; a `read' of a ref not
in READ signals.  SESSION answers `session-p'.  SIGNAL lists ops that
signal an error instead of answering; QUIT lists ops that signal `quit'
\(the keeper pressing C-g while a read blocks).  `forget' removes REF from CACHE."
  (lambda (op &rest args)
    (push (cons op args) (car log))
    (when (memq op signal)
      (error "fake backend: %s signals" op))
    (when (memq op quit)
      (signal 'quit nil))
    (pcase op
      ('lookup (cdr (assoc (car args) cache)))
      ('session-p session)
      ('read (or (cdr (assoc (car args) read))
                 (error "fake backend: cannot read %s" (car args))))
      ('forget (setq cache (cl-remove (car args) cache
                                      :key #'car :test #'equal))
               nil)
      (_ (error "fake backend: unknown op %s" op)))))

(defmacro satan-credential-fixture-with (spec &rest body)
  "Run BODY with `satan-credential-function' bound to a fake backend.
SPEC is (CALLS-VAR . KEYS): KEYS go to `satan-credential-fixture-backend';
CALLS-VAR is bound to a function returning the backend calls made so
far, oldest first, each as (OP . ARGS); name it `_calls' when unused."
  (declare (indent 1))
  (let ((log (make-symbol "log")))
    `(let* ((,log (list nil))
            (satan-credential-function
             (satan-credential-fixture-backend ,log ,@(cdr spec)))
            (,(car spec) (lambda () (reverse (car ,log)))))
       ,@body)))

(defun satan-credential-fixture-ops (calls)
  "The op symbols of CALLS (as returned by a CALLS-VAR function)."
  (mapcar #'car calls))

(provide 'satan-credential-fixture)
;;; satan-credential-fixture.el ends here
