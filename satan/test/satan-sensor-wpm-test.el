;;; satan-sensor-wpm-test.el --- the presence sensor (IMP-055) -*- lexical-binding: t; -*-

;; `satan-sensor-wpm-probe-read' / `-probe-commit' against raw keyrate
;; files in a scratch behaviour root and a scratch state file.  Every
;; probe is read at a fixed `:ts', so the window never depends on now.

;;; Code:

(require 'ert)
(require 'satan-sensor-wpm)
(require 'satan-attribute)
(require 'satan-keyrate-fixture)

;; ── helpers ─────────────────────────────────────────────────────────────────

(defconst satan-sensor-wpm-test--now "2026-09-26T09:10:00+10:00"
  "The instant every probe reads at: the window is 09:00..09:10.")

(defmacro satan-sensor-wpm-test--with (&rest body)
  "Run BODY against a fresh behaviour root and state file, updates enabled."
  (declare (indent 0))
  `(satan-keyrate-fixture-with-root root
     (let* ((satan-sensor-wpm-behaviour-dir root)
            (satan-sensor-wpm-state-file (expand-file-name "state.json" root))
            (satan-attribute-updates-enabled t))
       ,@body)))

(defun satan-sensor-wpm-test--minutes (key pointer)
  "Write today's file: ten minutes 09:00..09:09, each KEY and POINTER seconds."
  (satan-keyrate-fixture-write
   satan-sensor-wpm-behaviour-dir "2026-09-26"
   (cl-loop for m from 0 below 10
            collect (satan-keyrate-fixture-minute
                     (format "2026-09-26T09:%02d:00.000+10:00" m)
                     key pointer))))

(defun satan-sensor-wpm-test--read ()
  (satan-sensor-wpm-probe-read :run-id "run-1" :ts satan-sensor-wpm-test--now))

(defun satan-sensor-wpm-test--emitted (snapshot)
  "SNAPSHOT's (REASON METRIC-VALUE METRIC-UNIT), or nil when it emits nothing."
  (when (plist-get snapshot :emit)
    (let ((p (plist-get snapshot :payload)))
      (list (plist-get p :reason) (plist-get p :metric_value)
            (plist-get p :metric_unit)))))

;; ── classification → reason ─────────────────────────────────────────────────

(ert-deftest satan-sensor-wpm/typing-emits-typing-active-with-key-seconds ()
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 40 0)
    (should (equal (satan-sensor-wpm-test--emitted (satan-sensor-wpm-test--read))
                   '("typing_active" 400 "key_seconds")))))

(ert-deftest satan-sensor-wpm/reading-emits-reading-with-pointer-seconds ()
  "Few keys and pointer activity: the new `reading' reason."
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 1 12)
    (should (equal (satan-sensor-wpm-test--emitted (satan-sensor-wpm-test--read))
                   '("reading" 120 "pointer_seconds")))))

(ert-deftest satan-sensor-wpm/idle-emits-typing-idle-with-input-seconds ()
  "Few keys, little pointer: `typing_idle', metric the total input seconds."
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 1 1)
    (should (equal (satan-sensor-wpm-test--emitted (satan-sensor-wpm-test--read))
                   '("typing_idle" 20 "input_seconds")))))

(ert-deftest satan-sensor-wpm/an-empty-window-with-a-file-is-idle ()
  "Quiet minutes are not written: rows earlier today but none in the window
means no input, so idle."
  (satan-sensor-wpm-test--with
    (satan-keyrate-fixture-write
     root "2026-09-26"
     (list (satan-keyrate-fixture-minute "2026-09-26T07:00:00.000+10:00" 30 0)))
    (should (equal (satan-sensor-wpm-test--emitted (satan-sensor-wpm-test--read))
                   '("typing_idle" 0 "input_seconds")))))

(ert-deftest satan-sensor-wpm/no-keyrate-file-emits-nothing ()
  "No producer output for the span: no signal, not idle."
  (satan-sensor-wpm-test--with
    (should-not (plist-get (satan-sensor-wpm-test--read) :emit))))

(ert-deftest satan-sensor-wpm/mixed-emits-nothing ()
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 10 0)
    (should-not (plist-get (satan-sensor-wpm-test--read) :emit))))

(ert-deftest satan-sensor-wpm/window-reaches-into-yesterday ()
  "Just after midnight the window also reads yesterday's file."
  (satan-sensor-wpm-test--with
    (satan-keyrate-fixture-write
     root "2026-09-25"
     (cl-loop for m from 55 below 60
              collect (satan-keyrate-fixture-minute
                       (format "2026-09-25T23:%02d:00.000+10:00" m) 60 0)))
    (should (equal (satan-sensor-wpm-test--emitted
                    (satan-sensor-wpm-probe-read
                     :run-id "run-1" :ts "2026-09-26T00:05:00+10:00"))
                   '("typing_active" 300 "key_seconds")))))

;; ── transitions ─────────────────────────────────────────────────────────────

(ert-deftest satan-sensor-wpm/emits-only-on-a-state-change ()
  "Commit records the state; the same state again emits nothing."
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 1 12)
    (cl-letf (((symbol-function 'satan-attribute-enqueue) #'ignore))
      (should (satan-sensor-wpm-probe-commit (satan-sensor-wpm-test--read))))
    (should-not (plist-get (satan-sensor-wpm-test--read) :emit))
    (satan-sensor-wpm-test--minutes 40 0)
    (should (plist-get (satan-sensor-wpm-test--read) :emit))))

(ert-deftest satan-sensor-wpm/read-is-pure ()
  "The read never writes the state file."
  (satan-sensor-wpm-test--with
    (satan-sensor-wpm-test--minutes 40 0)
    (satan-sensor-wpm-test--read)
    (should-not (file-exists-p satan-sensor-wpm-state-file))))

;;; satan-sensor-wpm-test.el ends here
