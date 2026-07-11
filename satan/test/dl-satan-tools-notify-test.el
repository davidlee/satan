;;; dl-satan-tools-notify-test.el --- ert tests for dl-satan-tools-notify -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-tools-notify-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tools)
(require 'dl-satan-tools-notify)
(require 'dl-satan-intervention)

(defconst dl-satan-notify-test--ctx
  '(:id "20260523T120000-morning-deadbe"
    :mode-name "morning"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities (notify)
    :audit dl-satan-notify-test--stub-audit)
  "Synthetic tool-ctx used by every notify dispatch test.
\\=`:audit' carries a sentinel symbol; the stubbed intervention-create
ignores it.")

(defmacro dl-satan-notify-test--with-stubs (&rest body)
  "Stub `notifications-notify' (returns 42) and capture intervention writes.
Inside BODY, the symbol `dl-satan-notify-test--captured' is a list of
keyword-args plists handed to `dl-satan-intervention-create'."
  (declare (indent 0))
  `(let ((dl-satan-notify-test--captured '()))
     (cl-letf (((symbol-function 'notifications-notify)
                (lambda (&rest _args) 42))
               ((symbol-function 'dl-satan-intervention-create)
                (lambda (&rest args)
                  (push args dl-satan-notify-test--captured)
                  "iv-stub-01")))
       ,@body)))

(ert-deftest dl-satan-notify/dispatch-ok ()
  "notify.send dispatches via the registry, stubbing the D-Bus call."
  (dl-satan-notify-test--with-stubs
    (let ((res (dl-satan-tool-dispatch
                '(:type "tool_call" :id "n1" :name "notify_send"
                  :args (:title "hi" :body "there"))
                '("notify_send")
                dl-satan-notify-test--ctx)))
      (should (eq (plist-get res :ok) t))
      (should (equal 42 (plist-get (plist-get res :result) :id))))))

(ert-deftest dl-satan-notify/dispatch-surfaces-intervention-id ()
  "tool_result carries the intervention_id minted by the write API."
  (dl-satan-notify-test--with-stubs
    (let ((res (dl-satan-tool-dispatch
                '(:type "tool_call" :id "n1" :name "notify_send"
                  :args (:title "hi" :body "there"))
                '("notify_send")
                dl-satan-notify-test--ctx)))
      (should (equal "iv-stub-01"
                     (plist-get (plist-get res :result) :intervention_id))))))

(ert-deftest dl-satan-notify/intervention-args-shape ()
  "Handler passes the §3.1 metadata into `dl-satan-intervention-create'."
  (dl-satan-notify-test--with-stubs
    (dl-satan-tool-dispatch
     '(:type "tool_call" :id "n1" :name "notify_send"
       :args (:title "hi" :body "do the thing" :urgency "critical"))
     '("notify_send")
     dl-satan-notify-test--ctx)
    (let ((args (car dl-satan-notify-test--captured)))
      (should args)
      (should (equal "notify"        (plist-get args :kind)))
      (should (equal "dbus"          (plist-get args :target-surface)))
      (should (equal "high"          (plist-get args :severity)))
      (should (equal 30              (plist-get args :outcome-window-minutes)))
      (should (string-match-p "hi"        (plist-get args :message)))
      (should (string-match-p "do the"    (plist-get args :message))))))

(ert-deftest dl-satan-notify/severity-defaults-medium ()
  "Default urgency maps to medium severity."
  (dl-satan-notify-test--with-stubs
    (dl-satan-tool-dispatch
     '(:type "tool_call" :id "n1" :name "notify_send"
       :args (:title "t" :body "b"))
     '("notify_send")
     dl-satan-notify-test--ctx)
    (should (equal "medium"
                   (plist-get (car dl-satan-notify-test--captured) :severity)))))

(ert-deftest dl-satan-notify/schema-missing-title ()
  (let ((res (dl-satan-tool-dispatch
              '(:type "tool_call" :id "n2" :name "notify_send"
                :args (:body "x"))
              '("notify_send")
              dl-satan-notify-test--ctx)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "title" (plist-get res :error)))))

(ert-deftest dl-satan-notify/schema-urgency-enum ()
  (let ((res (dl-satan-tool-dispatch
              '(:type "tool_call" :id "n3" :name "notify_send"
                :args (:title "t" :body "b" :urgency "screaming"))
              '("notify_send")
              dl-satan-notify-test--ctx)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "urgency" (plist-get res :error)))))

(ert-deftest dl-satan-notify/handler-error-propagates ()
  "If `notifications-notify' signals, the result is `error' with message."
  (cl-letf (((symbol-function 'notifications-notify)
             (lambda (&rest _args) (error "no D-Bus today")))
            ((symbol-function 'dl-satan-intervention-create)
             (lambda (&rest _args) "iv-unused")))
    (let ((res (dl-satan-tool-dispatch
                '(:type "tool_call" :id "n4" :name "notify_send"
                  :args (:title "t" :body "b"))
                '("notify_send")
                dl-satan-notify-test--ctx)))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "no D-Bus" (plist-get res :error))))))

(provide 'dl-satan-tools-notify-test)
;;; dl-satan-tools-notify-test.el ends here
