;;; satan-goad-test.el --- goad readers (SL-016) -*- lexical-binding: t; -*-

;; SATAN's read side of goad: the emit date of an ask, the queue (with
;; its answer forms), an ask's record in its emit date's day file, and
;; the truncation of long values in the `:goad' slice.  Records are read
;; from the golden output of goad's `backend.py' (`goad-fixtures/'),
;; never from hand-built plists; malformed inputs use a scratch dir, and
;; a long value is one golden value replaced in a copy of the goldens.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'satan-custom)
(require 'satan-goad)
(require 'satan-intervention)
(require 'satan-jsonl)
(require 'satan-percept)
(require 'satan-goad-fixture)
(require 'satan-custom-test)
;; DB-backed T2 tests reuse the intervention suite's `--with-db' /
;; `--with-ctx' / `--ask' fixtures rather than cloning DB scaffolding
;; (mem.fact.satan.test-db-isolation); `noerror' so a pure-only run
;; (no test DB) still loads this file, guarded by `skip-unless fboundp'
;; at each such test.
(require 'satan-intervention-test nil 'noerror)

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
  "The five fields of every golden entry, plus `:form' exactly when the
golden entry has one."
  (satan-goad-fixture-with-goldens
    (let ((queue (satan-goad-read-queue)))
      (should (equal (mapcar #'cdr satan-goad-fixture-ids)
                     (satan-goad-fixture-iids queue)))
      (cl-loop for (outcome . _) in satan-goad-fixture-ids
               for entry in queue
               do (should (equal (append satan-goad-test--queue-fields
                                         (and (plist-member
                                               (satan-goad-fixture-golden-entry
                                                outcome)
                                               :form)
                                              '(:form)))
                                 (satan-goad-fixture-keys entry)))
               (dolist (k satan-goad-test--queue-fields)
                 (should (stringp (plist-get entry k))))))))

(ert-deftest satan-goad/queue-entry-keeps-form ()
  "VT-54 — the golden `form' entry keeps its form verbatim, after the five
fields; no other golden entry carries a `:form' key."
  (satan-goad-fixture-with-goldens
    (let ((queue (satan-goad-read-queue)))
      (let ((entry (satan-goad-fixture-find 'form queue)))
        (should (plist-get entry :form))
        (should (equal (plist-get (satan-goad-fixture-golden-entry 'form) :form)
                       (plist-get entry :form)))
        (should (equal (append satan-goad-test--queue-fields '(:form))
                       (satan-goad-fixture-keys entry))))
      (dolist (entry queue)
        (unless (equal (satan-goad-fixture-id 'form)
                       (plist-get entry :intervention_id))
          (should-not (plist-member entry :form)))))))

(defun satan-goad-test--ask-json-with-form (form &rest overrides)
  "A queue entry as JSON text, with FORM (raw JSON text) as its `form'.
Raw text, since `null', `[]' and `{}' do not survive `json-serialize' of
a plist.  OVERRIDES as for `satan-goad-fixture-ask'."
  (concat (string-remove-suffix
           "}" (json-serialize (apply #'satan-goad-fixture-ask overrides)))
          ", \"form\": " form "}"))

(ert-deftest satan-goad/read-queue-drops-a-malformed-form ()
  "A `form' key that is present but not a non-empty list of options, each
with a string `id' and `label', drops the whole entry, as goad's
`parse_ask' does (`null' included).  A well-formed form is kept."
  (satan-goad-fixture-with-tmp _dir
    (let ((good (json-serialize (satan-goad-fixture-ask
                                 :intervention_id "keep")))
          (bad (lambda (form)
                 (satan-goad-test--ask-json-with-form
                  form :intervention_id "drop"))))
      (dolist (form '("null" "[]" "{}" "{\"id\": \"a\", \"label\": \"A\"}"
                      "\"x\"" "[7]" "[{}]" "[null]" "[false, true]"
                      "[{\"id\": \"a\"}]" "[{\"label\": \"A\"}]"
                      "[{\"id\": 7, \"label\": \"A\"}]"
                      "[{\"id\": \"a\", \"label\": \"A\"}, {\"id\": \"b\"}]"))
        (satan-goad-fixture-write
         satan-goad-queue-file
         (format "{\"asks\": [%s, %s, %s]}" good (funcall bad form) good))
        (should (equal '("keep" "keep")
                       (satan-goad-fixture-iids (satan-goad-read-queue)))))
      (satan-goad-fixture-write
       satan-goad-queue-file
       (format "{\"asks\": [%s]}"
               (satan-goad-test--ask-json-with-form
                "[{\"id\": \"a\", \"label\": \"A\", \"fields\": []}]")))
      (should (equal '((:id "a" :label "A" :fields nil))
                     (plist-get (car (satan-goad-read-queue)) :form))))))

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
                       (satan-goad-fixture-iids (satan-goad-read-queue)))))
      (satan-goad-fixture-write satan-goad-queue-file
                                "{\"asks\": [7, \"x\", null, []]}")
      (should-not (satan-goad-read-queue)))))

(ert-deftest satan-goad/read-queue-keeps-only-the-five-fields ()
  (satan-goad-fixture-with-tmp _dir
    (satan-goad-fixture-write-queue
     (list (satan-goad-fixture-ask :extra "ignored")))
    (should (equal satan-goad-test--queue-fields
                   (satan-goad-fixture-keys (car (satan-goad-read-queue)))))))

;; ── records ─────────────────────────────────────────────────────────────────

(defun satan-goad-test--read-record (outcome)
  "OUTCOME's record as `satan-goad-read-record' reads it, by its queue entry."
  (let ((entry (satan-goad-fixture-find outcome (satan-goad-read-queue))))
    (satan-goad-read-record (plist-get entry :intervention_id)
                            (plist-get entry :emitted_at))))

(ert-deftest satan-goad/read-record-matches-the-scenario-table ()
  "Each golden outcome reads as the README's scenario table says."
  (satan-goad-fixture-with-goldens
    (let ((answered (satan-goad-test--read-record 'answered))
          (later (satan-goad-test--read-record 'later))
          (seen (satan-goad-test--read-record 'enough-seen))
          (unseen (satan-goad-test--read-record 'enough-unseen))
          (untouched (satan-goad-test--read-record 'untouched))
          (form (satan-goad-test--read-record 'form)))
      (dolist (record (list answered form))
        (should (equal '(:presented_at :value :at)
                       (satan-goad-fixture-keys record)))
        (should (stringp (plist-get record :at)))
        (should (stringp (plist-get record :presented_at))))
      (should (equal "later" (plist-get later :deferred_by)))
      (should (equal "enough" (plist-get seen :deferred_by)))
      (should (plist-get seen :presented_at))
      (should (equal "enough" (plist-get unseen :deferred_by)))
      (should-not (plist-member unseen :presented_at))
      (should (equal '(:presented_at) (satan-goad-fixture-keys untouched)))
      (should-not (satan-goad-test--read-record 'expired)))))

(ert-deftest satan-goad/read-record-without-a-usable-day-file-is-nil ()
  (satan-goad-fixture-with-tmp _dir
    (let ((day (expand-file-name "2026-09-23.json" satan-goad-data-dir))
          (at "2026-09-23T09:30:00+10:00"))
      (should-not (satan-goad-read-record "x" at))
      (dolist (doc '("{\"asks\": {\"x\": " "[]" "{\"asks\": []}"
                     "{\"asks\": {\"x\": 7}}" "{\"items\": {}}"))
        (satan-goad-fixture-write day doc)
        (should-not (satan-goad-read-record "x" at)))))
  (satan-goad-fixture-with-goldens
    (let* ((entry (satan-goad-fixture-golden-entry 'answered))
           (iid (plist-get entry :intervention_id))
           (at (plist-get entry :emitted_at)))
      (should (satan-goad-read-record iid at))
      (should-not (satan-goad-read-record
                   iid (string-replace "T" " " at))))))

(ert-deftest satan-goad/answer-is-option-and-values ()
  "VT-54 — an answered ask's record carries goad's `{option, values}' object
verbatim, whatever the form: no reader interprets it (DEC-025)."
  (satan-goad-fixture-with-goldens
    (let ((slice (satan-goad-slice)))
      (pcase-dolist (`(,outcome . ,option) '((form . "rate")
                                             (answered . "yes")
                                             (midnight . "yes")))
        (let ((value (satan-goad-fixture-answer outcome slice)))
          (should (equal (plist-get (satan-goad-fixture-golden-record outcome)
                                    :value)
                         value))
          (should (equal '(:option :values) (satan-goad-fixture-keys value)))
          (should (equal option (plist-get value :option)))))
      (dolist (outcome '(expired later enough-seen enough-unseen untouched))
        (should-not (plist-member (plist-get (satan-goad-fixture-find
                                              outcome slice)
                                             :record)
                                  :value))))))

;; ── VT-55: long strings are truncated, with a marker ────────────────────────

(defun satan-goad-test--bytes (s)
  "The UTF-8 length of the string S."
  (string-bytes (encode-coding-string s 'utf-8 t)))

(defun satan-goad-test--should-be-cut (original cut)
  "CUT is ORIGINAL truncated: within the cap, a character-whole prefix of
ORIGINAL followed by the marker naming ORIGINAL's size."
  (let ((marker (format satan-goad-truncate-marker
                        (satan-goad-test--bytes original))))
    (should (string-match-p "truncated from [0-9]+ bytes" marker))
    (should (<= (satan-goad-test--bytes cut) satan-goad-truncate-bytes))
    (should (string-suffix-p marker cut))
    (should (string-prefix-p (string-remove-suffix marker cut) original))
    (should (< (length marker) (length cut)))))

(defun satan-goad-test--form-answer-with-note (note)
  "The golden `form' answer, NOTE in place of its note.  A fresh value:
the golden read is copied, never altered."
  (let* ((golden (plist-get (satan-goad-fixture-golden-record 'form) :value))
         (values (plist-put (copy-sequence (plist-get golden :values))
                            :note note)))
    (plist-put (copy-sequence golden) :values values)))

(ert-deftest satan-goad-truncate-value/keeps-strings-within-the-cap ()
  (dolist (s (list "" "steady after lunch"
                   (make-string satan-goad-truncate-bytes ?a)
                   (apply #'concat (make-list 512 "é"))))
    (should (equal s (satan-goad-truncate-value s)))))

(ert-deftest satan-goad-truncate-value/cuts-a-long-string-to-the-cap ()
  (dolist (n (list (1+ satan-goad-truncate-bytes) 5120))
    (let* ((s (make-string n ?a))
           (cut (satan-goad-truncate-value s)))
      (satan-goad-test--should-be-cut s cut)
      (should (= satan-goad-truncate-bytes (satan-goad-test--bytes cut))))))

(ert-deftest satan-goad-truncate-value/cuts-on-a-character-boundary ()
  "Multibyte text loses whole characters, never a byte of one."
  (dolist (s (list (apply #'concat (make-list 600 "é"))
                   (concat "a" (apply #'concat (make-list 400 "語")))
                   (apply #'concat (make-list 300 "🜏"))))
    (let ((cut (satan-goad-truncate-value s)))
      (satan-goad-test--should-be-cut s cut)
      (should (> (satan-goad-test--bytes cut)
                 (- satan-goad-truncate-bytes 4))))))

(ert-deftest satan-goad-truncate-value/is-idempotent ()
  (dolist (v (list (make-string 5120 ?a)
                   (apply #'concat (make-list 600 "é"))
                   (satan-goad-test--form-answer-with-note
                    (make-string 5120 ?n))))
    (let ((once (satan-goad-truncate-value v)))
      (should (equal once (satan-goad-truncate-value once))))))

(ert-deftest satan-goad-truncate-value/passes-non-strings-unchanged ()
  (dolist (v (list 0 6 2.5 t :false nil :option))
    (should (eq v (satan-goad-truncate-value v)))))

(ert-deftest satan-goad-truncate-value/walks-a-value-without-mutating-it ()
  "The golden form answer with a long note comes back with only the note
cut; every other key and value is as goad wrote it, and the input is
untouched."
  (let* ((long (make-string 5120 ?n))
         (input (satan-goad-test--form-answer-with-note long))
         (before (copy-tree input))
         (out (satan-goad-truncate-value input)))
    (should (equal before input))
    (satan-goad-test--should-be-cut
     long (plist-get (plist-get out :values) :note))
    (should (equal (satan-goad-test--form-answer-with-note
                    (plist-get (plist-get out :values) :note))
                   out))))

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

(ert-deftest satan-goad/long-string-truncated ()
  "VT-55 — a note over 1 KiB in goad's day file reaches the `:goad' slice
truncated with a marker, its sibling values unchanged; the day file,
read by `satan-goad-read-record', keeps it whole."
  (satan-goad-fixture-with-golden-copy _dir
    (let ((long (make-string 5120 ?n)))
      (satan-goad-fixture-replace
       (expand-file-name (format "%s.json" satan-goad-fixture-day)
                         satan-goad-data-dir)
       "\"steady after lunch\"" (format "\"%s\"" long))
      (let* ((slice-value (satan-goad-fixture-answer 'form (satan-goad-slice)))
             (cut (plist-get (plist-get slice-value :values) :note))
             (whole (plist-get (satan-goad-test--read-record 'form) :value)))
        (satan-goad-test--should-be-cut long cut)
        (should (equal (satan-goad-test--form-answer-with-note cut)
                       slice-value))
        (should (equal (satan-goad-test--form-answer-with-note long)
                       whole))))))

(ert-deftest satan-goad/slice-survives-json ()
  "The golden slice persists into `percept.json' and reads back equal: the
form's list of option objects and an empty `values' ({}) survive the
wire, and the `form' ask's form and answer are goad's own."
  (satan-goad-fixture-with-golden-copy dir
    (let* ((slice (satan-goad-slice))
           (back (plist-get (satan-jsonl-read-object-file
                             (satan-percept-persist dir (list :goad slice)))
                            :goad)))
      (should (equal slice back))
      (should (equal (plist-get (satan-goad-fixture-golden-entry 'form) :form)
                     (plist-get (satan-goad-fixture-find 'form back) :form)))
      (should (equal (plist-get (satan-goad-fixture-golden-record 'form) :value)
                     (satan-goad-fixture-answer 'form back))))))

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

;; ── VT-47: satan-goad-form-validate ──────────────────────────────────────────
;;
;; Every rule of design sec-3 *The answer form*.  `satan-goad-form-validate'
;; is the single entry point under test — behaviour, not its internal
;; predicates.  A well-formed base form (one option, one field of each
;; shape-relevant kind) is copied and mutated per rule.

(defconst satan-goad-form-test--number-field
  '(:id "energy" :kind "number" :label "Energy" :min 0 :max 10))

(defconst satan-goad-form-test--choice-field
  '(:id "blocker" :kind "choice" :label "Blocker"
    :options ((:id "none" :label "None") (:id "unclear" :label "Unclear"))))

(defconst satan-goad-form-test--form
  `((:id "rate" :label "Rate it"
     :fields (,satan-goad-form-test--number-field
              ,satan-goad-form-test--choice-field
              (:id "note" :kind "text" :label "Note")
              (:id "walked" :kind "boolean" :label "Walked")
              (:id "back_at" :kind "datetime" :label "Back at")))
    (:id "skip" :label "Not now"))
  "A well-formed form drawing every kind; mirrors the golden `form' ask
\(the golden itself predates F1 — RESIDUAL, PHASE-06 notes).")

(defun satan-goad-form-test--ok-rebuilt (form)
  "FORM validated `ok'; the rebuilt value, or a test failure otherwise."
  (pcase (satan-goad-form-validate form)
    (`(ok . ,rebuilt) rebuilt)
    (result (ert-fail (format "expected ok, got %S" result)))))

(defun satan-goad-form-test--refused (form)
  "FORM validated `error'; the reason string, or a test failure otherwise."
  (pcase (satan-goad-form-validate form)
    (`(error . ,reason) reason)
    (result (ert-fail (format "expected error, got %S" result)))))

(ert-deftest satan-goad/form-accepts-the-golden-form ()
  (let ((rebuilt (satan-goad-form-test--ok-rebuilt
                  satan-goad-form-test--form)))
    (should (equal (satan-goad-fixture-json-canon
                    satan-goad-form-test--form)
                   (satan-goad-fixture-json-canon rebuilt)))))

(ert-deftest satan-goad/form-refuses-empty ()
  (should (satan-goad-form-test--refused nil))
  (should (satan-goad-form-test--refused []))
  (should (satan-goad-form-test--refused ())))

(ert-deftest satan-goad/form-refuses-non-object-option ()
  (should (satan-goad-form-test--refused (list "not an option")))
  (should (satan-goad-form-test--refused (list 7))))

(ert-deftest satan-goad/form-refuses-unknown-key ()
  "VT-47 — closed keys at every level: an option, a field, a choice
alternative (SATAN emits no hints)."
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A" :hint "nope"))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text" :label "F"
                                         :hint "x"))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "choice" :label "F"
                                         :options (list (list :id "x" :label "X"
                                                              :hint "h")))))))))

(ert-deftest satan-goad/form-refuses-option-missing-id-or-label ()
  (should (satan-goad-form-test--refused (list (list :label "A"))))
  (should (satan-goad-form-test--refused (list (list :id "a")))))

(ert-deftest satan-goad/form-refuses-bad-option-id ()
  (dolist (bad '("Has-Caps" "has space" "" "has/slash"))
    (should (satan-goad-form-test--refused
             (list (list :id bad :label "A"))))))

(ert-deftest satan-goad/form-refuses-duplicate-option-ids ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A") (list :id "a" :label "B")))))

(ert-deftest satan-goad/form-refuses-key-on-wrong-kind ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text" :label "F"
                                         :min 0))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "number" :label "F"
                                          :options (list (list :id "x"
                                                               :label "X")))))))))

(ert-deftest satan-goad/form-refuses-unknown-kind ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "date" :label "F")))))))

(ert-deftest satan-goad/form-refuses-bad-field-id ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "Bad Id" :kind "text" :label "F")))))))

(ert-deftest satan-goad/form-refuses-field-missing-label ()
  "F1 — SPEC-001 R-15 requires every field to carry `label', not only
`id'/`kind' (goad-semantics `WireField', no serde default on `label')."
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text")))))))

(ert-deftest satan-goad/form-refuses-bad-field-label ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text" :label 7))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text"
                                         :label (make-string 201 ?x))))))))

(ert-deftest satan-goad/form-field-label-survives-rebuild ()
  (let ((rebuilt (satan-goad-form-test--ok-rebuilt
                  (list (list :id "a" :label "A"
                             :fields (list (list :id "f" :kind "text"
                                                :label "Note")))))))
    (should (equal "Note"
                   (plist-get (car (plist-get (car rebuilt) :fields)) :label)))))

(ert-deftest satan-goad/form-refuses-duplicate-field-ids-within-an-option ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text" :label "F")
                                    (list :id "f" :kind "boolean" :label "F")))))))

(ert-deftest satan-goad/form-allows-the-same-field-id-across-options ()
  (should (satan-goad-form-test--ok-rebuilt
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "text" :label "F")))
                (list :id "b" :label "B"
                      :fields (list (list :id "f" :kind "text" :label "F")))))))

(ert-deftest satan-goad/form-refuses-duplicate-alternative-ids ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "choice" :label "F"
                                         :options (list (list :id "x" :label "X")
                                                       (list :id "x" :label "Y")))))))))

(ert-deftest satan-goad/form-refuses-malformed-alternative ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "choice" :label "F"
                                         :options (list (list :id "x"))))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "choice" :label "F"
                                         :options (list (list :label "X"))))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "choice" :label "F"
                                         :options (list (list :id "x" :label "X"
                                                              :note "n")))))))))

(ert-deftest satan-goad/form-refuses-empty-choice-options ()
  "R5 — a choice with no alternatives is not drawable, empty vector,
empty list, or the key omitted alike."
  (dolist (options (list [] () :absent))
    (should (satan-goad-form-test--refused
             (list (list :id "a" :label "A"
                        :fields (list (append
                                       (list :id "f" :kind "choice" :label "F")
                                       (unless (eq options :absent)
                                         (list :options options))))))))))

(ert-deftest satan-goad/form-normalises-empty-fields-away ()
  "R5 — an option's `fields: []' (or the JSONB `{}' rendering of it,
already an empty list by the time this runs) rebuilds with no `fields'
key at all — the no-fields case, not `fields: []'."
  (dolist (fields (list [] ()))
    (let ((rebuilt (satan-goad-form-test--ok-rebuilt
                    (list (list :id "a" :label "A" :fields fields)))))
      (should-not (plist-member (car rebuilt) :fields))))
  ;; An option with no `fields' key at all rebuilds the same way.
  (should-not (plist-member
               (car (satan-goad-form-test--ok-rebuilt
                     (list (list :id "a" :label "A"))))
               :fields)))

(ert-deftest satan-goad/form-refuses-non-number-min-max ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "number" :label "F"
                                         :min "x")))))))

(ert-deftest satan-goad/form-refuses-min-greater-than-max ()
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "number" :label "F"
                                         :min 10 :max 0)))))))

(ert-deftest satan-goad/form-allows-a-lone-min-or-max ()
  (should (satan-goad-form-test--ok-rebuilt
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "number" :label "F"
                                         :min 0))))))
  (should (satan-goad-form-test--ok-rebuilt
           (list (list :id "a" :label "A"
                      :fields (list (list :id "f" :kind "number" :label "F"
                                         :max 10)))))))

(ert-deftest satan-goad/form-size-caps ()
  "At most 8 options, 8 fields per option, 200-char labels, 8 KiB rebuilt."
  (should (satan-goad-form-test--refused
           (cl-loop for i from 0 below 9
                    collect (list :id (format "o%d" i) :label "L"))))
  (should (satan-goad-form-test--ok-rebuilt
           (cl-loop for i from 0 below 8
                    collect (list :id (format "o%d" i) :label "L"))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label "A"
                      :fields (cl-loop for i from 0 below 9
                                       collect (list :id (format "f%d" i)
                                                    :kind "boolean" :label "L"))))))
  (should (satan-goad-form-test--ok-rebuilt
           (list (list :id "a" :label "A"
                      :fields (cl-loop for i from 0 below 8
                                       collect (list :id (format "f%d" i)
                                                    :kind "boolean" :label "L"))))))
  (should (satan-goad-form-test--refused
           (list (list :id "a" :label (make-string 201 ?x)))))
  (should (satan-goad-form-test--ok-rebuilt
           (list (list :id "a" :label (make-string 200 ?x)))))
  ;; The byte cap is the last line of defence beyond the counts above:
  ;; a choice field's alternatives have no count cap of their own, so
  ;; many long-labelled ones overflow it.
  (cl-flet ((alts (n) (cl-loop for i from 0 below n
                               collect (list :id (format "alt%d" i)
                                            :label (make-string 200 ?y)))))
    (should (satan-goad-form-test--refused
             (list (list :id "a" :label "A"
                        :fields (list (list :id "f" :kind "choice" :label "F"
                                           :options (alts 40)))))))
    (should (satan-goad-form-test--ok-rebuilt
             (list (list :id "a" :label "A"
                        :fields (list (list :id "f" :kind "choice" :label "F"
                                           :options (alts 4)))))))))

(ert-deftest satan-goad/form-rebuild-is-canonical-regardless-of-input-shape ()
  "Key order and vector-vs-list at every level do not leak into the
rebuilt form: two forms differing only in those respects rebuild
identically."
  (let ((scrambled
         (vector (list :fields (vector (list :label "Note" :kind "text" :id "note"))
                      :label "Rate it" :id "rate")
                (list :label "Not now" :id "skip")))
        (canonical
         (list (list :id "rate" :label "Rate it"
                    :fields (list (list :id "note" :kind "text" :label "Note")))
              (list :id "skip" :label "Not now"))))
    (should (equal (satan-goad-form-test--ok-rebuilt canonical)
                   (satan-goad-form-test--ok-rebuilt scrambled)))))

;; ── VT-28, VT-48, VT-51: satan-goad-queue-rewrite ────────────────────────────

(defconst satan-goad-test--row
  '(:intervention_id "20260923T093000-tick-pulse-a3f01c.iv001"
    :run_id "20260923T093000-tick-pulse-a3f01c"
    :ts "2026-09-22T23:30:00+00" :mode "tick-pulse" :kind "ask"
    :target_surface "goad" :message "Is the literature review still the next step?"
    :related_motive_id nil :cue_handles ("artifact:thesis-outline")
    :expected_outcome "an answer" :outcome_window_minutes 60 :severity "low")
  "An open-ask row, `satan-intervention-open-asks' shape (not itself
under test — a fixture input, matching the golden `answered' ask).")

(ert-deftest satan-goad/queue-entry-from-row-round-trips-through-the-reader ()
  "T2 — the entry `satan-goad--queue-entry-from-row' builds is accepted
unchanged by `satan-goad--queue-entry' (the reader): the reader is the
round-trip contract, not a hand-pinned shape."
  (let ((entry (satan-goad--queue-entry-from-row satan-goad-test--row 36000)))
    (should (equal "20260923T093000-tick-pulse-a3f01c.iv001"
                   (plist-get entry :intervention_id)))
    (should (equal "Is the literature review still the next step?"
                   (plist-get entry :question)))
    (should (equal "artifact:thesis-outline" (plist-get entry :subject)))
    (should (equal "2026-09-23T09:30:00+10:00" (plist-get entry :emitted_at)))
    (should (equal "2026-09-23T10:30:00+10:00" (plist-get entry :expires_at)))
    (should-not (plist-member entry :form))
    (should (equal entry (satan-goad--queue-entry entry)))))

(ert-deftest satan-goad/queue-entry-from-row-carries-form ()
  "T2 — a row's `:form' rides through verbatim and still round-trips."
  (let* ((form (plist-get (satan-goad-fixture-golden-entry 'form) :form))
         (row (append (list :form form) satan-goad-test--row))
         (entry (satan-goad--queue-entry-from-row row 36000)))
    (should (equal form (plist-get entry :form)))
    (should (equal entry (satan-goad--queue-entry entry)))))

(defconst satan-goad-test--cue-handles '("app:emacs")
  "The single subject handle a real ask handler cues an ask on (T5's
`:cue-handles (list subject)'); the fixture asks below pass it
explicitly, since `satan-intervention-test--ask-args' — built for
VT-57's pipe/newline concern, not goad's — carries none.")

(ert-deftest satan-goad/queue-regenerates ()
  "VT-28 — the queue file is replaced whole from the open asks at NOW: a
stale pre-seeded entry is gone; a matured (window closed), a classified
(has an outcome) and a non-ask row are all absent; the one open ask
remains."
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-intervention-test--with-db
   (satan-intervention-test--with-ctx ctx
     (satan-goad-fixture-with-tmp _dir
       (satan-goad-fixture-write-queue
        (list (satan-goad-fixture-ask :intervention_id "stale")))
       (let* ((ask (lambda (ts window &rest args)
                     (apply #'satan-intervention-test--ask
                            ctx (concat "2026-05-23T" ts "+1000") window
                            :cue-handles satan-goad-test--cue-handles args)))
              (open-id (funcall ask "12:00:00" 60)))
         (funcall ask "11:00:00" 30)                 ; matured by NOW
         (funcall ask "12:10:00" 60 :kind "notify")   ; not an ask
         (should-not (satan-intervention-mark-undelivered ; classified
                      ctx
                      (apply #'satan-intervention-record :ctx ctx
                             :outcome-window-minutes 60
                             :cue-handles satan-goad-test--cue-handles
                             satan-intervention-test--ask-args)
                      (satan-intervention-test--boom-error)))
         (satan-goad-queue-rewrite "2026-05-23T12:30:00+1000")
         (should (equal (list open-id)
                        (satan-goad-fixture-iids (satan-goad-read-queue)))))))))

(ert-deftest satan-goad/queue-carries-form ()
  "VT-48 — an ask's form survives record, project and queue-rewrite,
JSON-equal to the golden form (JSONB reorders object keys, so compare
canonicalised, not with `equal' — satan-goad-fixture-json-canon)."
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-intervention-test--with-db
   (satan-intervention-test--with-ctx ctx
     (satan-goad-fixture-with-tmp _dir
       (let ((form (plist-get (satan-goad-fixture-golden-entry 'form) :form)))
         (satan-intervention-test--ask ctx "2026-05-23T12:00:00+1000" 60
                                       :cue-handles satan-goad-test--cue-handles
                                       :form form)
         (satan-goad-queue-rewrite "2026-05-23T12:30:00+1000")
         (should (equal (satan-goad-fixture-json-canon form)
                        (satan-goad-fixture-json-canon
                         (plist-get (car (satan-goad-read-queue)) :form)))))))))

(ert-deftest satan-goad/pipe-question-queued ()
  "VT-51 — a question carrying `|' and a newline survives record, project
and queue-rewrite intact (DEC-028 — every intervention reader reads
rows as JSON, never splits `psql' output on `|' and newlines)."
  (skip-unless (fboundp 'satan-intervention-test--with-db))
  (satan-intervention-test--with-db
   (satan-intervention-test--with-ctx ctx
     (satan-goad-fixture-with-tmp _dir
       (satan-intervention-test--ask ctx "2026-05-23T12:00:00+1000" 60
                                     :cue-handles satan-goad-test--cue-handles)
       (satan-goad-queue-rewrite "2026-05-23T12:30:00+1000")
       (should (equal (plist-get satan-intervention-test--ask-args :message)
                      (plist-get (car (satan-goad-read-queue)) :question)))))))

(ert-deftest satan-goad/queue-rewrite-no-asks-writes-an-array ()
  "With no open asks the queue document is `{\"asks\":[]}' — an array,
per goad's README schema — never `{\"asks\":{}}' (`satan-jsonl-prepare'
renders a bare nil as an object)."
  (satan-goad-fixture-with-tmp _dir
    (cl-letf (((symbol-function 'satan-intervention-open-asks)
               (lambda (&rest _) nil)))
      (satan-goad-queue-rewrite "2026-05-23T12:30:00+1000"))
    (should (equal "{\"asks\":[]}"
                   (with-temp-buffer
                     (insert-file-contents satan-goad-queue-file)
                     (buffer-string))))))

(provide 'satan-goad-test)
;;; satan-goad-test.el ends here
