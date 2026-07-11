;;; dl-satan-tick.el --- Tick mode family for SATAN -*- lexical-binding: t; -*-

;; Tick modes are short, frequent, lightly-budgeted SATAN runs.  A single
;; systemd timer fires the broker every ~30 minutes; the broker picks one
;; tick mode from `dl-satan-tick-pool' by weight and runs it.  Quiet hours
;; suppress the run entirely so SATAN does not nudge during sleep.
;;
;; Per-tick budget is tight by design (≤40000 tokens, ≤4 tool calls, ≤60s).
;; The daily ceiling in `dl-satan-budget' caps total spend regardless.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-mode)
(require 'dl-satan-context)
(require 'dl-satan-output)
(require 'dl-satan-broker)

(defcustom dl-satan-tick-pool '(("tick-pulse" . 5) ("tick-agent" . 3))
  "Weighted alist of tick mode names.  Each entry is (MODE-NAME . WEIGHT).
`dl-satan-tick-pick' samples by weight; total weight must be positive."
  :type '(alist :key-type string :value-type integer)
  :group 'dl-satan)

(defcustom dl-satan-tick-quiet-hours nil ; was '(22 . 7); disabled while iterating
  "Quiet-hours window as (START-HOUR . END-HOUR), inclusive of START and
exclusive of END.  Set start ≥ end for a wraparound window (e.g. 22..7
suppresses 22:00 through 06:59).  Set to nil to disable quiet hours."
  :type '(choice (cons (integer :tag "Start hour")
                   (integer :tag "End hour"))
           (const :tag "Disabled" nil))
  :group 'dl-satan)

(defun dl-satan-tick-quiet-p (&optional time)
  "Return non-nil if TIME (or now) falls within `dl-satan-tick-quiet-hours'."
  (when dl-satan-tick-quiet-hours
    (let* ((h (string-to-number (format-time-string "%H" time)))
            (start (car dl-satan-tick-quiet-hours))
            (end   (cdr dl-satan-tick-quiet-hours)))
      (if (< start end)
        (and (>= h start) (< h end))
        (or (>= h start) (< h end))))))

(defun dl-satan-tick-pick (&optional pool)
  "Sample a tick mode name from POOL by weight.  Defaults to
`dl-satan-tick-pool'.  Returns nil if POOL is empty or total weight ≤ 0."
  (let* ((pool (or pool dl-satan-tick-pool))
          (total (apply #'+ (mapcar #'cdr pool))))
    (when (and pool (> total 0))
      (let ((n (random total))
             (acc 0)
             picked)
        (dolist (entry pool)
          (unless picked
            (setq acc (+ acc (cdr entry)))
            (when (< n acc) (setq picked (car entry)))))
        picked))))

(defun dl-satan-tick-register (short-name &rest overrides)
  "Register a tick mode named `tick-SHORT-NAME' using sensible defaults.
OVERRIDES is a plist that wins over the defaults: useful for raising
budgets, swapping the tool list, or pointing at a different prompt.
The prompt file defaults to `<prompts>/tick/SHORT-NAME.txt'."
  (let* ((full-name (concat "tick-" short-name))
          (prompt-file (or (plist-get overrides :prompt-file)
                         (expand-file-name
                           (concat "tick/" short-name ".txt")
                           dl-satan-prompts-dir)))
          (defaults
            (list :name full-name
              :prompt-file prompt-file
              :context-fn 'dl-satan-context-tick
              :tools '("org_read_context" "notify_send" "inbox_append"
                        "activity_read" "notes_recent"
                        "sway_border_set" "sway_border_reset"
                        "bough_read" "memory_mark" "memory_resonate"
                        "memory_show_trace"
                        "motive_read" "motive_replace"
                        "vcs_log")
              :capabilities '(notify inbox-write memory-write motive-write)
              :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
              :jail-profile 'specDev
              :profile 'deepseek-pro
              :budget-tokens 100000
              :output-handler 'dl-satan-output/tick
              :auto-apply 'owned
              :timeout-seconds 60
              :budget-tool-calls 10
              :recent-runs 5))
          (spec defaults))
    (cl-loop for (k v) on overrides by #'cddr
      do (setq spec (plist-put spec k v)))
    (dl-satan-mode-register spec)
    full-name))

;; Default registration: a single lightweight pulse tick.
(dl-satan-tick-register "pulse")

;; tick-agent: the heavier @satan-directive + patch-orchestration tick.
;; Registered here beside tick-pulse and `dl-satan-tick-pool' so every
;; tick mode lives in one file — it was previously stranded in
;; dl-satan-tools-atsatan.el and got overlooked when its tool list was
;; edited.  The tools it names (notes_at_satan_*, patch_job_*) are
;; defined in dl-satan-tools-atsatan.el / dl-satan-tools-patch.el, both
;; of which load before dl-satan.el's load-time `check-tool-references',
;; so naming them here is safe even though those files require us.
(dl-satan-tick-register
 "agent"
 :tools '("notes_at_satan_scan" "notes_at_satan_done"
          "notes_at_satan_intervention_done"
          "org_read_context"
          "inbox_append"
          "notify_send"
          "hippocampus_write"
          "memory_mark" "memory_resonate" "memory_show_trace"
          "bough_read"
          "agenda_read"
          "activity_read"
          "vcs_log"
          "patch_job_create" "patch_job_status")
 :capabilities '(write-notes inbox-write memory-write notify)
 :budget-tokens 100000
 :budget-tool-calls 15
 :timeout-seconds 120)

(defun my/satan-tick ()
  "Run one tick: pick a mode from `dl-satan-tick-pool', skip in quiet hours.
Returns the run-id, or nil if the tick was suppressed."
  (interactive)
  (cond
    ((dl-satan-tick-quiet-p)
      (when (called-interactively-p 'interactive)
        (message "SATAN tick: skipped (quiet hours)"))
      nil)
    (t
      (let ((name (dl-satan-tick-pick)))
        (cond
          ((null name)
            (when (called-interactively-p 'interactive)
              (message "SATAN tick: empty pool"))
            nil)
          (t
            (let ((run-id (dl-satan-broker-run name)))
              (when (called-interactively-p 'interactive)
                (message "SATAN tick %s started: %s" name run-id))
              run-id)))))))

(provide 'dl-satan-tick)
;;; dl-satan-tick.el ends here
