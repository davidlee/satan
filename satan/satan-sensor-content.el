;;; satan-sensor-content.el --- Content backlog probe — panopticon capture backlog -*- lexical-binding: t; -*-

;; Emits a `panopticon_content_backlog' sensor attribute signal when
;; uninspected panopticon page captures exist (DE-005 O2 / DR-005 §4.2).
;;
;; "Uninspected" means: captures whose `captured_at' is lexically newer
;; than the last time this probe advanced its watermark.
;;
;; THE DEC-5 DIVERGENCE FROM CURIOSITY: The watermark is the max
;; `captured_at' string seen verbatim (UTC-millis-Z), NOT a formatted
;; `now()'.  The broker passes its own timestamp in a different format
;; (local offset), so lexical comparison between the two formats is
;; meaningless.  Storing the high-water `captured_at' keeps every
;; comparison within one format.
;;
;; See DR-005 DEC-5, mem.pattern.satan.jsonl-arity-trap.

(require 'cl-lib)
(require 'json)
(require 'satan-tools-content)          ; --read-articles-jsonl (lenient)

(declare-function satan-attribute-build-sensor-payload "satan-attribute")
(declare-function satan-attribute-enqueue "satan-attribute")

;; --- Defcustoms ------------------------------------------------

(defcustom satan-sensor-content-state-file
  (expand-file-name "satan/sensor-content.json"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Path to the content-backlog probe state file.
Stores the last-inspected `captured_at' watermark string."
  :type 'string :group 'satan-attribute)

(defcustom satan-sensor-content-enabled t
  "When nil, the content-backlog probe does nothing."
  :type 'boolean :group 'satan-attribute)

;; --- State file ------------------------------------------------

(defun satan-sensor-content--read-state ()
  "Read state file, return plist (defaulting to empty watermark if absent)."
  (if (file-readable-p satan-sensor-content-state-file)
      (condition-case nil
          (let ((raw (with-temp-buffer
                       (insert-file-contents satan-sensor-content-state-file)
                       (json-parse-buffer :object-type 'plist))))
            raw)
        (error '(:last_inspected "")))
    '(:last_inspected "")))

(defun satan-sensor-content--write-state (plist)
  "Write PLIST as JSON to state file."
  (let ((dir (file-name-directory satan-sensor-content-state-file)))
    (unless (file-directory-p dir) (make-directory dir t))
    (with-temp-file satan-sensor-content-state-file
      (insert (json-serialize plist)))))

(defun satan-sensor-content--last-inspected ()
  "Return the last-inspected `captured_at' watermark string."
  (plist-get (satan-sensor-content--read-state) :last_inspected))

(defun satan-sensor-content-mark-inspected (high-water)
  "Advance the watermark to HIGH-WATER (a `captured_at' string verbatim).
HIGH-WATER must be the max `captured_at' seen, NOT a formatted now().
This is the DEC-5 divergence from curiosity's `mark-inspected'."
  (let ((state (satan-sensor-content--read-state)))
    (satan-sensor-content--write-state
     (plist-put state :last_inspected high-water))))

;; --- Capture counting ------------------------------------------

(defun satan-sensor-content--count-uninspected (since-ts)
  "Count articles.jsonl rows with captured_at after SINCE-TS.
SINCE-TS is a `captured_at' watermark string (UTC-millis-Z).
Returns (COUNT . HIGH-WATER) where HIGH-WATER is the max captured_at seen.
Returns (0 . SINCE-TS) when no new captures or store is empty.
Uses the lenient JSONL reader (skips malformed lines per O-1)."
  (let ((articles (satan-tools-content--read-articles-jsonl :skip-malformed t))
        (count 0)
        (high-water since-ts))
    (dolist (a articles)
      (let ((captured-at (plist-get a :captured_at)))
        (when (and captured-at (stringp captured-at))
          ;; Track the max captured_at for the watermark (DEC-5)
          (when (string< high-water captured-at)
            (setq high-water captured-at))
          ;; Count uninspected
          (when (string< since-ts captured-at)
            (cl-incf count)))))
    (cons count high-water)))

;; --- Probe (read/commit split — DR-010 §3) ---------------------

(cl-defun satan-sensor-content-probe-read (&key run-id ts)
  "Pure read-snapshot for the content-backlog probe (perceive-side).
Reads the watermark, counts uninspected captures, computes the native
high-water captured_at, and builds (but does NOT enqueue) the would-be
attribute payload.  Zero mutation: no enqueue, no watermark advance, no
state write.

TS is the broker's `time_now' — used ONLY in the attribute payload, NOT
for the watermark (DEC-5: broker ts format ≠ captured_at format).

Returns a snapshot plist: (:emit t :payload PAYLOAD :high-water HW) when
a signal is warranted, else (:emit nil)."
  (condition-case err
      (when (and run-id
                 satan-sensor-content-enabled
                 (bound-and-true-p satan-attribute-updates-enabled))
        (let* ((last (satan-sensor-content--last-inspected))
               (since (or last ""))       ; "" sorts before all timestamps
               (count-high (satan-sensor-content--count-uninspected since))
               (count (car count-high))
               (high-water (cdr count-high)))
          (when (> count 0)
            (require 'satan-attribute)
            (list :emit t
                  :high-water high-water
                  :payload (satan-attribute-build-sensor-payload
                            :run-id run-id
                            :ts (or ts (format-time-string "%Y-%m-%dT%T%:z"))
                            :reason "content_backlog"
                            :sensor-type "panopticon_content_backlog"
                            :metric-value count
                            :metric-unit "uninspected_captures")))))
    (error
     (message "[satan-sensor-content] probe-read soft-failed: %S" err)
     nil)))

(defun satan-sensor-content-probe-commit (snapshot)
  "Commit SNAPSHOT from `satan-sensor-content-probe-read' (consume-side).
When (:emit SNAPSHOT) is non-nil, enqueue the payload and advance the
watermark to the snapshot's high-water (DEC-5: max captured_at, NOT ts).
Returns non-nil iff a signal was emitted."
  (condition-case err
      (when (plist-get snapshot :emit)
        (require 'satan-attribute)
        (satan-attribute-enqueue (plist-get snapshot :payload))
        (satan-sensor-content-mark-inspected (plist-get snapshot :high-water))
        t)
    (error
     (message "[satan-sensor-content] probe-commit soft-failed: %S" err)
     nil)))

(cl-defun satan-sensor-content-probe (&key run-id ts)
  "Check for uninspected panopticon content captures and emit signal if any.
Preserved wrapper: read-snapshot then commit.  Returns non-nil if a
signal was emitted."
  (satan-sensor-content-probe-commit
   (satan-sensor-content-probe-read :run-id run-id :ts ts)))

(provide 'satan-sensor-content)
;;; satan-sensor-content.el ends here
