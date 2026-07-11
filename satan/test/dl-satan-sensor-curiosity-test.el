;;; dl-satan-sensor-curiosity-test.el --- ert tests for dl-satan-sensor-curiosity -*- lexical-binding: t; -*-

;; VT-probe-split (DR-010 §5): the curiosity probe's read/commit split.
;;   - read charges nothing (no enqueue, no watermark advance);
;;   - commit charges + advances the watermark to the snapshot's native
;;     high-water `end_ts' (the DR-010 §3 bugfix — NOT broker wall-clock);
;;   - out-of-order rows (an `end_ts' lagging another) land the watermark
;;     on the true max and the lagging row is not skipped;
;;   - a budget-denied read taken but never committed loses no signal.

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'dl-satan-attribute)           ; load before tests (defcustoms)
(require 'dl-satan-sensor-curiosity)

;; --- Helpers ---------------------------------------------------

(defmacro dl-satan-sensor-curiosity-test--with-fixture (state-var seg-var &rest body)
  "Bind STATE-VAR + SEG-VAR to fresh temp paths for curiosity state/segments.
SEG-VAR is the segments DIR.  Rebinds the two probe defcustoms and
`dl-satan-attribute-updates-enabled' so probes are live.  Cleaned up on exit."
  (declare (indent 2))
  `(let* ((,state-var (make-temp-file "satan-sensor-curiosity-state-"))
          (,seg-var (make-temp-file "satan-sensor-curiosity-seg-" t))
          (dl-satan-sensor-curiosity-state-file ,state-var)
          (dl-satan-sensor-curiosity-segments-dir ,seg-var)
          (dl-satan-attribute-updates-enabled t))
     (unwind-protect
         (progn ,@body)
       (ignore-errors (delete-file ,state-var))
       (ignore-errors (delete-directory ,seg-var t)))))

(defun dl-satan-sensor-curiosity-test--seed-state (path watermark)
  "Write a state file at PATH with :last_inspected WATERMARK."
  (with-temp-file path
    (insert (json-serialize (list :last_inspected watermark)))))

(defun dl-satan-sensor-curiosity-test--read-watermark (path)
  "Return the :last_inspected watermark stored at PATH, or nil."
  (when (file-readable-p path)
    (plist-get (with-temp-buffer
                 (insert-file-contents path)
                 (json-parse-buffer :object-type 'plist))
               :last_inspected)))

(defun dl-satan-sensor-curiosity-test--write-segments (seg-dir rows)
  "Write ROWS (each (APP . END-TS)) as today's focus JSONL under SEG-DIR.
Each row gets a `start_ts' equal to its `end_ts' — only `end_ts'
drives the curiosity count/watermark."
  (let ((file (expand-file-name
               (format "focus-%s.jsonl" (format-time-string "%Y-%m-%d"))
               seg-dir)))
    (with-temp-file file
      (dolist (row rows)
        (insert (json-serialize (list :app_id (car row)
                                      :start_ts (cdr row)
                                      :end_ts (cdr row)
                                      :duration_s 60)))
        (insert "\n")))))

;; --- read charges nothing --------------------------------------

(ert-deftest dl-satan-sensor-curiosity/read-snapshot-charges-nothing ()
  "VT-probe-split: `-probe-read' enqueues nothing and never advances the
watermark.  The forbidden writers are spied to fail if called."
  (dl-satan-sensor-curiosity-test--with-fixture state-path seg-dir
    (dl-satan-sensor-curiosity-test--seed-state state-path "2026-06-09T08:00:00+10:00")
    (dl-satan-sensor-curiosity-test--write-segments
     seg-dir '(("firefox" . "2026-06-09T09:00:00+10:00")))
    (cl-letf (((symbol-function 'dl-satan-attribute-enqueue)
               (lambda (&rest _) (ert-fail "read enqueued an attribute")))
              ((symbol-function 'dl-satan-sensor-curiosity-mark-inspected)
               (lambda (&rest _) (ert-fail "read advanced the watermark"))))
      (let ((snap (dl-satan-sensor-curiosity-probe-read
                   :run-id "rid" :ts "2026-06-09T09:30:00+10:00")))
        ;; A signal is warranted (one uninspected segment) …
        (should (plist-get snap :emit))
        ;; … but the watermark is untouched.
        (should (equal (dl-satan-sensor-curiosity-test--read-watermark state-path)
                       "2026-06-09T08:00:00+10:00"))))))

;; --- commit advances to native high-water (the bugfix) ---------

(ert-deftest dl-satan-sensor-curiosity/commit-advances-to-max-end-ts-not-ts ()
  "VT-probe-split bugfix: commit advances the watermark to the snapshot's
native high-water `end_ts' (max across rows), NOT the broker wall-clock
`ts'.  Out-of-order rows (a later-listed row with an earlier `end_ts')
must not skip the true max, and the lagging row is still counted."
  (dl-satan-sensor-curiosity-test--with-fixture state-path seg-dir
    (dl-satan-sensor-curiosity-test--seed-state state-path "2026-06-09T08:00:00+10:00")
    ;; Out-of-order: the newest end_ts (10:00) is listed BEFORE an older
    ;; one (09:00).  Both are after the seed watermark → count = 2.
    (dl-satan-sensor-curiosity-test--write-segments
     seg-dir '(("firefox" . "2026-06-09T10:00:00+10:00")
               ("alacritty" . "2026-06-09T09:00:00+10:00")))
    (cl-letf (((symbol-function 'dl-satan-attribute-enqueue)
               (lambda (&rest _) nil)))    ; no DB; swallow the enqueue
      (let* ((ts "2026-06-09T12:34:56+10:00") ; broker wall-clock — must NOT win
             (snap (dl-satan-sensor-curiosity-probe-read :run-id "rid" :ts ts)))
        (should (plist-get snap :emit))
        ;; The read snapshot's high-water is the max end_ts, regardless of order.
        (should (equal (plist-get snap :high-water) "2026-06-09T10:00:00+10:00"))
        (should (dl-satan-sensor-curiosity-probe-commit snap))
        (let ((wm (dl-satan-sensor-curiosity-test--read-watermark state-path)))
          ;; Watermark lands on the true max end_ts …
          (should (equal wm "2026-06-09T10:00:00+10:00"))
          ;; … NOT the broker wall-clock ts (the bug this pins).
          (should-not (equal wm ts)))))))

;; --- budget-denied: read without commit loses no signal --------

(ert-deftest dl-satan-sensor-curiosity/read-without-commit-keeps-backlog ()
  "VT-probe-split: a read taken but never committed (budget-denied path)
leaves the watermark unchanged, so a subsequent commit still sees the
backlog — no signal is lost."
  (dl-satan-sensor-curiosity-test--with-fixture state-path seg-dir
    (dl-satan-sensor-curiosity-test--seed-state state-path "2026-06-09T08:00:00+10:00")
    (dl-satan-sensor-curiosity-test--write-segments
     seg-dir '(("firefox" . "2026-06-09T09:00:00+10:00")))
    (cl-letf (((symbol-function 'dl-satan-attribute-enqueue)
               (lambda (&rest _) nil)))
      ;; First tick: read only (commit deferred / denied).
      (let ((snap1 (dl-satan-sensor-curiosity-probe-read
                    :run-id "rid" :ts "2026-06-09T09:30:00+10:00")))
        (should (plist-get snap1 :emit))
        ;; Watermark unchanged by the un-committed read.
        (should (equal (dl-satan-sensor-curiosity-test--read-watermark state-path)
                       "2026-06-09T08:00:00+10:00")))
      ;; Next tick: the backlog is still visible (signal not lost).
      (let ((snap2 (dl-satan-sensor-curiosity-probe-read
                    :run-id "rid" :ts "2026-06-09T09:45:00+10:00")))
        (should (plist-get snap2 :emit))
        (should (equal (plist-get snap2 :high-water) "2026-06-09T09:00:00+10:00"))
        ;; This time we commit — watermark finally advances.
        (should (dl-satan-sensor-curiosity-probe-commit snap2))
        (should (equal (dl-satan-sensor-curiosity-test--read-watermark state-path)
                       "2026-06-09T09:00:00+10:00"))))))

(provide 'dl-satan-sensor-curiosity-test)
;;; dl-satan-sensor-curiosity-test.el ends here
