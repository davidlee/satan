;;; dl-satan-tank-test.el --- observation tank ert -*- lexical-binding: t; -*-

;; Pure renderer ert + a fixture-dir test for `dl-satan-tank--read-run-events'.
;; No DB / panopticon / bough access required.

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-tank)

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tank/truncate-shorter-passes-through ()
  (should (equal (dl-satan-tank--truncate "abc" 10) "abc")))

(ert-deftest dl-satan-tank/truncate-longer-appends-ellipsis ()
  (should (equal (dl-satan-tank--truncate "abcdef" 4) "abc…")))

(ert-deftest dl-satan-tank/short-ts-extracts-clock ()
  (should (equal (dl-satan-tank--short-ts "2026-05-20T08:28:38.199+10:00")
                 "08:28:38")))

(ert-deftest dl-satan-tank/short-run-pulls-mode-slug ()
  (should (equal (dl-satan-tank--short-run
                  "20260520T082808-tick-pulse-e44377")
                 "tick-pulse")))

(ert-deftest dl-satan-tank/short-run-passthrough-on-no-match ()
  (should (equal (dl-satan-tank--short-run "not-a-runid") "not-a-runid")))

(ert-deftest dl-satan-tank/summarize-args-plist ()
  (let ((out (dl-satan-tank--summarize-args
              '(:cue ("mode:motd") :limit 5))))
    (should (string-match-p "cue=" out))
    (should (string-match-p "limit=5" out))))

(ert-deftest dl-satan-tank/event-summary-tool-call ()
  (should (equal
           (dl-satan-tank--event-summary
            '(:event "tool-call"
              :payload (:name "memory_resonate"
                        :arguments (:limit 5))))
           "memory_resonate(limit=5)")))

(ert-deftest dl-satan-tank/event-summary-tool-result-error ()
  (should (equal
           (dl-satan-tank--event-summary
            '(:event "tool-result"
              :payload (:name "memory_mark" :ok :false)))
           "memory_mark → error")))

(ert-deftest dl-satan-tank/event-summary-tool-result-ok ()
  (should (equal
           (dl-satan-tank--event-summary
            '(:event "tool-result"
              :payload (:name "memory_mark" :ok t)))
           "memory_mark → ok")))

(ert-deftest dl-satan-tank/event-summary-timeout ()
  (should (equal
           (dl-satan-tank--event-summary
            '(:event "timeout" :payload (:after-seconds 30)))
           "after 30s")))

;; ---------------------------------------------------------------------
;; Pure renderers
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tank/render-evidence-nil ()
  (let ((out (dl-satan-tank--render-evidence nil)))
    (should (string-match-p "EVIDENCE WINDOW" out))
    (should (string-match-p "(unavailable)" out))))

(ert-deftest dl-satan-tank/render-evidence-populated ()
  (let* ((state
          '(:window_start_at "2026-05-20T08:00:00+10:00"
            :window_end_at   "2026-05-20T08:30:00+10:00"
            :current_window (:app_id "firefox"
                             :workspace "09"
                             :title "GitHub · prs")
            :focus_segments (1 2 3)
            :browser_segments (1 2)
            :bough_active
            ((:status "wip" :title "memory tank" :nanoid "abc12345")
             (:status "todo" :title "renormalize cli" :nanoid "def67890"))
            :git_commits
            ((:repo "/tmp/r" :slug "r" :sha "4bd198f6"
              :end_ts "2026-05-20T08:15:00+10:00"))
            :git_window_start_at "2026-05-19T08:30:00+10:00"
            :fs_state (:cwd "/home/david/.emacs.d")
            :truncated_at ("focus_segments_middle")))
         (out (dl-satan-tank--render-evidence state)))
    (should (string-match-p "firefox" out))
    (should (string-match-p "ws=09" out))
    (should (string-match-p "GitHub · prs" out))
    (should (string-match-p "focus:         3 segments" out))
    (should (string-match-p "browser:       2 segments" out))
    (should (string-match-p "bough_active:  2 nodes" out))
    (should (string-match-p "memory tank" out))
    (should (string-match-p "abc12345" out))
    (should (string-match-p "git:           1 commit(s)" out))
    (should (string-match-p "newest 4bd198f6" out))
    (should (string-match-p "/home/david/.emacs.d" out))
    (should (string-match-p "truncated_at:  focus_segments_middle" out))))

;; ---------------------------------------------------------------------
;; Attribute section
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tank/render-attributes-populated ()
  (let* ((snapshot '(("curiosity" . 0.30) ("shame" . 0.50)
                     ("friction" . 0.60)))
         (out (dl-satan-tank--render-attributes snapshot)))
    (should (string-match-p "ATTRIBUTES" out))
    (should (string-match-p "Curiosity" out))
    (should (string-match-p "Shame" out))
    (should (string-match-p "Cruelty" out))
    (should (string-match-p "0\\.30" out))))

(ert-deftest dl-satan-tank/render-attributes-disabled ()
  (let ((out (dl-satan-tank--render-attributes 'disabled)))
    (should (string-match-p "ATTRIBUTES" out))
    (should (string-match-p "(disabled)" out))))

(ert-deftest dl-satan-tank/render-attributes-nil ()
  (let ((out (dl-satan-tank--render-attributes nil)))
    (should (string-match-p "ATTRIBUTES" out))
    (should (string-match-p "(unavailable)" out))))

(ert-deftest dl-satan-tank/gather-attributes-disabled ()
  (let ((dl-satan-attribute-updates-enabled nil))
    (should (eq 'disabled (dl-satan-tank--gather-attributes)))))

(ert-deftest dl-satan-tank/render-traces-empty ()
  (let ((out (dl-satan-tank--render-traces nil)))
    (should (string-match-p "RECENT TRACES (last 0)" out))
    (should (string-match-p "(no traces)" out))))

(ert-deftest dl-satan-tank/render-traces-formats-row ()
  (let* ((rows '((:trace_id "20260520T080000-abc001"
                  :kind "observation" :valence "positive"
                  :observed_end_at "2026-05-20T08:05:00Z"
                  :payload "user pivoted from terminal to docs"
                  :handles ("app:firefox" "surface:browser" "mode:motd"))))
         (out (dl-satan-tank--render-traces rows)))
    (should (string-match-p "RECENT TRACES (last 1)" out))
    (should (string-match-p "observation" out))
    (should (string-match-p "positive" out))
    (should (string-match-p "app:firefox surface:browser mode:motd" out))
    (should (string-match-p "user pivoted from terminal to docs" out))))

(ert-deftest dl-satan-tank/render-events-empty ()
  (let ((out (dl-satan-tank--render-events nil)))
    (should (string-match-p "RECENT EVENTS (last 0)" out))
    (should (string-match-p "(no events)" out))))

(ert-deftest dl-satan-tank/render-events-formats-row ()
  (let* ((events '((:ts "2026-05-20T08:28:38+10:00"
                    :dir "out" :event "tool-call"
                    :run "tick-pulse"
                    :summary "memory_resonate(limit=5)")))
         (out (dl-satan-tank--render-events events)))
    (should (string-match-p "RECENT EVENTS (last 1)" out))
    (should (string-match-p "08:28:38" out))
    (should (string-match-p "tick-pulse" out))
    (should (string-match-p "tool-call" out))
    (should (string-match-p "memory_resonate(limit=5)" out))))

;; ---------------------------------------------------------------------
;; read-run-events fixture
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tank/read-run-events-fixture ()
  (let* ((tmp (make-temp-file "satan-tank-runs-" t))
         (run-id "20260520T100000-tick-pulse-fix001")
         (run-dir (expand-file-name run-id tmp))
         (jsonl (expand-file-name "transcript.jsonl" run-dir))
         (lines (list
                 "{\"ts\":\"2026-05-20T10:00:01+10:00\",\"dir\":\"in\",\"event\":\"ready\",\"payload\":{}}"
                 "{\"ts\":\"2026-05-20T10:00:02+10:00\",\"dir\":\"out\",\"event\":\"tool-call\",\"payload\":{\"name\":\"memory_resonate\",\"arguments\":{\"limit\":5}}}"
                 "garbage-not-json"
                 "{\"ts\":\"2026-05-20T10:00:03+10:00\",\"dir\":\"in\",\"event\":\"tool-result\",\"payload\":{\"name\":\"memory_resonate\",\"ok\":true}}")))
    (unwind-protect
        (progn
          (make-directory run-dir)
          (with-temp-file jsonl
            (insert (mapconcat #'identity lines "\n") "\n"))
          (let* ((dl-satan-runs-dir tmp)
                 (events (dl-satan-tank--read-run-events run-id)))
            (should (= 3 (length events)))
            (should (equal (plist-get (nth 0 events) :event) "ready"))
            (should (equal (plist-get (nth 1 events) :event) "tool-call"))
            (should (equal (plist-get (nth 1 events) :summary)
                           "memory_resonate(limit=5)"))
            (should (equal (plist-get (nth 1 events) :run) "tick-pulse"))
            (should (equal (plist-get (nth 2 events) :summary)
                           "memory_resonate → ok"))))
      (delete-directory tmp t))))

(ert-deftest dl-satan-tank/recent-runs-newest-first ()
  (let ((tmp (make-temp-file "satan-tank-runs-" t)))
    (unwind-protect
        (progn
          (dolist (id '("20260519T080000-tick-pulse-aaa111"
                        "20260520T080000-tick-pulse-bbb222"
                        "20260520T090000-tick-pulse-ccc333"))
            (make-directory (expand-file-name id tmp)))
          (let* ((dl-satan-runs-dir tmp)
                 (out (dl-satan-tank--recent-runs)))
            (should (equal (car out)
                           "20260520T090000-tick-pulse-ccc333"))
            (should (equal (length out) 3))))
      (delete-directory tmp t))))

;; ---------------------------------------------------------------------
;; last-run aggregation + render
;; ---------------------------------------------------------------------

(ert-deftest dl-satan-tank/last-run-state-aggregates ()
  "`--last-run-state' folds usage / tool-call / tool-result / final."
  (let* ((events
          '((:ts "2026-05-20T09:21:32+10:00" :dir "in"
             :event "ready" :payload (:type "ready"))
            (:ts "2026-05-20T09:21:37+10:00" :dir "in"
             :event "log"
             :payload (:kind "usage" :tokens_in 9000 :tokens_out 200
                       :tokens_total 9200))
            (:ts "2026-05-20T09:21:37+10:00" :dir "in"
             :event "tool-call"
             :payload (:id "c1" :name "activity_read"
                       :arguments (:window_minutes 30)))
            (:ts "2026-05-20T09:21:37+10:00" :dir "broker"
             :event "tool-result"
             :payload (:id "c1" :ok t))
            (:ts "2026-05-20T09:21:44+10:00" :dir "in"
             :event "tool-call"
             :payload (:id "c2" :name "memory_resonate"
                       :arguments (:limit 5)))
            (:ts "2026-05-20T09:21:44+10:00" :dir "broker"
             :event "tool-result"
             :payload (:id "c2" :ok :false))
            (:ts "2026-05-20T09:21:52+10:00" :dir "in"
             :event "log"
             :payload (:kind "usage" :tokens_in 1000 :tokens_out 100
                       :tokens_total 29040))
            (:ts "2026-05-20T09:21:52+10:00" :dir "in"
             :event "final"
             :payload (:summary "done" :actions ((:type "x"))))))
         (state (dl-satan-tank--last-run-state
                 "20260520T092127-tick-pulse-1e8e70" events)))
    (should (equal (plist-get state :mode) "tick-pulse"))
    (should (eq (plist-get state :status) 'final))
    (should (equal (plist-get state :tokens_total) 29040))
    (should (equal (length (plist-get state :tool_calls)) 2))
    (should (equal (plist-get (nth 0 (plist-get state :tool_calls)) :name)
                   "activity_read"))
    (should (eq (plist-get (nth 0 (plist-get state :tool_calls)) :ok) t))
    (should (equal (plist-get (nth 0 (plist-get state :tool_calls)) :args)
                   '(:window_minutes 30)))
    (should (eq (plist-get (nth 1 (plist-get state :tool_calls)) :ok) nil))
    (should (equal (plist-get state :final_summary) "done"))
    (should (equal (plist-get state :final_actions) 1))
    (should (numberp (plist-get state :duration_s)))
    (should (>= (plist-get state :duration_s) 19.0))))

(ert-deftest dl-satan-tank/last-run-status-timeout ()
  (let* ((events
          '((:ts "2026-05-20T08:28:08+10:00" :dir "in"
             :event "ready" :payload (:type "ready"))
            (:ts "2026-05-20T08:28:38+10:00" :dir "broker"
             :event "timeout" :payload (:after-seconds 30)))))
    (should (eq (dl-satan-tank--last-run-status events) 'timeout))))

(ert-deftest dl-satan-tank/last-run-status-error ()
  (let* ((events
          '((:ts "2026-05-20T09:03:34+10:00" :dir "in"
             :event "ready" :payload (:type "ready"))
            (:ts "2026-05-20T09:03:42+10:00" :dir "in"
             :event "protocol-error"
             :payload (:error "provider failed")))))
    (should (eq (dl-satan-tank--last-run-status events) 'error))))

(ert-deftest dl-satan-tank/render-last-run-nil ()
  (let ((out (dl-satan-tank--render-last-run nil)))
    (should (string-match-p "LAST RUN" out))
    (should (string-match-p "(no runs yet)" out))))

(ert-deftest dl-satan-tank/render-last-run-formats ()
  (let* ((state (list :run_id "20260520T092127-tick-pulse-1e8e70"
                      :mode "tick-pulse" :status 'final
                      :duration_s 20.0 :tokens_total 29040
                      :tool_calls '((:name "activity_read" :ok t
                                     :args (:window_minutes 30))
                                    (:name "memory_resonate" :ok nil
                                     :args (:limit 5)))
                      :final_summary "Tick at 09:21."
                      :final_actions 0))
         (out (dl-satan-tank--render-last-run state)))
    (should (string-match-p "LAST RUN" out))
    (should (string-match-p "tick-pulse" out))
    (should (string-match-p "status: final" out))
    (should (string-match-p "20.0s" out))
    (should (string-match-p "29040 cumulative" out))
    (should (string-match-p "tcalls: 2" out))
    (should (string-match-p "activity_read +ok +window_minutes=30" out))
    (should (string-match-p "memory_resonate +error +limit=5" out))
    (should (string-match-p "Tick at 09:21" out))))

(provide 'dl-satan-tank-test)
;;; dl-satan-tank-test.el ends here
