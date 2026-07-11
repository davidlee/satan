;;; dl-satan-memory-migrate.el --- SATAN memory migration runner -*- lexical-binding: t; -*-

;; Forward-only numbered SQL migrations for the `satan_memory' PG database.
;; Files live under `dl-satan-memory-migrate-directory' and match
;; `NNNN_<slug>.sql' (four-digit zero-padded version).  Applied state is
;; tracked in the target DB's `schema_migrations' table (created by
;; 0001_init.sql).  The runner refuses to apply a file unless its version
;; equals max(applied) + 1, and refuses to apply if a previously-applied
;; version's on-disk checksum no longer matches what was recorded.
;;
;; Implementation: subprocess to `psql' (R3 decided in memory.design.md
;; §6.1).  Each apply runs as a single transaction containing both the
;; migration body and the `schema_migrations' INSERT, so the bookkeeping
;; row cannot drift from the schema state.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-db)

(defgroup dl-satan-memory nil
  "SATAN memory substrate."
  :group 'dl-satan)

(defcustom dl-satan-memory-migrate-directory
  (expand-file-name "satan/memory/migrations/" user-emacs-directory)
  "Directory containing migration files (`NNNN_<slug>.sql')."
  :type 'directory :group 'dl-satan-memory)

(defcustom dl-satan-memory-migrate-psql-program
  (or (executable-find "psql") "psql")
  "Path to the `psql' binary."
  :type 'string :group 'dl-satan-memory)

(defcustom dl-satan-memory-migrate-host "/run/postgresql"
  "Postgres host or socket directory."
  :type 'string :group 'dl-satan-memory)

(defcustom dl-satan-memory-migrate-database "satan_memory"
  "Default database for migration operations."
  :type 'string :group 'dl-satan-memory)

(defconst dl-satan-memory-migrate--filename-re
  "\\`\\([0-9]\\{4\\}\\)_[a-z0-9][a-z0-9_]*\\.sql\\'"
  "Strict matcher for migration filenames.")

;; ---------- helpers ----------

(defun dl-satan-memory-migrate--parse-filename (basename)
  "Return integer version for BASENAME, or signal `user-error'."
  (let ((case-fold-search nil))
    (if (string-match dl-satan-memory-migrate--filename-re basename)
        (string-to-number (match-string 1 basename))
      (user-error "Bad migration filename: %s" basename))))

(defun dl-satan-memory-migrate--checksum (path)
  "Return SHA-256 hex of PATH's contents."
  (with-temp-buffer
    (set-buffer-multibyte nil)
    (insert-file-contents-literally path)
    (secure-hash 'sha256 (current-buffer))))

(defun dl-satan-memory-migrate--list-files (&optional dir)
  "Return list of (:version V :filename F :path P) for migrations in DIR.
Sorted ascending by version.  Signals on version collision."
  (let* ((dir (or dir dl-satan-memory-migrate-directory))
         (files (and (file-directory-p dir)
                     (directory-files dir nil "\\`[^.].*\\.sql\\'")))
         (rows (mapcar
                (lambda (f)
                  (list :version (dl-satan-memory-migrate--parse-filename f)
                        :filename f
                        :path (expand-file-name f dir)))
                files))
         (sorted (sort rows (lambda (a b) (< (plist-get a :version)
                                             (plist-get b :version))))))
    ;; collision check
    (cl-loop for (a b) on sorted
             when (and b (= (plist-get a :version) (plist-get b :version)))
             do (user-error "Duplicate migration version %d (%s, %s)"
                            (plist-get a :version)
                            (plist-get a :filename)
                            (plist-get b :filename)))
    sorted))

(defun dl-satan-memory-migrate--applied (db)
  "Return applied rows from DB.schema_migrations as plists, sorted asc.
If the table does not exist, return nil."
  (let* ((result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c"
                        (concat "SELECT version, filename, checksum "
                                "FROM schema_migrations ORDER BY version")))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string (string-trim out) "\n" t)
                for parts = (split-string line "|")
                when (= (length parts) 3)
                collect (list :version (string-to-number (nth 0 parts))
                              :filename (nth 1 parts)
                              :checksum (nth 2 parts))))
      (`(error . ,msg)
       (if (string-match-p "relation \"schema_migrations\" does not exist" msg)
           nil
         (user-error "%s" msg))))))

(defun dl-satan-memory-migrate--sql-literal (s)
  "Quote S as a single-quoted SQL literal."
  (concat "'" (replace-regexp-in-string "'" "''" s) "'"))

(defun dl-satan-memory-migrate--apply-one (db row)
  "Apply ROW (plist :version :filename :path) to DB in one transaction.
Includes the body via \\i and inserts the schema_migrations bookkeeping
row in the same transaction."
  (let* ((version  (plist-get row :version))
         (filename (plist-get row :filename))
         (path     (plist-get row :path))
         (checksum (dl-satan-memory-migrate--checksum path))
         (script   (concat
                    (format "\\i %s\n" path)
                    (format "INSERT INTO schema_migrations (version, filename, checksum) VALUES (%d, %s, %s);\n"
                            version
                            (dl-satan-memory-migrate--sql-literal filename)
                            (dl-satan-memory-migrate--sql-literal checksum))))
         ;; Migrations run in one transaction and may legitimately be
         ;; long; they must never be killed.  :timeout-secs nil = unbounded.
         (result   (dl-satan-db-psql
                    db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                    (list "--single-transaction" "-f" "-") script
                    :timeout-secs nil)))
    (pcase result
      (`(ok . ,_) checksum)
      (`(error . ,msg) (user-error "Migration %d (%s) failed: %s"
                                   version filename msg)))))

;; ---------- public ----------

(defun dl-satan-memory-migrate-status (&optional db)
  "Return migration status against DB.
DB defaults to `dl-satan-memory-migrate-database'.
Result is a list of plists:
  (:version V :filename F :status STATUS :checksum C [:expected E])
STATUS is one of `applied', `pending', `tampered', `missing'.
- applied:  on-disk file matches the recorded checksum.
- pending:  on disk, not yet applied.
- tampered: applied checksum differs from on-disk checksum.
- missing:  recorded as applied but no on-disk file."
  (let* ((db        (or db dl-satan-memory-migrate-database))
         (files     (dl-satan-memory-migrate--list-files))
         (applied   (dl-satan-memory-migrate--applied db))
         (by-version (make-hash-table :test 'eql))
         (out '()))
    (dolist (a applied)
      (puthash (plist-get a :version) a by-version))
    (dolist (f files)
      (let* ((v (plist-get f :version))
             (cs (dl-satan-memory-migrate--checksum (plist-get f :path)))
             (rec (gethash v by-version))
             (status (cond
                      ((null rec) 'pending)
                      ((string= (plist-get rec :checksum) cs) 'applied)
                      (t 'tampered))))
        (push (list :version v
                    :filename (plist-get f :filename)
                    :status status
                    :checksum cs
                    :expected (and rec (plist-get rec :checksum)))
              out)
        (remhash v by-version)))
    ;; anything left in by-version is recorded but missing on disk
    (maphash
     (lambda (v rec)
       (push (list :version v
                   :filename (plist-get rec :filename)
                   :status 'missing
                   :checksum nil
                   :expected (plist-get rec :checksum))
             out))
     by-version)
    (sort out (lambda (a b) (< (plist-get a :version) (plist-get b :version))))))

(defun dl-satan-memory-migrate-apply (&optional db)
  "Apply pending migrations to DB.  Return list of applied versions.
Refuses if any migration is tampered or missing, or if pending versions
would skip (must be max(applied)+1, max+2, ...)."
  (let* ((db (or db dl-satan-memory-migrate-database))
         (status (dl-satan-memory-migrate-status db))
         (bad (cl-remove-if-not
               (lambda (e) (memq (plist-get e :status) '(tampered missing)))
               status)))
    (when bad
      (user-error "Cannot apply: %d migration(s) tampered/missing: %s"
                  (length bad)
                  (mapconcat (lambda (e) (format "%04d/%s"
                                                 (plist-get e :version)
                                                 (plist-get e :status)))
                             bad ", ")))
    (let* ((pending (cl-remove-if-not
                     (lambda (e) (eq (plist-get e :status) 'pending))
                     status))
           (applied-max (cl-loop for e in status
                                 when (eq (plist-get e :status) 'applied)
                                 maximize (plist-get e :version))))
      (cl-loop for entry in pending
               for expected = (1+ (or applied-max 0))
               for v = (plist-get entry :version)
               unless (= v expected)
               do (user-error
                   "Migration version gap: next applicable is %d but found %d (%s)"
                   expected v (plist-get entry :filename))
               do (setq applied-max v)
               collect (let* ((file (cl-find v (dl-satan-memory-migrate--list-files)
                                             :key (lambda (r) (plist-get r :version)))))
                        (dl-satan-memory-migrate--apply-one db file)
                        v)))))

;;;###autoload
(defun my/satan-memory-migrate (&optional db)
  "Apply pending SATAN memory migrations.  With prefix arg prompt for DB."
  (interactive
   (list (if current-prefix-arg
             (read-string "Database: " dl-satan-memory-migrate-database)
           dl-satan-memory-migrate-database)))
  (let ((applied (dl-satan-memory-migrate-apply db)))
    (message "satan_memory: applied %d migration(s) %s"
             (length applied) applied)))

;;;###autoload
(defun my/satan-memory-migrate-status (&optional db)
  "Print migration status for DB."
  (interactive
   (list (if current-prefix-arg
             (read-string "Database: " dl-satan-memory-migrate-database)
           dl-satan-memory-migrate-database)))
  (let ((status (dl-satan-memory-migrate-status db)))
    (with-output-to-temp-buffer "*satan-memory-migrate*"
      (princ (format "Database: %s\n\n" db))
      (princ (format "%-7s %-30s %-9s\n" "version" "filename" "status"))
      (princ (make-string 50 ?-)) (princ "\n")
      (dolist (e status)
        (princ (format "%-7d %-30s %-9s\n"
                       (plist-get e :version)
                       (plist-get e :filename)
                       (plist-get e :status)))))))

;; ---------- renormalize (§7 grammar-bump replay) ----------
;;
;; `dl-satan-memory-renormalize' replays the canonicalizer over every
;; trace under a new grammar version, flipping old `trace_handles' rows
;; to `active = FALSE' and inserting the freshly-canonicalized set under
;; the new version.  Per-trace transaction, no-op when the new handle
;; set is byte-identical to the currently-active set (idempotence).
;;
;; Required modules pulled in lazily so this file stays loadable in
;; environments that only need the migrate runner.

(defun dl-satan-memory-renormalize--require ()
  (require 'dl-satan-memory-grammar)
  (require 'dl-satan-memory-canon))

(defun dl-satan-memory-renormalize--mode-from-source (source)
  "Extract mode name from SOURCE shaped `memory_mark@<mode>'.  Else nil."
  (when (and (stringp source)
             (string-match "\\`memory_mark@\\(.+\\)\\'" source))
    (match-string 1 source)))

(defun dl-satan-memory-renormalize--parse-metadata (s)
  "Parse JSONB text S into a plist; nil for empty input."
  (and (stringp s)
       (not (string-empty-p s))
       (condition-case _err
           (json-parse-string s
                              :object-type 'plist
                              :array-type 'list
                              :null-object nil
                              :false-object :false)
         (error nil))))

(defun dl-satan-memory-renormalize--fetch-traces (db)
  "Return list of (:trace_id :observed_end_at :source :metadata_json
:active_handles), one row per trace, sorted by trace_id ascending."
  (let* ((sql
          (concat
           "SELECT t.id, "
           "       to_char(t.observed_end_at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SSOF'), "
           "       t.source, "
           "       t.metadata_json::text, "
           "       COALESCE(("
           "         SELECT string_agg(th.handle, ',' ORDER BY th.handle) "
           "         FROM trace_handles th "
           "         WHERE th.trace_id = t.id AND th.active), '') "
           "FROM traces t "
           "ORDER BY t.id"))
         ;; Bulk scan of every trace row (metadata_json::text) for the
         ;; renormalize migration — legitimately long, never killed.
         ;; Explicit nil INPUT before the keyword so `:timeout-secs' is not
         ;; swallowed by the `&optional input' slot.
         (result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "\t" "-c" sql) nil
                  :timeout-secs nil)))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for parts = (split-string line "\t")
                when (>= (length parts) 5)
                collect
                (list :trace_id        (nth 0 parts)
                      :observed_end_at (nth 1 parts)
                      :source          (nth 2 parts)
                      :metadata_json   (nth 3 parts)
                      :active_handles
                      (split-string (nth 4 parts) "," t))))
      (`(error . ,msg) (user-error "%s" msg)))))

(defun dl-satan-memory-renormalize--build-ctx (row version)
  "Build the canon ctx plist for ROW under VERSION."
  (list :current_grammar_version version
        :mode_name (dl-satan-memory-renormalize--mode-from-source
                    (plist-get row :source))
        :time_now (plist-get row :observed_end_at)
        :run_id nil
        :run_started_at nil))

(defun dl-satan-memory-renormalize--source-jsonb (source grammar-version)
  "Serialise SOURCE plist as a JSON string for trace_handles.source."
  (let ((sanitized
         (list :rule_id  (or (plist-get source :rule_id) :null)
               :origin   (or (plist-get source :origin) :null)
               :evidence_pointer
               (or (plist-get source :evidence_pointer) :null)
               :hint_field
               (or (plist-get source :hint_field) :null)
               :confidence
               (or (plist-get source :confidence) 1.0)
               :grammar_version grammar-version)))
    (json-serialize sanitized)))

(defun dl-satan-memory-renormalize--apply-sql (row version canon)
  "Build the single-trace transaction SQL for ROW at VERSION."
  (let* ((tid (plist-get row :trace_id))
         (handles (plist-get canon :handles))
         (sources (plist-get canon :handle_sources))
         (tid-lit (dl-satan-memory-migrate--sql-literal tid))
         (rows
          (mapconcat
           (lambda (h)
             (let* ((src (cdr (assoc h sources)))
                    (json (dl-satan-memory-renormalize--source-jsonb
                           src version)))
               (format "(%s,%d::smallint,%s,%s::jsonb,TRUE)"
                       tid-lit
                       version
                       (dl-satan-memory-migrate--sql-literal h)
                       (dl-satan-memory-migrate--sql-literal json))))
           handles
           ",")))
    (concat
     "BEGIN;\n"
     (format
      "UPDATE trace_handles SET active = FALSE WHERE trace_id = %s AND active AND grammar_version < %d::smallint;\n"
      tid-lit version)
     (if (string-empty-p rows)
         ""
       (format
        "INSERT INTO trace_handles (trace_id, grammar_version, handle, source, active) VALUES %s;\n"
        rows))
     "COMMIT;\n")))

(defun dl-satan-memory-renormalize--one (db version row)
  "Renormalize ROW at VERSION.  Returns `updated' or `skipped'.
Signals on canon error or SQL failure (caller frames each trace in
its own condition-case)."
  (let* ((metadata (dl-satan-memory-renormalize--parse-metadata
                    (plist-get row :metadata_json)))
         (evidence (plist-get metadata :evidence))
         (raw-hints (plist-get metadata :hints))
         (ctx (dl-satan-memory-renormalize--build-ctx row version))
         (canon (dl-satan-memory-canon-canonicalize-from-raw
                 evidence raw-hints ctx))
         (new-handles (sort (copy-sequence (plist-get canon :handles))
                            #'string<))
         (current (sort (copy-sequence (plist-get row :active_handles))
                        #'string<)))
    (if (equal new-handles current)
        'skipped
      (let* ((sql (dl-satan-memory-renormalize--apply-sql row version canon))
             ;; Per-trace renormalize write — part of the migration path,
             ;; never killed.  :timeout-secs nil = unbounded.
             (result (dl-satan-db-psql db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program (list "-f" "-") sql
                                       :timeout-secs nil)))
        (pcase result
          (`(ok . ,_) 'updated)
          (`(error . ,msg)
           (error "renormalize failed for %s: %s"
                  (plist-get row :trace_id) msg)))))))

(defun dl-satan-memory-renormalize (&optional db version)
  "Replay canonicalization for every trace under VERSION.
DB defaults to `dl-satan-memory-migrate-database'; VERSION to the
current elisp grammar version.  Returns
  (:updated N :skipped N :failed LIST)
where LIST entries are (:trace_id ID :error MSG).  Idempotent: a
no-op pass touches zero rows."
  (dl-satan-memory-renormalize--require)
  (let* ((db (or db dl-satan-memory-migrate-database))
         (version (or version dl-satan-memory-grammar-current-version))
         (rows (dl-satan-memory-renormalize--fetch-traces db))
         (updated 0)
         (skipped 0)
         failed)
    (dolist (row rows)
      (condition-case err
          (pcase (dl-satan-memory-renormalize--one db version row)
            ('updated (cl-incf updated))
            ('skipped (cl-incf skipped)))
        (error
         (push (list :trace_id (plist-get row :trace_id)
                     :error (error-message-string err))
               failed))))
    (list :updated updated :skipped skipped :failed (nreverse failed))))

(defun dl-satan-memory-renormalize-status (&optional db)
  "Read-only summary of trace_handles activity per grammar_version.
DB defaults to `dl-satan-memory-migrate-database'.  Returns plist
  (:by-version ((1 . N1) (2 . N2) ...) :stale-traces M)
where a trace is stale when the newest active-handle row's
grammar_version is below the current elisp grammar version."
  (dl-satan-memory-renormalize--require)
  (let* ((db (or db dl-satan-memory-migrate-database))
         (current dl-satan-memory-grammar-current-version)
         (sql
          (concat
           "WITH per_trace AS ("
           "  SELECT trace_id, MAX(grammar_version) AS gv "
           "  FROM trace_handles WHERE active GROUP BY trace_id"
           ") "
           "SELECT 'by_version'::text, gv::text, COUNT(*)::text "
           "FROM per_trace GROUP BY gv "
           "UNION ALL "
           "SELECT 'stale'::text, ''::text, COUNT(*)::text "
           "FROM per_trace WHERE gv < "
           (number-to-string current)))
         (result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "\t" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (let (by-version stale)
         (dolist (line (split-string out "\n" t))
           (let ((parts (split-string line "\t")))
             (pcase (nth 0 parts)
               ("by_version"
                (push (cons (string-to-number (nth 1 parts))
                            (string-to-number (nth 2 parts)))
                      by-version))
               ("stale"
                (setq stale (string-to-number (nth 2 parts)))))))
         (list :by-version
               (sort by-version (lambda (a b) (< (car a) (car b))))
               :stale-traces (or stale 0))))
      (`(error . ,msg) (user-error "%s" msg)))))

;;;###autoload
(defun my/satan-memory-renormalize (&optional db)
  "Replay canonicalization against the current grammar version.
With prefix arg, prompt for DB."
  (interactive
   (list (if current-prefix-arg
             (read-string "Database: " dl-satan-memory-migrate-database)
           dl-satan-memory-migrate-database)))
  (let* ((before (dl-satan-memory-renormalize-status db))
         (result (dl-satan-memory-renormalize db))
         (after  (dl-satan-memory-renormalize-status db)))
    (message
     "renormalize: %d updated, %d skipped, %d failed; active by version: %S -> %S"
     (plist-get result :updated)
     (plist-get result :skipped)
     (length (plist-get result :failed))
     (plist-get before :by-version)
     (plist-get after :by-version))
    result))

(provide 'dl-satan-memory-migrate)
;;; dl-satan-memory-migrate.el ends here
