;;; satan-tools-vcs-test.el --- vcs_log ert -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-vcs-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-vcs)

(defmacro satan-tools-vcs-test--in-repo (var &rest body)
  "Create a tmp git repo with one commit; bind VAR to its path; run BODY."
  (declare (indent 1))
  `(let ((,var (make-temp-file "satan-vcs-test-" t)))
     (unwind-protect
         (let ((default-directory (file-name-as-directory ,var)))
           (call-process "git" nil nil nil "init" "-q" "-b" "main")
           (call-process "git" nil nil nil "config" "user.email" "t@example")
           (call-process "git" nil nil nil "config" "user.name" "T")
           (with-temp-file (expand-file-name "x" ,var) (insert "y"))
           (call-process "git" nil nil nil "add" "x")
           (call-process "git" nil nil nil "commit" "-qm" "init commit")
           ,@body)
       (delete-directory ,var t))))

(ert-deftest satan-tools-vcs/log-ok-pwd-independent ()
  "Returns history for an abs-path repo WITHOUT relying on
`default-directory' (deliberately pointed elsewhere)."
  (skip-unless (executable-find "git"))
  (satan-tools-vcs-test--in-repo repo
    (let* ((default-directory temporary-file-directory)
           (result (satan-tool/vcs-log (list :repo repo) nil)))
      (should (eq 'ok (car result)))
      (let ((commits (plist-get (cdr result) :commits)))
        (should (= 1 (length commits)))
        (should (equal "init commit" (plist-get (car commits) :subject)))
        (should (stringp (plist-get (car commits) :sha)))
        (should (stringp (plist-get (car commits) :at)))))))

(ert-deftest satan-tools-vcs/not-found ()
  (let ((result (satan-tool/vcs-log
                 (list :repo "/no/such/repo/anywhere-xyz123") nil)))
    (should (eq 'error (car result)))
    (should (string-match-p "repo not found" (cdr result)))))

(ert-deftest satan-tools-vcs/not-a-git-repo ()
  (skip-unless (executable-find "git"))
  (let ((tmp (make-temp-file "satan-vcs-nogit-" t)))
    (unwind-protect
        (let ((result (satan-tool/vcs-log (list :repo tmp) nil)))
          (should (eq 'error (car result)))
          (should (string-match-p "not a git repo" (cdr result))))
      (delete-directory tmp t))))

(ert-deftest satan-tools-vcs/limit-clamp ()
  (should (= 20 (satan-tools-vcs--clamp-limit nil)))
  (should (= 1 (satan-tools-vcs--clamp-limit 0)))
  (should (= 200 (satan-tools-vcs--clamp-limit 9999)))
  (should (= 5 (satan-tools-vcs--clamp-limit 5))))

(provide 'satan-tools-vcs-test)
;;; satan-tools-vcs-test.el ends here
