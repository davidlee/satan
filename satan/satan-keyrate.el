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
;;
;; The same file holds `keyrate_window' rows (IMP-059): the minute's keys
;; per focused window, same `ts'.  A second can hold keys in two windows,
;; so window seconds never sum to the minute's: presence reads minute rows
;; only, and `satan-keyrate-typing' reads window rows only.

;;; Code:

(require 'cl-lib)
(require 'seq)
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

(defcustom satan-keyrate-title-cap 5
  "Titles listed per app in `satan-keyrate-typing'; the rest are folded."
  :type 'integer :group 'satan)

(defconst satan-keyrate-minute-event "keyrate_minute"
  "The raw event holding a minute's totals.")

(defconst satan-keyrate-window-event "keyrate_window"
  "The raw event holding a minute's keys in one focused window.")

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

(defun satan-keyrate--scan-file (path event keep)
  "PATH's EVENT rows (INSTANT . ROW) whose INSTANT satisfies KEEP, in order."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (let ((rows nil))
      (dolist (line (split-string (buffer-string) "\n" t))
        (when-let* ((entry (satan-desktop-parse-raw-line line)))
          (when (and (equal (plist-get (cdr entry) :event) event)
                     (funcall keep (car entry)))
            (push entry rows))))
      (nreverse rows))))

(defun satan-keyrate--read-days (root days event keep)
  "(STATUS . MINUTES) from ROOT's DAYS files: the EVENT rows KEEP accepts.
STATUS is \"ok\" when any of the files exists, else \"missing\"."
  (let ((found nil) (minutes nil))
    (dolist (day days)
      (let ((path (satan-keyrate--day-file root day)))
        (when (file-readable-p path)
          (setq found t
                minutes (nconc minutes (satan-keyrate--scan-file path event keep))))))
    (cons (if found "ok" "missing") minutes)))

(defun satan-keyrate-read (root from to &optional event)
  "The keyrate minutes under ROOT overlapping [FROM, TO), Lisp times.
EVENT is the row kind, `satan-keyrate-minute-event' unless given.
Return (STATUS . MINUTES): STATUS is \"ok\" when a day file the span
needs exists, else \"missing\" (no producer output to read).  MINUTES
are (INSTANT . ROW), ROW the event plist, in time order.  An ok status
with no minutes means no input: quiet minutes are not written."
  (satan-keyrate--read-days
   root (satan-keyrate--days from to)
   (or event satan-keyrate-minute-event)
   (lambda (start) (satan-keyrate--overlaps-p start from to))))

(defun satan-keyrate-read-day (root day &optional event)
  "Every keyrate minute in ROOT's file for DAY, as `satan-keyrate-read'."
  (satan-keyrate--read-days root (list day)
                            (or event satan-keyrate-minute-event) #'always))

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

(defun satan-keyrate--share (start from to)
  "The share of the minute starting at START inside [FROM, TO), floats.
1.0 when FROM is nil: the caller counts whole rows."
  (if (null from)
      1.0
    (/ (max 0.0 (- (min to (+ start satan-keyrate--minute)) (max from start)))
       satan-keyrate--minute)))

(defun satan-keyrate-describe (minutes from to)
  "Key and pointer seconds of MINUTES within [FROM, TO), and the presence.
MINUTES are as `satan-keyrate-read' returns them; each counts in
proportion to its overlap.  Return (:key_seconds K :pointer_seconds P
:presence PRESENCE), K and P rounded to whole seconds."
  (let ((from (float-time from)) (to (float-time to))
        (key 0.0) (pointer 0.0))
    (pcase-dolist (`(,start . ,row) minutes)
      (let ((share (satan-keyrate--share (float-time start) from to)))
        (cl-incf key (* share (or (plist-get row :key_seconds) 0)))
        (cl-incf pointer (* share (or (plist-get row :pointer_seconds) 0)))))
    (list :key_seconds (round key)
          :pointer_seconds (round pointer)
          :presence (satan-keyrate-presence key pointer (- to from)))))

(defun satan-keyrate--wpm (keys key-seconds)
  "Words (5 keys) per minute of KEY-SECONDS, one decimal; nil without seconds."
  (when (> key-seconds 0)
    (/ (round (* 10 (/ keys 5.0) (/ 60.0 key-seconds))) 10.0)))

(defun satan-keyrate--tally (label key rows)
  "ROWS' prorated (KEYS . SECONDS) summed, as (LABEL KEY :keys K
:key_seconds S :wpm W), K and S rounded.  ROWS are (SHARE . ROW)."
  (let ((keys 0.0) (seconds 0.0))
    (pcase-dolist (`(,share . ,row) rows)
      (cl-incf keys (* share (or (plist-get row :keys) 0)))
      (cl-incf seconds (* share (or (plist-get row :key_seconds) 0))))
    (list label key :keys (round keys) :key_seconds (round seconds)
          :wpm (satan-keyrate--wpm keys seconds))))

(defun satan-keyrate--by-keys (tallies)
  "TALLIES sorted by `:keys', most first; ties keep their order."
  (sort (copy-sequence tallies)
        (lambda (a b) (> (plist-get a :keys) (plist-get b :keys)))))

(defun satan-keyrate--title (row)
  "ROW's window title; a null title is \"(untitled)\", as panopticon keys it."
  (or (plist-get (cdr row) :title) "(untitled)"))

(defun satan-keyrate--titles (rows)
  "ROWS' tallies per title, top `satan-keyrate-title-cap' by keys, the rest
folded into one \"(other)\" tally."
  (let* ((top (seq-take (satan-keyrate--by-keys
                         (mapcar (pcase-lambda (`(,title . ,group))
                                   (satan-keyrate--tally :title title group))
                                 (seq-group-by #'satan-keyrate--title rows)))
                        satan-keyrate-title-cap))
         (shown (mapcar (lambda (tally) (plist-get tally :title)) top))
         (rest (seq-remove (lambda (row) (member (satan-keyrate--title row) shown))
                           rows)))
    (if rest
        (append top (list (satan-keyrate--tally :title "(other)" rest)))
      top)))

(defun satan-keyrate-typing (windows titles &optional from to)
  "Per-app typing in WINDOWS, `keyrate_window' rows as `satan-keyrate-read'
returns them.  Each app is (:app_id A :keys K :key_seconds S :wpm W),
plus `:titles' (`satan-keyrate--titles') when TITLES is non-nil; apps by
keys, most first.  With FROM..TO, a row counts in proportion to its
overlap.  An app's seconds sum its windows', so they can exceed the
clock: a second can hold keys in two windows."
  (let* ((from (and from (float-time from)))
         (to (and to (float-time to)))
         (rows (mapcar (pcase-lambda (`(,start . ,row))
                         (cons (satan-keyrate--share (float-time start) from to) row))
                       windows)))
    (satan-keyrate--by-keys
     (mapcar (pcase-lambda (`(,app . ,group))
               (append (satan-keyrate--tally :app_id app group)
                       (and titles (list :titles (satan-keyrate--titles group)))))
             (seq-group-by (lambda (r) (plist-get (cdr r) :app_id)) rows)))))

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
