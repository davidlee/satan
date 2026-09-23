;;; satan-goad-fixture.el --- goad golden fixtures for tests -*- lexical-binding: t; -*-

;; Binds SATAN's goad readers to the golden output of goad's `backend.py'
;; (`goad-fixtures/', see its README), or to a scratch directory.  Not a
;; suite file (no -test suffix): suites `require' it.
;;
;; The goldens are read-only inputs.  Nothing here writes into them; the
;; scratch-directory macros write only inside their own temp dir.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'satan-custom)
(require 'satan-jsonl)
(require 'satan-goad)

(defconst satan-goad-fixture-dir
  (expand-file-name "goad-fixtures/"
                    (file-name-directory
                     (or load-file-name buffer-file-name
                         (locate-library "satan-goad-fixture"))))
  "The golden output of goad's `backend.py' (read-only).")

(defconst satan-goad-fixture-zone 36000
  "The zone the goldens were produced in: +10:00, the keeper's.")

(defconst satan-goad-fixture-ids
  '((expired       . "20260923T080000-tick-pulse-7b2e90.iv001")
    (answered      . "20260923T093000-tick-pulse-a3f01c.iv001")
    (later         . "20260923T093000-tick-pulse-a3f01c.iv002")
    (enough-seen   . "20260923T093000-tick-pulse-a3f01c.iv003")
    (enough-unseen . "20260923T093000-tick-pulse-a3f01c.iv004")
    (untouched     . "20260923T111000-tick-pulse-c41d5e.iv001")
    (form          . "20260923T130000-tick-pulse-d82c4f.iv001")
    (midnight      . "20260923T231500-tick-pulse-e90f27.iv001"))
  "Golden intervention ids by scenario outcome, copied from the fixtures
README's scenario table.  Inputs that select an ask, never values under
test.")

(defun satan-goad-fixture-id (outcome)
  "The golden intervention id for OUTCOME (a symbol from the README table)."
  (or (alist-get outcome satan-goad-fixture-ids)
      (error "satan-goad-fixture: no golden ask for outcome %s" outcome)))

(defun satan-goad-fixture-find (outcome entries)
  "The element of ENTRIES (queue entries or slice elements) for OUTCOME."
  (let ((iid (satan-goad-fixture-id outcome)))
    (cl-find-if (lambda (e) (equal iid (plist-get e :intervention_id)))
                entries)))

(defun satan-goad-fixture-answer (outcome entries)
  "The answer value in the record of OUTCOME's element of ENTRIES (slice
elements), or nil."
  (plist-get (plist-get (satan-goad-fixture-find outcome entries) :record)
             :value))

(defun satan-goad-fixture-iids (entries)
  "The intervention ids of ENTRIES, in order."
  (mapcar (lambda (e) (plist-get e :intervention_id)) entries))

(defmacro satan-goad-fixture-with-goldens (&rest body)
  "Run BODY with the goad readers bound to the goldens, in the goldens' zone."
  (declare (indent 0))
  `(let ((satan-goad-queue-file
          (expand-file-name "queue.json" satan-goad-fixture-dir))
         (satan-goad-data-dir (expand-file-name "data" satan-goad-fixture-dir))
         (satan-goad--zone satan-goad-fixture-zone))
     ,@body))

(defmacro satan-goad-fixture-with-tmp (var &rest body)
  "Run BODY with VAR bound to a fresh temp dir the goad readers point into.
The queue file is VAR/queue.json and the data dir VAR/data/; neither
exists until BODY writes it.  The dir is removed afterwards."
  (declare (indent 1))
  (let ((dir (make-symbol "dir")))
    `(let* ((,dir (make-temp-file "satan-goad-test-" t))
            (,var ,dir)
            (satan-goad-queue-file (expand-file-name "queue.json" ,dir))
            (satan-goad-data-dir (expand-file-name "data" ,dir))
            (satan-goad--zone satan-goad-fixture-zone))
       (unwind-protect (progn ,@body)
         (delete-directory ,dir t)))))

;; ── the goldens, decoded directly ───────────────────────────────────────────
;;
;; The producer's bytes as `satan-jsonl-read-object-file' decodes them,
;; bypassing SATAN's goad readers: the reference a reader's output is
;; compared against.

(defconst satan-goad-fixture-day "2026-09-23"
  "The golden day file's date: every golden ask files under it.")

(defun satan-goad-fixture--golden (file)
  "FILE, relative to `satan-goad-fixture-dir', decoded."
  (satan-jsonl-read-object-file (expand-file-name file satan-goad-fixture-dir)))

(defun satan-goad-fixture-golden-entry (outcome)
  "OUTCOME's entry in the golden `queue.json', decoded as it stands."
  (satan-goad-fixture-find
   outcome (plist-get (satan-goad-fixture--golden "queue.json") :asks)))

(defun satan-goad-fixture-golden-record (outcome)
  "OUTCOME's record in the golden day file, decoded as it stands; nil if none."
  (plist-get (plist-get (satan-goad-fixture--golden
                         (format "data/%s.json" satan-goad-fixture-day))
                        :asks)
             (intern (concat ":" (satan-goad-fixture-id outcome)))))

(defun satan-goad-fixture-keys (plist)
  "The keys of PLIST, in order."
  (cl-loop for (k _) on plist by #'cddr collect k))

;; ── scratch dirs ────────────────────────────────────────────────────────────

(defun satan-goad-fixture-write (path content)
  "Write the string CONTENT to PATH, creating its directory."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert content)))

(defmacro satan-goad-fixture-with-golden-copy (var &rest body)
  "Like `satan-goad-fixture-with-tmp', with the goldens copied into VAR first.
BODY may alter one value (`satan-goad-fixture-replace') and keep every
other byte the producer's.  The goldens themselves are never written."
  (declare (indent 1))
  `(satan-goad-fixture-with-tmp ,var
     (copy-file (expand-file-name "queue.json" satan-goad-fixture-dir)
                satan-goad-queue-file)
     (copy-directory (expand-file-name "data" satan-goad-fixture-dir)
                     satan-goad-data-dir nil nil t)
     ,@body))

(defun satan-goad-fixture-replace (file from to)
  "Replace the text FROM with TO in the copied FILE.
Signals when FROM is absent, so a regenerated golden cannot leave a
test silently checking nothing."
  (let ((text (with-temp-buffer
                (insert-file-contents file)
                (buffer-string))))
    (unless (string-search from text)
      (error "satan-goad-fixture: %S not in %s" from file))
    (satan-goad-fixture-write file (string-replace from to text))))

(defun satan-goad-fixture-write-queue (entries)
  "Write ENTRIES (plists) as the queue document at `satan-goad-queue-file'."
  (satan-goad-fixture-write
   satan-goad-queue-file
   (json-serialize (list :asks (vconcat entries)))))

(defun satan-goad-fixture-ask (&rest overrides)
  "A well-formed queue entry, with OVERRIDES (a plist) replacing fields.
An override of `:absent' removes the field."
  (let ((entry (list :intervention_id "20260923T093000-tick-pulse-000000.iv001"
                     :question "Still on it?"
                     :subject "app:emacs"
                     :emitted_at "2026-09-23T09:30:00+10:00"
                     :expires_at "2026-09-23T10:30:00+10:00")))
    (cl-loop for (k v) on overrides by #'cddr
             do (setq entry (if (eq v :absent)
                                (cl-loop for (k2 v2) on entry by #'cddr
                                         unless (eq k2 k) append (list k2 v2))
                              (plist-put entry k v))))
    entry))

(provide 'satan-goad-fixture)
;;; satan-goad-fixture.el ends here
