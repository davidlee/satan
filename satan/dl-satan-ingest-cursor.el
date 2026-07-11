;;; dl-satan-ingest-cursor.el --- per-source evidence ingest frontier -*- lexical-binding: t; -*-

;; DR-010 §3 "Cursor / watermark" (DEC-cursor-per-source-intra-day).
;;
;; A per-source ingest cursor records how far evidence assembly has
;; consumed each behaviour source.  This is DISTINCT from the per-sensor
;; private probe watermarks (`sensor-content.json' etc.) — those mark how
;; far a single backlog probe has fired; this marks the evidence-assembly
;; frontier.
;;
;; Three sources are tracked, each keyed on its NATIVE timestamp field:
;;   :focus    focus segments  -> :end_ts      (local-offset form)
;;   :browser  browser segments-> :end_ts      (local-offset form)
;;   :content  panopticon caps -> :captured_at (UTC-millis-Z)
;; Git is EXCLUDED: git rows key on a backdatable `%cI' and git keeps its
;; own 24h re-scan window — it does NOT get a cursor.
;;
;; CRITICAL — timestamp formats differ across sources
;; (mem.pattern.satan.sensor-watermark-format).  A cursor advanced by
;; comparison MUST store the source record's timestamp string VERBATIM,
;; never a formatted now() or the broker ts.  Advance is `max(current,
;; head)' under the SAME comparison the source uses:
;;   - focus/browser: parsed-instant compare (mirrors
;;     `dl-satan-memory-evidence--newest-segment-end', which sorts by
;;     `date-to-time' because a `Z' instant sorts LOWER as a string than a
;;     stale local one);
;;   - content: `string<' on the single UTC-millis-Z `captured_at' format
;;     (mirrors `dl-satan-sensor-content--count-uninspected').
;; Out-of-order rows behind the cursor must NEVER regress it (idempotent).
;;
;; ADDITIVE / low-risk: missing file / missing key / unparseable cursor
;; ⇒ nil ⇒ caller treats as "consume from head" (no error).  This is the
;; rollback path.
;;
;; NEGATIVE completeness guarantee only: the cursor advances the frontier
;; and feeds backlog depth.  It does NOT (this delta) gate what evidence
;; `assemble-with-bounds' reads — there is no positive per-segment replay.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-jsonl)
(require 'dl-satan-tools-activity)
(require 'dl-satan-memory-evidence)

(declare-function dl-satan-memory-evidence--newest-segment-end "dl-satan-memory-evidence")
(declare-function dl-satan-tools-content--read-articles-jsonl "dl-satan-tools-content")

;; --- Defcustoms ------------------------------------------------

(defcustom dl-satan-ingest-cursor-state-file
  (expand-file-name "satan/ingest-cursor.json"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Path to the per-source ingest-cursor state file.
Stores the persisted plist `(:focus TS :browser TS :content TS)' where
each TS is that source's native timestamp string, verbatim."
  :type 'string :group 'dl-satan)

(defconst dl-satan-ingest-cursor-sources '(:focus :browser :content)
  "The per-source frontier keys this store tracks.  Git is excluded.")

;; --- State file (JSON-plist idiom, mirrors the sensor stores) --
;;
;; NOTE: deliberately NOT sharing a JSON-state helper with the sensor
;; stores — extracting one would touch three existing sensor files and
;; break the "additive" stance of this delta (DR-010 §3).

(defun dl-satan-ingest-cursor-read ()
  "Return the persisted cursor plist, or nil when the file is absent/bad.
A present file yields `(:focus TS :browser TS :content TS)'; a missing
key (or missing/unparseable file) leaves that source nil so the caller
treats it as \"consume from head\"."
  (when (file-readable-p dl-satan-ingest-cursor-state-file)
    (condition-case nil
        (with-temp-buffer
          (insert-file-contents dl-satan-ingest-cursor-state-file)
          (json-parse-buffer :object-type 'plist))
      (error nil))))

(defun dl-satan-ingest-cursor--write (plist)
  "Write PLIST as JSON to the cursor state file."
  (let ((dir (file-name-directory dl-satan-ingest-cursor-state-file)))
    (unless (file-directory-p dir) (make-directory dir t))
    (with-temp-file dl-satan-ingest-cursor-state-file
      (insert (json-serialize plist)))))

(defun dl-satan-ingest-cursor-get (source)
  "Return the persisted cursor TS for SOURCE, or nil if unset.
SOURCE is one of `dl-satan-ingest-cursor-sources'."
  (plist-get (dl-satan-ingest-cursor-read) source))

;; --- Per-source comparators ------------------------------------
;;
;; Each comparator answers \"is A strictly older than B?\" in the SAME
;; discipline the source itself uses, so advance never regresses on an
;; out-of-order row and never mixes timestamp formats.

(defun dl-satan-ingest-cursor--instant-less-p (a b)
  "Return non-nil when A is a strictly earlier instant than B.
Parses both with `date-to-time' (focus/browser `:end_ts' may carry
mixed offsets within one day-file, so a string compare is unsafe —
this mirrors `dl-satan-memory-evidence--newest-segment-end')."
  (let ((at (and (stringp a) (ignore-errors (date-to-time a))))
        (bt (and (stringp b) (ignore-errors (date-to-time b)))))
    (cond
     ((null bt) nil)                    ; no candidate head -> never advance
     ((null at) t)                      ; no current cursor -> adopt head
     (t (time-less-p at bt)))))

(defun dl-satan-ingest-cursor--string-less-p (a b)
  "Return non-nil when A sorts strictly before B by `string<'.
For content's single UTC-millis-Z `captured_at' format a lexical
compare is exact (mirrors `dl-satan-sensor-content--count-uninspected').
nil B never advances; nil A adopts B."
  (cond
   ((not (stringp b)) nil)
   ((not (stringp a)) t)
   (t (string< a b))))

(defun dl-satan-ingest-cursor--less-p (source a b)
  "Dispatch the SOURCE-appropriate \"A older than B?\" comparator."
  (if (eq source :content)
      (dl-satan-ingest-cursor--string-less-p a b)
    (dl-satan-ingest-cursor--instant-less-p a b)))

;; --- Per-source head accessors ---------------------------------

(defun dl-satan-ingest-cursor--segment-head (kind)
  "Return the newest `:end_ts' in today's KIND segment day-file, or nil.
KIND is \"focus\" or \"browser\".  Reuses
`dl-satan-memory-evidence--newest-segment-end' over the lenient JSONL
read; a missing/empty/malformed file yields nil (⇒ from-head)."
  (let ((path (expand-file-name
               (format "segments/%s-%s.jsonl"
                       kind (dl-satan-tools-activity--today))
               dl-satan-tools-activity-dir)))
    (when (file-readable-p path)
      (condition-case nil
          (dl-satan-memory-evidence--newest-segment-end
           (dl-satan-jsonl-read-file path))
        (error nil)))))

(defun dl-satan-ingest-cursor--content-head ()
  "Return the max `:captured_at' across articles.jsonl, or nil.
Reuses `dl-satan-sensor-content--count-uninspected' high-water logic so
the scan is NOT duplicated: with a `\"\"' watermark its returned
high-water is the max captured_at seen (or `\"\"' when the store is
empty, which we normalise to nil = from-head)."
  (require 'dl-satan-sensor-content)
  (condition-case nil
      (let ((hw (cdr (dl-satan-sensor-content--count-uninspected ""))))
        (and (stringp hw) (not (string-empty-p hw)) hw))
    (error nil)))

(defun dl-satan-ingest-cursor-head (source)
  "Return the current head timestamp for SOURCE, or nil if none.
nil ⇒ caller consumes from head (no frontier to advance)."
  (pcase source
    (:focus   (dl-satan-ingest-cursor--segment-head "focus"))
    (:browser (dl-satan-ingest-cursor--segment-head "browser"))
    (:content (dl-satan-ingest-cursor--content-head))
    (_ nil)))

;; --- Advance ---------------------------------------------------

(defun dl-satan-ingest-cursor-advance ()
  "Advance every tracked source's cursor to its head (idempotent).
For each source writes `max(current, head)' under the source's native
comparator.  A nil/older head leaves the cursor untouched (an
out-of-order row behind the frontier cannot regress it).  Returns the
written plist.  Call ONLY on a successful consume run."
  (let ((state (or (dl-satan-ingest-cursor-read) '())))
    (dolist (source dl-satan-ingest-cursor-sources)
      (let ((head (dl-satan-ingest-cursor-head source))
            (current (plist-get state source)))
        (when (and head
                   (dl-satan-ingest-cursor--less-p source current head))
          (setq state (plist-put state source head)))))
    (dl-satan-ingest-cursor--write state)
    state))

;; --- Backlog depth ---------------------------------------------
;;
;; Returns the count of segments/captures that are newer than the
;; persisted cursor per source.  cursor == head ⇒ 0; missing cursor ⇒
;; full count (from-head).  Emacsclient-callable via the public fn.

(defun dl-satan-ingest-cursor--segment-count-after (kind cursor-ts)
  "Count rows in today's KIND segment JSONL with `:end_ts' newer than CURSOR-TS.
KIND is \"focus\" or \"browser\".  Uses parsed-instant compare (mirrors
`dl-satan-ingest-cursor--instant-less-p').  nil CURSOR-TS ⇒ count all rows."
  (let ((path (expand-file-name
               (format "segments/%s-%s.jsonl"
                       kind (dl-satan-tools-activity--today))
               dl-satan-tools-activity-dir)))
    (if (not (file-readable-p path))
        0
      (condition-case nil
          (let ((rows (dl-satan-jsonl-read-file path))
                (count 0))
            (dolist (row rows)
              (let ((ts (plist-get row :end_ts)))
                (when (dl-satan-ingest-cursor--instant-less-p cursor-ts ts)
                  (cl-incf count))))
            count)
        (error 0)))))

(defun dl-satan-ingest-cursor--content-count-after (cursor-ts)
  "Count articles.jsonl rows with `:captured_at' newer than CURSOR-TS.
Reuses `dl-satan-sensor-content--count-uninspected': nil CURSOR-TS ⇒ `\"\"'
watermark ⇒ counts all rows."
  (require 'dl-satan-sensor-content)
  (condition-case nil
      (car (dl-satan-sensor-content--count-uninspected
            (or cursor-ts "")))
    (error 0)))

(defun dl-satan-ingest-cursor-backlog-depth ()
  "Return per-source backlog depth plist `(:focus N :browser N :content N :total N)'.
Depth per source = count of evidence records newer than the persisted cursor.
cursor == head ⇒ 0.  Missing cursor ⇒ full count (consume from head).
Suitable for `emacsclient -e' polling (returns a readable plist)."
  (let* ((state   (dl-satan-ingest-cursor-read))
         (fc      (dl-satan-ingest-cursor--segment-count-after
                   "focus"   (and state (plist-get state :focus))))
         (bc      (dl-satan-ingest-cursor--segment-count-after
                   "browser" (and state (plist-get state :browser))))
         (cc      (dl-satan-ingest-cursor--content-count-after
                   (and state (plist-get state :content)))))
    (list :focus fc :browser bc :content cc :total (+ fc bc cc))))

(provide 'dl-satan-ingest-cursor)
;;; dl-satan-ingest-cursor.el ends here
