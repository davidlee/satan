;;; satan-protocol-test.el --- ert tests for satan-protocol -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-protocol-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-protocol)

(defun satan-protocol-test--direction (entry)
  (intern (plist-get entry :direction)))

(defun satan-protocol-test--wire-fixture-p (entry)
  "Non-nil when ENTRY is a wire-protocol fixture (direction in|out).
Skips Phase-0.4 `actions' fixtures which are validated by
`satan-audit-validate-actions', not the wire protocol module."
  (member (plist-get entry :direction) '("in" "out")))

(ert-deftest satan-protocol/fixtures-valid-pass ()
  "Every wire fixture marked `valid' validates clean."
  (dolist (entry (satan-protocol-fixtures))
    (when (and (string= (plist-get entry :kind) "valid")
               (satan-protocol-test--wire-fixture-p entry))
      (let* ((direction (satan-protocol-test--direction entry))
             (msg (plist-get entry :message))
             (err (satan-protocol-validate direction msg)))
        (should (null err))))))

(ert-deftest satan-protocol/fixtures-invalid-fail ()
  "Every wire fixture marked `invalid' validates to a matching reason."
  (dolist (entry (satan-protocol-fixtures))
    (when (and (string= (plist-get entry :kind) "invalid")
               (satan-protocol-test--wire-fixture-p entry))
      (let* ((direction (satan-protocol-test--direction entry))
             (msg (plist-get entry :message))
             (expected (plist-get entry :reason))
             (name (plist-get entry :name))
             (err (satan-protocol-validate direction msg)))
        (should (not (null err)))
        (should
         (equal expected (plist-get err :reason)))
        (ignore name)))))

(ert-deftest satan-protocol/rejects-bad-direction ()
  (should-error (satan-protocol-validate 'sideways
                                            '(:type "ready" :run_id "x"))))

(ert-deftest satan-protocol/tool-result-ok-true-passes ()
  (should (null (satan-protocol-validate
                 'out
                 '(:type "tool_result" :id "c1" :ok t :result (:content ""))))))

(ert-deftest satan-protocol/tool-result-ok-false-passes ()
  (should (null (satan-protocol-validate
                 'out
                 '(:type "tool_result" :id "c1" :ok :false :error "denied")))))

(provide 'satan-protocol-test)
;;; satan-protocol-test.el ends here
