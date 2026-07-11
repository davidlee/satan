;;; dl-satan-tools-agenda-test.el --- ert tests for dl-satan-tools-agenda -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-tools-agenda-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tools)
(require 'dl-satan-tools-agenda)

(defmacro dl-satan-tools-agenda-test--with-gcalcli-stub (status output &rest body)
  "Run BODY with `call-process' stubbed to return STATUS and emit OUTPUT.
Captures the argv passed to call-process in `argv-out'."
  (declare (indent 2))
  `(let ((argv-out nil))
     (cl-letf (((symbol-function 'call-process)
                (lambda (program &optional _in dest _disp &rest args)
                  (setq argv-out (cons program args))
                  (when (and dest (bufferp dest))
                    (with-current-buffer dest (insert ,output)))
                  (when (and dest (eq dest t))
                    (insert ,output))
                  ,status)))
       (let ((process-environment (cons "WORK_EMAIL=test@example.com"
                                        process-environment)))
         ,@body))))

(ert-deftest dl-satan-agenda/handler-ok ()
  "Happy path: agenda_read returns ok + trimmed text + echoed calendar/days."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 0 "Mon May 19  9:00 standup\n"
    (let ((res (dl-satan-tool/agenda-read nil nil)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get (cdr res) :text) "Mon May 19  9:00 standup"))
      (should (equal (plist-get (cdr res) :calendar) "test@example.com"))
      (should (equal (plist-get (cdr res) :days)
                     dl-satan-tools-agenda-default-days)))
    (should (member "timeout" argv-out))
    (should (member "gcalcli" argv-out))
    (should (member "--calendar" argv-out))
    (should (member "test@example.com" argv-out))))

(ert-deftest dl-satan-agenda/handler-respects-days ()
  "`:days' overrides the default and shows up in the response."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 0 ""
    (let ((res (dl-satan-tool/agenda-read '(:days 3) nil)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get (cdr res) :days) 3)))))

(ert-deftest dl-satan-agenda/days-clamped ()
  "Out-of-range `:days' is clamped to [1, agenda--days-max]."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 0 ""
    (let ((hi (dl-satan-tool/agenda-read '(:days 99) nil))
          (lo (dl-satan-tool/agenda-read '(:days 0) nil)))
      (should (equal (plist-get (cdr hi) :days)
                     dl-satan-tools-agenda--days-max))
      (should (equal (plist-get (cdr lo) :days) 1)))))

(ert-deftest dl-satan-agenda/missing-calendar-env ()
  "Unset env var yields a structured error, no process spawn."
  (let* ((spawned nil)
         (process-environment (cl-remove-if
                               (lambda (e) (string-prefix-p "WORK_EMAIL=" e))
                               process-environment)))
    (cl-letf (((symbol-function 'call-process)
               (lambda (&rest _) (setq spawned t) 0)))
      (let ((res (dl-satan-tool/agenda-read nil nil)))
        (should (eq (car res) 'error))
        (should (string-match-p "WORK_EMAIL" (cdr res)))
        (should-not spawned)))))

(ert-deftest dl-satan-agenda/handler-nonzero-exit ()
  "Non-zero exit surfaces stderr/stdout in the error string."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 1 "auth failure\n"
    (let ((res (dl-satan-tool/agenda-read nil nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "auth failure" (cdr res))))))

(ert-deftest dl-satan-agenda/handler-timeout ()
  "Status 124 from `timeout(1)' is reported as a timeout."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 124 ""
    (let ((res (dl-satan-tool/agenda-read nil nil)))
      (should (eq (car res) 'error))
      (should (string-match-p "timed out" (cdr res))))))

(ert-deftest dl-satan-agenda/dispatch-mode-allowlist ()
  "agenda_read is allowed in morning and motd, blocked elsewhere."
  (dl-satan-tools-agenda-test--with-gcalcli-stub 0 "x"
    (let ((ok (dl-satan-tool-dispatch
               '(:type "tool_call" :id "a1" :name "agenda_read" :args nil)
               '("agenda_read")
               nil))
          (blocked (dl-satan-tool-dispatch
                    '(:type "tool_call" :id "a2" :name "agenda_read" :args nil)
                    '("inbox_append")
                    nil)))
      (should (eq (plist-get ok :ok) t))
      (should (equal (plist-get blocked :ok) :false))
      (should (string-match-p "not allowed" (plist-get blocked :error))))))

(provide 'dl-satan-tools-agenda-test)
;;; dl-satan-tools-agenda-test.el ends here
