;;; satan-ingest-cursor-test.el --- ert tests for satan-ingest-cursor -*- lexical-binding: t; -*-

;; VT-cursor-advance (DE-010 Phase 2 / B2)
;;
;; Covers:
;;   1. consume (advance) writes max(current,head) per source
;;   2. idempotent — double advance with unchanged head is a no-op
;;   3. out-of-order/older row does NOT regress the cursor
;;   4. mixed-offset focus: Z-instant newer than stale local-offset,
;;      advance picks by parsed instant not string<
;;   5. missing cursor (nil read) ⇒ from-head initialisation
;;   6. backlog-depth: known cursor+tail ⇒ expected count per source
;;   7. backlog-depth: cursor==head ⇒ 0 per source
;;   8. backlog-depth: missing cursor ⇒ full count (from-head)

(require 'ert)
(require 'cl-lib)
(require 'satan-tools-activity)
(require 'satan-tools-content)
(require 'satan-tools-content-test nil t) ; fixture macros (write-article-jsonl etc.)
(require 'satan-sensor-content)
(require 'satan-ingest-cursor)

;; --- Fixture helpers -------------------------------------------

(defmacro satan-ingest-cursor-test--with-env (&rest body)
  "Run BODY with activity dir, content dir, and cursor state file all in temps.
Binds `satan-tools-activity-dir', `satan-tools-content-dir', and
`satan-ingest-cursor-state-file' to isolated temp trees.
Also binds `satan-tools-descriptions-dir' so tool schema assembly works."
  (declare (indent 0))
  `(let* ((act-dir   (make-temp-file "satan-cursor-act-" t))
          (desc-dir  (make-temp-file "satan-cursor-desc-" t))
          (cursor-f  (make-temp-file "satan-cursor-state-"))
          (satan-tools-activity-dir act-dir)
          (satan-tools-content-dir
           ;; reuse tools-content-test fixture scaffolding —
           ;; we need a temp dir with an articles.jsonl
           (make-temp-file "satan-cursor-content-" t))
          (satan-tools-descriptions-dir desc-dir)
          (satan-ingest-cursor-state-file cursor-f))
     (make-directory (expand-file-name "segments" act-dir) t)
     ;; Provide a minimal tool description so schema assembly doesn't crash
     (with-temp-file (expand-file-name "content_read.md" desc-dir)
       (insert "Read panopticon page captures."))
     ;; Remove the auto-created cursor file so read returns nil by default
     (delete-file cursor-f)
     (unwind-protect (progn ,@body)
       (ignore-errors (delete-directory act-dir t))
       (ignore-errors (delete-directory satan-tools-content-dir t))
       (ignore-errors (delete-directory desc-dir t))
       (ignore-errors (delete-file cursor-f)))))

(defun satan-ingest-cursor-test--today ()
  (format-time-string "%Y-%m-%d"))

(defun satan-ingest-cursor-test--write-segment (dir kind rows)
  "Write ROWS (list of plists) as today's KIND segments JSONL under DIR."
  (let ((path (expand-file-name
               (format "segments/%s-%s.jsonl"
                       kind (satan-ingest-cursor-test--today))
               dir)))
    (with-temp-file path
      (dolist (r rows)
        (insert (json-serialize (satan-jsonl-prepare r)
                                :null-object :null :false-object :false))
        (insert "\n")))))

(defun satan-ingest-cursor-test--write-articles (content-dir rows)
  "Write ROWS (list of plists) as articles.jsonl under CONTENT-DIR."
  (let ((path (expand-file-name "articles.jsonl" content-dir)))
    (with-temp-file path
      (dolist (r rows)
        (insert (json-serialize (satan-jsonl-prepare r)
                                :null-object :null :false-object :false))
        (insert "\n")))))

(defun satan-ingest-cursor-test--seed-cursor (cursor-f plist)
  "Write PLIST as JSON to CURSOR-F (the state file)."
  (with-temp-file cursor-f
    (insert (json-serialize plist :null-object :null :false-object :false))))

(defun satan-ingest-cursor-test--seg (end-ts)
  "Return a minimal focus/browser segment plist with :end_ts END-TS."
  (list :start_ts "2026-06-10T09:00:00+10:00"
        :end_ts end-ts
        :duration_s 60
        :app_id "emacs"
        :workspace "1"))

(defun satan-ingest-cursor-test--article (captured-at)
  "Return a minimal articles.jsonl row plist with :captured_at CAPTURED-AT."
  (list :content_hash (md5 captured-at)
        :url (concat "https://example.com/" captured-at)
        :domain "example.com"
        :title "Test"
        :captured_at captured-at
        :extractor "readability"))

;; --- VT-cursor-advance tests -----------------------------------

(ert-deftest satan-ingest-cursor/advance-writes-head-per-source ()
  "Advance writes each source's head TS to the cursor state file."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir)
          (cfile satan-ingest-cursor-state-file))
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:30:00+10:00")
             (satan-ingest-cursor-test--seg "2026-06-10T09:45:00+10:00")))
      (satan-ingest-cursor-test--write-browser-and-content
       today content
       "2026-06-10T09:20:00+10:00"
       "2026-06-10T05:00:00.000Z")
      (satan-ingest-cursor-advance)
      (let ((state (satan-ingest-cursor-read)))
        (should (equal "2026-06-10T09:45:00+10:00" (plist-get state :focus)))
        (should (equal "2026-06-10T09:20:00+10:00" (plist-get state :browser)))
        (should (equal "2026-06-10T05:00:00.000Z"  (plist-get state :content)))))))

;; helper shared by multiple tests
(defun satan-ingest-cursor-test--write-browser-and-content
    (act-dir content-dir browser-ts content-ts)
  "Seed today's browser segment and articles.jsonl with single rows."
  (satan-ingest-cursor-test--write-segment
   act-dir "browser"
   (list (satan-ingest-cursor-test--seg browser-ts)))
  (satan-ingest-cursor-test--write-articles
   content-dir
   (list (satan-ingest-cursor-test--article content-ts))))

(ert-deftest satan-ingest-cursor/advance-idempotent ()
  "Double advance with unchanged data leaves cursor unchanged."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir))
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T10:00:00+10:00")))
      (satan-ingest-cursor-test--write-browser-and-content
       today content
       "2026-06-10T09:00:00+10:00"
       "2026-06-10T05:00:00.000Z")
      (satan-ingest-cursor-advance)
      (let ((state1 (satan-ingest-cursor-read)))
        (satan-ingest-cursor-advance)
        (let ((state2 (satan-ingest-cursor-read)))
          (should (equal (plist-get state1 :focus)   (plist-get state2 :focus)))
          (should (equal (plist-get state1 :browser) (plist-get state2 :browser)))
          (should (equal (plist-get state1 :content) (plist-get state2 :content))))))))

(ert-deftest satan-ingest-cursor/advance-does-not-regress-on-older-row ()
  "A stale row arriving behind the cursor does not regress it."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir)
          (cfile satan-ingest-cursor-state-file))
      ;; Seed cursor already at a later time
      (satan-ingest-cursor-test--seed-cursor
       cfile (list :focus   "2026-06-10T10:00:00+10:00"
                   :browser "2026-06-10T09:30:00+10:00"
                   :content "2026-06-10T06:00:00.000Z"))
      ;; Data files contain only rows OLDER than the cursor
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:00:00+10:00")))
      (satan-ingest-cursor-test--write-browser-and-content
       today content
       "2026-06-10T08:00:00+10:00"
       "2026-06-10T04:00:00.000Z")
      (satan-ingest-cursor-advance)
      (let ((state (satan-ingest-cursor-read)))
        ;; cursor must NOT regress
        (should (equal "2026-06-10T10:00:00+10:00" (plist-get state :focus)))
        (should (equal "2026-06-10T09:30:00+10:00" (plist-get state :browser)))
        (should (equal "2026-06-10T06:00:00.000Z"  (plist-get state :content)))))))

(ert-deftest satan-ingest-cursor/advance-mixed-offset-focus-uses-parsed-instant ()
  "Focus advance uses parsed-instant compare: a Z-form instant ahead of a stale
local-offset row is selected, not discarded by string< (which would rank Z lower)."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir))
      ;; Focus day-file: stale local-offset row (string-greater but time-older)
      ;; followed by a Z-instant (string-lower but time-newer).
      ;; String-max would wrongly pick "2026-06-10T08:00:00+10:00".
      ;; Parsed-instant max must pick "2026-06-09T23:30:00Z" (== 09:30 AEST).
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T08:00:00+10:00") ; stale local
             (satan-ingest-cursor-test--seg "2026-06-09T23:30:00Z")))   ; newer Z-form
      (satan-ingest-cursor-test--write-browser-and-content
       today content
       "2026-06-10T09:00:00+10:00"
       "2026-06-10T05:00:00.000Z")
      (satan-ingest-cursor-advance)
      (let* ((state (satan-ingest-cursor-read))
             (focus-cursor (plist-get state :focus))
             ;; Parse both candidates
             (local-t (date-to-time "2026-06-10T08:00:00+10:00"))
             (z-t     (date-to-time "2026-06-09T23:30:00Z"))
             (cursor-t (and focus-cursor (date-to-time focus-cursor))))
        ;; Z-instant is newer; cursor must be the Z-form row, not the stale local one
        (should focus-cursor)
        ;; The Z instant is 23:30 UTC = 09:30 AEST, which is 30 min ahead of 08:00 local
        (should (time-less-p local-t z-t))
        ;; Cursor must not be behind z-t
        (should (not (time-less-p cursor-t z-t)))))))

(ert-deftest satan-ingest-cursor/advance-missing-cursor-initialises-to-head ()
  "When no cursor file exists, advance initialises each source to its head."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir))
      (should-not (satan-ingest-cursor-read)) ; cursor absent initially
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:00:00+10:00")))
      (satan-ingest-cursor-test--write-browser-and-content
       today content
       "2026-06-10T08:30:00+10:00"
       "2026-06-10T04:00:00.000Z")
      (satan-ingest-cursor-advance)
      (let ((state (satan-ingest-cursor-read)))
        (should (equal "2026-06-10T09:00:00+10:00" (plist-get state :focus)))
        (should (equal "2026-06-10T08:30:00+10:00" (plist-get state :browser)))
        (should (equal "2026-06-10T04:00:00.000Z"  (plist-get state :content)))))))

;; --- VT-backlog-depth tests ------------------------------------

(ert-deftest satan-ingest-cursor/backlog-depth-known-cursor ()
  "backlog-depth with a known cursor returns counts of newer records per source."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir)
          (cfile satan-ingest-cursor-state-file))
      ;; Seed cursor at a mid-point
      (satan-ingest-cursor-test--seed-cursor
       cfile (list :focus   "2026-06-10T09:00:00+10:00"
                   :browser "2026-06-10T08:00:00+10:00"
                   :content "2026-06-10T03:00:00.000Z"))
      ;; 3 focus rows: 1 at cursor, 2 after
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:00:00+10:00") ; == cursor
             (satan-ingest-cursor-test--seg "2026-06-10T09:30:00+10:00") ; after
             (satan-ingest-cursor-test--seg "2026-06-10T10:00:00+10:00"))) ; after
      ;; 2 browser rows: 1 before cursor, 1 after
      (satan-ingest-cursor-test--write-segment
       today "browser"
       (list (satan-ingest-cursor-test--seg "2026-06-10T07:30:00+10:00") ; before
             (satan-ingest-cursor-test--seg "2026-06-10T08:30:00+10:00"))) ; after
      ;; 3 articles: 1 before cursor, 2 after
      (satan-ingest-cursor-test--write-articles
       content
       (list (satan-ingest-cursor-test--article "2026-06-10T02:00:00.000Z") ; before
             (satan-ingest-cursor-test--article "2026-06-10T04:00:00.000Z") ; after
             (satan-ingest-cursor-test--article "2026-06-10T05:00:00.000Z"))) ; after
      (let ((depth (satan-ingest-cursor-backlog-depth)))
        (should (= 2 (plist-get depth :focus)))
        (should (= 1 (plist-get depth :browser)))
        (should (= 2 (plist-get depth :content)))
        (should (= 5 (plist-get depth :total)))))))

(ert-deftest satan-ingest-cursor/backlog-depth-cursor-at-head-is-zero ()
  "backlog-depth returns 0 per source when cursor equals head."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir)
          (cfile satan-ingest-cursor-state-file))
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:00:00+10:00")))
      (satan-ingest-cursor-test--write-segment
       today "browser"
       (list (satan-ingest-cursor-test--seg "2026-06-10T08:00:00+10:00")))
      (satan-ingest-cursor-test--write-articles
       content
       (list (satan-ingest-cursor-test--article "2026-06-10T03:00:00.000Z")))
      ;; Cursor is at head for all sources
      (satan-ingest-cursor-test--seed-cursor
       cfile (list :focus   "2026-06-10T09:00:00+10:00"
                   :browser "2026-06-10T08:00:00+10:00"
                   :content "2026-06-10T03:00:00.000Z"))
      (let ((depth (satan-ingest-cursor-backlog-depth)))
        (should (= 0 (plist-get depth :focus)))
        (should (= 0 (plist-get depth :browser)))
        (should (= 0 (plist-get depth :content)))
        (should (= 0 (plist-get depth :total)))))))

(ert-deftest satan-ingest-cursor/backlog-depth-missing-cursor-full-count ()
  "backlog-depth with no cursor state returns full count per source (from-head)."
  (satan-ingest-cursor-test--with-env
    (let ((today satan-tools-activity-dir)
          (content satan-tools-content-dir))
      (should-not (satan-ingest-cursor-read)) ; confirm absent
      (satan-ingest-cursor-test--write-segment
       today "focus"
       (list (satan-ingest-cursor-test--seg "2026-06-10T09:00:00+10:00")
             (satan-ingest-cursor-test--seg "2026-06-10T09:30:00+10:00")))
      (satan-ingest-cursor-test--write-segment
       today "browser"
       (list (satan-ingest-cursor-test--seg "2026-06-10T08:00:00+10:00")))
      (satan-ingest-cursor-test--write-articles
       content
       (list (satan-ingest-cursor-test--article "2026-06-10T03:00:00.000Z")
             (satan-ingest-cursor-test--article "2026-06-10T04:00:00.000Z")
             (satan-ingest-cursor-test--article "2026-06-10T05:00:00.000Z")))
      (let ((depth (satan-ingest-cursor-backlog-depth)))
        (should (= 2 (plist-get depth :focus)))
        (should (= 1 (plist-get depth :browser)))
        (should (= 3 (plist-get depth :content)))
        (should (= 6 (plist-get depth :total)))))))

(provide 'satan-ingest-cursor-test)
;;; satan-ingest-cursor-test.el ends here
