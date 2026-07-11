;;; dl-satan-broker-test.el --- ert tests for dl-satan-broker -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/lisp -L ~/.emacs.d/org \
;;     -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-broker-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)                          ; budget gating test parses final.json
(require 'dl-satan-jsonl)
(require 'dl-satan-audit)
(require 'dl-satan-broker)
(require 'dl-satan-budget)               ; budget gating cross-cutter
(require 'cl-macs)                       ; cl-letf used in tool-ctx tests
(require 'dl-satan-mode)                 ; manifest-tools-shape resolves "morning"
;; Tool modules must be loaded so each registers via `dl-satan-tool-register'
;; before `dl-satan-broker--build-manifest' looks them up.
(require 'dl-satan-tools-notify)
(require 'dl-satan-tools-hippocampus)
(require 'dl-satan-tools-inbox)
(require 'dl-satan-tools-org)
(require 'dl-satan-tools-agenda)
(require 'dl-satan-tools-activity)
(require 'dl-satan-tools-notes)
(require 'dl-satan-tools-atsatan)
(require 'dl-satan-tools-sway)
(require 'dl-satan-tools-docs)
(require 'dl-satan-tools-memory)
(require 'dl-satan-tools-motive)
(require 'dl-satan-tools-bough)
(require 'dl-satan-tools-vcs)            ; morning/tick modes reference vcs_log
(require 'dl-satan-mcp)                   ; dl-satan-mcp--session-active (session gate)
(require 'dl-satan-trace)                 ; SL-011 tick trace row (VT-1)

;; Cross-cutter: assertion subject is broker (action-failed audit
;; emission); secondary subject is the tools dispatcher's
;; capability-guard.  Filed under broker per T6 brief.
(ert-deftest dl-satan-broker/capability-denial-emits-failed-action-audit ()
  "On dispatch capability denial, broker writes an `action-failed' audit
record using the canonical failed-action plist shape
`(:action ACTION :reason MSG)' alongside the tool_result record."
  (let* ((mode (list :name "test-mode"
                     :capabilities '(inbox-write)
                     :tools '("notify_send")
                     :budget-tool-calls 4))
         (dir (make-temp-file "satan-cap-audit-" t)))
    (unwind-protect
        (let* ((audit (dl-satan-audit-open
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
               (run-ctx (make-dl-satan-run
                         :id "rid" :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir :tool-calls-done 0
                         :status 'running
                         :audit audit
                         :prepare prepare))
               ;; Hold process slot so send-validated has something to call;
               ;; intercept the send instead of touching a real pipe.
               (sent nil))
          (cl-letf (((symbol-function 'dl-satan-jsonl-send)
                     (lambda (_proc obj) (push obj sent))))
            (dl-satan-broker--on-tool-call
             run-ctx
             '(:type "tool_call" :id "c-cap" :name "notify_send"
               :args (:title "t" :body "b"))))
          (let* ((records (dl-satan-jsonl-read-file
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

;; ---------- dl-satan-broker tool-ctx ----------

(ert-deftest dl-satan-broker/tool-ctx-shape ()
  "Tool-ctx carries run-id, mode, capabilities, dirs, and frozen time fields
read from the prepare-phase run_ctx plist."
  (let* ((mode '(:name morning :capabilities (memory-write)))
         (start (encode-time '(0 0 10 19 5 2026 nil nil 36000)))
         (prepare (list :run_id "20260519T100000-morning-abc123"
                        :time_now "2026-05-19T10:00:00+1000"
                        :start_time start
                        :evidence nil :percept nil
                        :sensor_status nil :pre_spawn nil :motive nil))
         (run-ctx (make-dl-satan-run
                   :id "20260519T100000-morning-abc123"
                   :mode mode
                   :start-time start
                   :dir "/tmp/satan-run-test"
                   :prepare prepare))
         (tool-ctx (dl-satan-broker--tool-ctx run-ctx)))
    (should (equal (plist-get tool-ctx :id)
                   "20260519T100000-morning-abc123"))
    (should (equal (plist-get tool-ctx :mode-name) 'morning))
    (should (equal (plist-get tool-ctx :capabilities) '(memory-write)))
    (should (equal (plist-get tool-ctx :run-dir) "/tmp/satan-run-test"))
    (should (equal (plist-get tool-ctx :run-started-at)
                   "2026-05-19T10:00:00+1000"))
    (should (equal (plist-get tool-ctx :time-now)
                   "2026-05-19T10:00:00+1000"))))

(ert-deftest dl-satan-broker/tool-ctx-does-not-call-format-time-string ()
  "tool-ctx must read time_now from run_ctx, never compute it on demand."
  (let* ((mode '(:name morning :capabilities ()))
         (prepare (list :run_id "rid" :time_now "2026-01-01T00:00:00+0000"
                        :start_time (current-time)
                        :evidence nil :percept nil
                        :sensor_status nil :pre_spawn nil :motive nil))
         (run-ctx (make-dl-satan-run
                   :id "rid" :mode mode
                   :start-time (plist-get prepare :start_time)
                   :dir "/tmp/x" :prepare prepare))
         (called nil))
    (cl-letf (((symbol-function 'format-time-string)
               (lambda (&rest args) (setq called args) "NEVER")))
      (let ((tool-ctx (dl-satan-broker--tool-ctx run-ctx)))
        (should (equal (plist-get tool-ctx :time-now)
                       "2026-01-01T00:00:00+0000"))
        (should (null called))))))

(ert-deftest dl-satan-broker/date-bucket-extracted-from-run-id ()
  (should (equal (dl-satan-broker--date-bucket-for-run-id
                  "20260520T163446-tick-pulse-5e8018")
                 "2026-05-20"))
  (should (null (dl-satan-broker--date-bucket-for-run-id "garbage")))
  (should (null (dl-satan-broker--date-bucket-for-run-id nil))))

(ert-deftest dl-satan-broker/run-id-from-leaf-strips-failed-suffix ()
  (should (equal (dl-satan-broker--run-id-from-leaf
                  "20260520T163446-tick-pulse-5e8018.FAILED")
                 "20260520T163446-tick-pulse-5e8018"))
  (should (equal (dl-satan-broker--run-id-from-leaf
                  "20260520T163446-tick-pulse-5e8018")
                 "20260520T163446-tick-pulse-5e8018")))

(ert-deftest dl-satan-broker/list-run-dirs-walks-both-layouts ()
  "Enumerator returns paths for legacy flat and bucketed runs, plus FAILED."
  (let ((root (make-temp-file "satan-runs-list-" t)))
    (unwind-protect
        (let ((legacy   (expand-file-name "20260519T100000-x-aaaaaa" root))
              (legacy-f (expand-file-name "20260519T110000-x-bbbbbb.FAILED" root))
              (bucket   (expand-file-name "2026-05-20" root))
              (bucketed (expand-file-name
                         "2026-05-20/20260520T120000-x-cccccc" root))
              (bucketed-f (expand-file-name
                           "2026-05-20/20260520T130000-x-dddddd.FAILED" root))
              (noise    (expand-file-name "not-a-run-dir" root))
              (noise-bucket-child
               (expand-file-name "2026-05-20/scratch" root)))
          (dolist (d (list legacy legacy-f bucket bucketed bucketed-f
                           noise noise-bucket-child))
            (make-directory d t))
          (let ((got (dl-satan-broker-list-run-dirs root)))
            (should (member legacy got))
            (should (member legacy-f got))
            (should (member bucketed got))
            (should (member bucketed-f got))
            (should-not (member noise got))
            (should-not (member noise-bucket-child got))
            (should-not (cl-find-if (lambda (p)
                                      (equal (file-name-nondirectory p)
                                             "2026-05-20"))
                                    got))))
      (delete-directory root t))))

(ert-deftest dl-satan-broker/failure-streak-counts-trailing-failed ()
  "Counts consecutive .FAILED dirs back from the newest run-id."
  (let ((root (make-temp-file "satan-runs-streak-" t)))
    (unwind-protect
        (progn
          ;; Empty → 0.
          (should (= 0 (dl-satan-broker--failure-streak-count root)))
          ;; One done run → 0.
          (make-directory
           (expand-file-name "2026-05-20/20260520T100000-x-aaaaaa" root) t)
          (should (= 0 (dl-satan-broker--failure-streak-count root)))
          ;; Add a newer FAILED run → 1.
          (make-directory
           (expand-file-name
            "2026-05-20/20260520T110000-x-bbbbbb.FAILED" root) t)
          (should (= 1 (dl-satan-broker--failure-streak-count root)))
          ;; And another → 2.
          (make-directory
           (expand-file-name
            "2026-05-20/20260520T120000-x-cccccc.FAILED" root) t)
          (should (= 2 (dl-satan-broker--failure-streak-count root)))
          ;; A done run on top breaks the streak → 0.
          (make-directory
           (expand-file-name "2026-05-20/20260520T130000-x-dddddd" root) t)
          (should (= 0 (dl-satan-broker--failure-streak-count root))))
      (delete-directory root t))))

(ert-deftest dl-satan-broker/announce-failure-syslog-and-streak-gate ()
  "Always logs via syslog; only notifies on streak == 1."
  (let* ((logged nil)
         (notified 0)
         (root (make-temp-file "satan-runs-announce-" t))
         (dl-satan-runs-dir root)
         (dl-satan-failure-syslog t)
         (dl-satan-failure-notify t))
    (unwind-protect
        (cl-letf
            (((symbol-function 'call-process)
              (lambda (cmd &rest args)
                (when (equal cmd "logger") (push args logged))
                0))
             ((symbol-function 'notifications-notify)
              (lambda (&rest _args) (cl-incf notified) 42)))
          ;; No prior runs → streak == 0 before rename; the just-renamed
          ;; dir is what bumps it to 1.  Emulate by creating that dir
          ;; first, then calling announce.
          (make-directory
           (expand-file-name
            "2026-05-20/20260520T100000-tick-pulse-aaaaaa.FAILED" root) t)
          (dl-satan-broker--announce-failure
           "20260520T100000-tick-pulse-aaaaaa" "tick-pulse"
           'failed "child-exit-1")
          (should (= 1 (length logged)))
          (should (= 1 notified))
          ;; Second consecutive failure → still logged, NOT notified.
          (make-directory
           (expand-file-name
            "2026-05-20/20260520T110000-tick-pulse-bbbbbb.FAILED" root) t)
          (dl-satan-broker--announce-failure
           "20260520T110000-tick-pulse-bbbbbb" "tick-pulse"
           'failed "child-exit-1")
          (should (= 2 (length logged)))
          (should (= 1 notified)))
      (delete-directory root t))))

(ert-deftest dl-satan-broker/announce-failure-respects-disables ()
  "Both syslog and notify are gated by their respective defcustom flags."
  (let* ((logged 0) (notified 0)
         (root (make-temp-file "satan-runs-announce2-" t))
         (dl-satan-runs-dir root)
         (dl-satan-failure-syslog nil)
         (dl-satan-failure-notify nil))
    (unwind-protect
        (cl-letf
            (((symbol-function 'call-process)
              (lambda (&rest _args) (cl-incf logged) 0))
             ((symbol-function 'notifications-notify)
              (lambda (&rest _args) (cl-incf notified) 42)))
          (make-directory
           (expand-file-name
            "2026-05-20/20260520T100000-tick-pulse-aaaaaa.FAILED" root) t)
          (dl-satan-broker--announce-failure
           "20260520T100000-tick-pulse-aaaaaa" "tick-pulse"
           'failed "child-exit-1")
          (should (= 0 logged))
          (should (= 0 notified)))
      (delete-directory root t))))

(ert-deftest dl-satan-broker/locate-run-dir-finds-failed-and-buckets ()
  "Locator falls back through bucketed, bucketed-FAILED, legacy, legacy-FAILED."
  (let ((root (make-temp-file "satan-runs-locate-" t)))
    (unwind-protect
        (progn
          (let ((d (expand-file-name "2026-05-20/20260520T100000-x-aaaaaa"
                                     root)))
            (make-directory d t)
            (should (equal (dl-satan-broker-locate-run-dir
                            "20260520T100000-x-aaaaaa" root)
                           d)))
          (let ((d (expand-file-name
                    "2026-05-20/20260520T110000-x-bbbbbb.FAILED" root)))
            (make-directory d t)
            (should (equal (dl-satan-broker-locate-run-dir
                            "20260520T110000-x-bbbbbb" root)
                           d)))
          (let ((d (expand-file-name "20260520T120000-x-cccccc" root)))
            (make-directory d t)
            (should (equal (dl-satan-broker-locate-run-dir
                            "20260520T120000-x-cccccc" root)
                           d)))
          (should (null (dl-satan-broker-locate-run-dir
                         "20260520T999999-nope-zzzzzz" root))))
      (delete-directory root t))))

;; ---------- dl-satan-broker--prepare (Phase 0.1) ----------

(ert-deftest dl-satan-broker/prepare-plist-shape ()
  "prepare returns a run_ctx plist with frozen run_id + time_now and v0 placeholders."
  (let* ((mode '(:name "tick-pulse"))
         (run-ctx (dl-satan-broker--prepare mode)))
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

(ert-deftest dl-satan-broker/prepare-mints-distinct-run-ids ()
  "Two calls to prepare allocate different run_ids."
  (let* ((mode '(:name "x"))
         (a (dl-satan-broker--prepare mode))
         (b (dl-satan-broker--prepare mode)))
    (should-not (equal (plist-get a :run_id) (plist-get b :run_id)))))

(ert-deftest dl-satan-broker/prepare-freezes-time-now-once ()
  "time_now is computed exactly once at prepare; identical across reads."
  (let* ((mode '(:name "tick-pulse"))
         (run-ctx (dl-satan-broker--prepare mode))
         (frozen (plist-get run-ctx :time_now)))
    (sleep-for 0.05)
    (should (equal frozen (plist-get run-ctx :time_now)))))

;; ---------- dl-satan-broker manifest assembly ----------

(defconst dl-satan-broker-test--morning-tool-descriptions
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
    ("bough_read"             . "Read bough.")
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
Shared by every broker gate VT that drives `dl-satan-broker-run' (the
manifest build looks up a description per allowed tool).")

(defun dl-satan-broker-test--with-tool-descriptions (alist body-fn)
  "Run BODY-FN with `dl-satan-tools-descriptions-dir' bound to a tmp dir
populated from ALIST `((NAME . CONTENT) …)'."
  (let ((tmp (make-temp-file "satan-tools-" t)))
    (unwind-protect
        (let ((dl-satan-tools-descriptions-dir tmp))
          (dolist (pair alist)
            (with-temp-file (expand-file-name (concat (car pair) ".md") tmp)
              (insert (cdr pair))))
          (funcall body-fn))
      (delete-directory tmp t))))

(ert-deftest dl-satan-broker/manifest-tools-shape ()
  "Manifest carries one JSON Schema per allowed tool plus satan_final."
  (dl-satan-broker-test--with-tool-descriptions
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
     ("bough_read"             . "Read from bough.")
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
     (let* ((mode (dl-satan-mode-resolve "morning"))
            (manifest (dl-satan-broker--build-manifest mode "test-run"))
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

(defun dl-satan-broker-test--write-transcript (dir lines)
  "Write LINES (each a plist) as transcript.jsonl under DIR."
  (make-directory dir t)
  (let ((coding-system-for-write 'utf-8))
    (with-temp-file (expand-file-name "transcript.jsonl" dir)
      (dolist (l lines)
        (insert (json-serialize
                 (dl-satan-jsonl-prepare l)
                 :null-object :null :false-object :false))
        (insert "\n")))))

(defun dl-satan-broker-test--usage-record (tokens-total)
  (list :ts "2026-05-19T09:00:00.000000+1000"
        :dir "in" :event "log"
        :payload (list :type "log" :kind "usage"
                       :tokens_in 0 :tokens_out 0
                       :tokens_total tokens-total)))

(defun dl-satan-broker-test--minimal-perceive (prepare _mode pdir)
  "Minimal `dl-satan-run-perceive' stub for gate-path tests (DR-010 §3).
Threads a minimal non-nil `:percept' onto PREPARE and persists
`percept.json' under PDIR, exactly as the real perceive does for the
identity/mirror invariants — but without the live evidence assembler
(which reads sensors/git/bough, out of scope for gate tests).  Also
threads empty `:probe_snapshots' so the consume-side commit (only
reached on the spawn path) has the key to read.  Reuse this in any
broker gate VT that asserts the percept/bundle artifacts."
  (let ((percept (list :run_id (plist-get prepare :run_id)
                       :time_now (plist-get prepare :time_now)
                       :handles nil
                       :evidence_window nil)))
    (dl-satan-percept-persist pdir percept)
    (thread-first prepare
                  (plist-put :percept percept)
                  (plist-put :evidence nil)
                  (plist-put :sensor_status nil)
                  (plist-put :probe_snapshots
                             (list :curiosity nil :content nil :wpm nil)))))

(defun dl-satan-broker-test--read-bundle (dir)
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

(ert-deftest dl-satan-broker/refuses-spawn-when-budget-exceeded ()
  "Pre-spawn gate writes status=budget-exceeded; no child spawned.
Secondary subject: dl-satan-budget (gating policy)."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-bud-broker-" t))
            (now (current-time))
            (today (format-time-string "%Y%m%dT" now))
            (existing (expand-file-name (concat today "080000-x-eeeeee") root))
            (dl-satan-runs-dir root)
            (dl-satan-budget-daily-tokens 400000)
            (dl-satan-trace-enabled nil))  ; SL-011: keep the real trace dir clean
       (unwind-protect
           ;; DR-010 §3: perceive now runs UNCONDITIONALLY before the budget
           ;; gate.  This test's subject is the gate, not perception, so stub
           ;; `dl-satan-run-perceive' to thread a minimal `:percept' (the real
           ;; evidence assembler reads sensors/git/bough — out of scope here).
           ;; The stub still persists `percept.json' and threads `:percept' so
           ;; the gate path and the new bundle `:percept' mirror stay exercised;
           ;; the budget assertions below are untouched.
           (cl-letf (((symbol-function 'dl-satan-run-perceive)
                      #'dl-satan-broker-test--minimal-perceive))
             (dl-satan-broker-test--write-transcript
              existing (list (dl-satan-broker-test--usage-record 500000)))
             (let* ((run-id (dl-satan-broker-run "morning"))
                    (dir (dl-satan-broker-locate-run-dir run-id root))
                    (status-path (expand-file-name "status" dir)))
               (should (string-suffix-p ".FAILED" dir))
               (should (file-directory-p dir))
               (should (file-readable-p status-path))
               (should (equal (string-trim
                               (with-temp-buffer
                                 (insert-file-contents status-path)
                                 (buffer-string)))
                              "budget-exceeded"))
               (should (eq (dl-satan-audit-verify-run dir) t))
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

;; ---------- VT-budget-denied-perceives (DR-010 §5, ISSUE-001) ----------

(ert-deftest dl-satan-broker/budget-denied-still-perceives ()
  "ISSUE-001 regression: a budget-denied tick perceives FIRST.
`percept.json' is written under the run-dir AND `bundle.json' carries a
non-nil `:percept' (consumers read the bundle, not the sidecar).  Status
is `budget-exceeded'.  Mirrors the gate test's fixture (over-ceiling
existing transcript) but asserts the perceive artifacts, not the gate."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-bud-perceive-" t))
            (now (current-time))
            (today (format-time-string "%Y%m%dT" now))
            (existing (expand-file-name (concat today "080000-x-eeeeee") root))
            (dl-satan-runs-dir root)
            (dl-satan-budget-daily-tokens 400000)
            (dl-satan-trace-enabled nil))  ; SL-011: keep the real trace dir clean
       (unwind-protect
           (cl-letf (((symbol-function 'dl-satan-run-perceive)
                      #'dl-satan-broker-test--minimal-perceive))
             (dl-satan-broker-test--write-transcript
              existing (list (dl-satan-broker-test--usage-record 500000)))
             (let* ((run-id (dl-satan-broker-run "morning"))
                    (dir (dl-satan-broker-locate-run-dir run-id root))
                    (status-path (expand-file-name "status" dir))
                    (percept-path (expand-file-name "percept.json" dir))
                    (bundle (dl-satan-broker-test--read-bundle dir)))
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

(ert-deftest dl-satan-broker/session-blocked-still-perceives ()
  "ISSUE-001 regression: a session-blocked tick perceives FIRST and stays silent.
With an interactive session active and budget UNDER ceiling,
`dl-satan-broker-run' still writes `percept.json' + a `:percept'-bearing
`bundle.json'; status is `failed' with reason \"session_blocked\".  The
run dir is NOT `.FAILED'-renamed and `dl-satan-broker--announce-failure'
is NOT called (DEC-8: the deferral must not pollute the failure streak or
pop a desktop alert).  The bundle is verify-clean."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (let* ((root (make-temp-file "satan-session-perceive-" t))
            (dl-satan-runs-dir root)
            (dl-satan-budget-daily-tokens 2500000) ; under ceiling: no spend
            (dl-satan-mcp--session-active t)        ; interactive session open
            (dl-satan-trace-enabled nil)  ; SL-011: keep the real trace dir clean
            (announced nil))
       (unwind-protect
           (cl-letf (((symbol-function 'dl-satan-run-perceive)
                      #'dl-satan-broker-test--minimal-perceive)
                     ((symbol-function 'dl-satan-broker--announce-failure)
                      (lambda (&rest _) (setq announced t))))
             (let* ((run-id (dl-satan-broker-run "morning"))
                    (dir (dl-satan-broker-locate-run-dir run-id root))
                    (status-path (expand-file-name "status" dir))
                    (percept-path (expand-file-name "percept.json" dir))
                    (bundle (dl-satan-broker-test--read-bundle dir)))
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
               (should (eq (dl-satan-audit-verify-run dir) t))))
         (delete-directory root t))))))

;; ---------- VT-1 (SL-011): one tick trace row per dl-satan-broker-run ----------

(defmacro dl-satan-broker-test--with-trace-dir (dir-var &rest body)
  "Bind `dl-satan-trace-dir' to a fresh temp DIR-VAR, run BODY, clean up."
  (declare (indent 1))
  `(let* ((,dir-var (make-temp-file "satan-broker-trace-" t))
          (dl-satan-trace-dir ,dir-var)
          (dl-satan-trace-enabled t))
     (unwind-protect
         (progn ,@body)
       (when (file-directory-p ,dir-var)
         (delete-directory ,dir-var t)))))

(defun dl-satan-broker-test--tick-rows (trace-dir)
  "Read today's kind:\"tick\" rows written under TRACE-DIR."
  (let ((file (expand-file-name
               (format "tick-trace-%s.jsonl" (format-time-string "%Y-%m-%d"))
               trace-dir)))
    (cl-remove-if-not
     (lambda (r) (equal (plist-get r :kind) "tick"))
     (dl-satan-jsonl-read-file file))))

(defun dl-satan-broker-test--fixture-percept (prepare _mode)
  "Fixture `dl-satan-percept-build' stub: identity keys only, no evidence."
  (list :run_id (plist-get prepare :run_id)
        :time_now (plist-get prepare :time_now)
        :handles nil
        :evidence_window nil))

(ert-deftest dl-satan-broker/run-emits-one-tick-row-outcome-spawned ()
  "VT-1: `dl-satan-trace-with-tick' wraps `dl-satan-broker-run'.
Exactly ONE kind:\"tick\" row is written, its `outcome' is \"spawned\",
and its `stages' map carries the perceive-path stage keys.  The real
`dl-satan-run-perceive' runs (percept-build stubbed to a fixture) so
the stage wraps inside the shared perceive fn record onto the tick."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (dl-satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-spawn-" t))
              (dl-satan-runs-dir root)
              (dl-satan-budget-daily-tokens 2500000) ; under ceiling
              (dl-satan-mcp--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'dl-satan-percept-build)
                        #'dl-satan-broker-test--fixture-percept)
                       ((symbol-function 'dl-satan-broker--spawn)
                        (lambda (_mode prepare _dir)
                          (plist-get prepare :run_id))))
               (let* ((run-id (dl-satan-broker-run "morning"))
                      (ticks (dl-satan-broker-test--tick-rows trace-dir))
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

(ert-deftest dl-satan-broker/run-tick-row-outcome-perceive-failed ()
  "VT-1: a perceive error stamps `outcome' \"perceive_failed\" on the tick row."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (dl-satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-perc-" t))
              (dl-satan-runs-dir root)
              (dl-satan-budget-daily-tokens 2500000)
              (dl-satan-mcp--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'dl-satan-run-perceive)
                        (lambda (&rest _) (error "sensor exploded")))
                       ((symbol-function 'dl-satan-broker--announce-failure)
                        (lambda (&rest _) nil)))
               (dl-satan-broker-run "morning")
               (let ((ticks (dl-satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "perceive_failed"
                                (plist-get (car ticks) :outcome)))))
           (delete-directory root t)))))))

(ert-deftest dl-satan-broker/run-tick-row-outcome-session-blocked ()
  "VT-1: an active interactive session stamps `outcome' \"session_blocked\"."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (dl-satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-sess-" t))
              (dl-satan-runs-dir root)
              (dl-satan-budget-daily-tokens 2500000)
              (dl-satan-mcp--session-active t))
         (unwind-protect
             (cl-letf (((symbol-function 'dl-satan-run-perceive)
                        #'dl-satan-broker-test--minimal-perceive))
               (dl-satan-broker-run "morning")
               (let ((ticks (dl-satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "session_blocked"
                                (plist-get (car ticks) :outcome)))))
           (delete-directory root t)))))))

(ert-deftest dl-satan-broker/run-tick-row-outcome-budget-denied ()
  "VT-1: an over-ceiling day stamps `outcome' \"budget_denied\"."
  (dl-satan-broker-test--with-tool-descriptions
   dl-satan-broker-test--morning-tool-descriptions
   (lambda ()
     (dl-satan-broker-test--with-trace-dir trace-dir
       (let* ((root (make-temp-file "satan-tick-bud-" t))
              (now (current-time))
              (today (format-time-string "%Y%m%dT" now))
              (existing (expand-file-name (concat today "080000-x-eeeeee") root))
              (dl-satan-runs-dir root)
              (dl-satan-budget-daily-tokens 400000)
              (dl-satan-mcp--session-active nil))
         (unwind-protect
             (cl-letf (((symbol-function 'dl-satan-run-perceive)
                        #'dl-satan-broker-test--minimal-perceive))
               (dl-satan-broker-test--write-transcript
                existing (list (dl-satan-broker-test--usage-record 500000)))
               (dl-satan-broker-run "morning")
               (let ((ticks (dl-satan-broker-test--tick-rows trace-dir)))
                 (should (= 1 (length ticks)))
                 (should (equal "budget_denied"
                                (plist-get (car ticks) :outcome)))))
           (delete-directory root t)))))))

;; ---------- VT-perceive-pure (DR-010 §5) ----------

(ert-deftest dl-satan-broker/perceive-is-pure ()
  "`dl-satan-run-perceive' performs no cognition / effects / consumption-mutation.
It may persist `percept.json' and take pure probe READS, but must NOT:
spawn a process (`make-process'), dispatch a tool (`dl-satan-tool-dispatch'),
enqueue an attribute (`dl-satan-attribute-enqueue'), advance any probe
watermark (the three `mark-inspected' / `--write-state' writers), OR advance
the ingest cursor (`dl-satan-ingest-cursor-advance' /
`dl-satan-ingest-cursor--write').  Each forbidden fn is spied to fail the
test if called.  Read-only local subprocess probes (git/bough via
`call-process') are ALLOWED and not spied.  `dl-satan-percept-build' is
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
         (dl-satan-attribute-updates-enabled t))
     (unwind-protect
         (cl-letf (((symbol-function 'dl-satan-percept-build)
                    (lambda (&rest _) fixture-percept))
                   ((symbol-function 'make-process)
                    (lambda (&rest _) (ert-fail "perceive spawned a process")))
                   ((symbol-function 'dl-satan-tool-dispatch)
                    (lambda (&rest _) (ert-fail "perceive dispatched a tool")))
                   ((symbol-function 'dl-satan-attribute-enqueue)
                    (lambda (&rest _) (ert-fail "perceive enqueued an attribute")))
                   ((symbol-function 'dl-satan-sensor-curiosity-mark-inspected)
                    (lambda (&rest _) (ert-fail "perceive advanced curiosity watermark")))
                   ((symbol-function 'dl-satan-sensor-content-mark-inspected)
                    (lambda (&rest _) (ert-fail "perceive advanced content watermark")))
                   ((symbol-function 'dl-satan-sensor-wpm--write-state)
                    (lambda (&rest _) (ert-fail "perceive advanced wpm state")))
                   ;; DE-010 P02 — ingest-cursor advance is consume-side only
                   ((symbol-function 'dl-satan-ingest-cursor-advance)
                    (lambda (&rest _) (ert-fail "perceive called ingest-cursor-advance")))
                   ((symbol-function 'dl-satan-ingest-cursor--write)
                    (lambda (&rest _) (ert-fail "perceive wrote ingest cursor state"))))
           (let ((out (dl-satan-run-perceive prepare '(:name "morning") dir)))
             ;; percept.json was persisted …
             (should (file-readable-p (expand-file-name "percept.json" dir)))
             ;; … and the pure probe read-snapshots were threaded.
             (should (plist-member out :probe_snapshots))
             (should (plist-get out :percept))))
       (delete-directory dir t))))

;; ---------- pre_spawn threading (Phase 4.4) ----------

(ert-deftest dl-satan-broker/finalize-threads-pre-spawn-into-actions-json ()
  "broker--finalize copies `:pre_spawn' from the prepare run_ctx into the
actions plist passed to `dl-satan-audit-close', which lands the
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
               (audit (dl-satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 30
                       :budget-tool-calls 1 :capabilities ()))
               (run-ctx (make-dl-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'dl-satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (dl-satan-broker--finalize run-ctx))
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
            (should (eq (dl-satan-audit-verify-run dir) t))))
      (delete-directory dir t))))

(ert-deftest dl-satan-broker/finalize-omits-pre-spawn-when-empty ()
  "When `:pre_spawn' is nil on prepare, actions.json omits the key
entirely so untouched runs keep the original four-partition shape."
  (let ((dir (make-temp-file "satan-broker-pre-spawn-empty-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-22T11:13Z"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (dl-satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 30
                       :budget-tool-calls 1 :capabilities ()))
               (run-ctx (make-dl-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'dl-satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (dl-satan-broker--finalize run-ctx))
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

(ert-deftest dl-satan-broker/crash-context-emitted-on-failed ()
  "Finalize emits a `crash-context' audit record on non-done terminal paths."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (dl-satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-dl-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'failed
                         :tool-calls-done 3
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'dl-satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (dl-satan-broker--finalize run-ctx))
          (let* ((records (dl-satan-jsonl-read-file
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

(ert-deftest dl-satan-broker/crash-context-not-emitted-on-done ()
  "Successful runs must NOT emit a crash-context record."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-done-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (dl-satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-dl-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'running
                         :final '(:summary "ok" :actions ())
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'dl-satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (dl-satan-broker--finalize run-ctx))
          (let* ((records (dl-satan-jsonl-read-file
                           (expand-file-name "transcript.jsonl" dir) :null-object :null))
                 (crash-ctx (cl-find-if
                             (lambda (r)
                               (and (equal (plist-get r :dir) "broker")
                                    (equal (plist-get r :event) "crash-context")))
                             records)))
            (should-not crash-ctx)))
      (delete-directory dir t))))

(ert-deftest dl-satan-broker/crash-context-emitted-on-timed-out ()
  "Timeout paths also emit crash-context."
  (let ((dir (make-temp-file "satan-broker-crash-ctx-timeout-" t)))
    (unwind-protect
        (let* ((prepare (list :run_id "rid" :time_now "2026-05-24T10:00:00+1000"
                              :start_time (current-time)
                              :evidence nil :percept nil
                              :sensor_status nil :motive nil :pre_spawn nil))
               (audit (dl-satan-audit-open
                       dir '(:run_id "rid" :mode (:name "test"))
                       '(:bundle t) prepare))
               (mode '(:name "test" :auto-apply none :timeout-seconds 1800
                       :budget-tool-calls 100 :budget-tokens 300000
                       :capabilities ()))
               (run-ctx (make-dl-satan-run
                         :id "rid"
                         :mode mode
                         :start-time (plist-get prepare :start_time)
                         :dir dir
                         :status 'timed-out
                         :tool-calls-done 7
                         :audit audit
                         :prepare prepare)))
          (cl-letf (((symbol-function 'dl-satan-broker--mark-failed-on-disk)
                     (lambda (&rest _) nil)))
            (dl-satan-broker--finalize run-ctx))
          (let* ((records (dl-satan-jsonl-read-file
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

;; ── DEC-8 mutual exclusion: producer side (AUD-008 F-001) ──────────────────

(ert-deftest dl-satan-broker/dec8-spawn-running-persists-until-sentinel ()
  "AUD-008 F-001: `dl-satan-broker--spawn-running' stays t across the live
async run and is cleared ONLY by the child sentinel — never at the
synchronous launch return (the original unwind-protect bug)."
  (let ((dir (make-temp-file "satan-spawn-flag-" t))
        (dl-satan-broker--spawn-running nil)
        (dl-satan-hippocampus-dir (make-temp-file "satan-hippo-" t)))
    (unwind-protect
        (cl-letf (((symbol-function 'dl-satan-broker--build-manifest)
                   (lambda (&rest _) '(:manifest t)))
                  ((symbol-function 'dl-satan-audit-open)
                   (lambda (&rest _) '(:audit t)))
                  ((symbol-function 'dl-satan-audit-attach-bundle)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-audit-record)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-observer-process)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-run-enrich)
                   (lambda (prepare &rest _) prepare))
                  ((symbol-function 'dl-satan-sensor-alerts-check)
                   (lambda (&rest _) nil))
                  ;; DR-010 §3: --spawn now calls the consume-side
                  ;; -probe-commit variants (perceive took the reads).
                  ((symbol-function 'dl-satan-sensor-curiosity-probe-commit)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-sensor-content-probe-commit)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-sensor-wpm-probe-commit)
                   (lambda (&rest _) nil))
                  ((symbol-function 'my/scrub-op-refs-env)
                   (lambda (env) env))
                  ((symbol-function 'dl-satan-broker--direnv-env)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-broker--exec-path-from-env)
                   (lambda (&rest _) exec-path))
                  ((symbol-function 'dl-satan-broker--update-most-recent)
                   (lambda (&rest _) nil))
                  ((symbol-function 'dl-satan-broker--finalize)
                   (lambda (&rest _) nil)))
          (let* ((prepare (list :run_id "rid-flag"
                                :time_now "2026-06-03T00:00:00Z"
                                :start_time (current-time)))
                 ;; A real but long-lived child so the run is genuinely "live"
                 ;; after spawn returns; no :timeout-seconds so no timer.
                 (mode '(:name "test" :harness (:cmd "sleep" :args ("30"))))
                 (run-id (dl-satan-broker--spawn mode prepare dir)))
            (should (equal run-id "rid-flag"))
            ;; Child still running → flag MUST still be set.  The bug cleared
            ;; it here, at synchronous return.
            (should dl-satan-broker--spawn-running)
            (let ((proc (get-process "satan-rid-flag")))
              (should (process-live-p proc))
              ;; Kill it: "killed" event → sentinel finalises + clears flag
              ;; (regex now matches "killed", AUD-008 F-001).
              (delete-process proc)
              (accept-process-output nil 0.3)
              (sleep-for 0.1)
              (should-not dl-satan-broker--spawn-running))))
      (delete-directory dir t)
      (when (file-directory-p dl-satan-hippocampus-dir)
        (delete-directory dl-satan-hippocampus-dir t)))))

(ert-deftest dl-satan-broker/dec8-sentinel-clears-flag-on-exit-events ()
  "AUD-008 F-001: the child sentinel clears `--spawn-running' on every
terminal event — including \"killed\" (timeout/`delete-process'), which the
old regex missed."
  (dolist (event '("finished\n" "exited abnormally with code 1\n"
                   "killed\n" "broken pipe\n"))
    (let* ((dl-satan-broker--spawn-running t)
           (run-ctx (make-dl-satan-run
                     :id "rid" :mode '(:name "test")
                     :start-time (current-time) :dir "/tmp"
                     :status 'running :audit '(:audit t)))
           (sentinel (dl-satan-broker--make-sentinel run-ctx)))
      (cl-letf (((symbol-function 'dl-satan-audit-record) (lambda (&rest _) nil))
                ((symbol-function 'dl-satan-broker--finalize) (lambda (&rest _) nil)))
        (funcall sentinel nil event))
      (should-not dl-satan-broker--spawn-running))))

(provide 'dl-satan-broker-test)
;;; dl-satan-broker-test.el ends here
