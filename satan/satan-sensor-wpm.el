;;; satan-sensor-wpm.el --- Hunger probe — WPM activity state -*- lexical-binding: t; -*-

;; Emits `typing_active' or `typing_idle' sensor attribute signals based
;; on WPM log data (design-contract §6S).
;;
;; Reads the per-minute TSV log at ~/notes/satan/log/wpm/YYYY-MM-DD.tsv.
;; Format: <iso8601>\t<keys>\t<peak_5s_wpm>\t<active_seconds>
;;
;; Classifies last 10 minutes: active (>50% active_seconds), idle (<5%),
;; or ambiguous (no signal).  Emits only on state transitions to avoid
;; repeated signals on consecutive ticks.

(require 'cl-lib)
(require 'json)
(require 'satan-custom)

(declare-function satan-attribute-build-sensor-payload "satan-attribute")
(declare-function satan-attribute-enqueue "satan-attribute")

(defcustom satan-sensor-wpm-log-dir
  (expand-file-name "satan/log/wpm" satan-notes-root)
  "Directory containing per-day WPM TSV logs."
  :type 'string :group 'satan-attribute)

(defcustom satan-sensor-wpm-state-file
  (expand-file-name "satan/sensor-wpm.json"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Path to the WPM probe state file.
Tracks last emitted state to avoid duplicate signals."
  :type 'string :group 'satan-attribute)

(defcustom satan-sensor-wpm-window-minutes 10
  "Number of recent minutes to consider for activity classification."
  :type 'integer :group 'satan-attribute)

(defcustom satan-sensor-wpm-active-threshold 300
  "Sum of active_seconds in window above which state is `active'.
Default 300 = 50% of a 10-minute window."
  :type 'integer :group 'satan-attribute)

(defcustom satan-sensor-wpm-idle-threshold 30
  "Sum of active_seconds in window below which state is `idle'.
Default 30 = 5% of a 10-minute window."
  :type 'integer :group 'satan-attribute)

;; -----------------------------------------------------------------
;; state file
;; -----------------------------------------------------------------

(defun satan-sensor-wpm--read-state ()
  "Read state file, return plist or nil."
  (when (file-readable-p satan-sensor-wpm-state-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents satan-sensor-wpm-state-file)
          (json-parse-buffer :object-type 'plist))
      (error nil))))

(defun satan-sensor-wpm--write-state (plist)
  "Write PLIST as JSON to state file."
  (let ((dir (file-name-directory satan-sensor-wpm-state-file)))
    (unless (file-directory-p dir) (make-directory dir t))
    (with-temp-file satan-sensor-wpm-state-file
      (insert (json-serialize plist)))))

;; -----------------------------------------------------------------
;; TSV parsing
;; -----------------------------------------------------------------

(defun satan-sensor-wpm--today-file ()
  "Return today's WPM TSV log path."
  (expand-file-name
   (format "%s.tsv" (format-time-string "%Y-%m-%d"))
   satan-sensor-wpm-log-dir))

(defun satan-sensor-wpm--parse-recent-rows (window-minutes)
  "Parse TSV rows from the last WINDOW-MINUTES minutes.
Returns list of plists (:ts :keys :peak_wpm :active_seconds)."
  (let ((file (satan-sensor-wpm--today-file))
        (cutoff (format-time-string
                 "%Y-%m-%dT%T"
                 (time-subtract nil (* window-minutes 60))))
        (rows nil))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-max))
        (while (and (not (bobp))
                    (zerop (forward-line -1)))
          (let* ((line (buffer-substring-no-properties
                        (line-beginning-position) (line-end-position)))
                 (fields (split-string line "\t")))
            (when (>= (length fields) 4)
              (let ((ts (nth 0 fields)))
                (if (string< ts cutoff)
                    (goto-char (point-min))
                  (push (list :ts ts
                              :keys (string-to-number (nth 1 fields))
                              :peak_wpm (string-to-number (nth 2 fields))
                              :active_seconds (string-to-number (nth 3 fields)))
                        rows))))))))
    rows))

