;;; satan-broker-test.el --- ert tests for satan-broker -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/lisp -L ~/.emacs.d/org \
;;     -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-broker-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)                          ; budget gating test parses final.json
(require 'satan-jsonl)
(require 'satan-audit)
(require 'satan-announce)
(require 'satan-broker)
(require 'satan-budget)               ; budget gating cross-cutter
(require 'cl-macs)                       ; cl-letf used in tool-ctx tests
(require 'satan-mode)                 ; manifest-tools-shape resolves "morning"
;; Tool modules must be loaded so each registers via `satan-tool-register'
;; before `satan-broker--build-manifest' looks them up.
(require 'satan-tools-notify)
(require 'satan-tools-hippocampus)
(require 'satan-tools-inbox)
(require 'satan-tools-org)
(require 'satan-tools-agenda)
(require 'satan-tools-activity)
(require 'satan-tools-notes)
(require 'satan-tools-atsatan)
(require 'satan-tools-sway)
(require 'satan-tools-docs)
(require 'satan-tools-memory)
(require 'satan-tools-motive)
(require 'satan-tools-vcs)            ; morning/tick modes reference vcs_log
(require 'satan-trace)                 ; SL-011 tick trace row (VT-1)
(require 'satan-run-test)              ; satan-run-test--mkrun fixture (PHASE-07)

;; Cross-cutter: assertion subject is broker (action-failed audit
;; emission); secondary subject is the tools dispatcher's
;; capability-guard.  Filed under broker per T6 brief.
(ert-deftest satan-broker/capability-denial-emits-failed-action-audit ()
  "On dispatch capability denial, broker writes an `action-failed' audit
record using the canonical failed-action plist shape
`(:action ACTION :reason MSG)' alongside the tool_result record."
  (let* ((mode (list :name "test-mode"
                     :capabilities '(inbox-write)
                     :tools '("notify_send")
                     :budget-tool-calls 4))
         (dir (make-temp-file "satan-cap-audit-" t)))
    (unwind-protect
        (let* ((audit (satan-audit-open
                       dir
                       '(:run_id "rid" :mode (:name "test-mode"))
                       '(:bundle t)
                       (list :run_id "rid"
                             :time_now "2026-05-22T10:00:00+1000")))
               (prepare (list :run_id "rid"
                              :time_now "2026-05-22T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :pre_spawn nil :motive nil))
               (run-ctx (make-satan-run
                         :id "rid" :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir :tool-calls-done 0
                         :status 'running
                         :audit audit
                         :prepare prepare))
               ;; Hold process slot so send-validated has something to call;
               ;; intercept the send instead of touching a real pipe.
               (sent nil))
          (cl-letf (((symbol-function 'satan-jsonl-send)
                     (lambda (_proc obj) (push obj sent))))
            (satan-broker--on-tool-call
             run-ctx
             '(:type "tool_call" :id "c-cap" :name "notify_send"
               :args (:title "t" :body "b"))))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (failed-action (cl-find-if
                                 (lambda (r)
                                   (and (equal (plist-get r :dir) "broker")
                                        (equal (plist-get r :event)
                                               "action-failed")))
                                 records)))
            (should failed-action)
            (let ((payload (plist-get failed-action :payload)))
              (should (plistp payload))
              (let ((action (plist-get payload :action))
                    (reason (plist-get payload :reason)))
                (should (plistp action))
                (should (equal (plist-get action :type) "notify_send"))
                (should (equal (plist-get (plist-get action :args) :title) "t"))
                (should (stringp reason))
                (should (string-match-p "capability" reason))
                (should (string-match-p "notify" reason))))))
      (delete-directory dir t))))

;; ---------- satan-broker tool-ctx ----------

(ert-deftest satan-broker/tool-ctx-shape ()
  "Tool-ctx carries run-id, mode, capabilities, dirs, and frozen time fields
read from the prepare-phase run_ctx plist."
  (let* ((mode '(:name morning :capabilities (memory-write)))
         (start (encode-time '(0 0 10 19 5 2026 nil nil 36000)))
         (prepare (list :run_id "20260519T100000-morning-abc123"
                        :time_now "2026-05-19T10:00:00+1000"
                        :start_time start
                        :evidence nil :percept nil
                        :sensor_status nil :pre_spawn nil :motive nil))
         (run-ctx (make-satan-run
                   :id "20260519T100000-morning-abc123"
                   :mode mode
                   :start-time start
                   :dir "/tmp/satan-run-test"
                   :prepare prepare))
         (tool-ctx (satan-run-tool-ctx run-ctx)))
    (should (equal (plist-get tool-ctx :id)
                   "20260519T100000-morning-abc123"))
    (should (equal (plist-get tool-ctx :mode-name) 'morning))
    (should (equal (plist-get tool-ctx :capabilities) '(memory-write)))
    (should (equal (plist-get tool-ctx :run-dir) "/tmp/satan-run-test"))
    (should (equal (plist-get tool-ctx :run-started-at)
                   "2026-05-19T10:00:00+1000"))
    (should (equal (plist-get tool-ctx :time-now)
                   "2026-05-19T10:00:00+1000"))))

(ert-deftest satan-broker/tool-ctx-does-not-call-format-time-string ()
  "tool-ctx must read time_now from run_ctx, never compute it on demand."
  (let* ((mode '(:name morning :capabilities ()))
         (prepare (list :run_id "rid" :time_now "2026-01-01T00:00:00+0000"
                        :start_time (current-time)
                        :evidence nil :percept nil
                        :sensor_status nil :pre_spawn nil :motive nil))
         (run-ctx (make-satan-run
                   :id "rid" :mode mode
                   :start-time (plist-get prepare :start_time)
                   :dir "/tmp/x" :prepare prepare))
         (called nil))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (&rest args) (setq called args) "NEVER")))
      (let ((tool-ctx (satan-run-tool-ctx run-ctx)))
        (should (equal (plist-get tool-ctx :time-now)
                       "2026-01-01T00:00:00+0000"))
        (should (null called))))))

(ert-deftest satan-broker/date-bucket-extracted-from-run-id ()
  (should (equal (satan-run--date-bucket
                  "20260520T163446-tick-pulse-5e8018")
                 "2026-05-20"))
  (should (null (satan-run--date-bucket "garbage")))
  (should (null (satan-run--date-bucket nil))))

(ert-deftest satan-broker/announce-failure-respects-disables ()
  "Both syslog and notify are gated by their respective defcustom flags
\(ported to the 5-arg `--announce-failure' signature, PHASE-07\): with
both off, neither a journal line nor a pop is due, so `--announce-failure'
never reaches `satan-announce' at all (design sec-6's `(when (or pop
satan-failure-syslog) ...)' guard) — the recorder stays empty."
  (let* ((root (make-temp-file "satan-runs-announce2-" t))
         (satan-runs-dir root)
         (satan-failure-syslog nil)
         (satan-failure-notify nil)
         (dir (satan-run-test--mkrun root "20260520T100000-tick-pulse-aaaaaa"
                                     "failed" "child-exit-1" t)))
    (unwind-protect
        (satan-announce-with-recorder
          (satan-broker--announce-failure
           "20260520T100000-tick-pulse-aaaaaa" "tick-pulse"
           'failed "child-exit-1" dir)
          (should (null satan-announce-recorded)))
      (delete-directory root t))))

;; ── Announce policy back-off (PHASE-07, design sec-6) ───────────────────────

(defmacro satan-broker-test--outside-quiet-hours (&rest body)
  "Run BODY with `satan-tick-quiet-p' stubbed to nil, so whether a pop is
due never depends on the wall clock or `satan-tick-quiet-hours'."
  (declare (indent 0) (debug t))
  `(cl-letf (((symbol-function 'satan-tick-quiet-p)
              (lambda (&optional _time) nil)))
     ,@body))

(ert-deftest satan-broker/announce-due-at-powers-of-two ()
  "For an ordinary reason, a pop is due only at streak positions that are
powers of two (1, 2, 4, 8)."
  (let ((outcome '(:status failed :reason "unknown")))
    (dolist (position '(1 2 4 8))
      (should (satan-broker--announce-due-p outcome position)))
    (dolist (position '(3 5 6 7))
      (should-not (satan-broker--announce-due-p outcome position)))))

(ert-deftest satan-broker/announce-auth-always-critical ()
  "`auth' is due at every position, including non-powers-of-two, and the
composed announce sends critical urgency for it regardless of position."
  (should (satan-broker--announce-due-p '(:status failed :reason "auth") 1))
  (should (satan-broker--announce-due-p '(:status failed :reason "auth") 3))
  (should (satan-broker--announce-due-p '(:status failed :reason "auth") 5))
  (let* ((root (make-temp-file "satan-runs-announce-auth-" t))
         (satan-runs-dir root)
         (satan-failure-syslog t)
         (satan-failure-notify t)
         (dir (satan-run-test--mkrun root "20260520T100000-tick-pulse-aaaaaa"
                                     "failed" "auth" t)))
    (unwind-protect
        (satan-broker-test--outside-quiet-hours
          (satan-announce-with-recorder
            (satan-broker--announce-failure
             "20260520T100000-tick-pulse-aaaaaa" "tick-pulse" 'failed "auth"
             dir)
            (should (eq (plist-get (car satan-announce-recorded) :urgency)
                        'critical))
            (should (plist-get (car satan-announce-recorded) :title))))
      (delete-directory root t))))

(ert-deftest satan-broker/announce-budget-once ()
  "`budget-exceeded' pops only at streak position 1, never at 2 — and the
policy match is against `final.json's raw :reason (\"budget_daily_tokens\"),
never the human-readable display REASON argument (\"500000/400000 tokens\"),
which is what A1 warns could be silently conflated."
  (should (satan-broker--announce-due-p
           '(:status budget-exceeded :reason "budget_daily_tokens") 1))
  (should-not (satan-broker--announce-due-p
               '(:status budget-exceeded :reason "budget_daily_tokens") 2))
  (should-not (satan-broker--announce-due-p
               '(:status budget-exceeded :reason "budget_daily_tokens") 4))
  (let* ((root (make-temp-file "satan-runs-announce-budget-" t))
         (satan-runs-dir root)
         (satan-failure-syslog t)
         (satan-failure-notify t))
    (unwind-protect
        (satan-broker-test--outside-quiet-hours
          (satan-announce-with-recorder
            ;; Each run's dir is created just before its own announce call,
            ;; mirroring production (the walk always sees the just-renamed
            ;; dir as the newest on disk) — creating both dirs up front
            ;; would make the first call's walk see the second run too.
            (let ((dir1 (satan-run-test--mkrun
                         root "20260520T080000-morning-aaaaaa"
                         "budget-exceeded" "budget_daily_tokens" t)))
              (satan-broker--announce-failure
               "20260520T080000-morning-aaaaaa" "morning" 'budget-exceeded
               "500000/400000 tokens" dir1))
            (should (plist-get (car satan-announce-recorded) :title))
            (let ((dir2 (satan-run-test--mkrun
                         root "20260520T090000-morning-bbbbbb"
                         "budget-exceeded" "budget_daily_tokens" t)))
              (satan-broker--announce-failure
               "20260520T090000-morning-bbbbbb" "morning" 'budget-exceeded
               "500000/400000 tokens" dir2))
            (should-not (plist-get (car satan-announce-recorded) :title))
            (should (plist-get (car satan-announce-recorded) :journal))))
      (delete-directory root t))))

(ert-deftest satan-broker/failure-streak-restarts-on-new-cause ()
  "A new cause (status/reason pair differing from the two prior same-mode
failures) restarts the same-cause streak at position 1 (DEC-015 F-3
regression)."
  (let* ((root (make-temp-file "satan-runs-streak-cause-" t))
         (satan-runs-dir root))
    (unwind-protect
        (progn
          (satan-run-test--mkrun root "20260520T080000-motd-aaaaaa"
                                 "failed" "auth" t)
          (satan-run-test--mkrun root "20260520T090000-motd-bbbbbb"
                                 "failed" "auth" t)
          (let* ((newest-dir (satan-run-test--mkrun
                              root "20260520T100000-motd-cccccc"
                              "failed" "unknown" t))
                 (newest (satan-run-outcome newest-dir))
                 (streak (satan-broker--failure-streak "motd" newest)))
            (should (= 1 (length streak)))
            (should (equal (plist-get (car streak) :run-id)
                           "20260520T100000-motd-cccccc"))))
      (delete-directory root t))))

(ert-deftest satan-broker/session-blocked-transparent-to-failure-streak ()
  "`session_blocked', `credential_deferred' and `run_busy' are transparent:
they neither extend nor break a same-cause failure streak, and the walk's
position numbering steps over them (EX-3)."
  (let* ((root (make-temp-file "satan-runs-streak-transparent-" t))
         (satan-runs-dir root))
    (unwind-protect
        (progn
          (satan-run-test--mkrun root "20260520T070000-motd-aaaaaa"
                                 "failed" "auth" t)
          (satan-run-test--mkrun root "20260520T080000-motd-bbbbbb"
                                 "failed" "session_blocked")
          (satan-run-test--mkrun root "20260520T090000-motd-cccccc"
                                 "failed" "credential_deferred")
          (satan-run-test--mkrun root "20260520T093000-motd-eeeeee"
                                 "failed" "run_busy")
          (let* ((newest-dir (satan-run-test--mkrun
                              root "20260520T100000-motd-dddddd"
                              "failed" "auth" t))
                 (newest (satan-run-outcome newest-dir))
                 (streak (satan-broker--failure-streak "motd" newest)))
            (should (= 2 (length streak)))
            (should (equal (mapcar (lambda (o) (plist-get o :run-id)) streak)
                           '("20260520T100000-motd-dddddd"
                             "20260520T070000-motd-aaaaaa")))))
      (delete-directory root t))))

(ert-deftest satan-broker/announce-journals-every-failure-ascii ()
  "The journal/body line is `<status> <mode> <run-id> <reason> x<N>' at
position 1 (no ` since ...'), gains ` since <first-run-id>' at position >
1, is pure ASCII, and is written for every failure even when no pop is
due (EX-2)."
  (let ((line1 (satan-broker--failure-line
               'failed "motd" "20260520T100000-motd-aaaaaa" "auth" 1 nil))
        (line2 (satan-broker--failure-line
               'failed "motd" "20260526T081501-motd-9a01c2" "auth" 4
               "20260520T081501-motd-33ec98")))
    (should (equal line1 "failed motd 20260520T100000-motd-aaaaaa auth x1"))
    (should (equal line2
                   (concat "failed motd 20260526T081501-motd-9a01c2 auth x4"
                          " since 20260520T081501-motd-33ec98")))
    (should (string-match-p "\\`[[:ascii:]]*\\'" line1))
    (should (string-match-p "\\`[[:ascii:]]*\\'" line2)))
  ;; Written for every failure: a non-due position (budget-exceeded, 2nd
  ;; run) still gets a journal line, just no pop.
  (let* ((root (make-temp-file "satan-runs-announce-journal-" t))
         (satan-runs-dir root)
         (satan-failure-syslog t)
         (satan-failure-notify t))
    (unwind-protect
        (satan-announce-with-recorder
          ;; Sequential creation (see announce-budget-once) so the second
          ;; call's walk sees itself at position 2, not both at once.
          (let ((dir1 (satan-run-test--mkrun
                      root "20260520T080000-morning-aaaaaa"
                      "budget-exceeded" "budget_daily_tokens" t)))
            (satan-broker--announce-failure
             "20260520T080000-morning-aaaaaa" "morning" 'budget-exceeded
             "500000/400000 tokens" dir1))
          (let ((dir2 (satan-run-test--mkrun
                      root "20260520T090000-morning-bbbbbb"
                      "budget-exceeded" "budget_daily_tokens" t)))
            (satan-broker--announce-failure
             "20260520T090000-morning-bbbbbb" "morning" 'budget-exceeded
             "500000/400000 tokens" dir2))
          (should (= 2 (length satan-announce-recorded)))
          (should (plist-get (car satan-announce-recorded) :journal))
          (should-not (plist-get (car satan-announce-recorded) :title)))
      (delete-directory root t))))

(ert-deftest satan-broker/announce-quiet-suppresses-pop-not-journal ()
  "Quiet hours (via `satan-tick-quiet-p', stubbed — never the real wall
clock) suppress the desktop pop but not the journal line."
  (let* ((root (make-temp-file "satan-runs-announce-quiet-" t))
         (satan-runs-dir root)
         (satan-failure-syslog t)
         (satan-failure-notify t)
         (dir (satan-run-test--mkrun root "20260520T080000-motd-aaaaaa"
                                     "failed" "unknown" t)))
    (unwind-protect
        (progn
          (satan-announce-with-recorder
            (cl-letf (((symbol-function 'satan-tick-quiet-p)
                       (lambda (&optional _time) t)))
              (satan-broker--announce-failure
               "20260520T080000-motd-aaaaaa" "motd" 'failed "unknown" dir))
            (should (plist-get (car satan-announce-recorded) :journal))
            (should-not (plist-get (car satan-announce-recorded) :title)))
          (satan-announce-with-recorder
            (satan-broker-test--outside-quiet-hours
              (satan-broker--announce-failure
               "20260520T080000-motd-aaaaaa" "motd" 'failed "unknown" dir))
            (should (plist-get (car satan-announce-recorded) :journal))
            (should (plist-get (car satan-announce-recorded) :title))))
      (delete-directory root t))))

;; ---------- satan-run-new-ctx (Phase 0.1) ----------

(ert-deftest satan-broker/prepare-plist-shape ()
  "prepare returns a run_ctx plist with frozen run_id + time_now and v0 placeholders."
  (let* ((mode '(:name "tick-pulse"))
         (run-ctx (satan-run-new-ctx mode)))
    (should (stringp (plist-get run-ctx :run_id)))
    (should (string-prefix-p (format-time-string "%Y%m%dT")
                             (plist-get run-ctx :run_id)))
    (should (stringp (plist-get run-ctx :time_now)))
    (should (string-match-p
             "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}"
             (plist-get run-ctx :time_now)))
    (dolist (k '(:evidence :percept :sensor_status :pre_spawn :motive))
      (should (plist-member run-ctx k))
      (should (null (plist-get run-ctx k))))))

(ert-deftest satan-broker/prepare-mints-distinct-run-ids ()
  "Two calls to prepare allocate different run_ids."
  (let* ((mode '(:name "x"))
         (a (satan-run-new-ctx mode))
         (b (satan-run-new-ctx mode)))
    (should-not (equal (plist-get a :run_id) (plist-get b :run_id)))))

(ert-deftest satan-broker/prepare-freezes-time-now-once ()
  "time_now is computed exactly once at prepare; identical across reads."
  (let* ((mode '(:name "tick-pulse"))
         (run-ctx (satan-run-new-ctx mode))
         (frozen (plist-get run-ctx :time_now)))
    (sleep-for 0.05)
    (should (equal frozen (plist-get run-ctx :time_now)))))

;; ---------- satan-broker manifest assembly ----------

(defconst satan-broker-test--morning-tool-descriptions
  '(("org_read_context"       . "Read.")
    ("org_update_owned_block" . "Write owned.")
    ("proposal_stage"         . "Stage.")
    ("notify_send"            . "Notify.")
    ("hippocampus_list"       . "List hippo.")
    ("hippocampus_read"       . "Read hippo.")
    ("hippocampus_write"      . "Write hippo.")
    ("hippocampus_overwrite"  . "Overwrite hippo.")
    ("hippocampus_delete"     . "Delete hippo.")
    ("hippocampus_grep"       . "Search hippo.")
    ("hippocampus_rename"     . "Rename hippo.")
    ("inbox_append"           . "Append inbox.")
    ("agenda_read"            . "Read agenda.")
    ("activity_read"          . "Read activity.")
    ("notes_recent"           . "List recent notes.")
    ("notes_at_satan_scan"    . "Scan @satan directives.")
    ("sway_border_set"        . "Retint sway borders.")
    ("sway_border_reset"      . "Restore sway borders.")
    ("memory_mark"            . "Mark.")
    ("memory_resonate"        . "Resonate.")
    ("memory_show_trace"      . "Show.")
    ("docs_list"              . "List docs.")
    ("docs_search"            . "Search docs.")
    ("docs_read"              . "Read doc.")
    ("motive_read"            . "Read motives.")
    ("motive_replace"         . "Replace motive.")
    ("vcs_log"                . "Read commit log.")
    ("satan_final"            . "Terminate."))
  "Tool descriptions sufficient to build the `morning' mode manifest.
Shared by every broker gate VT that drives `satan-broker-run' (the
manifest build looks up a description per allowed tool).")

(defun satan-broker-test--with-tool-descriptions (alist body-fn)
  "Run BODY-FN with `satan-tools-descriptions-dir' bound to a tmp dir
populated from ALIST `((NAME . CONTENT) …)'."
  (let ((tmp (make-temp-file "satan-tools-" t)))
    (unwind-protect
        (let ((satan-tools-descriptions-dir tmp))
          (dolist (pair alist)
            (with-temp-file (expand-file-name (concat (car pair) ".md") tmp)
              (insert (cdr pair))))
          (funcall body-fn))
      (delete-directory tmp t))))

(ert-deftest satan-broker/manifest-tools-shape ()
  "Manifest carries one JSON Schema per allowed tool plus satan_final."
  (satan-broker-test--with-tool-descriptions
   '(("org_read_context"      . "Read a slice of the notes corpus.")
     ("org_update_owned_block" . "Replace a SATAN-owned org block.")
     ("proposal_stage"         . "Stage a proposal.")
     ("notify_send"            . "Send a desktop notification.")
     ("hippocampus_list"       . "List hippocampus entries.")
     ("hippocampus_read"       . "Read a hippocampus entry.")
     ("hippocampus_write"      . "Write to the hippocampus.")
     ("hippocampus_overwrite"  . "Overwrite a hippocampus entry.")
     ("hippocampus_delete"     . "Delete a hippocampus entry.")
     ("hippocampus_grep"       . "Search hippocampus entries.")
     ("hippocampus_rename"     . "Rename a hippocampus entry.")
     ("inbox_append"           . "Append to the inbox.")
     ("agenda_read"            . "Read the agenda.")
     ("activity_read"          . "Read the user's recent activity.")
     ("notes_recent"           . "List recently changed notes files.")
     ("notes_at_satan_scan"    . "Scan @satan directives.")
     ("sway_border_set"        . "Retint sway window borders.")
     ("sway_border_reset"      . "Restore sway borders.")
     ("memory_mark"            . "Mark a memory trace.")
     ("memory_resonate"        . "Resonate against handles.")
     ("memory_show_trace"      . "Show a memory trace.")
     ("docs_list"              . "List doc chunks.")
     ("docs_search"            . "Filter doc chunks.")
     ("docs_read"              . "Read a doc chunk.")
     ("motive_read"            . "Read motive entries.")
     ("motive_replace"         . "Replace a motive entry.")
     ("vcs_log"                . "Read a repository's commit log.")
     ("satan_final"            . "Terminate the run."))
   (lambda ()
     (let* ((mode (satan-mode-resolve "morning"))
            (manifest (satan-broker--build-manifest mode "test-run"))
            (tools (append (plist-get manifest :tools) nil))
            (names (mapcar (lambda (t-) (plist-get (plist-get t- :function) :name))
                           tools)))
       (should (equal (plist-get manifest :run_id) "test-run"))
       (should (member "org_read_context" names))
       (should (member "org_update_owned_block" names))
       (should (member "notify_send" names))
       (should (member "hippocampus_write" names))
       (should (member "inbox_append" names))
       (should (member "agenda_read" names))
       (should (member "activity_read" names))
       (should (member "notes_recent" names))
       (should (member "satan_final" names))
       ;; Descriptions came from notes files, not elisp.
       (let ((notify (cl-find "notify_send" tools
                              :key (lambda (t-)
                                     (plist-get (plist-get t- :function) :name))
                              :test #'equal)))
         (should (string-match-p
                  "Send a desktop notification"
                  (plist-get (plist-get notify :function) :description))))))))

;; ---------- budget gating (cross-cutter: assertion subject = broker) ----------

(defun satan-broker-test--write-transcript (dir lines)
  "Write LINES (each a plist) as transcript.jsonl under DIR."
  (make-directory dir t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file (expand-file-name "transcript.jsonl" dir)
      (dolist (l lines)
        (insert (json-serialize
                 (satan-jsonl-prepare l)
                 :null-object :null :false-object :false))
        (insert "\n")))))

(defun satan-broker-test--usage-record (tokens-total)
  (list :ts "2026-05-19T09:00:00.000000+1000"
        :dir "in" :event "log"
        :payload (list :type "log" :kind "usage"
                       :tokens_in 0 :tokens_out 0
                       :tokens_total tokens-total)))

(defun satan-broker-test--minimal-perceive (prepare _mode pdir)
  "Minimal `satan-run-perceive' stub for gate-path tests (DR-010 §3).
Threads a minimal non-nil `:percept' onto PREPARE and persists
`percept.json' under PDIR, exactly as the real perceive does for the
identity/mirror invariants — but without the live evidence assembler
(which reads sensors/git, out of scope for gate tests).  Also
threads empty `:probe_snapshots' so the consume-side commit (only
reached on the spawn path) has the key to read.  Reuse this in any
broker gate VT that asserts the percept/bundle artifacts."
  (let ((percept (list :run_id (plist-get prepare :run_id)
                       :time_now (plist-get prepare :time_now)
                       :handles nil
                       :evidence_window nil)))
    (satan-percept-persist pdir percept)
    (thread-first prepare
                  (plist-put :percept percept)
                  (plist-put :evidence nil)
                  (plist-put :sensor_status nil)
                  (plist-put :probe_snapshots
                             (list :curiosity nil :content nil :wpm nil)))))

(defun satan-broker-test--read-bundle (dir)
  "Parse `bundle.json' under DIR into a plist (or nil if absent)."
  (let ((path (expand-file-name "bundle.json" dir)))
    (when (file-readable-p path)
      (with-temp-buffer
        (insert-file-contents path)
        (goto-char (point-min))
        (json-parse-buffer :object-type 'plist
                           :array-type 'list
                           :null-object :null
                           :false-object :false)))))

(ert-deftest satan-broker/refuses-spawn-when-budget-exceeded ()
  "Pre-spawn gate writes status=budget-exceeded; no child spawned.
Secondary subject: satan-budget (gating policy)."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-bud-broker-" t))
            (now (current-time))
            (today (format-time-string "%Y%m%dT" now))
            (existing (expand-file-name (concat today "080000-x-eeeeee") root))
            (satan-runs-dir root)
            (satan-budget-daily-tokens 400000)
            (satan-trace-enabled nil))  ; SL-011: keep the real trace dir clean
       (unwind-protect
           ;; DR-010 §3: perceive now runs UNCONDITIONALLY before the budget
           ;; gate.  This test's subject is the gate, not perception, so stub
           ;; `satan-run-perceive' to thread a minimal `:percept' (the real
           ;; evidence assembler reads sensors/git — out of scope here).
           ;; The stub still persists `percept.json' and threads `:percept' so
           ;; the gate path and the new bundle `:percept' mirror stay exercised;
           ;; the budget assertions below are untouched.
           (cl-letf (((symbol-function 'satan-run-perceive)
                      #'satan-broker-test--minimal-perceive))
             (satan-broker-test--write-transcript
              existing (list (satan-broker-test--usage-record 500000)))
             (let* ((run-id (satan-broker-run "morning"))
                    (dir (satan-run-locate-dir run-id root))
                    (status-path (expand-file-name "status" dir)))
               (should (string-suffix-p ".FAILED" dir))
               (should (file-directory-p dir))
               (should (file-readable-p status-path))
               (should (equal (string-trim
                               (with-temp-buffer
                                 (insert-file-contents status-path)
                                 (buffer-string)))
                              "budget-exceeded"))
               (should (eq (satan-audit-verify-run dir) t))
               (let* ((final-path (expand-file-name "final.json" dir))
                      (final (with-temp-buffer
                               (insert-file-contents final-path)
                               (goto-char (point-min))
                               (json-parse-buffer
                                :object-type 'plist
                                :array-type 'list
                                :null-object :null
                                :false-object :false))))
                 (should (string-match-p "budget-exceeded"
                                         (plist-get final :summary)))
                 (should (equal (plist-get final :reason)
                                "budget_daily_tokens")))))
         (delete-directory root t))))))

(ert-deftest satan-broker/budget-denied-run-is-recorded-not-delivered ()
  "ISS-015: a budget-denied run's failure announcement lands in the
recorder, never the real announcer — structurally, with no per-test
D-Bus/logger stub needed."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-bud-recorded-" t))
            (now (current-time))
            (today (format-time-string "%Y%m%dT" now))
            (existing (expand-file-name (concat today "080000-x-eeeeee") root))
            (satan-runs-dir root)
            (satan-budget-daily-tokens 400000)
            (satan-trace-enabled nil))
       (unwind-protect
           (cl-letf (((symbol-function 'satan-run-perceive)
                      #'satan-broker-test--minimal-perceive))
             (satan-broker-test--write-transcript
              existing (list (satan-broker-test--usage-record 500000)))
             (satan-announce-with-recorder
               (satan-broker-run "morning")
               (should satan-announce-recorded)
               (should (plist-get (car satan-announce-recorded) :journal))))
         (delete-directory root t))))))

;; ---------- VT-budget-denied-perceives (DR-010 §5, ISSUE-001) ----------

(ert-deftest satan-broker/budget-denied-still-perceives ()
  "ISSUE-001 regression: a budget-denied tick perceives FIRST.
`percept.json' is written under the run-dir AND `bundle.json' carries a
non-nil `:percept' (consumers read the bundle, not the sidecar).  Status
is `budget-exceeded'.  Mirrors the gate test's fixture (over-ceiling
existing transcript) but asserts the perceive artifacts, not the gate."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-bud-perceive-" t))
            (now (current-time))
            (today (format-time-string "%Y%m%dT" now))
            (existing (expand-file-name (concat today "080000-x-eeeeee") root))
            (satan-runs-dir root)
            (satan-budget-daily-tokens 400000)
            (satan-trace-enabled nil))  ; SL-011: keep the real trace dir clean
       (unwind-protect
           (cl-letf (((symbol-function 'satan-run-perceive)
                      #'satan-broker-test--minimal-perceive))
             (satan-broker-test--write-transcript
              existing (list (satan-broker-test--usage-record 500000)))
             (let* ((run-id (satan-broker-run "morning"))
                    (dir (satan-run-locate-dir run-id root))
                    (status-path (expand-file-name "status" dir))
                    (percept-path (expand-file-name "percept.json" dir))
                    (bundle (satan-broker-test--read-bundle dir)))
               ;; Perceive ran before the budget gate: the sidecar exists …
               (should (file-readable-p percept-path))
               ;; … and the bundle carries the percept consumers actually read.
               (should bundle)
               (should (plist-get bundle :percept))
               (should (equal (plist-get (plist-get bundle :percept) :run_id)
                              run-id))
               ;; Gate decision still stands.
               (should (equal (string-trim
                               (with-temp-buffer
                                 (insert-file-contents status-path)
                                 (buffer-string)))
                              "budget-exceeded"))))
         (delete-directory root t))))))

(ert-deftest satan-broker/session-blocked-still-perceives ()
  "ISSUE-001 regression: a session-blocked tick perceives FIRST and stays silent.
With an interactive session active and budget UNDER ceiling,
`satan-broker-run' still writes `percept.json' + a `:percept'-bearing
`bundle.json'; status is `failed' with reason \"session_blocked\".  The
run dir is NOT `.FAILED'-renamed and `satan-broker--announce-failure'
is NOT called (DEC-8: the deferral must not pollute the failure streak or
pop a desktop alert).  The bundle is verify-clean."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-session-perceive-" t))
            (satan-runs-dir root)
            (satan-budget-daily-tokens 2500000) ; under ceiling: no spend
            (satan-run--session-active t)        ; interactive session open
            (satan-trace-enabled nil)  ; SL-011: keep the real trace dir clean
            (announced nil))
       (unwind-protect
           (cl-letf (((symbol-function 'satan-run-perceive)
                      #'satan-broker-test--minimal-perceive)
                     ((symbol-function 'satan-broker--announce-failure)
                      (lambda (&rest _) (setq announced t))))
             (let* ((run-id (satan-broker-run "morning"))
                    (dir (satan-run-locate-dir run-id root))
                    (status-path (expand-file-name "status" dir))
                    (percept-path (expand-file-name "percept.json" dir))
                    (bundle (satan-broker-test--read-bundle dir)))
               ;; Perceived before the session gate fired.
               (should (file-readable-p percept-path))
               (should bundle)
               (should (plist-get bundle :percept))
               ;; Terminal status + reason.
               (should (equal (string-trim
                               (with-temp-buffer
                                 (insert-file-contents status-path)
                                 (buffer-string)))
                              "failed"))
               (let* ((final-path (expand-file-name "final.json" dir))
                      (final (with-temp-buffer
                               (insert-file-contents final-path)
                               (goto-char (point-min))
                               (json-parse-buffer :object-type 'plist
                                                  :array-type 'list
                                                  :null-object :null
                                                  :false-object :false))))
                 (should (equal (plist-get final :reason) "session_blocked")))
               ;; DEC-8: no rename, no announce — silent deferral.
               (should-not (string-suffix-p ".FAILED" dir))
               (should-not announced)
               ;; Bundle remains verify-clean.
               (should (eq (satan-audit-verify-run dir) t))))
         (delete-directory root t))))))

;; ---------- SL-018 PHASE-03: run_busy gate (DEC-023) ----------

(cl-defun satan-broker-test--gate-run (&key busy session perceive-error)
  "Run `satan-broker-run' \"morning\" through the pre-spawn gates.
BUSY binds `satan-run--spawn-running', SESSION `satan-run--session-active';
PERCEIVE-ERROR non-nil makes perceive signal.  `--spawn' is stubbed.
Returns (:reason R :dir DIR :announced BOOL :spawned BOOL), R nil when
it spawned; the temp
runs root is deleted afterwards, so DIR is for its name only."
  (let (result)
    (satan-broker-test--with-tool-descriptions
     satan-broker-test--morning-tool-descriptions
     (lambda ()
       (let* ((root (make-temp-file "satan-gate-" t))
              (satan-runs-dir root)
              (satan-budget-daily-tokens 2500000)
              (satan-run--spawn-running busy)
              (satan-run--session-active session)
              (satan-trace-enabled nil)
              (announced nil) (spawned nil))
         (unwind-protect
             (cl-letf (((symbol-function 'satan-run-perceive)
                        (if perceive-error
                            (lambda (&rest _) (error "perceive boom"))
                          #'satan-broker-test--minimal-perceive))
                       ((symbol-function 'satan-broker--announce-failure)
                        (lambda (&rest _) (setq announced t)))
                       ((symbol-function 'satan-broker--spawn)
                        (lambda (&rest _) (setq spawned t) "spawned")))
               (let* ((run-id (satan-broker-run "morning"))
                      (dir (satan-run-locate-dir run-id root)))
                 ;; A stubbed spawn writes nothing; a gated run must be
                 ;; a complete, verify-clean bundle.
                 (unless spawned
                   (should (eq (satan-audit-verify-run dir) t)))
                 (setq result
                       (list :reason (and (not spawned)
                                          (plist-get (satan-broker-test--run-json
                                                      dir "final.json")
                                                     :reason))
                             :dir dir :announced announced
                             :spawned spawned))))
           (delete-directory root t)))))
    result))

(ert-deftest satan-broker/run-busy-refuses-silently ()
  "VT-27: a live child → `run_busy' no-child run: no spawn, no rename, no pop."
  (let ((r (satan-broker-test--gate-run :busy t)))
    (should (equal (plist-get r :reason) "run_busy"))
    (should-not (plist-get r :spawned))
    (should-not (string-suffix-p ".FAILED" (plist-get r :dir)))
    (should-not (plist-get r :announced))))

(ert-deftest satan-broker/run-busy-gate-precedence ()
  "VT-22: real failures outrank run_busy: perceive_failed, then session_blocked."
  (should (equal (plist-get (satan-broker-test--gate-run
                             :busy t :perceive-error t)
                            :reason)
                 "perceive_failed"))
  (should (equal (plist-get (satan-broker-test--gate-run :busy t :session t)
                            :reason)
                 "session_blocked"))
  (should (plist-get (satan-broker-test--gate-run) :spawned)))

;; ---------- VT-1 (SL-011): one tick trace row per satan-broker-run ----------

(defmacro satan-broker-test--with-trace-dir (dir-var &rest body)
  "Bind `satan-trace-dir' to a fresh temp DIR-VAR, run BODY, clean up."
  (declare (indent 1))
  `(let* ((,dir-var (make-temp-file "satan-broker-trace-" t))
          (satan-trace-dir ,dir-var)
          (satan-trace-enabled t))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p ,dir-var)
         (delete-directory ,dir-var t)))))

(defun satan-broker-test--tick-rows (trace-dir)
  "Read today's kind:\"tick\" rows written under TRACE-DIR."
  (let ((file (expand-file-name
               (format "tick-trace-%s.jsonl" (format-time-string "%Y-%m-%d"))
               trace-dir)))
    (cl-remove-if-not
     (lambda (r) (equal (plist-get r :kind) "tick"))
     (satan-jsonl-read-file file))))

(defun satan-broker-test--fixture-percept (prepare _mode)
  "Fixture `satan-percept-build' stub: identity keys only, no evidence."
  (list :run_id (plist-get prepare :run_id)
        :time_now (plist-get prepare :time_now)
        :handles nil
        :evidence_window nil))

(ert-deftest satan-broker/run-emits-one-tick-row-outcome-spawned ()
  "VT-1: `satan-trace-with-tick' wraps `satan-broker-run'.
Exactly ONE kind:\"tick\" row is written, its `outcome' is \"spawned\",
and its `stages' map carries the perceive-path stage keys.  The real
`satan-run-perceive' runs (percept-build stubbed to a fixture) so
the stage wraps inside the shared perceive fn record onto the tick."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-spawn-" t))
              (satan-runs-dir root)
              (satan-budget-daily-tokens 2500000) ; under ceiling
              (satan-run--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'satan-percept-build)
                        #'satan-broker-test--fixture-percept)
                       ((symbol-function 'satan-broker--spawn)
                        (lambda (_mode prepare _dir)
                          (plist-get prepare :run_id))))
               (let* ((run-id (satan-broker-run "morning"))
                      (ticks (satan-broker-test--tick-rows trace-dir))
                      (row (car ticks))
                      (stages (plist-get row :stages)))
                 (should (= 1 (length ticks)))
                 (should (equal "spawned" (plist-get row :outcome)))
                 (should (equal run-id (plist-get row :run_id)))
                 (should (equal "morning" (plist-get row :mode)))
                 ;; Perceive-path stages recorded onto the tick accumulator.
                 (should (plist-member stages :perceive.persist))
                 (should (plist-member stages :probes.read.curiosity))
                 (should (plist-member stages :probes.read.content))
                 (should (plist-member stages :probes.read.wpm))))
           (delete-directory root t)))))))

(ert-deftest satan-broker/run-tick-row-outcome-perceive-failed ()
  "VT-1: a perceive error stamps `outcome' \"perceive_failed\" on the tick
row, and the run's transcript names the error (RV-012 F-6)."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-perc-" t))
              (satan-runs-dir root)
              (satan-budget-daily-tokens 2500000)
              (satan-run--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'satan-run-perceive)
                        (lambda (&rest _) (error "sensor exploded")))
                       ((symbol-function 'satan-broker--announce-failure)
                        (lambda (&rest _) nil)))
               (satan-broker-run "morning")
               (let ((ticks (satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "perceive_failed"
                                (plist-get (car ticks) :outcome))))
               (should (equal "sensor exploded"
                              (plist-get (satan-broker-test--broker-event
                                          (car (file-expand-wildcards
                                                (expand-file-name
                                                 "*/*.FAILED" root)))
                                          "perceive-failed")
                                         :error))))
           (delete-directory root t)))))))

(ert-deftest satan-broker/run-tick-row-outcome-session-blocked ()
  "VT-1: an active interactive session stamps `outcome' \"session_blocked\"."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-sess-" t))
              (satan-runs-dir root)
              (satan-budget-daily-tokens 2500000)
              (satan-run--session-active t))
         (unwind-protect
             (cl-letf (((symbol-function 'satan-run-perceive)
                        #'satan-broker-test--minimal-perceive))
               (satan-broker-run "morning")
               (let ((ticks (satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "session_blocked"
                                (plist-get (car ticks) :outcome)))))
           (delete-directory root t)))))))

(ert-deftest satan-broker/run-tick-row-outcome-budget-denied ()
  "VT-1: an over-ceiling day stamps `outcome' \"budget_denied\"."
  (satan-broker-test--with-tool-descriptions
   satan-broker-test--morning-tool-descriptions
   (lambda ()
     (satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-bud-" t))
              (now (current-time))
              (today (format-time-string "%Y%m%dT" now))
              (existing (expand-file-name (concat today "080000-x-eeeeee") root))
              (satan-runs-dir root)
              (satan-budget-daily-tokens 400000)
              (satan-run--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'satan-run-perceive)
                        #'satan-broker-test--minimal-perceive))
               (satan-broker-test--write-transcript
                existing (list (satan-broker-test--usage-record 500000)))
               (satan-broker-run "morning")
               (let ((ticks (satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "budget_denied"
                                (plist-get (car ticks) :outcome)))))
           (delete-directory root t)))))))

;; ---------- VT-perceive-pure (DR-010 §5) ----------

(ert-deftest satan-broker/perceive-is-pure ()
  "`satan-run-perceive' performs no cognition / effects / consumption-mutation.
It may persist `percept.json' and take pure probe READS, but must NOT:
spawn a process (`make-process'), dispatch a tool (`satan-tool-dispatch'),
enqueue an attribute (`satan-attribute-enqueue'), advance any probe
watermark (the three `mark-inspected' / `--write-state' writers), OR advance
the ingest cursor (`satan-ingest-cursor-advance' /
`satan-ingest-cursor--write').  Each forbidden fn is spied to fail the
test if called.  Read-only local subprocess probes (git via
`call-process') are ALLOWED and not spied.  `satan-percept-build' is
stubbed to a fixture percept — the purity subject is the perceive
orchestration, not the builder internals."
  (let* ((dir (make-temp-file "satan-perceive-pure-" t))
         (prepare (list :run_id "20260609T100000-morning-aaaaaa"
                        :time_now "2026-06-09T10:00:00+10:00"
                        :percept nil :evidence nil :sensor_status nil))
         (fixture-percept (list :run_id (plist-get prepare :run_id)
                                :time_now (plist-get prepare :time_now)
                                :handles nil
                                :evidence_window nil))
         (satan-attribute-updates-enabled t))
     (unwind-protect
         (cl-letf (((symbol-function 'satan-percept-build)
                    (lambda (&rest _) fixture-percept))
                   ((symbol-function 'make-process)
                    (lambda (&rest _) (ert-fail "perceive spawned a process")))
                   ((symbol-function 'satan-tool-dispatch)
                    (lambda (&rest _) (ert-fail "perceive dispatched a tool")))
                   ((symbol-function 'satan-attribute-enqueue)
                    (lambda (&rest _) (ert-fail "perceive enqueued an attribute")))
                   ((symbol-function 'satan-sensor-curiosity-mark-inspected)
                    (lambda (&rest _) (ert-fail "perceive advanced curiosity watermark")))
                   ((symbol-function 'satan-sensor-content-mark-inspected)
                    (lambda (&rest _) (ert-fail "perceive advanced content watermark")))
                   ((symbol-function 'satan-sensor-wpm--write-state)
                    (lambda (&rest _) (ert-fail "perceive advanced wpm state")))
                   ;; DE-010 P02 — ingest-cursor advance is consume-side only
                   ((symbol-function 'satan-ingest-cursor-advance)
                    (lambda (&rest _) (ert-fail "perceive called ingest-cursor-advance")))
                   ((symbol-function 'satan-ingest-cursor--write)
                    (lambda (&rest _) (ert-fail "perceive wrote ingest cursor state"))))
           (let ((out (satan-run-perceive prepare '(:name "morning") dir)))
             ;; percept.json was persisted …
             (should (file-readable-p (expand-file-name "percept.json" dir)))
             ;; … and the pure probe read-snapshots were threaded.
             (should (plist-member out :probe_snapshots))
             (should (plist-get out :percept))))
       (delete-directory dir t))))

;; ---------- pre_spawn threading (Phase 4.4) ----------

(ert-deftest satan-broker/finalize-threads-pre-spawn-into-actions-json ()
  "broker--finalize copies `:pre_spawn' from the prepare run_ctx into the
actions plist passed to `satan-audit-close', which lands the
entries in `actions.json'.  Phase 4.4 — wires the producer side
(Phase 4.3 `sensor-alerts.check') into the audit close (Phase 0.3
schema bump)."
  (let ((dir (make-temp-file "satan-broker-pre-spawn-" t))
        (entries (list (list :kind "sensor_alert"
                             :cause "panopticon_current_stale"
                             :severity "warning"
                             :message "stale 28m"
                             :suppressed :false
                             :dispatched_at "2026-05-22T11:13Z"))))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-22T11:13Z"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil
                              :pre_spawn entries))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 30
                       :budget-tool-calls 1 :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((actions-path (expand-file-name "actions.json" dir))
                 (parsed (with-temp-buffer
                           (insert-file-contents actions-path)
                           (goto-char (point-min))
                           (json-parse-buffer :object-type 'plist
                                              :array-type 'list
                                              :null-object :null
                                              :false-object :false))))
            (let ((ps (plist-get parsed :pre_spawn)))
              (should (listp ps))
              (should (= 1 (length ps)))
              (should (equal "panopticon_current_stale"
                             (plist-get (car ps) :cause)))
              (should (equal "2026-05-22T11:13Z"
                             (plist-get (car ps) :dispatched_at))))
            (should (eq (satan-audit-verify-run dir) t))))
      (delete-directory dir t))))

(ert-deftest satan-broker/finalize-omits-pre-spawn-when-empty ()
  "When `:pre_spawn' is nil on prepare, actions.json omits the key
entirely so untouched runs keep the original four-partition shape."
  (let ((dir (make-temp-file "satan-broker-pre-spawn-empty-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-22T11:13Z"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 30
                       :budget-tool-calls 1 :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((actions-path (expand-file-name "actions.json" dir))
                 (parsed (with-temp-buffer
                           (insert-file-contents actions-path)
                           (goto-char (point-min))
                           (json-parse-buffer :object-type 'plist
                                              :array-type 'list
                                              :null-object :null
                                              :false-object :false))))
            (should-not (plist-member parsed :pre_spawn))))
      (delete-directory dir t))))

;; ---------- crash-context event (resilience PR 2) ----------

(ert-deftest satan-broker/crash-context-emitted-on-failed ()
  "Finalize emits a `crash-context' audit record on non-done terminal paths."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'failed
                         :tool-calls-done 3
                         :audit audit
                         :prepare prepare
                         :pre-spawn-completed t)))
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (crash-ctx (cl-find-if
                             (lambda (r)
                               (and (equal (plist-get r :dir) "broker")
                                    (equal (plist-get r :event) "crash-context")))
                             records)))
            (should crash-ctx)
            (let ((p (plist-get crash-ctx :payload)))
              (should (equal (plist-get p :status) "failed"))
              (should (equal (plist-get p :tool_calls_done) 3))
              (should (equal (plist-get p :tool_calls_budget) 100))
              (should (equal (plist-get p :budget_tokens) 300000))
              (should (equal (plist-get p :timeout_seconds) 1800))
              (should (integerp (plist-get p :elapsed_seconds)))
              (should (equal (plist-get p :pre_spawn_completed) t)))))
      (delete-directory dir t))))

(ert-deftest satan-broker/crash-context-not-emitted-on-done ()
  "Successful runs must NOT emit a crash-context record."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-done-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (crash-ctx (cl-find-if
                             (lambda (r)
                               (and (equal (plist-get r :dir) "broker")
                                    (equal (plist-get r :event) "crash-context")))
                             records)))
            (should-not crash-ctx)))
      (delete-directory dir t))))

(ert-deftest satan-broker/crash-context-emitted-on-timed-out ()
  "Timeout paths also emit crash-context."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-timeout-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'timed-out
                         :tool-calls-done 7
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (crash-ctx (cl-find-if
                             (lambda (r)
                               (and (equal (plist-get r :dir) "broker")
                                    (equal (plist-get r :event) "crash-context")))
                             records)))
            (should crash-ctx)
            (let ((p (plist-get crash-ctx :payload)))
              (should (equal (plist-get p :status) "timed-out"))
              (should (equal (plist-get p :tool_calls_done) 7)))))
      (delete-directory dir t))))

;; ---------- failure-reason: harness class transport (SL-017 sec-7) --------

(ert-deftest satan-broker/error-class-parsed-from-harness-json ()
  "`satan-broker--error-class' pulls :class out of the harness's
double-encoded JSON payload."
  (let ((obj (list :type "error"
                    :error (json-serialize '(:class "auth" :detail "Error code: 401 ... API key expired")))))
    (should (equal (satan-broker--error-class obj) "auth"))))

(ert-deftest satan-broker/error-class-unknown-for-plain-string ()
  "`satan-broker--error-class' returns \"unknown\" for an init-path error
that is a plain string, not JSON."
  (let ((obj (list :type "error" :error "init failed: OPENROUTER_API_KEY not set")))
    (should (equal (satan-broker--error-class obj) "unknown"))))

(ert-deftest satan-broker/failed-run-final-carries-failure-reason ()
  "A child that dies with a harness error and no `final' leaves
`final.json' carrying the parsed class as its reason (EX-2), and
`crash-context' carries the same class as :failure_reason (T4).  The
final's own :reason, when present, still wins over the slot (T6
precedence — the Risks section's named regression)."
  (let ((dir (make-temp-file "satan-broker-failure-reason-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :audit audit
                         :prepare prepare)))
          (satan-broker--on-error
           run-ctx (list :type "error"
                         :error (json-serialize '(:class "auth" :detail "expired"))))
          (should (equal (satan-run-failure-reason run-ctx) "auth"))
          ;; first write wins: a second --on-error must not overwrite it.
          (satan-broker--on-error
           run-ctx (list :type "error"
                         :error (json-serialize '(:class "rate_limit" :detail "later"))))
          (should (equal (satan-run-failure-reason run-ctx) "auth"))
          ;; precedence: failure-reason alone resolves --failure-reason ...
          (should (equal (satan-broker--failure-reason run-ctx) "auth"))
          ;; ... but an explicit final reason still wins over the slot.
          (setf (satan-run-final run-ctx) '(:status "invalid" :reason "explicit"))
          (should (equal (satan-broker--failure-reason run-ctx) "explicit"))
          (setf (satan-run-final run-ctx) nil)
          (cl-letf (((symbol-function 'satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (satan-broker--finalize run-ctx))
          (let* ((final-path (expand-file-name "final.json" dir))
                 (final (with-temp-buffer
                          (insert-file-contents final-path)
                          (goto-char (point-min))
                          (json-parse-buffer
                           :object-type 'plist
                           :array-type 'list
                           :null-object :null
                           :false-object :false))))
            (should (equal (plist-get final :status) "invalid"))
            (should (equal (plist-get final :reason) "auth")))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (crash-ctx (cl-find-if
                             (lambda (r)
                               (and (equal (plist-get r :dir) "broker")
                                    (equal (plist-get r :event) "crash-context")))
                             records)))
            (should crash-ctx)
            (should (equal (plist-get (plist-get crash-ctx :payload) :failure_reason)
                           "auth"))))
      (delete-directory dir t))))

;; ── DEC-8 mutual exclusion: producer side (AUD-008 F-001) ──────────────────

(defvar satan-memory-store--current-run-id) ; `--spawn' sets it; tests bind it

(defmacro satan-broker-test--with-spawn-collaborators (root dir &rest body)
  "Evaluate BODY with `satan-broker--spawn''s side collaborators stubbed.
ROOT is bound to a tmp `satan-runs-dir' and DIR to a run dir under it
\(created).  Stubs the soft pre-spawn stages (observer, enrich, sensor
alerts, probe commits, ingest cursor), env shaping and the
`most-recent' symlink; the record path (manifest, audit, finalize)
stays real.  Binds `satan-run--spawn-running',
`satan-memory-store--current-run-id', a tmp `satan-hippocampus-dir' and
a tmp `satan-tools-descriptions-dir' holding only `satan_final', so the
real manifest build never reads the live corpus.  Deletes ROOT
afterwards, so a `.FAILED'-renamed DIR goes with it."
  (declare (indent 2))
  `(let* ((,root (make-temp-file "satan-spawn-" t))
          (,dir (expand-file-name "run" ,root))
          (satan-runs-dir ,root)
          (satan-run--spawn-running nil)
          (satan-memory-store--current-run-id nil)
          (satan-hippocampus-dir (expand-file-name "hippocampus" ,root)))
     (make-directory ,dir)
     (unwind-protect
         (satan-broker-test--with-tool-descriptions
          (list (assoc "satan_final" satan-broker-test--morning-tool-descriptions))
          (lambda ()
            (cl-letf (((symbol-function 'satan-observer-process)
                       (lambda (&rest _) nil))
                      ((symbol-function 'satan-run-enrich)
                       (lambda (prepare &rest _) prepare))
                      ((symbol-function 'satan-sensor-alerts-check)
                       (lambda (&rest _) nil))
                      ;; DR-010 §3: --spawn now calls the consume-side
                      ;; -probe-commit variants (perceive took the reads).
                      ((symbol-function 'satan-sensor-curiosity-probe-commit)
                       (lambda (&rest _) nil))
                      ((symbol-function 'satan-sensor-content-probe-commit)
                       (lambda (&rest _) nil))
                      ((symbol-function 'satan-sensor-wpm-probe-commit)
                       (lambda (&rest _) nil))
                      ;; Writes the live state root's cursor file otherwise.
                      ((symbol-function 'satan-ingest-cursor-advance)
                       (lambda (&rest _) nil))
                      ((symbol-function 'my/scrub-op-refs-env)
                       (lambda (env) env))
                      ((symbol-function 'satan-broker--direnv-env)
                       (lambda (&rest _) nil))
                      ((symbol-function 'satan-broker--exec-path-from-env)
                       (lambda (&rest _) exec-path))
                      ((symbol-function 'satan-broker--update-most-recent)
                       (lambda (&rest _) nil)))
              ,@body)))
       (delete-directory ,root t))))

(defmacro satan-broker-test--with-spawn-stubs (dir &rest body)
  "Evaluate BODY with DIR bound to a tmp run dir and `--spawn' made hermetic.
`satan-broker-test--with-spawn-collaborators' plus stubs for the
record path (manifest, audit, finalize); the harness command still
runs for real.  Tests override individual stubs with an inner
`cl-letf'."
  (declare (indent 1))
  (let ((root (make-symbol "root")))
    `(satan-broker-test--with-spawn-collaborators ,root ,dir
       (cl-letf (((symbol-function 'satan-broker--build-manifest)
                  (lambda (&rest _) '(:manifest t)))
                 ((symbol-function 'satan-audit-open)
                  (lambda (&rest _) '(:audit t)))
                 ((symbol-function 'satan-audit-attach-bundle)
                  (lambda (&rest _) nil))
                 ((symbol-function 'satan-audit-record)
                  (lambda (&rest _) nil))
                 ((symbol-function 'satan-broker--finalize)
                  (lambda (&rest _) nil)))
         ,@body))))

(ert-deftest satan-broker/dec8-spawn-running-persists-until-sentinel ()
  "AUD-008 F-001: `satan-run--spawn-running' stays t across the live
async run and is cleared ONLY by the child sentinel — never at the
synchronous launch return (the original unwind-protect bug)."
  (satan-broker-test--with-spawn-stubs dir
    (let* ((prepare (list :run_id "rid-flag"
                          :time_now "2026-06-03T00:00:00Z"
                          :start_time (current-time)))
           ;; A real but long-lived child so the run is genuinely "live"
           ;; after spawn returns; no :timeout-seconds so no timer.
           (mode '(:name "test" :harness (:cmd "sleep" :args ("30"))))
           (run-id (satan-broker--spawn mode prepare dir)))
      (should (equal run-id "rid-flag"))
      ;; Child still running → flag MUST still be set.  The bug cleared
      ;; it here, at synchronous return.
      (should satan-run--spawn-running)
      (let ((proc (get-process "satan-rid-flag")))
        (should (process-live-p proc))
        ;; Kill it: "killed" event → sentinel finalises + clears flag
        ;; (regex now matches "killed", AUD-008 F-001).
        (delete-process proc)
        (accept-process-output nil 0.3)
        (sleep-for 0.1)
        (should-not satan-run--spawn-running)))))

;; ── SL-017 DEC-016: one tool-ctx, from the run struct ──────────────────────

(ert-deftest satan-broker/spawn-hands-run-tool-ctx-to-observer-and-alerts ()
  "The observer and the pre-spawn alerts both see the run's own tool-ctx.
The struct is built right after the audit opens, and every later
`prepare' rebind is synced into it: enrich is stubbed to return a
FRESH list, so only an explicit `setf' can carry its keys into the
struct the filter is handed."
  (satan-broker-test--with-spawn-stubs dir
    (let* ((audit (list :audit 'sentinel))
           (run-id "20260603T000000-test-a1b2c3")
           (prepare (list :run_id run-id
                          :time_now "2026-06-03T00:00:00Z"
                          :start_time (current-time)
                          :percept '(:handles ("h1" "h2"))))
           (mode '(:name "test" :capabilities (notify)
                   :harness (:cmd "true" :args nil)))
           observer-ctx alerts-ctx run-ctx)
      (cl-letf (((symbol-function 'satan-audit-open)
                 (lambda (&rest _) audit))
                ((symbol-function 'satan-observer-process)
                 (lambda (ctx &rest _) (setq observer-ctx ctx) 'OBS))
                ((symbol-function 'satan-run-enrich)
                 (lambda (p &rest _) (append p (list :resonance 'R))))
                ((symbol-function 'satan-sensor-alerts-check)
                 (lambda (_ss &rest kw)
                   (setq alerts-ctx (plist-get kw :tool-ctx))
                   'PRE))
                ((symbol-function 'satan-broker--make-filter)
                 (lambda (ctx) (setq run-ctx ctx) #'ignore)))
        (should (equal run-id (satan-broker--spawn mode prepare dir)))
        (let ((proc (get-process (format "satan-%s" run-id))))
          (while (process-live-p proc) (accept-process-output proc 0.1))
          (accept-process-output nil 0.1)))
      (should (equal run-id (plist-get observer-ctx :id)))
      (should (eq audit (plist-get observer-ctx :audit)))
      (should (equal "2026-06-03T00:00:00Z"
                     (plist-get observer-ctx :time-now)))
      (should (equal '("h1" "h2") (plist-get observer-ctx :percept-handles)))
      (should (equal run-id (plist-get alerts-ctx :id)))
      (should (eq audit (plist-get alerts-ctx :audit)))
      (should (equal '(notify) (plist-get alerts-ctx :capabilities)))
      (let ((final (satan-run-prepare run-ctx)))
        (should (eq 'OBS (plist-get final :observer)))
        (should (eq 'R (plist-get final :resonance)))
        (should (eq 'PRE (plist-get final :pre_spawn)))))))

(ert-deftest satan-broker/dec8-sentinel-clears-flag-on-exit-events ()
  "AUD-008 F-001: the child sentinel clears `--spawn-running' on every
terminal event — including \"killed\" (timeout/`delete-process'), which the
old regex missed."
  (dolist (event '("finished\n" "exited abnormally with code 1\n"
                   "killed\n" "broken pipe\n"))
    (let* ((satan-run--spawn-running t)
           (run-ctx (make-satan-run
                     :id "rid" :mode '(:name "test")
                     :start-time (current-time) :dir "/tmp"
                     :status 'running :audit '(:audit t)))
           (sentinel (satan-broker--make-sentinel run-ctx)))
      (cl-letf (((symbol-function 'satan-audit-record) (lambda (&rest _) nil))
                ((symbol-function 'satan-broker--finalize) (lambda (&rest _) nil)))
        (funcall sentinel nil event))
      (should-not satan-run--spawn-running))))

(ert-deftest satan-broker/sentinel-clears-flag-when-finalize-or-exit-record-signals ()
  "VT-19 (ISS-020): a signal from the `child-exit' record or from finalize
still clears `--spawn-running', and still propagates."
  (dolist (failing '(satan-audit-record satan-broker--finalize))
    (let* ((satan-run--spawn-running t)
           (run-ctx (make-satan-run
                     :id "rid" :mode '(:name "test")
                     :start-time (current-time) :dir "/tmp"
                     :status 'running :audit '(:audit t)))
           (sentinel (satan-broker--make-sentinel run-ctx)))
      (cl-letf (((symbol-function 'satan-audit-record) #'ignore)
                ((symbol-function 'satan-broker--finalize) #'ignore))
        (cl-letf (((symbol-function failing)
                   (lambda (&rest _) (error "%s boom" failing))))
          (should-error (funcall sentinel nil "finished\n"))))
      (should-not satan-run--spawn-running))))

;; ── SL-017 I7: a spawn that cannot fail silently ───────────────────────────

(defconst satan-broker-test--spawn-run-id "20260603T000000-test-a1b2c3"
  "A minted-shape run-id for the spawn-failure tests.")

(defun satan-broker-test--spawn-prepare (&rest extra)
  "A prepare plist for `satan-broker-test--spawn-run-id', plus EXTRA."
  (append (list :run_id satan-broker-test--spawn-run-id
                :time_now "2026-06-03T00:00:00Z"
                :start_time (current-time)
                :percept '(:handles ("h1")))
          extra))

(defun satan-broker-test--run-json (dir name)
  "Parse the JSON artefact NAME under run DIR into a plist."
  (satan-audit--read-json (expand-file-name name dir)))

(defun satan-broker-test--run-status (dir)
  "Return the trimmed contents of DIR's `status' file."
  (with-temp-buffer
    (insert-file-contents (expand-file-name "status" dir))
    (string-trim (buffer-string))))

(ert-deftest satan-broker/no-child-run-survives-broken-manifest ()
  "I7: a no-child run whose manifest cannot be built still ends with a
status.  The mode names an unregistered tool, so the real
`--build-manifest' signals; the writer records a stub manifest instead."
  (satan-broker-test--with-spawn-collaborators root dir
    (let ((prepare (satan-broker-test--spawn-prepare))
          (mode '(:name "test" :tools ("no_such_tool")))
          (failed (concat dir ".FAILED")))
      (satan-announce-with-recorder
        (satan-broker--write-budget-denied-run mode prepare dir 10 5))
      (should (equal "budget-exceeded" (satan-broker-test--run-status failed)))
      (let ((manifest (satan-broker-test--run-json failed "manifest.json")))
        (should (stringp (plist-get manifest :manifest_error)))
        (should (equal satan-broker-test--spawn-run-id
                       (plist-get manifest :run_id))))
      (should (equal '(:handles ("h1"))
                     (plist-get (satan-broker-test--run-json
                                 failed "bundle.json")
                                :percept)))
      (should (eq t (satan-audit-verify-run failed))))))

(defun satan-broker-test--spawn-failing (mode prepare dir)
  "Run `satan-broker--spawn' for MODE under a tick accumulator and recorder.
The accumulator starts stamped \"spawned\", as `satan-broker-run'
leaves it.  Returns (:run-id ID :outcome STAMP :announced RECORDED)."
  (let ((satan-trace--current (list :outcome "spawned")))
    (satan-announce-with-recorder
      (let ((run-id (satan-broker--spawn mode prepare dir)))
        (list :run-id run-id
              :outcome (plist-get satan-trace--current :outcome)
              :announced satan-announce-recorded)))))

(defun satan-broker-test--broker-event (dir event)
  "Payload of the first `broker' EVENT record in DIR's transcript."
  (plist-get (cl-find-if
              (lambda (r)
                (and (equal "broker" (plist-get r :dir))
                     (equal event (plist-get r :event))))
              (satan-jsonl-read-file
               (expand-file-name "transcript.jsonl" dir) :null-object :null))
             :payload))

(defun satan-broker-test--should-spawn-fail (result dir)
  "Assert RESULT (see `satan-broker-test--spawn-failing') is a recorded
pre-child failure of the run in DIR.  Returns the `.FAILED' dir."
  (let ((failed (concat dir ".FAILED"))
        (run-id satan-broker-test--spawn-run-id))
    (should (equal run-id (plist-get result :run-id)))
    (should-not satan-run--spawn-running)
    (should-not satan-memory-store--current-run-id)
    (should-not (get-buffer (format " *satan-stderr-%s*" run-id)))
    (should-not (get-process (format "satan-%s stderr" run-id)))
    (should (equal "spawn_failed" (plist-get result :outcome)))
    (should (equal "failed" (satan-broker-test--run-status failed)))
    (should (equal "spawn_failed"
                   (plist-get (satan-broker-test--run-json failed "final.json")
                              :reason)))
    (should (stringp (plist-get (satan-broker-test--broker-event
                                 failed "spawn-failed")
                                :error)))
    (should (eq t (satan-audit-verify-run failed)))
    (let ((announced (plist-get result :announced)))
      (should (= 1 (length announced)))
      (should (string-match-p "spawn_failed"
                              (plist-get (car announced) :journal))))
    failed))

(ert-deftest satan-broker/spawn-error-before-child-finalizes-spawn-failed ()
  "A pre-child error after the audit opened finalises the run as
`spawn_failed' and returns the run-id: the context-fn throws before
any bundle, so the percept is mirrored into `bundle.json'."
  (satan-broker-test--with-spawn-collaborators root dir
    (let* ((mode (list :name "test"
                       :context-fn (lambda (&rest _) (error "boom"))
                       :harness '(:cmd "true")))
           (failed (satan-broker-test--should-spawn-fail
                    (satan-broker-test--spawn-failing
                     mode (satan-broker-test--spawn-prepare) dir)
                    dir)))
      (should (equal '(:handles ("h1"))
                     (plist-get (satan-broker-test--run-json
                                 failed "bundle.json")
                                :percept)))
      (should (equal "boom" (plist-get (satan-broker-test--broker-event
                                        failed "spawn-failed")
                                       :error)))
      ;; Finalised through the open audit (the run struct), not re-opened
      ;; by the no-child writer: only `--finalize' records crash context.
      ;; The context-fn runs after the pre-spawn window, which completed.
      (should (eq t (plist-get (satan-broker-test--broker-event
                                failed "crash-context")
                               :pre_spawn_completed))))))

(ert-deftest satan-broker/spawn-error-in-pre-spawn-reports-incomplete ()
  "A pre-spawn stage that throws (enrich) is a pre-child failure whose
crash context says the pre-spawn window did not complete (RV-012 F-4)."
  (satan-broker-test--with-spawn-collaborators root dir
    (cl-letf (((symbol-function 'satan-run-enrich)
               (lambda (&rest _) (error "enrich exploded"))))
      (let* ((mode '(:name "test" :harness (:cmd "true")))
             (failed (satan-broker-test--should-spawn-fail
                      (satan-broker-test--spawn-failing
                       mode (satan-broker-test--spawn-prepare) dir)
                      dir)))
        (should (eq :false (plist-get (satan-broker-test--broker-event
                                       failed "crash-context")
                                      :pre_spawn_completed)))))))

(ert-deftest satan-broker/manifest-error-finalizes-spawn-failed ()
  "A manifest that cannot be built (before the audit opens) still ends
the run with a status: the no-child writer records a stub manifest."
  (satan-broker-test--with-spawn-collaborators root dir
    (let* ((mode '(:name "test" :tools ("no_such_tool")
                   :harness (:cmd "true")))
           (failed (satan-broker-test--should-spawn-fail
                    (satan-broker-test--spawn-failing
                     mode (satan-broker-test--spawn-prepare) dir)
                    dir)))
      (should (string-match-p
               "no_such_tool"
               (plist-get (satan-broker-test--run-json failed "final.json")
                          :summary)))
      (should (stringp (plist-get (satan-broker-test--run-json
                                   failed "manifest.json")
                                  :manifest_error)))
      (should (equal '(:handles ("h1"))
                     (plist-get (satan-broker-test--run-json
                                 failed "bundle.json")
                                :percept))))))

(ert-deftest satan-broker/spawn-exec-failure-keeps-context-bundle ()
  "`make-process' itself failing is a pre-child error too, and the
percept is mirrored only when no bundle exists: the context-fn's
bundle, already attached, survives."
  (satan-broker-test--with-spawn-collaborators root dir
    (let* ((mode (list :name "test"
                       :context-fn (lambda (&rest _)
                                     '(:ctx t :percept (:handles ("ctx"))))
                       :harness '(:cmd "/nonexistent/satan-harness")))
           (failed (satan-broker-test--should-spawn-fail
                    (satan-broker-test--spawn-failing
                     mode (satan-broker-test--spawn-prepare) dir)
                    dir))
           (bundle (satan-broker-test--run-json failed "bundle.json")))
      (should (eq t (plist-get bundle :ctx)))
      (should (equal '(:handles ("ctx")) (plist-get bundle :percept))))))

(ert-deftest satan-broker/error-after-child-not-finalized-twice ()
  "An error after `make-process' leaves the run to the child's sentinel:
the handler re-signals and finalises nothing, and the sentinel later
finalises exactly once and kills the stderr buffer."
  (satan-broker-test--with-spawn-stubs dir
    (let* ((run-id "rid-post-child")
           (proc-name (format "satan-%s" run-id))
           (stderr-name (format " *satan-stderr-%s*" run-id))
           (prepare (list :run_id run-id
                          :time_now "2026-06-03T00:00:00Z"
                          :start_time (current-time)))
           (mode '(:name "test" :timeout-seconds 30
                   :harness (:cmd "sleep" :args ("30"))))
           (finalized 0))
      (cl-letf (((symbol-function 'satan-broker--finalize)
                 (lambda (&rest _) (cl-incf finalized))))
        (unwind-protect
            (progn
              (cl-letf (((symbol-function 'run-with-timer)
                         (lambda (&rest _) (error "timer wiring"))))
                (should-error (satan-broker--spawn mode prepare dir)))
              (should (= 0 finalized))
              (should-not satan-run--spawn-running)
              (should (process-live-p (get-process proc-name)))
              (delete-process (get-process proc-name))
              (accept-process-output nil 0.3)
              (sleep-for 0.1)
              (should (= 1 finalized))
              (should-not (get-buffer stderr-name)))
          (let ((proc (get-process proc-name)))
            (when proc (delete-process proc)))
          (let ((buf (get-buffer stderr-name)))
            (when buf (kill-buffer buf))))))))

;; ---------------------------------------------------------------------
;; PRESERVED-BOUNDARY PIN — SL-002 §5.3 / §9.  Do not prune with the bough
;; integration: this asserts the *preserved* content-agnostic substrate.
;; ---------------------------------------------------------------------

(ert-deftest satan-broker/audit-records-explicit-bough-cue-handles-verbatim ()
  "The inbound `tool_call' audit record copies the caller's args verbatim,
including explicit `bough_*' literals in a `memory_resonate' cue.

One of the five fresh-introduction surfaces (RN-9/RN-11).  The audit writer
is content-agnostic — it neither derives nor filters handles — so removing
the bough integration must not change what it records.  Explicit-handle
resonate remains a preserved read path even once nothing derives a bough
handle any more."
  (let* ((mode (list :name "test-mode"
                     :capabilities '()
                     :tools '("memory_resonate")
                     :budget-tool-calls 4))
         (dir (make-temp-file "satan-bough-audit-" t)))
    (unwind-protect
        (let* ((audit (satan-audit-open
                       dir
                       '(:run_id "rid" :mode (:name "test-mode"))
                       '(:bundle t)
                       (list :run_id "rid"
                             :time_now "2026-05-22T10:00:00+1000")))
               (prepare (list :run_id "rid"
                              :time_now "2026-05-22T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :pre_spawn nil :motive nil))
               (run-ctx (make-satan-run
                         :id "rid" :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir :tool-calls-done 0
                         :status 'running
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'satan-jsonl-send) (lambda (&rest _) nil)))
            (satan-broker--on-tool-call
             run-ctx
             '(:type "tool_call" :id "c-bough" :name "memory_resonate"
               :args (:cue (:handles ["bough_node:abc" "app:emacs"])))))
          (let* ((records (satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir)
                           :null-object :null))
                 (call (cl-find-if
                        (lambda (r)
                          (and (equal (plist-get r :dir) "in")
                               (equal (plist-get r :event) "tool-call")))
                        records))
                 (handles (thread-first call
                                        (plist-get :payload)
                                        (plist-get :args)
                                        (plist-get :cue)
                                        (plist-get :handles))))
            (should call)
            ;; `satan-jsonl-read-file' returns JSON arrays as lists.
            (should (equal '("bough_node:abc" "app:emacs") (append handles nil)))))
      (delete-directory dir t))))

(provide 'satan-broker-test)
;;; satan-broker-test.el ends here
