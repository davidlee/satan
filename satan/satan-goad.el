;;; satan-goad.el --- read side of goad, SATAN's elicitation surface -*- lexical-binding: t; -*-

;; SL-016 PERCEIVE (design sec-2).  goad's `backend.py' (corpus repo,
;; `goad/') renders SATAN's asks and files what the keeper did with each
;; one.  Two files meet here:
;;
;;   `satan-goad-queue-file'  SATAN's outstanding asks, {"asks": [...]},
;;                            five string fields per entry (state root).
;;   `satan-goad-data-dir'    goad's day records, YYYY-MM-DD.json; an ask's
;;                            record sits under `asks.<intervention_id>' in
;;                            the file of its local EMIT date, whenever
;;                            the event happened (corpus root).
;;
;; Readers only: nothing here writes, and every reader returns nil
;; rather than signal on an absent or malformed file.  The evidence
;; assembler contributes `satan-goad-slice' as `:goad'; canon's
;; `goad.outstanding' rule turns it into handles.
;;
;; Dependency direction: this module requires canon (for the instant
;; parser and the topic handle), never the reverse — canon must run
;; without goad loaded (migrate recanonicalises stored evidence).

;;; Code:

(require 'cl-lib)
(require 'satan-custom)
(require 'satan-jsonl)
(require 'satan-memory-canon)

(defconst satan-goad--queue-fields
  '(:intervention_id :question :subject :emitted_at :expires_at)
  "The fields of a queue entry, in order.  goad's `QUEUE_FIELDS'.")

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

(defun satan-goad--queue-entry (raw)
  "RAW as a queue entry of exactly the five fields, or nil when malformed.
Mirrors goad's `parse_ask': every field a string, a non-empty id, and
both stamps instants with an offset."
  (when (and (satan-jsonl--plist-p raw)
             (cl-every (lambda (k) (stringp (plist-get raw k)))
                       satan-goad--queue-fields)
             (not (string-empty-p (plist-get raw :intervention_id)))
             (satan-memory-canon-parse-instant (plist-get raw :emitted_at))
             (satan-memory-canon-parse-instant (plist-get raw :expires_at)))
    (cl-loop for k in satan-goad--queue-fields
             append (list k (plist-get raw k)))))

(defun satan-goad-read-queue (&optional file)
  "The well-formed entries of the queue FILE, in file order.
FILE defaults to `satan-goad-queue-file'.  An absent or malformed file
means no asks; a malformed entry is dropped alone.  Never signals."
  (let* ((doc (satan-jsonl-read-object-file (or file satan-goad-queue-file)))
         (entries (and (satan-jsonl--plist-p doc) (plist-get doc :asks))))
    (and (listp entries)
         (delq nil (mapcar #'satan-goad--queue-entry entries)))))

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

;; ── the evidence slice ──────────────────────────────────────────────────────

(defun satan-goad-slice (&optional file data-dir)
  "Every queue entry with its record, in queue order: the `:goad' evidence.
Each element is the entry's five fields plus `:record' when the ask has
one in its emit date's day file.  FILE and DATA-DIR default to
`satan-goad-queue-file' and `satan-goad-data-dir'.

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
                (if record (append entry (list :record record)) entry)))
            queue)))

(provide 'satan-goad)
;;; satan-goad.el ends here
