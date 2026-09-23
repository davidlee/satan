;;; satan-mode-test.el --- ert for satan-mode -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'satan)  ; pulls in tools + modes so the registry is populated

;; ---------------------------------------------------------------------
;; Mode/tool consistency check (T4)
;; ---------------------------------------------------------------------

(ert-deftest satan-mode/check-tool-references-passes-on-live-registry ()
  "The shipped mode registry must reference only registered tools."
  (should (null (satan-mode-check-tool-references))))

(ert-deftest satan-mode/check-tool-references-signals-on-typo ()
  "Adding a mode that lists a non-existent tool must fail the check."
  (let ((satan-modes
         (cons (cons "fake-mode"
                     (list :name "fake-mode"
                           :tools '("memory_mark" "no_such_tool_xyz")))
               satan-modes)))
    (let ((err (should-error (satan-mode-check-tool-references)
                             :type 'error)))
      (should (string-match-p "no_such_tool_xyz"
                              (error-message-string err))))))

;; ---------------------------------------------------------------------
;; SL-018: credential policy keys (design sec-4)
;; ---------------------------------------------------------------------

(defmacro satan-mode-test--isolated (&rest body)
  "Run BODY with a private mode registry and profile table."
  `(let ((satan-modes nil)
         (satan-profiles '((p . (:credential-policy prompt
                                 :credential-escalate-after 60)))))
     ,@body))

(ert-deftest satan-mode/register-validates-credential-keys ()
  "VT-18: a bad policy or duration signals at registration."
  (satan-mode-test--isolated
    (dolist (bad '((:credential-policy ask)
                   (:credential-policy "prompt")
                   (:credential-escalate-after -1)
                   (:credential-escalate-after "4h")))
      (should-error (satan-mode-register (append '(:name "m") bad))))
    (satan-mode-register '(:name "ok" :credential-policy defer
                           :credential-escalate-after 0))
    (satan-mode-register '(:name "absent"))
    (should (equal (satan-mode-names) '("absent" "ok")))))

(ert-deftest satan-mode/credential-keys-merge-from-profile ()
  "VT-18: a profile carries the keys; the mode's own value wins."
  (satan-mode-test--isolated
    (satan-mode-register '(:name "a" :profile p))
    (satan-mode-register '(:name "b" :profile p :credential-policy defer))
    (should (eq (plist-get (satan-mode-resolve "a") :credential-policy) 'prompt))
    (should (= (plist-get (satan-mode-resolve "a") :credential-escalate-after) 60))
    (should (eq (plist-get (satan-mode-resolve "b") :credential-policy) 'defer))))

(ert-deftest satan-mode/morning-and-motd-prompt ()
  "The modes meant to be seen prompt; the tick pulse defers by absence."
  (should (eq (plist-get (satan-mode-resolve "morning") :credential-policy)
              'prompt))
  (should (eq (plist-get (satan-mode-resolve "motd") :credential-policy)
              'prompt))
  (should-not (plist-get (satan-mode-resolve "tick-pulse") :credential-policy)))

(provide 'satan-mode-test)
;;; satan-mode-test.el ends here
