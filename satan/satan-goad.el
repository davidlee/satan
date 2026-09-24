;;; satan-goad.el --- read side of goad, SATAN's elicitation surface -*- lexical-binding: t; -*-

;; SL-016 PERCEIVE (design sec-2).  goad's `backend.py' (corpus repo,
;; `goad/') renders SATAN's asks and files what the keeper did with each
;; one.  Two files meet here:
;;
;;   `satan-goad-queue-file'  SATAN's outstanding asks, {"asks": [...]},
;;                            five string fields per entry and an
;;                            optional answer form (state root).
;;   `satan-goad-data-dir'    goad's day records, YYYY-MM-DD.json; an ask's
;;                            record sits under `asks.<intervention_id>' in
;;                            the file of its local EMIT date, whenever
;;                            the event happened (corpus root).
;;
;; Every reader returns nil rather than signal on an absent or
;; malformed file.  The evidence assembler contributes `satan-goad-
;; slice' as `:goad'; canon's `goad.outstanding' rule turns it into
;; handles.
;;
;; SL-016 PROMPT (design sec-3) adds the queue's write side alongside
;; the readers: `satan-goad-form-validate' (pure — the one place every
;; rule of *The answer form* lives) and `satan-goad-queue-rewrite',
;; which regenerates the queue file whole from the open asks — the
;; queue is a disposable projection of Postgres rows, never itself the
;; record of one.  That is why this module now requires
;; `satan-intervention': the read side stays dependency-light, but the
;; rewrite must read the rows it projects.
;;
;; Dependency direction: this module requires canon (for the instant
;; parser and the topic handle) and intervention (for the open-asks
;; query), never the reverse — canon must run without goad loaded
;; (migrate recanonicalises stored evidence), and intervention has no
;; use for goad's queue shape.

;;; Code:

