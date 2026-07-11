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

(provide 'satan-mode-test)
;;; satan-mode-test.el ends here
