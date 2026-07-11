;;; satan-patch-store.el --- DB-backed patch-job store -*- lexical-binding: t; -*-

;; Phase 1.2 of satan/patch-harness.plan.md.  Transactional storage for
;; the patch-agent job table introduced by migration 0005.  Surfaces:
;;
;;   `satan-patch-store-insert'         insert one queued job
;;   `satan-patch-store-get'            fetch one job by id
;;   `satan-patch-store-list'           filter by state, limit
;;   `satan-patch-store-update-state'   transition state + fields
;;   `satan-patch-store-claim-next'     atomic queued -> claimed
;;   `satan-patch-store-event'          append-only event log
;;
;; Implementation: subprocess to `psql', same as `satan-memory-store'.
;; State transitions are validated server-side by the CHECK constraint
;; on the `state' column.  `claim-next' uses FOR UPDATE SKIP LOCKED so
;; multiple runners are safe even though v1 ships only one.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-db)
(require 'satan-jsonl)

(defgroup satan-patch nil
  "SATAN patch-agent."
  :group 'satan)

(defcustom satan-patch-store-database "satan_memory"
  "Production database holding the patch_jobs table."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-store-host "/run/postgresql"
  "Postgres host or socket directory."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-store-psql-program
  (or (executable-find "psql") "psql")
  "Path to the `psql' binary."
  :type 'string :group 'satan-patch)

(defconst satan-patch-store--id-charset
  "abcdefghijklmnopqrstuvwxyz0123456789")

(defconst satan-patch-store--terminal-states
  '("needs_review" "failed" "cancelled" "accepted_external" "stale")
  "States from which no further automated transition occurs.")

;; ---------------------------------------------------------------------
;; id minting
;; ---------------------------------------------------------------------

(defun satan-patch-store-job-id-new (time-iso &optional rand-fn)
  "Build `patch_YYYYMMDDTHHMMSS_<4char>' from TIME-ISO.
RAND-FN is an optional thunk returning the suffix for testability;
defaults to a 4-char base36 random string."
  (let* ((stamp (format-time-string "%Y%m%dT%H%M%S"
                                    (date-to-time time-iso)))
         (suffix (if rand-fn
                     (funcall rand-fn)
                   (cl-loop with s = (make-string 4 ?a)
                            for i below 4
                            do (aset s i
                                     (aref satan-patch-store--id-charset
                                           (random 36)))
                            finally return s))))
    (format "patch_%s_%s" stamp suffix)))

;; ---------------------------------------------------------------------
;; psql plumbing
;; ---------------------------------------------------------------------

;; ---------------------------------------------------------------------
;; row parsing
;; ---------------------------------------------------------------------

(defconst satan-patch-store--row-columns
  '(id state mode directive repo base_ref branch worktree_path adapter
       created_at updated_at started_at finished_at
       source_json context_json allowed_paths_json checks_json
       result_json error_json)
  "Column ordering matched by `--row-select' and `--parse-row'.")

(defun satan-patch-store--row-select (&optional prefix)
  "Comma-separated column list for SELECT, optionally PREFIX-qualified.
PREFIX is a SQL alias like \"p\" (no trailing dot)."
  (let ((p (if prefix (concat prefix ".") "")))
    (mapconcat
     (lambda (col)
       (pcase col
         ((or 'created_at 'updated_at 'started_at 'finished_at)
          (format
           "COALESCE(to_char(%s%s AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SSOF'),'')"
           p col))
         ((or 'source_json 'context_json 'allowed_paths_json
              'checks_json 'result_json 'error_json)
          (format "COALESCE(%s%s::text,'')" p col))
         (_ (format "COALESCE(%s%s,'')" p col))))
     satan-patch-store--row-columns
     ",")))

(defun satan-patch-store--parse-json-or-nil (s)
  (cond
   ((or (null s) (string-empty-p s)) nil)
   (t (condition-case _err
          (json-parse-string s
                             :object-type 'plist
                             :array-type 'list
                             :null-object nil
                             :false-object :false)
        (error nil)))))

(defun satan-patch-store--parse-row (line)
  "Parse a tab-separated LINE into a job plist."
  (let* ((parts (split-string line "\t"))
         (plist '()))
    (cl-loop
     for col in satan-patch-store--row-columns
     for v in parts
     do (setq plist
              (plist-put plist (intern (concat ":" (symbol-name col)))
                         (pcase col
                           ((or 'source_json 'context_json 'allowed_paths_json
                                'checks_json 'result_json 'error_json)
                            (satan-patch-store--parse-json-or-nil v))
                           (_ (if (string-empty-p v) nil v))))))
    plist))

;; ---------------------------------------------------------------------
;; insert
;; ---------------------------------------------------------------------

(cl-defun satan-patch-store-insert
    (&key job-id mode directive
          repo base_ref branch worktree_path
          (adapter "pi")
          (state "queued")
          source context allowed_paths checks
          (db satan-patch-store-database))
  "Insert one patch job row.  Returns (ok . JOB-ID) or (error . MSG).
Required: MODE, DIRECTIVE, REPO, BASE_REF, BRANCH, WORKTREE_PATH,
ALLOWED_PATHS (list of repo-relative strings).
Optional: JOB-ID (else minted from current time), STATE (default
\"queued\"), ADAPTER (default \"pi\"), SOURCE, CONTEXT, CHECKS."
  (unless (and mode directive repo base_ref branch worktree_path allowed_paths)
    (error "satan-patch-store-insert: missing required field"))
  (let* ((now (format-time-string "%Y-%m-%dT%H:%M:%S%z"))
         (id (or job-id (satan-patch-store-job-id-new now)))
         ;; CTE fires NOTIFY in the same transaction as the INSERT so the
         ;; satan-patcher daemon's LISTEN sees the new row without polling.
         ;; If pg_notify raises (rare), the row rolls back too -- daemon's
         ;; idle-tick fallback is independent.
         (sql (concat
               "WITH ins AS ("
               " INSERT INTO patch_jobs ("
               "  id, state, mode, directive, repo, base_ref, branch,"
               "  worktree_path, adapter, source_json, context_json,"
               "  allowed_paths_json, checks_json"
               " ) VALUES ("
               "  :'id', :'state', :'mode', :'directive',"
               "  :'repo', :'base_ref', :'branch', :'worktree_path',"
               "  :'adapter',"
               "  :'source'::jsonb, :'context'::jsonb,"
               "  :'allowed'::jsonb, :'checks'::jsonb"
               " ) RETURNING id, state"
               ") "
               "SELECT CASE WHEN state = 'queued' "
               "            THEN pg_notify('patch_jobs_new', id) END "
               "FROM ins"))
         (vars `(("id"            . ,id)
                 ("state"         . ,state)
                 ("mode"          . ,mode)
                 ("directive"     . ,directive)
                 ("repo"          . ,repo)
                 ("base_ref"      . ,base_ref)
                 ("branch"        . ,branch)
                 ("worktree_path" . ,worktree_path)
                 ("adapter"       . ,adapter)
                 ("source"        . ,(json-serialize (satan-jsonl-prepare (or source '()))))
                 ("context"       . ,(json-serialize (satan-jsonl-prepare (or context '()))))
                 ("allowed"       . ,(json-serialize (satan-jsonl-prepare (or allowed_paths '()))))
                 ("checks"        . ,(json-serialize (satan-jsonl-prepare (or checks '()))))))
         (result (satan-db-query db satan-patch-store-host satan-patch-store-psql-program sql vars
                                    :label "patch.enqueue")))
    (pcase result
      (`(ok . ,_) (cons 'ok id))
      (err err))))

;; ---------------------------------------------------------------------
;; get / list
;; ---------------------------------------------------------------------

(cl-defun satan-patch-store-get
    (job-id &key (db satan-patch-store-database))
  "Fetch one job by JOB-ID.
Returns (ok . PLIST) or (ok . nil) if missing, or (error . MSG)."
  (let* ((sql (format "SELECT %s FROM patch_jobs WHERE id = :'id'"
                      (satan-patch-store--row-select)))
         (result (satan-db-query
                  db satan-patch-store-host satan-patch-store-psql-program
                  sql `(("id" . ,job-id)))))
    (pcase result
      (`(ok . ,out)
       (cond
        ((string-empty-p out) (cons 'ok nil))
        (t (cons 'ok (satan-patch-store--parse-row out)))))
      (err err))))

(cl-defun satan-patch-store-list
    (&key state (limit 50) (db satan-patch-store-database))
  "List jobs filtered by optional STATE, sorted by created_at DESC.
Returns (ok . LIST) or (error . MSG)."
  (let* ((where (if state " WHERE state = :'state'" ""))
         (sql (format "SELECT %s FROM patch_jobs%s ORDER BY created_at DESC LIMIT %d"
                      (satan-patch-store--row-select)
                      where
                      limit))
         (vars (if state `(("state" . ,state)) nil))
         (result (satan-db-query db satan-patch-store-host satan-patch-store-psql-program sql vars)))
    (pcase result
      (`(ok . ,out)
       (cons 'ok
             (cl-loop for line in (split-string out "\n" t)
                      collect (satan-patch-store--parse-row line))))
      (err err))))

;; ---------------------------------------------------------------------
;; update-state
;; ---------------------------------------------------------------------

(defconst satan-patch-store--updatable-fields
  '(:started_at :finished_at :result :error :worktree_path :branch)
  "Fields `update-state' accepts in addition to the new state.
:result and :error are serialised to JSONB; timestamps go through
as ISO strings; the rest as text.")

(cl-defun satan-patch-store-update-state
    (job-id new-state &rest fields
            &key (db satan-patch-store-database) &allow-other-keys)
  "Transition JOB-ID to NEW-STATE, optionally setting FIELDS.
FIELDS is a plist whose recognised keys are listed in
`satan-patch-store--updatable-fields'.  :result and :error are
serialised to JSONB; everything else is text.

The CHECK constraint enforces valid states server-side.  Returns
\(ok . JOB-ID) or (error . MSG)."
  (cl-remf fields :db)
  (let* ((sets (list "state = :'state'"))
         (vars `(("id" . ,job-id) ("state" . ,new-state))))
    (cl-loop for (k v) on fields by #'cddr
             when (memq k satan-patch-store--updatable-fields)
             do
             (let ((name (substring (symbol-name k) 1)))  ; strip leading `:'
               (pcase k
                 ((or :result :error)
                  (let ((col (if (eq k :result) "result_json" "error_json")))
                    (push (format "%s = :'%s'::jsonb" col name) sets)
                    (push (cons name (json-serialize (satan-jsonl-prepare v))) vars)))
                 ((or :started_at :finished_at)
                  (push (format "%s = :'%s'::timestamptz" name name) sets)
                  (push (cons name v) vars))
                 (_
                  (push (format "%s = :'%s'" name name) sets)
                  (push (cons name v) vars)))))
    (let* ((sql (format "UPDATE patch_jobs SET %s WHERE id = :'id'"
                        (mapconcat #'identity (nreverse sets) ", ")))
           (result (satan-db-query db satan-patch-store-host satan-patch-store-psql-program sql vars)))
      (pcase result
        (`(ok . ,_) (cons 'ok job-id))
        (err err)))))

;; ---------------------------------------------------------------------
;; claim-next
;; ---------------------------------------------------------------------

(cl-defun satan-patch-store-claim-next
    (&key (db satan-patch-store-database))
  "Atomically transition the oldest `queued' job to `claimed'.
Returns (ok . PLIST) for the claimed row, (ok . nil) when no job
is queued, or (error . MSG).  Safe under concurrent runners via
FOR UPDATE SKIP LOCKED."
  (let* ((sql
          (concat
           "WITH claimed AS ("
           "  SELECT id FROM patch_jobs "
           "  WHERE state = 'queued' "
           "  ORDER BY created_at ASC "
           "  LIMIT 1 FOR UPDATE SKIP LOCKED"
           ") "
           "UPDATE patch_jobs p "
           "SET state = 'claimed', started_at = NOW() "
           "FROM claimed c "
           "WHERE p.id = c.id "
           "RETURNING " (satan-patch-store--row-select "p")))
         (result (satan-db-query db satan-patch-store-host satan-patch-store-psql-program sql nil)))
    (pcase result
      (`(ok . ,out)
       (cond
        ((string-empty-p out) (cons 'ok nil))
        (t (cons 'ok (satan-patch-store--parse-row out)))))
      (err err))))

;; ---------------------------------------------------------------------
;; event log
;; ---------------------------------------------------------------------

(cl-defun satan-patch-store-event
    (job-id kind payload &key (db satan-patch-store-database))
  "Append one event row.  KIND is short text (transition|log|warning|check).
PAYLOAD is any JSON-serialisable plist or list.  Returns (ok . nil)
or (error . MSG)."
  (let* ((sql (concat
               "INSERT INTO patch_job_events (job_id, kind, payload) "
               "VALUES (:'id', :'kind', :'payload'::jsonb)"))
         (vars `(("id"      . ,job-id)
                 ("kind"    . ,kind)
                 ("payload" . ,(json-serialize (satan-jsonl-prepare
                                (or payload '()))))))
         (result (satan-db-query db satan-patch-store-host satan-patch-store-psql-program sql vars)))
    (pcase result
      (`(ok . ,_) (cons 'ok nil))
      (err err))))

(cl-defun satan-patch-store-events
    (job-id &key (limit 200) (db satan-patch-store-database))
  "Return chronological event log for JOB-ID up to LIMIT entries.
Returns (ok . LIST) of plists (:id N :at ISO :kind STR :payload PLIST)
or (error . MSG)."
  (let* ((sql (concat
               "SELECT id::text, "
               "to_char(at AT TIME ZONE 'UTC', 'YYYY-MM-DD\"T\"HH24:MI:SSOF'),"
               " kind, payload::text "
               "FROM patch_job_events "
               "WHERE job_id = :'id' "
               "ORDER BY at ASC, id ASC "
               (format "LIMIT %d" limit)))
         (result (satan-db-query
                  db satan-patch-store-host satan-patch-store-psql-program
                  sql `(("id" . ,job-id)))))
    (pcase result
      (`(ok . ,out)
       (cons 'ok
             (cl-loop for line in (split-string out "\n" t)
                      for parts = (split-string line "\t")
                      when (= 4 (length parts))
                      collect
                      (list :id      (string-to-number (nth 0 parts))
                            :at      (nth 1 parts)
                            :kind    (nth 2 parts)
                            :payload (satan-patch-store--parse-json-or-nil
                                      (nth 3 parts))))))
      (err err))))

;; ---------------------------------------------------------------------
;; shared review-commands builder (used by tools-patch + patch-runner)
;; ---------------------------------------------------------------------

(defun satan-patch--build-review-commands (row &optional commits)
  "Build suggested review shell commands for ROW.
COMMITS, when nil, is extracted from ROW's `:result_json'.
Returns nil until the job has produced commits — a queued job has
nothing to review."
  (let* ((repo (plist-get row :repo))
         (base (plist-get row :base_ref))
         (branch (plist-get row :branch))
         ;; If commits not provided, extract from result_json
         (commits (or commits
                      (let ((result (plist-get row :result_json)))
                        (and result (plist-get result :commits))))))
    (when (and repo base branch (consp commits))
      (let ((cmds (list (format "git -C %s diff %s...%s" repo base branch)
                        (format "git -C %s log %s..%s" repo base branch)))
            (sha (plist-get (car commits) :sha)))
        (if sha
            (append cmds (list (format "git -C %s cherry-pick %s" repo sha)))
          cmds)))))

(provide 'satan-patch-store)
;;; satan-patch-store.el ends here