(require 'cl-lib)
(require 'satan-custom)
(require 'satan-jsonl)
(require 'satan-memory-canon)
(require 'satan-intervention)

(defconst satan-goad--queue-fields
  '(:intervention_id :question :subject :emitted_at :expires_at)
  "The required fields of a queue entry, in order.  goad's `QUEUE_FIELDS'.
An entry may also carry `form' (`satan-goad--form-p').")

(defvar satan-goad--zone nil
  "Zone the emit date is taken in; nil is Emacs's local zone.
A test seam: production never sets it.  Bind it to an offset in
seconds (`36000') rather than mutating the process's TZ.")

(defalias 'satan-goad-subject-topic #'satan-memory-canon-topic-handle
  "The `topic:' handle canon's `goad.outstanding' rule emits for a subject.")

;; ── the emit date ───────────────────────────────────────────────────────────

(defun satan-goad-local-date (ts &optional zone)
  "The local calendar date, \"YYYY-MM-DD\", of the instant TS.
ZONE defaults to `satan-goad--zone'.  nil when TS is not an ISO 8601
date-time with an offset — a raw psql cell must be normalised first
\(`satan-intervention--normalize-pg-timestamp').  Always the date of a
parsed instant, never a substring: psql renders `ts' in GMT, so its
first ten characters are the wrong day for anything emitted before
10:00 in +10:00 (design sec-2, RV-007 F-33)."
  (let ((instant (satan-memory-canon-parse-instant ts)))
    (and instant
         (format-time-string "%F" instant (or zone satan-goad--zone)))))

;; ── the queue ───────────────────────────────────────────────────────────────

(defun satan-goad--form-p (form)
  "Non-nil when FORM is a well-formed answer form.  goad's `is_form'.
A non-empty list of options, each a plist with a string `:id' and a
string `:label'; fields are not inspected — the emit side validated
them (DEC-026)."
  (and (consp form)
       (cl-every (lambda (option)
                   (and (satan-jsonl--plist-p option)
                        (stringp (plist-get option :id))
                        (stringp (plist-get option :label))))
                 form)))

(defun satan-goad--queue-entry (raw)
  "RAW as a queue entry — the five fields, then `:form' if any — or nil.
Mirrors goad's `parse_ask': every field a string, a non-empty id, both
stamps instants with an offset, and a `form' key, when present, a
well-formed form (`satan-goad--form-p'; JSON null is not).  The form is
kept verbatim; a formless entry has no `:form' key at all."
  (when (satan-jsonl--plist-p raw)
    (let ((form (plist-member raw :form)))
      (when (and (cl-every (lambda (k) (stringp (plist-get raw k)))
                           satan-goad--queue-fields)
                 (not (string-empty-p (plist-get raw :intervention_id)))
                 (satan-memory-canon-parse-instant (plist-get raw :emitted_at))
                 (satan-memory-canon-parse-instant (plist-get raw :expires_at))
                 (or (null form) (satan-goad--form-p (cadr form))))
        (append (cl-loop for k in satan-goad--queue-fields
                         append (list k (plist-get raw k)))
                (and form (list :form (cadr form))))))))

(defun satan-goad-read-queue (&optional file)
  "The well-formed entries of the queue FILE, in file order.
FILE defaults to `satan-goad-queue-file'.  An absent or malformed file
means no asks; a malformed entry is dropped alone.  Never signals."
  (let* ((doc (satan-jsonl-read-object-file (or file satan-goad-queue-file)))
         (entries (and (satan-jsonl--plist-p doc) (plist-get doc :asks))))
    (and (listp entries)
         (delq nil (mapcar #'satan-goad--queue-entry entries)))))

;; ── the answer form (write side; design sec-3 "The answer form", VT-47) ─────
;;
;; `satan-goad-form-validate' is the one place every rule of the answer
;; form lives (DEC-026): the tool's `:args-schema' has no closed
;; objects and no rules keyed to a field's kind, so it only declares
;; `form' an optional array.  On success the form is rebuilt from its
;; named keys, in canonical order, lists throughout — that is what is
;; recorded, never the caller's own shape.  `satan-goad--form-p' (the
;; reader) stays deliberately lax; the two are not the same check.

(defconst satan-goad-form-max-options 8
  "The most options a form may carry.")

(defconst satan-goad-form-max-fields 8
  "The most fields a single option may carry.")

(defconst satan-goad-form-max-label-chars 200
  "The most characters an option's or a choice alternative's label may hold.")

(defconst satan-goad-form-max-bytes 8192
  "The most UTF-8 bytes the rebuilt form may serialise to (8 KiB).
The last line of defence: the counts above already bound options and
fields, but a choice field's alternatives carry no count cap of their
own.")

(defconst satan-goad-form--id-re "\\`[a-z0-9_-]+\\'"
  "Every option, field and choice-alternative id matches this, anchored.")

(defconst satan-goad-form--kinds '("text" "boolean" "datetime" "number" "choice")
  "The five field kinds a form may draw.")

(defconst satan-goad-form--kind-extra-keys
  '(("number" :min :max)
    ("choice" :options))
  "Extra keys a field's kind allows beyond `:id', `:kind' and `:label' (R-50).
`text', `boolean' and `datetime' allow none.")

(defun satan-goad-form--fail (reason)
  "Abort validation with REASON (a string); never returns."
  (throw 'satan-goad-form--invalid (cons 'error reason)))

(defun satan-goad-form--as-list (value)
  "VALUE as a list: a vector's elements, or VALUE itself when already a
list (nil included — an absent key, or one JSONB rendered `{}', R5)."
  (if (vectorp value) (append value nil) value))

(defun satan-goad-form--closed-keys (plist allowed context)
  "Fail unless PLIST is an object whose every key is in ALLOWED.
CONTEXT names the level, for the failure reason."
  (unless (satan-jsonl--plist-p plist)
    (satan-goad-form--fail (format "%s must be an object" context)))
  (cl-loop for (k _v) on plist by #'cddr
           unless (memq k allowed)
           do (satan-goad-form--fail
               (format "%s: unknown key %s" context k))))

(defun satan-goad-form--unique-ids (ids context)
  "Fail when IDS (a list of id strings) holds a duplicate."
  (let ((seen (make-hash-table :test 'equal)))
    (dolist (id ids)
      (when (gethash id seen)
        (satan-goad-form--fail (format "%s: duplicate id %S" context id)))
      (puthash id t seen))))

(defun satan-goad-form--id (value context)
  "VALUE as a validated id string, or a failure naming CONTEXT.
Case-sensitive regardless of `case-fold-search' — `Has-Caps' is not
`[a-z0-9_-]+'."
  (unless (and (stringp value)
               (let (case-fold-search)
                 (string-match-p satan-goad-form--id-re value)))
    (satan-goad-form--fail
     (format "%s: id must be a non-empty [a-z0-9_-]+ string" context)))
  value)

(defun satan-goad-form--label (value context)
  "VALUE as a validated label string, or a failure naming CONTEXT."
  (unless (stringp value)
    (satan-goad-form--fail (format "%s: label must be a string" context)))
  (when (> (length value) satan-goad-form-max-label-chars)
    (satan-goad-form--fail
     (format "%s: label exceeds %d characters"
             context satan-goad-form-max-label-chars)))
  value)

(defun satan-goad-form--alternative (alt context)
  "ALT (a choice option, R-53) rebuilt as `(:id ID :label LABEL)'."
  (satan-goad-form--closed-keys alt '(:id :label) context)
  (unless (and (plist-member alt :id) (plist-member alt :label))
    (satan-goad-form--fail (format "%s: needs id and label" context)))
  (list :id (satan-goad-form--id (plist-get alt :id) context)
        :label (satan-goad-form--label (plist-get alt :label) context)))

(defun satan-goad-form--alternatives (options context)
  "A choice field's `:options' rebuilt (R-52); refuses empty (R5) — a
choice with no alternatives is not drawable, whether OPTIONS is
absent, `[]', or `{}' (JSONB's rendering of an empty array)."
  (let ((items (satan-goad-form--as-list options)))
    (unless (consp items)
      (satan-goad-form--fail (format "%s: options must not be empty" context)))
    (let ((rebuilt (cl-loop for item in items
                            for i from 0
                            collect (satan-goad-form--alternative
                                     item (format "%s option %d" context i)))))
      (satan-goad-form--unique-ids
       (mapcar (lambda (a) (plist-get a :id)) rebuilt) context)
      rebuilt)))

(defun satan-goad-form--number-extra (field context)
  "The `:min'/`:max' pair to append to a number FIELD's rebuild.
Each is validated as a number when present (absent stays absent);
fails when both are present and `min > max'."
  (cl-flet ((bound (key)
              (let ((cell (plist-member field key)))
                (when cell
                  (unless (numberp (cadr cell))
                    (satan-goad-form--fail
                     (format "%s: %s must be a number" context key)))
                  (cadr cell)))))
    (let ((min (bound :min)) (max (bound :max)))
      (when (and min max (> min max))
        (satan-goad-form--fail (format "%s: min must be <= max" context)))
      (append (and (plist-member field :min) (list :min min))
              (and (plist-member field :max) (list :max max))))))

(defun satan-goad-form--field (field context)
  "FIELD (an option's field) rebuilt; kind-scoped keys enforced (R-50).
`label' is required alongside `id'/`kind' (F1 — goad SPEC-001 R-15's
`WireField' has no serde default on `label'; a form the host would
refuse before this was caught blanked goad)."
  (unless (satan-jsonl--plist-p field)
    (satan-goad-form--fail (format "%s must be an object" context)))
  (unless (and (plist-member field :id) (plist-member field :kind)
               (plist-member field :label))
    (satan-goad-form--fail (format "%s: needs id, kind and label" context)))
  (let ((kind (plist-get field :kind)))
    (unless (member kind satan-goad-form--kinds)
      (satan-goad-form--fail (format "%s: unknown kind %S" context kind)))
    (satan-goad-form--closed-keys
     field (append '(:id :kind :label)
                    (cdr (assoc kind satan-goad-form--kind-extra-keys)))
     context)
    (append
     (list :id (satan-goad-form--id (plist-get field :id) context) :kind kind
           :label (satan-goad-form--label (plist-get field :label) context))
     (pcase kind
       ("number" (satan-goad-form--number-extra field context))
       ("choice" (list :options (satan-goad-form--alternatives
                                  (plist-get field :options) context)))))))

(defun satan-goad-form--fields (fields context)
  "An option's `:fields' rebuilt, or nil when empty (R5 — `fields: []',
or its JSONB `{}' rendering, normalises to no `fields' key at all: an
option with no fields is exactly the no-fields case)."
  (let ((items (satan-goad-form--as-list fields)))
    (when items
      (when (> (length items) satan-goad-form-max-fields)
        (satan-goad-form--fail
         (format "%s: at most %d fields" context satan-goad-form-max-fields)))
      (let ((rebuilt (cl-loop for item in items
                              for i from 0
                              collect (satan-goad-form--field
                                       item (format "%s field %d" context i)))))
        (satan-goad-form--unique-ids
         (mapcar (lambda (f) (plist-get f :id)) rebuilt) context)
        rebuilt))))

(defun satan-goad-form--option (option context)
  "OPTION rebuilt as `(:id ID :label LABEL [:fields FIELDS])'."
  (unless (satan-jsonl--plist-p option)
    (satan-goad-form--fail (format "%s must be an object" context)))
  (unless (and (plist-member option :id) (plist-member option :label))
    (satan-goad-form--fail (format "%s: needs id and label" context)))
  (satan-goad-form--closed-keys option '(:id :label :fields) context)
  (let ((fields (satan-goad-form--fields (plist-get option :fields) context)))
    (append
     (list :id (satan-goad-form--id (plist-get option :id) context)
           :label (satan-goad-form--label (plist-get option :label) context))
     (and fields (list :fields fields)))))

(defun satan-goad-form--options (form)
  "FORM (the top-level form) rebuilt as a list of options."
  (let ((items (satan-goad-form--as-list form)))
    (unless (consp items)
      (satan-goad-form--fail "form must not be empty"))
    (when (> (length items) satan-goad-form-max-options)
      (satan-goad-form--fail
       (format "form: at most %d options" satan-goad-form-max-options)))
    (let ((rebuilt (cl-loop for item in items
                            for i from 0
                            collect (satan-goad-form--option
                                     item (format "option %d" i)))))
      (satan-goad-form--unique-ids
       (mapcar (lambda (o) (plist-get o :id)) rebuilt) "form")
      rebuilt)))

(defun satan-goad-form--serialised-bytes (rebuilt)
  "The UTF-8 byte length of REBUILT, serialised as it would be recorded."
  (satan-goad--utf8-bytes
   (json-serialize (satan-jsonl-prepare rebuilt)
                   :null-object :null :false-object :false)))

(defun satan-goad-form-validate (form)
  "FORM (a list of option plists, or a vector of them — the MCP/JSON
path may hand vectors) validated against every rule of design sec-3
\"The answer form\" (VT-47).  `(ok . REBUILT)' on success: FORM rebuilt
from its named keys in canonical order, lists throughout, regardless
of FORM's own key order or vector-ness.  `(error . REASON)' on the
first rule FORM breaks, REASON a short human string — nothing is
recorded."
  (catch 'satan-goad-form--invalid
    (let ((rebuilt (satan-goad-form--options form)))
      (when (> (satan-goad-form--serialised-bytes rebuilt)
               satan-goad-form-max-bytes)
        (satan-goad-form--fail
         (format "form: serialised form exceeds %d bytes"
                 satan-goad-form-max-bytes)))
      (cons 'ok rebuilt))))

(defconst satan-goad-question-max-chars 280
  "The most characters an ask's question may hold: goad renders it as the
view's title (RV-017 F-8).")

(defun satan-goad-question-invalid (question)
  "Why QUESTION cannot be asked, or nil: it must be a non-blank string of
at most `satan-goad-question-max-chars' characters."
  (cond
   ((not (and (stringp question) (string-match-p "[^[:space:]]" question)))
    "question must be a non-blank string")
   ((> (length question) satan-goad-question-max-chars)
    (format "question exceeds %d characters" satan-goad-question-max-chars))))

;; ── the queue's write side (design sec-3 "The queue is a projection") ──────
;;
;; The queue file is a disposable projection of the open `"ask"' rows —
;; regenerating it from Postgres, not the transcript, is correct: a
;; row-less ask is one the observer cannot score, and should not be
;; asked (design sec-3).  `satan-goad--queue-entry' (the reader, above)
;; is the round-trip contract for `satan-goad--queue-entry-from-row':
;; an entry this module writes must read back unchanged.

(defun satan-goad--iso-instant (instant &optional zone)
  "INSTANT (a Lisp time value) as ISO 8601 with an explicit offset.
ZONE defaults to `satan-goad--zone'; nil means Emacs's local zone — the
same seam `satan-goad-local-date' uses, so one binding covers both."
  (format-time-string "%FT%T%:z" instant (or zone satan-goad--zone)))

(defun satan-goad--queue-entry-from-row (row &optional zone)
  "ROW (an open ask, `satan-intervention-open-asks' shape) as a queue
entry: the five fields the backend renders, plus `:form' when ROW
carries one.  Pure.  `intervention_id' is ROW's `:intervention_id',
`question' its `:message', `subject' the first (and only — the ask
handler cues exactly one) of its `:cue_handles'.  `emitted_at' is
ROW's `:ts' rendered in ZONE (default `satan-goad--zone'); `expires_at'
is that instant plus `:outcome_window_minutes'."
  (let* ((emitted (satan-memory-canon-parse-instant (plist-get row :ts)))
         (window (plist-get row :outcome_window_minutes))
         (form (plist-member row :form)))
    (append
     (list :intervention_id (plist-get row :intervention_id)
           :question (plist-get row :message)
           :subject (car (plist-get row :cue_handles))
           :emitted_at (satan-goad--iso-instant emitted zone)
           :expires_at (satan-goad--iso-instant
                        (time-add emitted (* window 60)) zone))
     (and form (list :form (cadr form))))))

(defun satan-goad-queue-rewrite (&optional now file db)
  "Rewrite the queue FILE whole, from the asks open at NOW.
NOW is an ISO8601 string, default the current instant; FILE defaults
to `satan-goad-queue-file'; DB defaults to `satan-intervention-open-
asks's own default.  Signals on failure — DB unreachable, or the
write — for the caller to catch (the tool handler, T5); this function
does not catch anything itself.

Fires only from the ask handler.  A matured ask's entry lingers in the
file until the next ask, harmlessly: it is past its `expires_at', which
every queue reader filters (RV-017 F-6)."
  (let* ((now (or now (satan-goad--iso-instant (current-time))))
         (rows (satan-intervention-open-asks now db))
         (entries (mapcar #'satan-goad--queue-entry-from-row rows)))
    (satan-jsonl-write-file-atomic
     (or file satan-goad-queue-file)
     ;; A vector, so no open asks is `[]': `satan-jsonl-prepare' renders
    ;; a bare nil as `{}', and the README schema says `asks' is an array.
    (json-serialize (satan-jsonl-prepare (list :asks (vconcat entries)))
                     :null-object :null :false-object :false))))

;; ── records ─────────────────────────────────────────────────────────────────

(defun satan-goad--day-file (date data-dir)
  "The day record for DATE (\"YYYY-MM-DD\") under DATA-DIR."
  (expand-file-name (concat date ".json") data-dir))

(defun satan-goad--day-asks (date data-dir)
  "The `asks' map of DATE's day record under DATA-DIR, or nil."
  (let ((doc (satan-jsonl-read-object-file
              (satan-goad--day-file date data-dir))))
    (and (satan-jsonl--plist-p doc)
         (let ((asks (plist-get doc :asks)))
           (and (satan-jsonl--plist-p asks) asks)))))

(defun satan-goad--ask-record (asks iid)
  "The record for intervention IID in the day's ASKS map, or nil."
  (let ((record (plist-get asks (intern (concat ":" iid)))))
    (and (satan-jsonl--plist-p record) record)))

(defun satan-goad--emit-date (entry)
  "The local emit date of the queue ENTRY."
  (satan-goad-local-date (plist-get entry :emitted_at)))

(defun satan-goad-read-record (iid emitted-at &optional data-dir)
  "Ask IID's record, from the day file of EMITTED-AT's local date.
DATA-DIR defaults to `satan-goad-data-dir'.  nil when EMITTED-AT has no
date, or the file or the record is absent or malformed."
  (let ((date (satan-goad-local-date emitted-at)))
    (and date
         (satan-goad--ask-record
          (satan-goad--day-asks date (or data-dir satan-goad-data-dir))
          iid))))

;; ── truncation ──────────────────────────────────────────────────────────────

(defconst satan-goad-truncate-bytes 1024
  "The most UTF-8 bytes a goad string value keeps in evidence and trace.
The marker counts against it (design sec-5, RV-015 F-8).")

(defconst satan-goad-truncate-marker "…[truncated from %d bytes]"
  "Appended to a truncated value; `format'ted with its original UTF-8 size.")

(defun satan-goad--utf8-bytes (s)
  "The UTF-8 length of the string S."
  (string-bytes (encode-coding-string s 'utf-8 t)))

(defun satan-goad--prefix-within (s budget)
  "The longest prefix of S, in whole characters, of at most BUDGET bytes."
  (let ((used 0) (end 0) (len (length s)))
    (while (and (< end len)
                (<= (setq used (+ used (satan-goad--utf8-bytes
                                        (string (aref s end)))))
                    budget))
      (setq end (1+ end)))
    (substring s 0 end)))

(defun satan-goad--truncate-string (s)
  "S, or its prefix plus the marker when S exceeds `satan-goad-truncate-bytes'."
  (let ((bytes (satan-goad--utf8-bytes s)))
    (if (<= bytes satan-goad-truncate-bytes)
        s
      (let* ((marker (format satan-goad-truncate-marker bytes))
             (budget (- satan-goad-truncate-bytes
                        (satan-goad--utf8-bytes marker))))
        (concat (satan-goad--prefix-within s budget) marker)))))

(defun satan-goad-truncate-value (value)
  "VALUE, a decoded JSON value, with every long string in it truncated.
A string over `satan-goad-truncate-bytes' of UTF-8 becomes a prefix cut
on a character boundary plus `satan-goad-truncate-marker', the whole
within the cap.  Lists are walked element by element, so plist keys
pass untouched; anything else is returned as is.

Pure — VALUE is never mutated — and idempotent: a truncated string is
within the cap, so a second pass leaves it alone.  The one truncation
for goad values (design sec-5): the `:goad' evidence slice here, and
the answer trace (PHASE-09)."
  (cond ((stringp value) (satan-goad--truncate-string value))
        ((consp value) (mapcar #'satan-goad-truncate-value value))
        (t value)))

;; ── the evidence slice ──────────────────────────────────────────────────────

(defun satan-goad--evidence-record (record)
  "RECORD for evidence: any `:value' through `satan-goad-truncate-value'.
A fresh plist; RECORD is not mutated."
  (let ((value (plist-member record :value)))
    (if value
        (plist-put (copy-sequence record) :value
                   (satan-goad-truncate-value (cadr value)))
      record)))

(defun satan-goad-slice (&optional file data-dir)
  "Every queue entry with its record, in queue order: the `:goad' evidence.
Each element is the queue entry (its five fields, and `:form' when it
has one) plus `:record' when the ask has one in its emit date's day
file.  The record's answer value has its long strings truncated
\(`satan-goad-truncate-value'); `satan-goad-read-record' reads it whole.
FILE and DATA-DIR default to `satan-goad-queue-file' and
`satan-goad-data-dir'.

Unfiltered: an evidence window's time bounds say nothing about an ask,
whose events all file under its emit date, so consumers apply each
ask's own window (design sec-2, RV-007 F-23).  Each day file is read
at most once."
  (let* ((data-dir (or data-dir satan-goad-data-dir))
         (queue (satan-goad-read-queue file))
         (days (mapcar (lambda (date)
                         (cons date (satan-goad--day-asks date data-dir)))
                       (delete-dups (mapcar #'satan-goad--emit-date queue)))))
    (mapcar (lambda (entry)
              (let ((record (satan-goad--ask-record
                             (cdr (assoc (satan-goad--emit-date entry) days))
                             (plist-get entry :intervention_id))))
                (if record
                    (append entry
                            (list :record (satan-goad--evidence-record record)))
                  entry)))
            queue)))

(provide 'satan-goad)
;;; satan-goad.el ends here
