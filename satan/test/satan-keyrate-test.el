;;; satan-keyrate-test.el --- the raw keyrate reader (IMP-055) -*- lexical-binding: t; -*-

;; `satan-keyrate-read' and the pure summaries over it, against raw keyrate
;; day files written into a scratch behaviour root.  Every test that reads
;; files runs under `satan-keyrate-fixture-with-root' (+10:00).

;;; Code:

(require 'ert)
(require 'satan-keyrate)
(require 'satan-keyrate-fixture)

;; ── helpers ─────────────────────────────────────────────────────────────────

(defconst satan-keyrate-test--day "2026-09-26")

(defun satan-keyrate-test--t (hhmmss &optional day)
  "The instant HHMMSS (\"09:00:00\") on DAY (default the test day), +10:00."
  (satan-memory-canon-parse-instant
   (format "%sT%s+10:00" (or day satan-keyrate-test--day) hhmmss)))

(defun satan-keyrate-test--min (hhmm key pointer &optional day)
  "A minute row at HHMM on DAY with KEY and POINTER seconds."
  (satan-keyrate-fixture-minute
   (format "%sT%s:00.000+10:00" (or day satan-keyrate-test--day) hhmm)
   key pointer))

(defun satan-keyrate-test--starts (minutes)
  "The `ts' of each of MINUTES, in order."
  (mapcar (lambda (m) (plist-get (cdr m) :ts)) minutes))

(defun satan-keyrate-test--describe (rows from to)
  "Describe ROWS (minute plists) over FROM..TO (HH:MM:SS strings)."
  (satan-keyrate-describe
   (mapcar (lambda (r)
             (cons (satan-memory-canon-parse-instant (plist-get r :ts)) r))
           rows)
   (satan-keyrate-test--t from) (satan-keyrate-test--t to)))

;; ── read ────────────────────────────────────────────────────────────────────

(ert-deftest satan-keyrate/read-keeps-minutes-overlapping-the-interval ()
  "A minute is kept when [start, start+60s) overlaps [FROM, TO)."
  (satan-keyrate-fixture-with-root root
    (satan-keyrate-fixture-write
     root satan-keyrate-test--day
     (list (satan-keyrate-test--min "08:58" 10 0)
           (satan-keyrate-test--min "08:59" 10 0)
           (satan-keyrate-test--min "09:05" 10 0)
           (satan-keyrate-test--min "09:10" 10 0)))
    (let ((res (satan-keyrate-read root (satan-keyrate-test--t "08:59:30")
                                   (satan-keyrate-test--t "09:10:00"))))
      (should (equal (car res) "ok"))
      (should (equal (satan-keyrate-test--starts (cdr res))
                     '("2026-09-26T08:59:00.000+10:00"
                       "2026-09-26T09:05:00.000+10:00"))))))

(ert-deftest satan-keyrate/read-skips-other-events-and-garbage ()
  "Torn lines, garbage and non-`keyrate_minute' events are skipped."
  (satan-keyrate-fixture-with-root root
    (satan-keyrate-fixture-write
     root satan-keyrate-test--day
     (list "{\"v\":1,\"ts\":"
           "not json"
           '(:v 1 :ts "2026-09-26T09:01:00.000+10:00" :source "keyrate"
                :event "something_else")
           (satan-keyrate-test--min "09:02" 5 5)))
    (should (equal (satan-keyrate-test--starts
                    (cdr (satan-keyrate-read
                          root (satan-keyrate-test--t "09:00:00")
                          (satan-keyrate-test--t "09:10:00"))))
                   '("2026-09-26T09:02:00.000+10:00")))))

(ert-deftest satan-keyrate/read-missing-when-no-day-file ()
  "No day file for the span: status missing, no minutes."
  (satan-keyrate-fixture-with-root root
    (should (equal (satan-keyrate-read root (satan-keyrate-test--t "09:00:00")
                                       (satan-keyrate-test--t "09:10:00"))
                   '("missing")))))

(ert-deftest satan-keyrate/read-ok-and-empty-when-the-file-has-no-rows-in-span ()
  "A day file with nothing in the span is ok with no minutes: quiet, not missing."
  (satan-keyrate-fixture-with-root root
    (satan-keyrate-fixture-write root satan-keyrate-test--day
                                 (list (satan-keyrate-test--min "07:00" 1 1)))
    (should (equal (satan-keyrate-read root (satan-keyrate-test--t "09:00:00")
                                       (satan-keyrate-test--t "09:10:00"))
                   '("ok")))))

(ert-deftest satan-keyrate/read-crosses-midnight ()
  "A span crossing local midnight reads both day files, in time order."
  (satan-keyrate-fixture-with-root root
    (satan-keyrate-fixture-write
     root "2026-09-25" (list (satan-keyrate-test--min "23:57" 30 0 "2026-09-25")))
    (satan-keyrate-fixture-write
     root "2026-09-26" (list (satan-keyrate-test--min "00:02" 30 0 "2026-09-26")))
    (should (equal (satan-keyrate-test--starts
                    (cdr (satan-keyrate-read
                          root (satan-keyrate-test--t "23:55:00" "2026-09-25")
                          (satan-keyrate-test--t "00:05:00" "2026-09-26"))))
                   '("2026-09-25T23:57:00.000+10:00"
                     "2026-09-26T00:02:00.000+10:00")))))

(ert-deftest satan-keyrate/read-compares-instants-not-strings ()
  "A row stamped in another offset is placed by its instant (DST, ISS-035).
09:30+11:00 is 08:30+10:00: outside a 09:00..09:10 +10:00 window, though
it sorts inside it as a string."
  (satan-keyrate-fixture-with-root root
    (satan-keyrate-fixture-write
     root satan-keyrate-test--day
     (list (satan-keyrate-fixture-minute "2026-09-26T09:05:00.000+11:00" 9 9)
           (satan-keyrate-test--min "09:05" 5 5)))
    (should (equal (satan-keyrate-test--starts
                    (cdr (satan-keyrate-read
                          root (satan-keyrate-test--t "09:00:00")
                          (satan-keyrate-test--t "09:10:00"))))
                   '("2026-09-26T09:05:00.000+10:00")))))

;; ── describe ────────────────────────────────────────────────────────────────

(ert-deftest satan-keyrate/describe-prorates-partial-minutes ()
  "A minute half inside the interval contributes half its seconds."
  (should (equal (satan-keyrate-test--describe
                  (list (satan-keyrate-test--min "09:00" 40 20)
                        (satan-keyrate-test--min "09:01" 10 30))
                  "09:00:30" "09:02:00")
                 '(:key_seconds 30 :pointer_seconds 40 :presence "mixed"))))

(ert-deftest satan-keyrate/describe-classifies-by-share-of-the-interval ()
  "typing ≥ 50% key; reading ≤ 5% key and ≥ 10% pointer; idle ≤ 5% key and
< 10% pointer; anything between is mixed.  Over 10 minutes (600 s)."
  (cl-flet ((presence (key pointer)
              (plist-get (satan-keyrate-test--describe
                          (list (satan-keyrate-test--min "09:00" key pointer))
                          "09:00:00" "09:10:00")
                         :presence)))
    ;; One minute holds at most 60 s, so a 10-minute window is reached
    ;; through `satan-keyrate-presence' directly for the high shares.
    (should (equal (satan-keyrate-presence 300 0 600) "typing"))
    (should (equal (satan-keyrate-presence 299 0 600) "mixed"))
    (should (equal (presence 30 60) "reading"))
    (should (equal (presence 30 59) "idle"))
    (should (equal (presence 31 60) "mixed"))
    (should (equal (presence 0 0) "idle"))))

(ert-deftest satan-keyrate/describe-no-minutes-is-idle ()
  "Quiet minutes are not written, so no rows means no input: idle."
  (should (equal (satan-keyrate-test--describe nil "09:00:00" "09:10:00")
                 '(:key_seconds 0 :pointer_seconds 0 :presence "idle"))))

(ert-deftest satan-keyrate/presence-of-an-empty-interval-is-nil ()
  "A zero-length interval has no share to classify."
  (should (null (satan-keyrate-presence 0 0 0))))

;; ── per hour ────────────────────────────────────────────────────────────────

(ert-deftest satan-keyrate/per-hour-buckets-by-local-hour ()
  "Seconds are summed into the 24 local hours of the fixture zone."
  (let* ((rows (list (satan-keyrate-test--min "09:00" 10 1)
                     (satan-keyrate-test--min "09:59" 5 2)
                     (satan-keyrate-test--min "23:00" 7 3)))
         (minutes (mapcar (lambda (r)
                            (cons (satan-memory-canon-parse-instant
                                   (plist-get r :ts))
                                  r))
                          rows))
         (satan-keyrate--zone satan-desktop-fixture-zone)
         (hours (satan-keyrate-per-hour minutes))
         (keys (plist-get hours :per_hour_key_seconds))
         (pointer (plist-get hours :per_hour_pointer_seconds)))
    (should (= (length keys) 24))
    (should (= (nth 9 keys) 15))
    (should (= (nth 23 keys) 7))
    (should (= (nth 9 pointer) 3))
    (should (= (apply #'+ keys) 22))))

;;; satan-keyrate-test.el ends here
