;;; satan-pattern.el --- pattern definitions + rebuild projection -*- lexical-binding: t; -*-

;; DE-009: SATAN pattern records and scars — outcome-linked pattern-local learning.
;;
;; This module owns the parse/sync of `patterns.eld' into `satan_patterns' and
;; the rebuild of `satan_pattern_outcomes' projection (containment join, mature/
;; non-unknown, head-only, advisory-locked).
;;
;; Public surface:
;;   (satan-pattern-sync &optional PATTERNS-FILE DB)
;;     Parse PATTERNS-FILE (default `satan/patterns.eld'), validate every
;;     cue_handle against the grammar, upsert definitions idempotently, and
;;     soft-retire absent patterns (enabled = false).  Returns `(:upserted N
;;     :retired M)' or signals on parse/grammar/DB failure.
;;
;;   (satan-pattern-rebuild &optional DB)
;;     TRUNCATE + INSERT … SELECT containment join: every mature, non-unknown
;;     outcome attributed to every pattern whose cue_handles ⊆ the
;;     intervention's percept snapshot (JSONB @>).  Advisory-locked, single
;;     transaction, head-only (reads current outcome head verdict).
;;     Returns `(:matched N)' or signals on DB failure.
;;
;;   (satan-pattern-stats &optional DB)
;;     Query satan_pattern_stats view → list of plists.
;;
;;   (satan-pattern-list &optional DB)
;;     Query satan_patterns → list of plists.
;;
;;   (satan-pattern-scars &optional PATTERN-ID DB)
;;     Query satan_pattern_outcomes WHERE classification IN
;;     ('contradicted','harmful') → list of plists.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-db)
(require 'satan-jsonl)
(require 'satan-memory-grammar)
(require 'satan-memory-migrate)
(require 'satan-custom)

;; ── file resolution ─────────────────────────────────────────────────────────

(defcustom satan-pattern-file
  (expand-file-name "patterns.eld" satan--root)
  "Path to the curated pattern definitions file (read-form list of plists)."
  :type 'file :group 'satan)

;; ── handle validation ───────────────────────────────────────────────────────

(defun satan-pattern--parse-handle (handle)
  "Parse HANDLE string into (NAMESPACE . VALUE), or signal user-error."
  (unless (stringp handle)
    (user-error "pattern handle must be string, got %S" handle))
  (let ((pos (string-match ":" handle)))
    (unless (and pos (> pos 0) (< pos (1- (length handle))))
      (user-error "pattern handle %S: must be namespace:value" handle))
    (let ((ns (substring handle 0 pos))
          (val (substring handle (1+ pos))))
      (unless (satan-memory-grammar-namespace-world (intern ns))
        (user-error "pattern handle %S: unknown namespace %S" handle ns))
      (unless (satan-memory-grammar-valid-value-p (intern ns) val)
        (user-error "pattern handle %S: invalid value %S for namespace %S"
                    handle val ns))
      (cons ns val))))

(defun satan-pattern--validate-handles (handles pattern-id)
  "Validate every handle in HANDLES (vector or list of strings).
PATTERN-ID is used in error messages.  Returns t on success; signals on failure."
  (let ((hs (if (vectorp handles) (append handles nil) handles)))
    (unless (and (listp hs) (cl-every #'stringp hs))
      (user-error "pattern %S: :cue_handles must be list of strings, got %S"
                  pattern-id handles))
    (dolist (h hs)
      (satan-pattern--parse-handle h)))
  t)

;; ── SQL helpers ─────────────────────────────────────────────────────────────

(defun satan-pattern--quote-text (s)
  "Return the SQL literal for S; nil → NULL."
  (cond
   ((null s) "NULL")
   ((stringp s)
    (concat "'" (replace-regexp-in-string "'" "''" s) "'"))
   (t (error "satan-pattern--quote-text: not stringy: %S" s))))

(defun satan-pattern--quote-jsonb (obj)
  "Serialize OBJ as JSON, wrapping as `'…'::jsonb'.
Converts elisp lists to vectors via `satan-jsonl-prepare' so they
serialize as JSON arrays, matching the pattern used by the intervention
layer."
  (let* ((prepared (satan-jsonl-prepare (if obj obj (vector))))
         (coded (json-serialize prepared
                                :null-object :null
                                :false-object :false)))
    (concat (satan-pattern--quote-text coded) "::jsonb")))

(defun satan-pattern--exec-sql (db sql &optional extra-flags)
  "Run SQL through psql --single-transaction.  Signals on failure."
  (let ((flags (append (or extra-flags '())
                       (list "--single-transaction" "-f" "-"))))
    (pcase (satan-db-psql db satan-memory-migrate-host
                             satan-memory-migrate-psql-program
                             flags sql)
      (`(ok . ,_) nil)
      (`(error . ,msg)
       (user-error "satan-pattern SQL: %s" msg)))))

;; ── sync ────────────────────────────────────────────────────────────────────

(defun satan-pattern--read-file (path)
  "Read PATH as pattern definitions (a flat list of plists); signal on failure.
Reads *every* top-level form and appends them, so the file may be one
`((..) (..))' list or several such forms — nothing is silently dropped.
A `read'-once parser discards every form after the first, which would
quietly retire all but the first pattern in a multi-form file."
  (with-temp-buffer
    (insert-file-contents path)
    (goto-char (point-min))
    (condition-case err
        (let ((forms '()))
          (condition-case nil
              (while t (push (read (current-buffer)) forms))
            (end-of-file nil))
          (apply #'append (nreverse forms)))
      (error
       (user-error "satan-pattern: failed to parse %s: %s" path
                   (error-message-string err))))))

(defun satan-pattern--validate-definition (entry)
  "Validate a single pattern ENTRY (plist).  Signal on failure."
  (let ((id (plist-get entry :id)))
    (unless (and id (stringp id) (not (string-empty-p id)))
      (user-error "pattern entry missing or invalid :id: %S" entry))
    (unless (and (plist-get entry :label) (stringp (plist-get entry :label)))
      (user-error "pattern %S: missing or invalid :label" id))
    (unless (plist-member entry :cue_handles)
      (user-error "pattern %S: missing :cue_handles" id))
    (satan-pattern--validate-handles (plist-get entry :cue_handles) id)
    (unless (or (null (plist-get entry :priority))
                (integerp (plist-get entry :priority)))
      (user-error "pattern %S: :priority must be integer" id))
    id))

(defun satan-pattern--upsert-sql (entry updated-at)
  "Build UPSERT SQL for ENTRY (plist) with UPDATED-AT (ISO8601 string)."
  (concat
   "INSERT INTO satan_patterns ("
   "id, label, cue_handles_json, default_intervention, "
   "intrusion_ceiling, priority, enabled, notes, updated_at) VALUES ("
   (mapconcat #'identity
              (list (satan-pattern--quote-text (plist-get entry :id))
                    (satan-pattern--quote-text (plist-get entry :label))
                    (satan-pattern--quote-jsonb (plist-get entry :cue_handles))
                    (satan-pattern--quote-text (plist-get entry :default_intervention))
                    (satan-pattern--quote-text (plist-get entry :intrusion_ceiling))
                    (number-to-string (or (plist-get entry :priority) 0))
                    (if (plist-get entry :enabled) "true" "false")
                    (satan-pattern--quote-text (plist-get entry :notes))
                    (concat (satan-pattern--quote-text updated-at)
                            "::timestamptz"))
              ", ")
   ") ON CONFLICT (id) DO UPDATE SET "
   "label = EXCLUDED.label, "
   "cue_handles_json = EXCLUDED.cue_handles_json, "
   "default_intervention = EXCLUDED.default_intervention, "
   "intrusion_ceiling = EXCLUDED.intrusion_ceiling, "
   "priority = EXCLUDED.priority, "
   "enabled = EXCLUDED.enabled, "
   "notes = EXCLUDED.notes, "
   "updated_at = EXCLUDED.updated_at;"))

(defun satan-pattern-sync (&optional patterns-file db)
  "Parse PATTERNS-FILE, validate, upsert definitions, soft-retire absent ones.
DB defaults to `satan-memory-migrate-database'.
PATTERNS-FILE defaults to `satan-pattern-file'.
Returns `(:upserted N :retired M)'."
  (let* ((db (or db satan-memory-migrate-database))
         (file (or patterns-file satan-pattern-file))
         (definitions (satan-pattern--read-file file))
         (now (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
         (ids-in-file (make-hash-table :test 'equal)))
    ;; Validate and upsert
    (unless (and (listp definitions) (cl-every #'consp definitions))
      (user-error "patterns.eld must be a list of plists, got %S"
                  (type-of definitions)))
    (let ((upserted 0))
      (dolist (entry definitions)
        (let ((id (satan-pattern--validate-definition entry)))
          (puthash id t ids-in-file)
          (satan-pattern--exec-sql
           db (satan-pattern--upsert-sql entry now))
          (cl-incf upserted)))
      ;; Soft-retire patterns not in file
      (let ((retired 0))
        (cl-loop for p in (satan-pattern-list db)
                 do (unless (gethash (plist-get p :id) ids-in-file)
                      (satan-pattern--exec-sql
                       db (concat
                           "UPDATE satan_patterns SET enabled = false, "
                           "updated_at = "
                           (satan-pattern--quote-text now)
                           "::timestamptz WHERE id = "
                           (satan-pattern--quote-text
                            (plist-get p :id))))
                      (cl-incf retired)))
        (list :upserted upserted :retired retired)))))

;; ── rebuild ─────────────────────────────────────────────────────────────────

(defconst satan-pattern--rebuild-lock-key 900876543
  "Advisory lock key for pattern-outcome rebuild (arbitrary bigint).")

(defun satan-pattern-rebuild (&optional db)
  "Rebuild `satan_pattern_outcomes' projection.
TRUNCATE + INSERT … SELECT containment join: every mature, non-unknown
outcome attributed to every pattern whose cue_handles ⊂ the intervention's
percept snapshot (JSONB @>).  Advisory-locked, single transaction, head-only
\(reads current outcome head-verdict).

Returns `(:matched N)' or signals on DB failure."
  (let* ((db (or db satan-memory-migrate-database))
         (script
          (concat
           ;; Advisory lock to serialize overlapping rebuilds
           (format "SELECT pg_advisory_xact_lock(%d);\n"
                   satan-pattern--rebuild-lock-key)
           "TRUNCATE satan_pattern_outcomes;\n"
           "INSERT INTO satan_pattern_outcomes "
           "(pattern_id, intervention_id, classification, ts)\n"
           "SELECT p.id, i.id, o.classification, i.ts\n"
           "FROM satan_patterns p\n"
           "JOIN satan_interventions i "
           "ON i.percept_handles_json @> p.cue_handles_json\n"
           "JOIN satan_intervention_outcomes o "
           "ON o.intervention_id = i.id\n"
           "WHERE o.maturity = 'mature'\n"
           "  AND o.classification <> 'unknown';\n")))
    (satan-pattern--exec-sql db script)
    ;; Count rows after rebuild
    (let* ((count-sql "SELECT COUNT(*)::text FROM satan_pattern_outcomes")
           (result (satan-db-psql
                    db satan-memory-migrate-host
                    satan-memory-migrate-psql-program
                    (list "-A" "-t" "-c" count-sql))))
      (pcase result
        (`(ok . ,out)
         (list :matched (string-to-number (string-trim out))))
        (`(error . ,msg)
         (user-error "satan-pattern-rebuild count: %s" msg))))))

;; ── read accessors ──────────────────────────────────────────────────────────

(defun satan-pattern--query-with-cols (db cols sql)
  "Run SQL (expecting |-separated rows) and return list of plists.
COLS is a list of column name strings, used as :keyword keys."
  (let ((result (satan-db-psql
                 db satan-memory-migrate-host satan-memory-migrate-psql-program
                 (list "-A" "-t" "-F" "|" "-c" sql)))
        (keys (mapcar (lambda (c) (intern (concat ":" c))) cols)))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string (string-trim out) "\n" t)
                for cells = (split-string line "|")
                when (= (length cells) (length keys))
                collect (cl-mapcan
                         (lambda (k v)
                           (list k (if (string-empty-p v) nil v)))
                         keys cells)))
      (`(error . ,msg)
       (user-error "satan-pattern query: %s" msg)))))

(defun satan-pattern-stats (&optional db)
  "Query `satan_pattern_stats' view.  Returns list of plists."
  (let ((db (or db satan-memory-migrate-database))
        (cols '("pattern_id" "success_count" "ignored_count"
                "contradicted_count" "harmful_count"
                "last_tested_at" "last_outcome")))
    (satan-pattern--query-with-cols
     db cols
     "SELECT * FROM satan_pattern_stats ORDER BY pattern_id")))

(defun satan-pattern-list (&optional db)
  "Return all pattern definitions as plists from `satan_patterns'."
  (let ((db (or db satan-memory-migrate-database))
        (cols '("id" "label" "default_intervention" "intrusion_ceiling"
                "priority" "enabled" "notes")))
    (satan-pattern--query-with-cols
     db cols
     "SELECT id, label, default_intervention, intrusion_ceiling,
             priority, enabled, notes
      FROM satan_patterns ORDER BY priority DESC")))

(defun satan-pattern-scars (&optional pattern-id db)
  "Return scar rows (contradicted/harmful) from `satan_pattern_outcomes'.
If PATTERN-ID is non-nil, filter to that pattern."
  (let ((db (or db satan-memory-migrate-database))
        (cols '("pattern_id" "intervention_id" "classification" "ts")))
    (satan-pattern--query-with-cols
     db cols
     (concat
      "SELECT pattern_id, intervention_id, classification, ts "
      "FROM satan_pattern_outcomes "
      "WHERE classification IN ('contradicted','harmful')"
      (when pattern-id
        (concat " AND pattern_id = "
                (satan-pattern--quote-text pattern-id)))
      " ORDER BY ts DESC"))))

(provide 'satan-pattern)
;;; satan-pattern.el ends here
