;;; satan-goad-test.el --- goad readers (SL-016 PHASE-03) -*- lexical-binding: t; -*-

;; SATAN's read side of goad: the emit date of an ask, the queue, and an
;; ask's record in its emit date's day file.  Records are read from the
;; golden output of goad's `backend.py' (`goad-fixtures/'), never from
;; hand-built plists; malformed inputs use a scratch dir.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'satan-custom)
(require 'satan-goad)
(require 'satan-intervention)
(require 'satan-goad-fixture)
(require 'satan-custom-test)

;; ── paths ───────────────────────────────────────────────────────────────────

(ert-deftest satan-goad/queue-file-is-state-and-data-dir-is-corpus ()
  "The queue is SATAN's discardable projection; the day records are goad's,
corpus-tracked.  Each default follows its root and nothing else."
  (satan-custom-test--follows-root 'satan-goad-queue-file 'satan-state-root)
  (satan-custom-test--follows-root 'satan-goad-data-dir 'satan-corpus-root)
  (let ((satan-state-root "/tmp/st")
        (satan-corpus-root "/tmp/co"))
    (should (equal (satan-custom-test--default-of 'satan-goad-queue-file)
                   (satan-state-path "goad/queue.json")))
    (should (equal (satan-custom-test--default-of 'satan-goad-data-dir)
                   (satan-corpus-path "goad/data")))))

;; ── VT-24: the emit date is the local date of a parsed instant ──────────────

(ert-deftest satan-goad/local-date-of-a-gmt-instant-is-the-zone-date ()
  "VT-24 — `satan-goad-local-date': under a UTC database session and a
+10:00 zone, an ask emitted at 09:30 local has the local date, although
its GMT rendering starts with the previous day."
  (should (equal "2026-09-23"
                 (satan-goad-local-date "2026-09-22T23:30:00+00" 36000)))
  (should (equal "2026-09-22"
                 (satan-goad-local-date "2026-09-22T23:30:00+00" 0)))
  (should (equal "2026-09-23"
                 (satan-goad-local-date "2026-09-23T09:30:00+10:00" 36000)))
  (should (equal "2026-09-23"
                 (satan-goad-local-date "2026-09-22T23:30:00Z" 36000))))

(ert-deftest satan-goad/local-date-reads-microsecond-golden-stamps ()
  "VT-24 — the backend's stamps carry microseconds."
  (should (equal "2026-09-24"
                 (satan-goad-local-date "2026-09-24T00:05:26.407718+10:00"
                                        36000)))
  (should (equal "2026-09-23"
                 (satan-goad-local-date "2026-09-24T00:05:26.407718+10:00" 0))))

(ert-deftest satan-goad/local-date-refuses-what-it-cannot-place ()
  "VT-24 — a raw psql cell (space separator) is nil, not a wrong date.
`date-to-time' silently drops its time of day; so would a substring.
A naive stamp has no instant; garbage and non-strings have no date."
  (should-not (satan-goad-local-date "2026-09-22 23:30:00+00" 36000))
  (should-not (satan-goad-local-date "2026-09-22 23:30:00.123456+00" 36000))
  (should-not (satan-goad-local-date "2026-09-23T09:30:00" 36000))
  (should-not (satan-goad-local-date "2026-09-23" 36000))
  (should-not (satan-goad-local-date "" 36000))
  (should-not (satan-goad-local-date "garbage" 36000))
  (should-not (satan-goad-local-date nil 36000)))

(ert-deftest satan-goad/local-date-defaults-to-the-zone-seam ()
  "With no ZONE argument the date is taken in `satan-goad--zone'."
  (let ((satan-goad--zone 36000))
    (should (equal "2026-09-23" (satan-goad-local-date "2026-09-22T23:30:00+00"))))
  (let ((satan-goad--zone 0))
    (should (equal "2026-09-22" (satan-goad-local-date "2026-09-22T23:30:00+00")))))

