;;; satan-sensor-wpm.el --- Hunger probe — presence from keyrate -*- lexical-binding: t; -*-

;; Emits a sensor attribute signal on each change of the user's presence
;; over the last `satan-keyrate-window-minutes' (design-contract §6S):
;;
;;   typing  -> typing_active   (metric: key seconds)
;;   reading -> reading         (metric: pointer seconds)
;;   idle    -> typing_idle     (metric: key + pointer seconds)
;;   mixed   -> no signal
;;
;; Presence comes from panopticon's raw keyrate minutes through
;; `satan-keyrate' (IMP-055), read below the behaviour root (panopticon's,
;; not SATAN's: spelled out here, SL-015 D1).  No keyrate file for the
;; window means no producer output, and no signal.  The name keeps its
;; WPM history; the TSV it once read is gone.

(require 'cl-lib)
(require 'json)
(require 'satan-custom)
(require 'satan-keyrate)
(require 'satan-memory-canon)

(declare-function satan-attribute-build-sensor-payload "satan-attribute")
(declare-function satan-attribute-enqueue "satan-attribute")

(defcustom satan-sensor-wpm-behaviour-dir
  (expand-file-name "behaviour" (satan-state-home))
  "Panopticon's behaviour root, holding `raw/keyrate-YYYY-MM-DD.jsonl'."
  :type 'directory :group 'satan-attribute)

(defcustom satan-sensor-wpm-state-file
  (satan-state-path "sensor-wpm.json")
  "Path to the WPM probe state file.
Tracks last emitted state to avoid duplicate signals."
  :type 'string :group 'satan-attribute)

(defconst satan-sensor-wpm--signals
  '(("typing"  "typing_active" "key_seconds")
    ("reading" "reading"       "pointer_seconds")
    ("idle"    "typing_idle"   "input_seconds"))
  "Presence -> (REASON METRIC-UNIT); a presence not listed emits nothing.")

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
;; classification
;; -----------------------------------------------------------------

(defun satan-sensor-wpm--metric (unit description)
  "DESCRIPTION's seconds for metric UNIT."
  (let ((key (plist-get description :key_seconds))
        (pointer (plist-get description :pointer_seconds)))
    (pcase unit
      ("key_seconds" key)
      ("pointer_seconds" pointer)
      (_ (+ key pointer)))))

;; -----------------------------------------------------------------
;; probe
;; -----------------------------------------------------------------

(cl-defun satan-sensor-wpm-probe-read (&key run-id ts)
  "Pure read-snapshot for the presence probe (perceive-side).
Classifies the window ending at TS (or now), reads the previous
emitted state, and builds (but does NOT enqueue) the would-be attribute
payload on a state transition.  Zero mutation: no enqueue, no state write.

For WPM the \"high-water\" is the classified state itself; the snapshot
carries `:state' (the new state to record) and `:emitted-at'.

Returns (:emit t :payload PAYLOAD :state STATE :emitted-at TS) when the
state changed, else (:emit nil)."
  (condition-case err
      (when (and run-id (bound-and-true-p satan-attribute-updates-enabled))
        (let* ((emitted-at (or ts (format-time-string "%Y-%m-%dT%T%:z")))
               (description (satan-keyrate-recent
                             satan-sensor-wpm-behaviour-dir
                             (or (satan-memory-canon-parse-instant emitted-at)
                                 (current-time))))
               (state (plist-get description :presence))
               (signal (cdr (assoc state satan-sensor-wpm--signals)))
               (prev (plist-get (satan-sensor-wpm--read-state) :last_state))
               (prev-str (if (stringp prev) prev nil)))
          (when (and signal (not (equal state prev-str)))
            (require 'satan-attribute)
            (pcase-let ((`(,reason ,unit) signal))
              (list :emit t
                    :state state
                    :emitted-at emitted-at
                    :payload (satan-attribute-build-sensor-payload
                              :run-id run-id
                              :ts emitted-at
                              :reason reason
                              :sensor-type "wpm_activity"
                              :metric-value (satan-sensor-wpm--metric
                                             unit description)
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
  "Check presence and emit a signal on a state transition.
Preserved wrapper: read-snapshot then commit.  Returns non-nil if a
signal was emitted."
  (satan-sensor-wpm-probe-commit
   (satan-sensor-wpm-probe-read :run-id run-id :ts ts)))

(provide 'satan-sensor-wpm)
;;; satan-sensor-wpm.el ends here
