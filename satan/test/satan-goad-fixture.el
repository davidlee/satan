;;; satan-goad-fixture.el --- goad golden fixtures for tests -*- lexical-binding: t; -*-

;; Binds SATAN's goad readers to the golden output of goad's `backend.py'
;; (`goad-fixtures/', see its README), or to a scratch directory.  Not a
;; suite file (no -test suffix): suites `require' it.
;;
;; The goldens are read-only inputs.  Nothing here writes into them; the
;; scratch-directory macro writes only inside its own temp dir.

;;; Code:

(require 'cl-lib)
(require 'json)
(require 'satan-custom)
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
  `(let* ((,var (make-temp-file "satan-goad-test-" t))
          (satan-goad-queue-file (expand-file-name "queue.json" ,var))
          (satan-goad-data-dir (expand-file-name "data" ,var))
          (satan-goad--zone satan-goad-fixture-zone))
     (unwind-protect (progn ,@body)
       (delete-directory ,var t))))

(defun satan-goad-fixture-write (path content)
  "Write the string CONTENT to PATH, creating its directory."
  (make-directory (file-name-directory path) t)
  (with-temp-file path (insert content)))

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