;; -----------------------------------------------------------------
;; classification
;; -----------------------------------------------------------------

(defun satan-sensor-wpm--classify ()
  "Classify recent WPM activity.
Returns \"active\", \"idle\", or nil (ambiguous)."
  (let* ((rows (satan-sensor-wpm--parse-recent-rows
                satan-sensor-wpm-window-minutes))
         (total-active (cl-reduce #'+ rows
                                  :key (lambda (r) (plist-get r :active_seconds))
                                  :initial-value 0)))
    (cond
     ((null rows) nil)
     ((>= total-active satan-sensor-wpm-active-threshold) "active")
     ((<= total-active satan-sensor-wpm-idle-threshold) "idle")
     (t nil))))

;; -----------------------------------------------------------------
;; probe
;; -----------------------------------------------------------------

(cl-defun satan-sensor-wpm-probe-read (&key run-id ts)
  "Pure read-snapshot for the WPM activity probe (perceive-side).
Classifies the recent window (pure `--classify'), reads the previous
emitted state, and builds (but does NOT enqueue) the would-be attribute
payload on a state transition.  Zero mutation: no enqueue, no state write.

For WPM the \"high-water\" is the classified state itself; the snapshot
carries `:state' (the new state to record) and `:emitted-at'.

Returns (:emit t :payload PAYLOAD :state STATE :emitted-at TS) when the
state changed, else (:emit nil)."
  (condition-case err
      (when (and run-id (bound-and-true-p satan-attribute-updates-enabled))
        (let* ((state (satan-sensor-wpm--classify))
               (prev (plist-get (satan-sensor-wpm--read-state) :last_state))
               (prev-str (if (stringp prev) prev nil)))
          (when (and state (not (equal state prev-str)))
            (require 'satan-attribute)
            (let* ((reason (if (equal state "active") "typing_active" "typing_idle"))
                   (metric (if (equal state "active")
                               satan-sensor-wpm-active-threshold
                             satan-sensor-wpm-idle-threshold))
                   (unit (if (equal state "active") "active_seconds" "idle_seconds"))
                   (emitted-at (or ts (format-time-string "%Y-%m-%dT%T%:z"))))
              (list :emit t
                    :state state
                    :emitted-at emitted-at
                    :payload (satan-attribute-build-sensor-payload
                              :run-id run-id
                              :ts emitted-at
                              :reason reason
                              :sensor-type "wpm_activity"
                              :metric-value metric
                              :metric-unit unit))))))
    (error
     (message "[satan-sensor-wpm] probe-read soft-failed: %S" err)
     nil)))

(defun satan-sensor-wpm-probe-commit (snapshot)
  "Commit SNAPSHOT from `satan-sensor-wpm-probe-read' (consume-side).
When (:emit SNAPSHOT) is non-nil, enqueue the payload and advance the
state file to the snapshot's classified `:state'/`:emitted-at'.
Returns non-nil iff a signal was emitted."
  (condition-case err
      (when (plist-get snapshot :emit)
        (require 'satan-attribute)
        (satan-attribute-enqueue (plist-get snapshot :payload))
        (satan-sensor-wpm--write-state
         (list :last_state (plist-get snapshot :state)
               :last_emitted_at (plist-get snapshot :emitted-at)))
        t)
    (error
     (message "[satan-sensor-wpm] probe-commit soft-failed: %S" err)
     nil)))

(cl-defun satan-sensor-wpm-probe (&key run-id ts)
  "Check WPM activity state and emit signal on state transition.
Preserved wrapper: read-snapshot then commit.  Returns non-nil if a
signal was emitted."
  (satan-sensor-wpm-probe-commit
   (satan-sensor-wpm-probe-read :run-id run-id :ts ts)))

(provide 'satan-sensor-wpm)
;;; satan-sensor-wpm.el ends here
