;;; dl-satan-patch-classify-test.el --- ert for the classifier -*- lexical-binding: t; -*-

(require 'ert)
(require 'dl-satan-patch-classify)

(ert-deftest dl-satan-patch-classify/patch-verbs ()
  (dolist (d '("rewrite this section as a tight brief"
               "implement the canonicalizer"
               "refactor the broker dispatch"
               "add tests for the resonate path"
               "tighten the morning prompt"
               "update the memory grammar"
               "fix the off-by-one in claim-next"
               "extract the SQL helper into its own file"
               "rename foo to bar"))
    (should (eq 'patch (dl-satan-patch-classify d)))))

(ert-deftest dl-satan-patch-classify/dispatch-verbs ()
  (dolist (d '("read agenda for today"
               "scan inbox for unread"
               "show recent traces"
               "list active boughs"
               "mark this observation"
               "summarise yesterday's notes"
               "append an inbox item"
               "notify the user"
               "log a memory note"))
    (should (eq 'dispatch (dl-satan-patch-classify d)))))

(ert-deftest dl-satan-patch-classify/empty-and-noise ()
  (should (eq 'dispatch (dl-satan-patch-classify "")))
  (should (eq 'dispatch (dl-satan-patch-classify nil)))
  (should (eq 'dispatch (dl-satan-patch-classify "🤔"))))

(ert-deftest dl-satan-patch-classify/explain-returns-keyword ()
  (let ((r (dl-satan-patch-classify-explain "rewrite this brief")))
    (should (eq 'patch (car r)))
    (should (string-match-p "rewrite" (cdr r))))
  (let ((r (dl-satan-patch-classify-explain "show recent")))
    (should (eq 'dispatch (car r)))
    (should (string-match-p "show" (cdr r))))
  (let ((r (dl-satan-patch-classify-explain "no verbs at all here")))
    (should (eq 'dispatch (car r)))
    (should (string-match-p "no patch verb" (cdr r)))))

(ert-deftest dl-satan-patch-classify/patch-wins-when-both ()
  "When a directive carries both a patch verb and a dispatch verb,
patch wins — rewrites/refactors are git-diff-shaped regardless of
read-flavoured supporting verbs."
  (should (eq 'patch (dl-satan-patch-classify
                      "read the file and rewrite the second section")))
  (should (eq 'patch (dl-satan-patch-classify
                      "scan the notes and refactor the cluster"))))

(provide 'dl-satan-patch-classify-test)
;;; dl-satan-patch-classify-test.el ends here
