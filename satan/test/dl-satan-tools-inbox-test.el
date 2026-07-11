;;; dl-satan-tools-inbox-test.el --- ert tests for dl-satan-tools-inbox -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-tools-inbox-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tools)
(require 'dl-satan-tools-inbox)
(require 'dl-satan-intervention)

(defconst dl-satan-inbox-test--ctx
  '(:id "20260523T120000-motd-deadbe"
    :mode-name "motd"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities (inbox-write)
    :audit dl-satan-inbox-test--stub-audit)
  "Synthetic tool-ctx used by inbox dispatch tests.")

(defmacro dl-satan-inbox-test--with-stubs (&rest body)
  "Capture intervention-create kwarg plists into `…--captured'."
  (declare (indent 0))
  `(let ((dl-satan-inbox-test--captured '()))
     (cl-letf (((symbol-function 'dl-satan-intervention-create)
                (lambda (&rest args)
                  (push args dl-satan-inbox-test--captured)
                  "iv-inbox-stub-01")))
       ,@body)))

(ert-deftest dl-satan-inbox/handler-appends-headline ()
  (let* ((tmp (make-temp-file "satan-inbox-"))
         (dl-satan-inbox-file tmp))
    (unwind-protect
        (dl-satan-inbox-test--with-stubs
          (let* ((res (dl-satan-tool/inbox-append
                       '(:title "Daily plan ready"
                         :body "Focus section blank; nudge to fill in.")
                       dl-satan-inbox-test--ctx)))
            (should (eq (car res) 'ok))
            (let ((text (with-temp-buffer
                          (insert-file-contents tmp)
                          (buffer-string))))
              (should (string-match-p "#\\+title:    SATAN inbox" text))
              (should (string-match-p "^\\* \\[.*\\] Daily plan ready" text))
              (should (string-match-p ":unread:satan:" text))
              (should (string-match-p ":RUN_ID: 20260523T120000-motd-deadbe" text))
              (should (string-match-p "Focus section blank" text)))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest dl-satan-inbox/capability-required ()
  ;; Capability is enforced by the dispatcher (spec `:capability'),
  ;; not the handler — drive through dispatch with the cap absent.
  (let ((res (dl-satan-tool-dispatch
              '(:type "tool_call" :id "c1" :name "inbox_append"
                :args (:title "t" :body "b"))
              '("inbox_append")
              '(:capabilities (write-daily)))))
    (should (eq (plist-get res :ok) :false))
    (should (string-match-p "inbox-write" (plist-get res :error)))))

(ert-deftest dl-satan-inbox/append-preserves-existing ()
  (let* ((tmp (make-temp-file "satan-inbox-"))
         (dl-satan-inbox-file tmp))
    (unwind-protect
        (dl-satan-inbox-test--with-stubs
          (dl-satan-tool/inbox-append
           '(:title "first" :body "a")
           dl-satan-inbox-test--ctx)
          (dl-satan-tool/inbox-append
           '(:title "second" :body "b" :urgency "urgent")
           dl-satan-inbox-test--ctx)
          (let ((text (with-temp-buffer
                        (insert-file-contents tmp)
                        (buffer-string))))
            (should (string-match-p "first" text))
            (should (string-match-p "second" text))
            (should (string-match-p ":urgent:" text))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest dl-satan-inbox/unread-count-matches-tags ()
  (let* ((tmp (make-temp-file "satan-inbox-"))
         (dl-satan-inbox-file tmp))
    (unwind-protect
        (dl-satan-inbox-test--with-stubs
          (should (equal (my/satan-inbox-unread-count) 0))
          (dl-satan-tool/inbox-append
           '(:title "a" :body "x") dl-satan-inbox-test--ctx)
          (dl-satan-tool/inbox-append
           '(:title "b" :body "y") dl-satan-inbox-test--ctx)
          (should (equal (my/satan-inbox-unread-count) 2)))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest dl-satan-inbox/surfaces-intervention-id ()
  "Successful append carries the minted intervention_id."
  (let* ((tmp (make-temp-file "satan-inbox-"))
         (dl-satan-inbox-file tmp))
    (unwind-protect
        (dl-satan-inbox-test--with-stubs
          (let ((res (dl-satan-tool/inbox-append
                      '(:title "t" :body "b")
                      dl-satan-inbox-test--ctx)))
            (should (eq (car res) 'ok))
            (should (equal "iv-inbox-stub-01"
                           (plist-get (cdr res) :intervention_id)))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(ert-deftest dl-satan-inbox/intervention-args-shape ()
  "Handler passes §3.3 defaults into `dl-satan-intervention-create'."
  (let* ((tmp (make-temp-file "satan-inbox-"))
         (dl-satan-inbox-file tmp))
    (unwind-protect
        (dl-satan-inbox-test--with-stubs
          (dl-satan-tool/inbox-append
           '(:title "Daily plan" :body "do the thing")
           dl-satan-inbox-test--ctx)
          (let ((args (car dl-satan-inbox-test--captured)))
            (should args)
            (should (equal "inbox"   (plist-get args :kind)))
            (should (equal tmp       (plist-get args :target-surface)))
            (should (equal "medium"  (plist-get args :severity)))
            (should (equal 30        (plist-get args :outcome-window-minutes)))
            (should (string-match-p "Daily plan"    (plist-get args :message)))
            (should (string-match-p "do the thing"  (plist-get args :message)))
            (should (string-match-p "user reads"
                                    (plist-get args :expected-outcome)))))
      (when (file-exists-p tmp) (delete-file tmp)))))

(provide 'dl-satan-tools-inbox-test)
;;; dl-satan-tools-inbox-test.el ends here
