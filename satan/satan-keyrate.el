;;; satan-keyrate.el --- presence from panopticon's keyrate minutes -*- lexical-binding: t; -*-

;; Reads panopticon's raw keyrate log, `ROOT/raw/keyrate-YYYY-MM-DD.jsonl'
;; (schema owned by panopticon: `panopticon/docs/schema.md', "Keyrate
;; events"), and summarises an interval as key and pointer seconds plus a
;; presence: typing, reading, idle or mixed (IMP-055).  ROOT is the
;; behaviour root, passed in, as for `satan-desktop'.
;;
;; One row per wall-clock minute with any input; quiet minutes are not
;; written, so a missing minute is zero.  Rows are placed by instant,
;; never by string (their offset changes across DST, cf. ISS-035), and a
;; row counts toward an interval in proportion to its overlap with it.
;;
;; The reader and the summaries are separate so a caller describing many
;; intervals (`activity_read' annotating segments) reads the files once.

;;; Code:

(require 'cl-lib)
(require 'satan-custom)
(require 'satan-desktop)
(require 'satan-memory-canon)

(defcustom satan-keyrate-typing-share 0.5
  "Share of an interval with key presses at or above which it is typing."
  :type 'number :group 'satan)

(defcustom satan-keyrate-quiet-share 0.05
  "Share of an interval with key presses at or below which keys are quiet.
A quiet interval is reading or idle, by `satan-keyrate-reading-share'."
  :type 'number :group 'satan)

(defcustom satan-keyrate-reading-share 0.1
  "Share of a key-quiet interval with pointer input at or above which it is
reading rather than idle."
  :type 'number :group 'satan)

(defcustom satan-keyrate-window-minutes 10
  "Minutes of recent input that describe the user's presence now.
Read by the presence sensor and by `activity_read''s `current' scope."
  :type 'integer :group 'satan)

(defvar satan-keyrate--zone nil
  "Zone that day files and hours are chosen in; nil is Emacs's local zone.
A test seam, as `satan-desktop--zone'.")

(defconst satan-keyrate--minute 60
  "Seconds a keyrate row covers, from its `ts'.")

;; ── reading ─────────────────────────────────────────────────────────────────

(defun satan-keyrate--day-file (root day)
  "The raw keyrate log for DAY (\"YYYY-MM-DD\") under behaviour ROOT."
  (expand-file-name (format "raw/keyrate-%s.jsonl" day) root))

(defun satan-keyrate--days (from to)
  "The local days, oldest first, holding a row that can overlap FROM..TO."
  (let ((day (format-time-string
              "%F" (time-subtract from satan-keyrate--minute) satan-keyrate--zone))
        (last (format-time-string "%F" to satan-keyrate--zone))
        (days nil))
    (while (not (string< last day))
      (push day days)
      (setq day (satan-memory-canon-day-shift day 1)))
    (nreverse days)))

(defun satan-keyrate--overlaps-p (start from to)
  "Non-nil when the minute starting at START overlaps [FROM, TO)."
  (and (time-less-p start to)
       (time-less-p from (time-add start satan-keyrate--minute))))

(defun satan-keyrate--scan-file (path keep)
  "PATH's minute rows (INSTANT . ROW) whose INSTANT satisfies KEEP, in order."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (let ((rows nil))
      (dolist (line (split-string (buffer-string) "\n" t))
        (when-let* ((entry (satan-desktop-parse-raw-line line)))
          (when (and (equal (plist-get (cdr entry) :event) "keyrate_minute")
                     (funcall keep (car entry)))
            (push entry rows))))
      (nreverse rows))))

(defun satan-keyrate--read-days (root days keep)
  "(STATUS . MINUTES) from ROOT's DAYS files, keeping rows KEEP accepts.
STATUS is \"ok\" when any of the files exists, else \"missing\"."
  (let ((found nil) (minutes nil))
    (dolist (day days)
      (let ((path (satan-keyrate--day-file root day)))
        (when (file-readable-p path)
          (setq found t
                minutes (nconc minutes (satan-keyrate--scan-file path keep))))))
    (cons (if found "ok" "missing") minutes)))

(defun satan-keyrate-read (root from to)
  "The keyrate minutes under ROOT overlapping [FROM, TO), Lisp times.
Return (STATUS . MINUTES): STATUS is \"ok\" when a day file the span
needs exists, else \"missing\" (no producer output to read).  MINUTES
are (INSTANT . ROW), ROW the event plist, in time order.  An ok status
with no minutes means no input: quiet minutes are not written."
  (satan-keyrate--read-days
   root (satan-keyrate--days from to)
   (lambda (start) (satan-keyrate--overlaps-p start from to))))

(defun satan-keyrate-read-day (root day)
  "Every keyrate minute in ROOT's file for DAY, as `satan-keyrate-read'."
  (satan-keyrate--read-days root (list day) #'always))

;; ── summaries (pure) ────────────────────────────────────────────────────────

(defun satan-keyrate-presence (key-seconds pointer-seconds span)
  "Presence over SPAN seconds with KEY-SECONDS and POINTER-SECONDS of input.
\"typing\", \"reading\", \"idle\" or \"mixed\" by share of SPAN (see the
`satan-keyrate-*-share' options); nil when SPAN is not positive."
  (when (> span 0)
    (let ((keys (/ key-seconds (float span)))
          (pointer (/ pointer-seconds (float span))))
      (cond ((>= keys satan-keyrate-typing-share) "typing")
            ((> keys satan-keyrate-quiet-share) "mixed")
            ((>= pointer satan-keyrate-reading-share) "reading")
            (t "idle")))))

(defun satan-keyrate-describe (minutes from to)
  "Key and pointer seconds of MINUTES within [FROM, TO), and the presence.
MINUTES are as `satan-keyrate-read' returns them; each counts in
proportion to its overlap.  Return (:key_seconds K :pointer_seconds P
:presence PRESENCE), K and P rounded to whole seconds."
  (let ((from (float-time from)) (to (float-time to))
        (key 0.0) (pointer 0.0))
    (pcase-dolist (`(,start . ,row) minutes)
      (let* ((start (float-time start))
             (share (/ (max 0.0 (- (min to (+ start satan-keyrate--minute))
                                   (max from start)))
                       satan-keyrate--minute)))
        (cl-incf key (* share (or (plist-get row :key_seconds) 0)))
        (cl-incf pointer (* share (or (plist-get row :pointer_seconds) 0)))))
    (list :key_seconds (round key)
          :pointer_seconds (round pointer)
          :presence (satan-keyrate-presence key pointer (- to from)))))

(defun satan-keyrate-recent (root now)
  "Presence over the `satan-keyrate-window-minutes' ending at NOW, under ROOT.
`satan-keyrate-describe''s plist, or nil when no keyrate file covers
the window (no producer output: nothing to say, not idle)."
  (let* ((from (time-subtract now (* 60 satan-keyrate-window-minutes)))
         (read (satan-keyrate-read root from now)))
    (when (equal (car read) "ok")
      (satan-keyrate-describe (cdr read) from now))))

(defun satan-keyrate-per-hour (minutes)
  "MINUTES' key and pointer seconds per local hour, as two lists of 24.
Return (:per_hour_key_seconds KEYS :per_hour_pointer_seconds POINTER),
hour 0 first, matching the histogram's `per_hour_seconds'."
  (let ((key (make-vector 24 0)) (pointer (make-vector 24 0)))
    (pcase-dolist (`(,start . ,row) minutes)
      (let ((hour (string-to-number
                   (format-time-string "%H" start satan-keyrate--zone))))
        (cl-incf (aref key hour) (or (plist-get row :key_seconds) 0))
        (cl-incf (aref pointer hour) (or (plist-get row :pointer_seconds) 0))))
    (list :per_hour_key_seconds (append key nil)
          :per_hour_pointer_seconds (append pointer nil))))

(provide 'satan-keyrate)
;;; satan-keyrate.el ends here
