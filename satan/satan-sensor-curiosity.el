;;; satan-sensor-curiosity.el --- Curiosity probe — panopticon segment backlog -*- lexical-binding: t; -*-

;; Emits a `segment_backlog' sensor attribute signal when uninspected
;; panopticon focus segments exist (design-contract §6S).
;;
;; "Uninspected" means: segments whose `end_ts' is newer than the last
;; time this probe ran.  Curiosity represents the gap between observable
;; and observed — the organism has unprocessed external signal.

(require 'cl-lib)
(require 'json)

(declare-function satan-attribute-build-sensor-payload "satan-attribute")
(declare-function satan-attribute-enqueue "satan-attribute")

(defcustom satan-sensor-curiosity-state-file
  (expand-file-name "satan/sensor-curiosity.json"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Path to the curiosity probe state file.
Stores the last-inspected timestamp."
  :type 'string :group 'satan-attribute)

(defcustom satan-sensor-curiosity-segments-dir
  (expand-file-name "behaviour/segments"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Directory containing panopticon focus segment JSONL files."
  :type 'string :group 'satan-attribute)

;; -----------------------------------------------------------------
;; state file
;; -----------------------------------------------------------------

(defun satan-sensor-curiosity--read-state ()
  "Read state file, return plist or nil."
  (when (file-readable-p satan-sensor-curiosity-state-file)
    (condition-case nil
        (let ((raw (with-temp-buffer
                     (insert-file-contents satan-sensor-curiosity-state-file)
                     (json-parse-buffer :object-type 'plist))))
          raw)
      (error nil))))

(defun satan-sensor-curiosity--write-state (plist)
  "Write PLIST as JSON to state file."
  (let ((dir (file-name-directory satan-sensor-curiosity-state-file)))
    (unless (file-directory-p dir) (make-directory dir t))
    (with-temp-file satan-sensor-curiosity-state-file
      (insert (json-serialize plist)))))

(defun satan-sensor-curiosity--last-inspected ()
  "Return the last-inspected ISO timestamp string, or nil."
  (plist-get (satan-sensor-curiosity--read-state) :last_inspected))

(defun satan-sensor-curiosity-mark-inspected (&optional ts)
  "Update the last-inspected timestamp to TS (default: now).
TS should be the max `end_ts' high-water seen (DR-010 §3, mirroring
content's DEC-5), NOT the broker wall-clock — advancing to wall-clock
silently skipped out-of-order rows whose `end_ts' lagged the tick time."
  (let ((state (or (satan-sensor-curiosity--read-state) '()))
        (timestamp (or ts (format-time-string "%Y-%m-%dT%T%:z"))))
    (satan-sensor-curiosity--write-state
     (plist-put state :last_inspected timestamp))))

;; -----------------------------------------------------------------
;; segment counting
;; -----------------------------------------------------------------

(defun satan-sensor-curiosity--today-file ()
  "Return today's focus segment JSONL path."
  (expand-file-name
   (format "focus-%s.jsonl" (format-time-string "%Y-%m-%d"))
   satan-sensor-curiosity-segments-dir))

(defun satan-sensor-curiosity--count-uninspected (since-ts)
  "Count focus segments in today's file with end_ts after SINCE-TS.
SINCE-TS is an ISO timestamp string.  Returns (COUNT . HIGH-WATER)
where HIGH-WATER is the max `end_ts' seen (DR-010 §3, mirroring
content's DEC-5 proven shape).  Returns (0 . SINCE-TS) when no rows.
HIGH-WATER, not the broker wall-clock, is what the watermark advances
to — out-of-order rows whose `end_ts' lags the tick are no longer
silently skipped."
  (let ((file (satan-sensor-curiosity--today-file))
        (count 0)
        (high-water since-ts))
    (when (file-readable-p file)
      (with-temp-buffer
        (insert-file-contents file)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (line-beginning-position) (line-end-position))))
            (unless (string-empty-p line)
              (condition-case nil
                  (let* ((obj (json-parse-string line :object-type 'plist))
                         (end-ts (plist-get obj :end_ts)))
                    (when (and end-ts (stringp end-ts))
                      (when (string< high-water end-ts)
                        (setq high-water end-ts))
                      (when (string< since-ts end-ts)
                        (cl-incf count))))
                (error nil))))
          (forward-line 1))))
    (cons count high-water)))

;; -----------------------------------------------------------------
;; probe
;; -----------------------------------------------------------------

(cl-defun satan-sensor-curiosity-probe-read (&key run-id ts)
  "Pure read-snapshot for the curiosity probe (perceive-side).
Reads the watermark, counts uninspected segments, computes the native
high-water `end_ts', and builds (but does NOT enqueue) the would-be
attribute payload.  Zero mutation: no enqueue, no watermark advance.

TS is used ONLY in the attribute payload, NOT for the watermark
(DR-010 §3 curiosity bugfix, mirroring content's DEC-5).

Returns (:emit t :payload PAYLOAD :high-water HW) when a signal is
warranted, else (:emit nil)."
  (condition-case err
      (when (and run-id (bound-and-true-p satan-attribute-updates-enabled))
        (let* ((last (satan-sensor-curiosity--last-inspected))
               (since (or last "1970-01-01T00:00:00+00:00"))
               (count-high (satan-sensor-curiosity--count-uninspected since))
               (count (car count-high))
               (high-water (cdr count-high)))
          (when (> count 0)
            (require 'satan-attribute)
            (list :emit t
                  :high-water high-water
                  :payload (satan-attribute-build-sensor-payload
                            :run-id run-id
                            :ts (or ts (format-time-string "%Y-%m-%dT%T%:z"))
                            :reason "segment_backlog"
                            :sensor-type "panopticon_backlog"
                            :metric-value count
                            :metric-unit "unprocessed_segments")))))
    (error
     (message "[satan-sensor-curiosity] probe-read soft-failed: %S" err)
     nil)))

(defun satan-sensor-curiosity-probe-commit (snapshot)
  "Commit SNAPSHOT from `satan-sensor-curiosity-probe-read' (consume-side).
When (:emit SNAPSHOT) is non-nil, enqueue the payload and advance the
watermark to the snapshot's high-water `end_ts' (DR-010 §3 bugfix: NOT
the broker wall-clock).  Returns non-nil iff a signal was emitted."
  (condition-case err
      (when (plist-get snapshot :emit)
        (require 'satan-attribute)
        (satan-attribute-enqueue (plist-get snapshot :payload))
        (satan-sensor-curiosity-mark-inspected (plist-get snapshot :high-water))
        t)
    (error
     (message "[satan-sensor-curiosity] probe-commit soft-failed: %S" err)
     nil)))

(cl-defun satan-sensor-curiosity-probe (&key run-id ts)
  "Check for uninspected panopticon segments and emit signal if any.
Preserved wrapper: read-snapshot then commit.  Returns non-nil if a
signal was emitted."
  (satan-sensor-curiosity-probe-commit
   (satan-sensor-curiosity-probe-read :run-id run-id :ts ts)))

(provide 'satan-sensor-curiosity)
;;; satan-sensor-curiosity.el ends here
