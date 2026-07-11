;;; dl-secret-test.el --- ert tests for dl-secret -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/lisp -L ~/.emacs.d/satan/test \
;;     -l dl-secret-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-secret)

(ert-deftest dl-secret/scrub-op-refs-env-drops-unresolved-keys ()
  "Env-list scrub removes any KEY=op://… entries before child spawn.

A literal `op://…' ref reaching the child shows up as an opaque
401 `****tial' from the provider.  When op resolution fails the
explicit provider-env entry is absent but the same key can still
inherit from `process-environment'.  The scrub closes that leak."
  (let* ((input '("PATH=/usr/bin"
                  "SATAN_RUN_ID=abc"
                  "DEEPSEEK_API_KEY=op://API_KEYS/DEEPSEEK_API_KEY/credential"
                  "OPENAI_API_KEY=sk-real"
                  "OPENROUTER_API_KEY=op://x/y/z"
                  "BARE=op://still-a-secret"
                  "EMPTY="))
         (got (my/scrub-op-refs-env input)))
    (should (member "PATH=/usr/bin" got))
    (should (member "SATAN_RUN_ID=abc" got))
    (should (member "OPENAI_API_KEY=sk-real" got))
    (should (member "EMPTY=" got))
    (should-not (cl-find-if (lambda (kv)
                              (string-prefix-p "DEEPSEEK_API_KEY=" kv))
                            got))
    (should-not (cl-find-if (lambda (kv)
                              (string-prefix-p "OPENROUTER_API_KEY=" kv))
                            got))
    (should-not (cl-find-if (lambda (kv)
                              (string-prefix-p "BARE=" kv))
                            got))))

(provide 'dl-secret-test)
;;; dl-secret-test.el ends here
