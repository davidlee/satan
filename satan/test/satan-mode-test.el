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
;; Profiles
;; ---------------------------------------------------------------------

(ert-deftest satan-mode/profile-merges-under-mode-keys ()
  "A mode inherits its profile's keys; the mode's own value wins."
  (let ((satan-modes nil)
        (satan-profiles '((p . (:model "p-model")))))
    (satan-mode-register '(:name "a" :profile p))
    (satan-mode-register '(:name "b" :profile p :model "b-model"))
    (should (equal (plist-get (satan-mode-resolve "a") :model) "p-model"))
    (should (equal (plist-get (satan-mode-resolve "b") :model) "b-model"))))

(ert-deftest satan-mode/profiles-carry-model-only ()
  "VT-2 (SL-022): a shipped profile names a model and nothing else (the
gateway owns provider choice), and no registered mode carries a
provider or a credential key."
  (let ((shipped (eval (car (get 'satan-profiles 'standard-value)) t)))
    (should (assq 'deepseek-flash shipped))
    (pcase-dolist (`(,name . ,plist) shipped)
      (should (equal (list name (cl-loop for k in plist by #'cddr collect k))
                     (list name '(:model))))))
  (should (equal (satan-profile-resolve 'deepseek-flash)
                 '(:model "deepseek-flash")))
  (pcase-dolist (`(,name . ,spec) satan-modes)
    (dolist (k '(:provider :credential-policy :credential-escalate-after))
      (should-not (and (plist-member spec k) (list name k))))))

(provide 'satan-mode-test)
;;; satan-mode-test.el ends here