(ert-deftest satan-goad/local-date-reads-the-emit-date-file-for-a-psql-ts ()
  "VT-24 read side — the intervention's `ts' as `satan-intervention-pending'
delivers it (psql's GMT cell, normalised by the row converter) finds the
answered ask in 2026-09-23.json, the day file of its local emit date."
  (satan-goad-fixture-with-goldens
    (let ((ts (satan-intervention--normalize-pg-timestamp
               "2026-09-22 23:30:00+00")))
      (should (equal "2026-09-23" (satan-goad-local-date ts)))
      (should (plist-get (satan-goad-read-record
                          (satan-goad-fixture-id 'answered) ts)
                         :value)))))

;; ── the queue ───────────────────────────────────────────────────────────────

(defconst satan-goad-test--queue-fields
  '(:intervention_id :question :subject :emitted_at :expires_at))

(ert-deftest satan-goad/read-queue-reads-the-goldens-in-file-order ()
  (satan-goad-fixture-with-goldens
    (let ((queue (satan-goad-read-queue)))
      (should (equal (mapcar #'cdr satan-goad-fixture-ids)
                     (mapcar (lambda (e) (plist-get e :intervention_id)) queue)))
      (dolist (entry queue)
        (should (equal satan-goad-test--queue-fields
                       (cl-loop for (k _) on entry by #'cddr collect k)))
        (dolist (k satan-goad-test--queue-fields)
          (should (stringp (plist-get entry k))))))))

(ert-deftest satan-goad/read-queue-without-a-usable-document-is-empty ()
  "An absent or malformed queue means no asks, never a signal."
  (satan-goad-fixture-with-tmp _dir
    (should-not (satan-goad-read-queue))
    (dolist (doc '("{\"asks\": [" "[]" "[{\"asks\": []}]" "\"asks\""
                   "{\"asks\": {}}" "{\"asks\": \"x\"}" "{\"asks\": 7}"
                   "{}" ""))
      (satan-goad-fixture-write satan-goad-queue-file doc)
      (should-not (satan-goad-read-queue)))))

(ert-deftest satan-goad/read-queue-drops-a-bad-entry-alone ()
  "A malformed entry is dropped on its own; its neighbours are kept."
  (satan-goad-fixture-with-tmp _dir
    (let ((good (satan-goad-fixture-ask :intervention_id "keep")))
      (dolist (bad (list (satan-goad-fixture-ask :question :absent)
                         (satan-goad-fixture-ask :subject 7)
                         (satan-goad-fixture-ask :intervention_id "")
                         (satan-goad-fixture-ask :emitted_at "2026-09-23 09:30:00+10")
                         (satan-goad-fixture-ask :emitted_at "2026-09-23T09:30:00")
                         (satan-goad-fixture-ask :expires_at "soon")))
        (satan-goad-fixture-write-queue (list good bad good))
        (should (equal '("keep" "keep")
                       (mapcar (lambda (e) (plist-get e :intervention_id))
                               (satan-goad-read-queue)))))
      (satan-goad-fixture-write satan-goad-queue-file
                                "{\"asks\": [7, \"x\", null, []]}")
      (should-not (satan-goad-read-queue)))))

(ert-deftest satan-goad/read-queue-keeps-only-the-five-fields ()
  (satan-goad-fixture-with-tmp _dir
    (satan-goad-fixture-write-queue
     (list (satan-goad-fixture-ask :extra "ignored")))
    (should (equal satan-goad-test--queue-fields
                   (cl-loop for (k _) on (car (satan-goad-read-queue))
                            by #'cddr collect k)))))

;; ── records ─────────────────────────────────────────────────────────────────

(defun satan-goad-test--golden-record (outcome)
  "The record the goldens hold for OUTCOME's ask, read by its queue entry."
  (let ((entry (satan-goad-fixture-find outcome (satan-goad-read-queue))))
    (satan-goad-read-record (plist-get entry :intervention_id)
                            (plist-get entry :emitted_at))))

(ert-deftest satan-goad/read-record-matches-the-scenario-table ()
  "Each golden outcome reads as the README's scenario table says."
  (satan-goad-fixture-with-goldens
    (let ((answered (satan-goad-test--golden-record 'answered))
          (later (satan-goad-test--golden-record 'later))
          (seen (satan-goad-test--golden-record 'enough-seen))
          (unseen (satan-goad-test--golden-record 'enough-unseen))
          (untouched (satan-goad-test--golden-record 'untouched)))
      (should (plist-get answered :value))
      (should (stringp (plist-get answered :at)))
      (should (stringp (plist-get answered :presented_at)))
      (should (equal "later" (plist-get later :deferred_by)))
      (should (equal "enough" (plist-get seen :deferred_by)))
      (should (plist-get seen :presented_at))
      (should (equal "enough" (plist-get unseen :deferred_by)))
      (should-not (plist-member unseen :presented_at))
      (should (equal '(:presented_at) (cl-loop for (k _) on untouched
                                               by #'cddr collect k)))
      (should-not (satan-goad-test--golden-record 'expired)))))

(ert-deftest satan-goad/read-record-without-a-usable-day-file-is-nil ()
  (satan-goad-fixture-with-tmp _dir
    (let ((day (expand-file-name "2026-09-23.json" satan-goad-data-dir))
          (at "2026-09-23T09:30:00+10:00"))
      (should-not (satan-goad-read-record "x" at))
      (dolist (doc '("{\"asks\": {\"x\": " "[]" "{\"asks\": []}"
                     "{\"asks\": {\"x\": 7}}" "{\"items\": {}}"))
        (satan-goad-fixture-write day doc)
        (should-not (satan-goad-read-record "x" at)))
      (satan-goad-fixture-write day "{\"asks\": {\"x\": {\"value\": false}}}")
      (should (eq :false (plist-get (satan-goad-read-record "x" at) :value)))
      (should-not (satan-goad-read-record "x" "2026-09-23 09:30:00+10")))))

;; ── the slice ───────────────────────────────────────────────────────────────

(ert-deftest satan-goad/slice-pairs-every-entry-with-its-record ()
  "One element per queue entry, in queue order, carrying the entry's five
fields and its record; an ask with no record carries none."
  (satan-goad-fixture-with-goldens
    (let ((slice (satan-goad-slice))
          (queue (satan-goad-read-queue)))
      (should (= (length satan-goad-fixture-ids) (length slice)))
      (cl-mapc (lambda (el entry)
                 (dolist (k satan-goad-test--queue-fields)
                   (should (equal (plist-get entry k) (plist-get el k))))
                 (should (equal (satan-goad-read-record
                                 (plist-get entry :intervention_id)
                                 (plist-get entry :emitted_at))
                                (plist-get el :record))))
               slice queue)
      (should-not (plist-member (car slice) :record))
      (should (plist-get (nth 1 slice) :record)))))

(ert-deftest satan-goad/slice-of-no-queue-is-empty ()
  (satan-goad-fixture-with-tmp _dir
    (should-not (satan-goad-slice))))

(ert-deftest satan-goad/after-midnight-reads-emit-date ()
  "VT-25 — the ask emitted 23:15 on the 23rd and answered 00:05 on the 24th
reads as answered from 2026-09-23.json, though no 2026-09-24.json exists."
  (satan-goad-fixture-with-goldens
    (should-not (file-exists-p
                 (expand-file-name "2026-09-24.json" satan-goad-data-dir)))
    (let* ((slice (satan-goad-slice))
           (record-of (lambda (outcome)
                        (plist-get (satan-goad-fixture-find outcome slice)
                                   :record))))
      (should (plist-get (funcall record-of 'midnight) :value))
      (should (string-prefix-p "2026-09-24T00:05"
                               (plist-get (funcall record-of 'midnight) :at)))
      (should (plist-get (funcall record-of 'answered) :value)))))

(provide 'satan-goad-test)
;;; satan-goad-test.el ends here
