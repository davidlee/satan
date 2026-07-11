;;; satan-tools-activity-test.el --- ert tests for satan-tools-activity -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-activity-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-activity)

(defmacro satan-tools-activity-test--with-root (&rest body)
  "Bind `satan-tools-activity-dir' to a temp dir for BODY."
  (declare (indent 0))
  `(let* ((dir (make-temp-file "satan-activity-" t))
          (satan-tools-activity-dir dir))
     (make-directory (expand-file-name "histograms" dir) t)
     (make-directory (expand-file-name "segments" dir) t)
     (unwind-protect (progn ,@body)
       (delete-directory dir t))))

(defun satan-tools-activity-test--today ()
  (format-time-string "%Y-%m-%d"))

(defun satan-tools-activity-test--write-histogram (dir payload)
  (let ((path (expand-file-name
               (format "histograms/daily-%s.json"
                       (satan-tools-activity-test--today))
               dir)))
    (with-temp-file path (insert payload))
    path))

(defun satan-tools-activity-test--write-focus-jsonl (dir lines)
  (let ((path (expand-file-name
               (format "segments/focus-%s.jsonl"
                       (satan-tools-activity-test--today))
               dir)))
    (with-temp-file path
      (dolist (l lines) (insert l) (insert "\n")))
    path))

(defun satan-tools-activity-test--write-browser-jsonl (dir lines)
  (let ((path (expand-file-name
               (format "segments/browser-%s.jsonl"
                       (satan-tools-activity-test--today))
               dir)))
    (with-temp-file path
      (dolist (l lines) (insert l) (insert "\n")))
    path))

(defun satan-tools-activity-test--write-current-sway (dir payload)
  (make-directory (expand-file-name "current" dir) t)
  (let ((path (expand-file-name "current/sway.json" dir)))
    (with-temp-file path (insert payload))
    path))

(ert-deftest satan-activity/today-returns-parsed-histogram ()
  "Scope `today' reads histograms/daily-<today>.json and returns a plist."
  (satan-tools-activity-test--with-root
    (satan-tools-activity-test--write-histogram
     satan-tools-activity-dir
     "{\"day\":\"2026-05-19\",\"per_app_seconds\":{\"emacs\":42.5},\"per_workspace_seconds\":{\"09\":42.5},\"per_hour_seconds\":[0.0]}")
    (let ((res (satan-tool/activity-read '(:scope "today") nil)))
      (should (eq (car res) 'ok))
      (let* ((p (cdr res))
             (h (plist-get p :histogram)))
        (should (equal (plist-get p :scope) "today"))
        (should (equal (plist-get p :date)
                       (satan-tools-activity-test--today)))
        (should (equal (plist-get h :day) "2026-05-19"))
        (should (equal (plist-get (plist-get h :per_app_seconds) :emacs)
                       42.5))))))

(ert-deftest satan-activity/today-missing-file-returns-nil-histogram ()
  "Missing histogram file yields ok with :histogram nil, not an error."
  (satan-tools-activity-test--with-root
    (let ((res (satan-tool/activity-read '(:scope "today") nil)))
      (should (eq (car res) 'ok))
      (should (null (plist-get (cdr res) :histogram))))))

(ert-deftest satan-activity/recent-focus-returns-tail ()
  "Scope `recent_focus' returns last :limit segments in file order."
  (satan-tools-activity-test--with-root
    (satan-tools-activity-test--write-focus-jsonl
     satan-tools-activity-dir
     (cl-loop for i from 1 to 5 collect
              (format "{\"v\":1,\"app_id\":\"app%d\",\"workspace\":\"01\",\"duration_s\":%d}"
                      i i)))
    (let* ((res (satan-tool/activity-read
                 '(:scope "recent_focus" :limit 2) nil))
           (p (cdr res))
           (segs (plist-get p :segments)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :limit) 2))
      (should (equal (length segs) 2))
      (should (equal (plist-get (car segs) :app_id) "app4"))
      (should (equal (plist-get (cadr segs) :app_id) "app5")))))

(ert-deftest satan-activity/recent-focus-limit-defaults-and-clamps ()
  "Missing :limit uses default; out-of-range clamps to [1, 200]."
  (satan-tools-activity-test--with-root
    (satan-tools-activity-test--write-focus-jsonl
     satan-tools-activity-dir
     '("{\"app_id\":\"a\"}"))
    (let ((default-res (satan-tool/activity-read
                        '(:scope "recent_focus") nil))
          (hi-res (satan-tool/activity-read
                   '(:scope "recent_focus" :limit 9999) nil))
          (lo-res (satan-tool/activity-read
                   '(:scope "recent_focus" :limit 0) nil)))
      (should (equal (plist-get (cdr default-res) :limit)
                     satan-tools-activity-default-limit))
      (should (equal (plist-get (cdr hi-res) :limit)
                     satan-tools-activity--limit-max))
      (should (equal (plist-get (cdr lo-res) :limit) 1)))))

(ert-deftest satan-activity/recent-focus-missing-file-empty-segments ()
  "Missing segments file yields ok with :segments '()."
  (satan-tools-activity-test--with-root
    (let ((res (satan-tool/activity-read
                '(:scope "recent_focus") nil)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get (cdr res) :segments) '())))))

(ert-deftest satan-activity/recent-browser-returns-tail ()
  "Scope `recent_browser' returns last :limit browser segments in order."
  (satan-tools-activity-test--with-root
    (satan-tools-activity-test--write-browser-jsonl
     satan-tools-activity-dir
     (cl-loop for i from 1 to 4 collect
              (format "{\"v\":1,\"origin\":\"site%d.example\",\"duration_s\":%d}"
                      i i)))
    (let* ((res (satan-tool/activity-read
                 '(:scope "recent_browser" :limit 2) nil))
           (p (cdr res))
           (segs (plist-get p :segments)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :scope) "recent_browser"))
      (should (equal (length segs) 2))
      (should (equal (plist-get (car segs) :origin) "site3.example"))
      (should (equal (plist-get (cadr segs) :origin) "site4.example")))))

(ert-deftest satan-activity/recent-browser-missing-file-empty-segments ()
  "Missing browser segments file yields ok with :segments '()."
  (satan-tools-activity-test--with-root
    (let ((res (satan-tool/activity-read
                '(:scope "recent_browser") nil)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get (cdr res) :segments) '())))))

(ert-deftest satan-activity/current-returns-window-snapshot ()
  "Scope `current' returns parsed current/sway.json verbatim (title included)."
  (satan-tools-activity-test--with-root
    (satan-tools-activity-test--write-current-sway
     satan-tools-activity-dir
     "{\"app_id\":\"emacs\",\"title\":\"~/notes/foo.org\",\"workspace\":\"09\",\"output\":\"DP-3\",\"pid\":4242}")
    (let* ((res (satan-tool/activity-read '(:scope "current") nil))
           (p (cdr res))
           (w (plist-get p :window)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :scope) "current"))
      (should (equal (plist-get w :app_id) "emacs"))
      (should (equal (plist-get w :workspace) "09"))
      (should (equal (plist-get w :title) "~/notes/foo.org")))))

(ert-deftest satan-activity/current-missing-file-nil-window ()
  "Missing current/sway.json yields ok with :window nil."
  (satan-tools-activity-test--with-root
    (let ((res (satan-tool/activity-read '(:scope "current") nil)))
      (should (eq (car res) 'ok))
      (should (null (plist-get (cdr res) :window))))))

(ert-deftest satan-activity/unknown-scope-errors ()
  "Unknown :scope is a structured error."
  (let ((res (satan-tool/activity-read '(:scope "tomorrow") nil)))
    (should (eq (car res) 'error))
    (should (string-match-p "unknown scope" (cdr res)))))

(ert-deftest satan-activity/dispatch-schema-enum ()
  "Dispatcher rejects scope values outside the registered enum."
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "ar1" :name "activity_read"
                :args (:scope "yesterday"))
              '("activity_read") nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "must be one of" (plist-get res :error)))))

(provide 'satan-tools-activity-test)
;;; satan-tools-activity-test.el ends here
