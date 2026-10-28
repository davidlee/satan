;;; satan-tools-activity-test.el --- ert tests for satan-tools-activity -*- lexical-binding: t; -*-

;; Run from CLI, at the repo root:
;;   emacs --batch \
;;     -L satan -L dev -L satan/test \
;;     -l satan-tools-activity-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-activity)
(require 'satan-desktop-fixture)
(require 'satan-keyrate-fixture)
(require 'seq)

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

(defun satan-tools-activity-test--ago (seconds)
  "A +10:00 timestamp SECONDS before the wall-clock now."
  (format-time-string "%FT%T+10:00" (time-subtract nil seconds)
                      satan-desktop-fixture-zone))

(defun satan-tools-activity-test--write-desktop (events)
  "Write EVENTS to the raw day files their `:ts' dates name."
  (pcase-dolist (`(,day . ,group)
                 (seq-group-by (lambda (e) (substring (plist-get e :ts) 0 10))
                               events))
    (satan-desktop-fixture-write satan-tools-activity-dir day group)))

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

(ert-deftest satan-activity/current-returns-replayed-window ()
  "Scope `current' replays the focused window from the raw desktop log."
  (satan-desktop-fixture-with-root satan-tools-activity-dir
    (let ((ts (satan-tools-activity-test--ago 60)))
      (satan-tools-activity-test--write-desktop
       (list (satan-desktop-fixture-event
              ts "snapshot" :app_id "emacs" :title "~/notes/foo.org"
              :workspace "09" :output "DP-3" :pid 4242)))
      (let* ((res (satan-tool/activity-read '(:scope "current") nil))
             (p (cdr res))
             (w (plist-get p :window)))
        (should (eq (car res) 'ok))
        (should (equal (plist-get p :scope) "current"))
        (should (equal (plist-get p :status) "ok"))
        (should (equal (plist-get w :app_id) "emacs"))
        (should (equal (plist-get w :workspace) "09"))
        (should (equal (plist-get w :title) "~/notes/foo.org"))
        (should (equal (plist-get w :since) ts))
        (should-not (plist-member p :path))))))

(ert-deftest satan-activity/current-disconnected-after-disconnect ()
  "A compositor disconnect after the last snapshot leaves no window."
  (satan-desktop-fixture-with-root satan-tools-activity-dir
    (satan-tools-activity-test--write-desktop
     (list (satan-desktop-fixture-event
            (satan-tools-activity-test--ago 120) "snapshot"
            :app_id "emacs" :workspace "09")
           (satan-desktop-fixture-event
            (satan-tools-activity-test--ago 60) "compositor_disconnected")))
    (let* ((res (satan-tool/activity-read '(:scope "current") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :status) "disconnected"))
      (should (null (plist-get p :window))))))

(ert-deftest satan-activity/current-missing-without-files ()
  "No raw desktop files yields ok with status missing and no window."
  (satan-desktop-fixture-with-root satan-tools-activity-dir
    (let* ((res (satan-tool/activity-read '(:scope "current") nil))
           (p (cdr res)))
      (should (eq (car res) 'ok))
      (should (equal (plist-get p :status) "missing"))
      (should (null (plist-get p :window)))
      (should-not (plist-member p :path)))))

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

;; ── keyrate presence (IMP-055) ──────────────────────────────────────────────

(defun satan-tools-activity-test--segment (event start-ago end-ago app)
  "A segment line of EVENT for APP from START-AGO to END-AGO seconds ago."
  (json-encode
   `((v . 1) (event . ,event) (app_id . ,app)
     (start_ts . ,(satan-tools-activity-test--ago start-ago))
     (end_ts . ,(satan-tools-activity-test--ago end-ago))
     (duration_s . ,(- start-ago end-ago)))))

(defun satan-tools-activity-test--keyrate (&rest minutes)
  "Write MINUTES, each (AGO KEY POINTER), to today's keyrate file."
  (satan-keyrate-fixture-write
   satan-tools-activity-dir (satan-tools-activity-test--today)
   (mapcar (pcase-lambda (`(,ago ,key ,pointer))
             (satan-keyrate-fixture-minute
              (satan-tools-activity-test--ago ago) key pointer))
           minutes)))

(defun satan-tools-activity-test--three-focus-segments ()
  "A 10 s hop from A to B, then 200 s of nothing, then C until 300 s ago."
  (make-directory (expand-file-name "segments" satan-tools-activity-dir) t)
  (satan-tools-activity-test--write-focus-jsonl
   satan-tools-activity-dir
   (list (satan-tools-activity-test--segment "focus_segment" 900 840 "a")
         (satan-tools-activity-test--segment "focus_segment" 830 600 "b")
         (satan-tools-activity-test--segment "focus_segment" 400 300 "c"))))

(defun satan-tools-activity-test--shape (segments)
  "SEGMENTS as (EVENT APP PRESENCE) triples."
  (mapcar (lambda (s) (list (plist-get s :event) (plist-get s :app_id)
                            (plist-get s :presence)))
          segments))

(ert-deftest satan-activity/recent-focus-is-a-timeline-with-presence ()
  "Segments carry key/pointer seconds and presence; a gap of a minute or
more between segments, or after the last one until now, is an entry of
its own, so a closed segment followed by nothing never reads as ongoing."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (satan-tools-activity-test--three-focus-segments)
    (satan-tools-activity-test--keyrate '(900 60 0) '(400 0 50))
    (let* ((p (cdr (satan-tool/activity-read '(:scope "recent_focus") nil)))
           (segs (plist-get p :segments)))
      (should (equal (plist-get p :keyrate) "ok"))
      (should (equal (satan-tools-activity-test--shape segs)
                     '(("focus_segment" "a" "typing")
                       ("focus_segment" "b" "idle")
                       ("gap" nil "idle")
                       ("focus_segment" "c" "reading")
                       ("gap" nil "idle"))))
      (should (equal (plist-get (nth 0 segs) :key_seconds) 60))
      (should (equal (plist-get (nth 3 segs) :pointer_seconds) 50))
      (should (equal (plist-get (nth 2 segs) :duration_s) 200))
      (should-not (plist-get (nth 2 segs) :open))
      (should (eq (plist-get (nth 4 segs) :open) t))
      (should (equal (plist-get (nth 2 segs) :start_ts)
                     (plist-get (nth 1 segs) :end_ts))))))

(ert-deftest satan-activity/recent-focus-gaps-without-keyrate ()
  "With no keyrate file, gaps still show; nothing carries a presence."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (satan-tools-activity-test--three-focus-segments)
    (let ((p (cdr (satan-tool/activity-read '(:scope "recent_focus") nil))))
      (should (equal (plist-get p :keyrate) "missing"))
      (should (equal (satan-tools-activity-test--shape (plist-get p :segments))
                     '(("focus_segment" "a" nil) ("focus_segment" "b" nil)
                       ("gap" nil nil) ("focus_segment" "c" nil)
                       ("gap" nil nil)))))))

(ert-deftest satan-activity/recent-browser-segments-carry-presence ()
  "Browser segments are annotated too, without gaps: leaving the browser
is not a gap in attention."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (make-directory (expand-file-name "segments" satan-tools-activity-dir) t)
    (satan-tools-activity-test--write-browser-jsonl
     satan-tools-activity-dir
     (list (satan-tools-activity-test--segment "browser_tab_segment" 900 840 "f")
           (satan-tools-activity-test--segment "browser_tab_segment" 400 340 "f")))
    (satan-tools-activity-test--keyrate '(400 0 30))
    (should (equal (satan-tools-activity-test--shape
                    (plist-get (cdr (satan-tool/activity-read
                                     '(:scope "recent_browser") nil))
                               :segments))
                   '(("browser_tab_segment" "f" "idle")
                     ("browser_tab_segment" "f" "reading"))))))

(ert-deftest satan-activity/today-carries-presence-per-hour ()
  "Scope `today' adds today's key and pointer seconds, per hour and in total."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (let ((day (satan-tools-activity-test--today)))
      (satan-keyrate-fixture-write
       satan-tools-activity-dir day
       (list (satan-keyrate-fixture-minute (format "%sT09:00:00.000+10:00" day) 10 1)
             (satan-keyrate-fixture-minute (format "%sT09:30:00.000+10:00" day) 5 2)))
      (let ((presence (plist-get (cdr (satan-tool/activity-read
                                       '(:scope "today") nil))
                                 :presence)))
        (should (equal (plist-get presence :status) "ok"))
        (should (equal (plist-get presence :key_seconds) 15))
        (should (equal (plist-get presence :pointer_seconds) 3))
        (should (equal (nth 9 (plist-get presence :per_hour_key_seconds)) 15))))))

(ert-deftest satan-activity/today-presence-missing-without-keyrate ()
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (should (equal (plist-get (cdr (satan-tool/activity-read '(:scope "today") nil))
                              :presence)
                   '(:status "missing")))))

(ert-deftest satan-activity/current-carries-recent-presence ()
  "Scope `current' adds presence over the last `satan-keyrate-window-minutes'."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (satan-tools-activity-test--keyrate '(120 1 60))
    (let ((presence (plist-get (cdr (satan-tool/activity-read
                                     '(:scope "current") nil))
                               :presence)))
      (should (equal (plist-get presence :presence) "reading"))
      (should (equal (plist-get presence :key_seconds) 1))
      (should (equal (plist-get presence :window_minutes) 10)))))

;; ── per-window typing (IMP-059) ────────────────────────────────────────────

(defun satan-tools-activity-test--window (ago app title keys key-seconds)
  "A window row AGO seconds ago: KEYS in KEY-SECONDS into APP's TITLE."
  (satan-keyrate-fixture-window (satan-tools-activity-test--ago ago)
                                app title keys key-seconds))

(defun satan-tools-activity-test--typing-rows ()
  "Today's keyrate file: one minute split across two windows, one minute
typed with nothing focused (minute row only)."
  (satan-keyrate-fixture-write
   satan-tools-activity-dir (satan-tools-activity-test--today)
   (list (satan-keyrate-fixture-minute (satan-tools-activity-test--ago 120) 50 0)
         (satan-tools-activity-test--window 120 "emacs" "a.el" 100 40)
         (satan-tools-activity-test--window 120 "ghostty" "zsh" 60 30)
         (satan-keyrate-fixture-minute (satan-tools-activity-test--ago 60) 20 0))))

(ert-deftest satan-activity/today-types-from-raw-windows-not-the-histogram ()
  "Scope `today' computes typing from today's raw window rows, with titles;
the histogram's lagging `typing_per_app' copy is dropped.  Presence still
counts minute rows only: the split minute's 50 s, not 40 + 30."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (make-directory (expand-file-name "histograms" satan-tools-activity-dir) t)
    (satan-tools-activity-test--write-histogram
     satan-tools-activity-dir
     "{\"per_app_seconds\":{\"emacs\":1},\"typing_per_app\":{\"emacs\":{\"keys\":1}}}")
    (satan-tools-activity-test--typing-rows)
    (let ((p (cdr (satan-tool/activity-read '(:scope "today") nil))))
      (should (equal (plist-get p :typing)
                     '((:app_id "emacs" :keys 100 :key_seconds 40 :wpm 30.0
                        :titles ((:title "a.el" :keys 100 :key_seconds 40 :wpm 30.0)))
                       (:app_id "ghostty" :keys 60 :key_seconds 30 :wpm 24.0
                        :titles ((:title "zsh" :keys 60 :key_seconds 30 :wpm 24.0))))))
      (should (plist-get (plist-get p :histogram) :per_app_seconds))
      (should-not (plist-member (plist-get p :histogram) :typing_per_app))
      (should (equal (plist-get (plist-get p :presence) :key_seconds) 70)))))

(ert-deftest satan-activity/recent-focus-segments-carry-their-app-typing ()
  "A focus segment carries its app's typing; titles only with `:titles'.
Gaps carry none: they have no app."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (make-directory (expand-file-name "segments" satan-tools-activity-dir) t)
    (satan-tools-activity-test--write-focus-jsonl
     satan-tools-activity-dir
     (list (satan-tools-activity-test--segment "focus_segment" 120 60 "emacs")))
    (satan-tools-activity-test--typing-rows)
    (cl-flet ((segments (args)
                (plist-get (cdr (satan-tool/activity-read args nil)) :segments)))
      (let ((plain (segments '(:scope "recent_focus")))
            (titled (segments '(:scope "recent_focus" :titles t))))
        (should (equal (plist-get (car plain) :typing)
                       '(:app_id "emacs" :keys 100 :key_seconds 40 :wpm 30.0)))
        (should (equal (plist-get (plist-get (car titled) :typing) :titles)
                       '((:title "a.el" :keys 100 :key_seconds 40 :wpm 30.0))))
        (should (equal (plist-get (cadr plain) :event) "gap"))
        (should-not (plist-member (cadr plain) :typing))))))

(ert-deftest satan-activity/current-carries-recent-typing-per-window ()
  "Scope `current' adds typing per app and title over the presence window."
  (satan-keyrate-fixture-with-root satan-tools-activity-dir
    (satan-tools-activity-test--typing-rows)
    (let ((typing (plist-get (cdr (satan-tool/activity-read '(:scope "current") nil))
                             :typing)))
      (should (equal (mapcar (lambda (app) (plist-get app :app_id)) typing)
                     '("emacs" "ghostty")))
      (should (equal (plist-get (car typing) :titles)
                     '((:title "a.el" :keys 100 :key_seconds 40 :wpm 30.0)))))))

(ert-deftest satan-activity/dispatch-accepts-titles-on-every-scope ()
  "`titles' is declared once, so no scope rejects it; scopes that always or
never list titles ignore it."
  (satan-tools-activity-test--with-root
    (dolist (scope '("today" "recent_focus" "recent_browser" "current"))
      (should (eq (plist-get (satan-tool-dispatch
                              `(:type "tool_call" :id "ar2" :name "activity_read"
                                :args (:scope ,scope :titles t))
                              '("activity_read") nil)
                             :ok)
                  t)))))

(provide 'satan-tools-activity-test)
;;; satan-tools-activity-test.el ends here
