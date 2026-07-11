;;; satan-block-test.el --- ert tests for satan-block -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-block-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-block)

(ert-deftest satan-block/replace-ok ()
  (let ((file (make-temp-file "satan-block-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "* h\n"
                    "#+begin_satan :block satan :owner SATAN :updated [old]\n"
                    "old body\n"
                    "#+end_satan\n"
                    "* tail\n"))
          (should (eq (satan-block-replace file "satan" "new body") 'ok))
          (let ((s (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "new body\n" s))
            (should-not (string-match-p "old body" s))
            (should (string-match-p ":updated \\[20" s))
            (should (string-match-p "\\* tail" s))))
      (delete-file file))))

(ert-deftest satan-block/multi-match-refuses ()
  (let ((file (make-temp-file "satan-block-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file
            (insert "#+begin_satan :block satan :owner SATAN :updated [a]\nA\n#+end_satan\n\n"
                    "#+begin_satan :block satan :owner SATAN :updated [b]\nB\n#+end_satan\n"))
          (should (eq (satan-block-replace file "satan" "new") 'multi-match)))
      (delete-file file))))

(ert-deftest satan-block/none-match-noop ()
  (let ((file (make-temp-file "satan-block-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "no block here\n"))
          (should (eq (satan-block-replace file "satan" "new") 'none-match)))
      (delete-file file))))

(ert-deftest satan-block/create-at-end ()
  (let ((file (make-temp-file "satan-block-" nil ".org")))
    (unwind-protect
        (progn
          (with-temp-file file (insert "* header\nbody\n"))
          (should (eq (satan-block-create-at-end file "satan" "fresh") 'ok))
          (let ((s (with-temp-buffer (insert-file-contents file) (buffer-string))))
            (should (string-match-p "#\\+begin_satan :block satan :owner SATAN :updated \\[20" s))
            (should (string-match-p "fresh\n#\\+end_satan" s))))
      (delete-file file))))

(provide 'satan-block-test)
;;; satan-block-test.el ends here
