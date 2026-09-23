;;; satan-intervention.el --- intervention projection rebuild + API -*- lexical-binding: t; -*-

;; T7 — first-class intervention records.
;;
;; This module owns the projection of intervention audit-events into
;; the `satan_interventions' / `satan_intervention_outcomes' tables
;; created by migration 0006_interventions.sql.  The audit log
;; (transcript.jsonl per run) is the source of truth; the tables are
;; rebuildable.
;;
;; PR 2 lands the rebuild CLI:
;;   - `satan-intervention-rebuild' replays every intervention event
;;     across all runs into the projection in (ts, run-id, seq) order.
;;     Idempotent: a second rebuild yields byte-identical rows.
;;   - `satan-rebuild-interventions' is the interactive command;
;;     `satan/bin/satan-rebuild-interventions' is the CLI wrapper.
;;
;; PR 3 adds the write/read API used by handlers and the observer.  Each
;; write is split (SL-017 DEC-018) into a RECORD half — validate and append
;; to the run's transcript.jsonl, no database — and a PROJECT half that
;; writes Postgres.  The composed functions keep their original contracts:
;;
;;   (satan-intervention-record &key CTX KIND TARGET-SURFACE MESSAGE
;;                                      RELATED-MOTIVE-ID CUE-HANDLES
;;                                      EXPECTED-OUTCOME OUTCOME-WINDOW-MINUTES
;;                                      SEVERITY)
;;     Mint a stable `<run-id>.iv<NNN>' id and emit `intervention.created'.
;;     Returns the payload plist.
;;   (satan-intervention-project PAYLOAD &key DB)
;;     INSERT into `satan_interventions' (ON CONFLICT DO NOTHING).
;;   (satan-intervention-create &key CTX ... DB)
;;     record then project.  Returns the intervention-id string.
;;
;;   (satan-intervention-classify-record &key CTX INTERVENTION-ID REVISION-P
;;                                               CLASSIFICATION CONFIDENCE
;;                                               EVIDENCE MATURITY
;;                                               NEXT-REVISIT-AT SOURCE
;;                                               CLASSIFIED-AT MARKED-BY NOTES)
;;     Emit `intervention.outcome_classified', or `intervention.outcome_revised'
;;     (with `:revises' set to the intervention-id) when REVISION-P.
;;     Returns the payload plist.
;;   (satan-intervention-classify-project PAYLOAD &key DB)
;;     UPSERT into `satan_intervention_outcomes'.
;;   (satan-intervention-classify &key CTX INTERVENTION-ID ... DB)
;;     lookup (REVISION-P = a prior outcome row exists), classify-record,
;;     classify-project, attribute enqueue.  Returns the event-name string
;;     or signals on validation/DB failure.
;;
;;   (satan-intervention-lookup INTERVENTION-ID &optional DB)
;;     Return `(:intervention <row-plist> :outcome <row-plist-or-nil>)' or nil.
;;
;;   (satan-intervention-pending NOW &optional DB)
;;     Return list of intervention plists whose maturity window has elapsed
;;     and which have no outcome row.  NOW is an ISO8601 string.
;;
;; **Transaction discipline:** the record is canonical and always comes
;; first; each projection write is a separate psql round-trip.  A record
;; whose projection failed is recoverable via `satan-rebuild-interventions'.
;; A caller whose side effect must be recorded before it happens (notify)
;; calls the record half, acts, then projects — so a Postgres outage can
;; never suppress the act (I3).

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-audit)             ; validators + closed-set constants
(require 'satan-jsonl)              ; prepare arrays/alists for json-serialize
(require 'satan-memory-migrate)    ; psql runner + database defcustoms
(require 'satan-memory-grammar)    ; grammar-current-version (counter-memory)
(require 'satan-memory-store)      ; memory-store-mark (counter-memory)
(require 'satan-attribute)         ; outcome → satan_outcome_inbox enqueue

;; ---------- runs-dir resolution ----------

(defun satan-intervention--runs-dir (&optional override)
  "Return the runs root directory.  OVERRIDE wins; else `satan-runs-dir'."
  (or override
      (and (boundp 'satan-runs-dir) satan-runs-dir)
      (user-error
       "satan-intervention: no runs-dir (set `satan-runs-dir' or pass override)")))

(defun satan-intervention--transcript-files (runs-dir)
  "Return sorted list of transcript.jsonl paths under RUNS-DIR.
Walks YYYY-MM-DD/<run-id>/ buckets; flat runs/<run-id>/ also supported."
  (let ((acc '()))
    (dolist (entry (and (file-directory-p runs-dir)
                        (directory-files runs-dir t "\\`[^.]" t)))
      (when (file-directory-p entry)
        (let ((direct (expand-file-name "transcript.jsonl" entry)))
          (if (file-readable-p direct)
              (push direct acc)
            (dolist (sub (and (file-directory-p entry)
                              (directory-files entry t "\\`[^.]" t)))
              (let ((p (expand-file-name "transcript.jsonl" sub)))
                (when (file-readable-p p) (push p acc))))))))
    (sort acc #'string<)))

;; ---------- transcript reader ----------



(defun satan-intervention--run-id-from-path (path)
  "Derive a run-id from PATH (parent directory name)."
  (file-name-nondirectory
   (directory-file-name (file-name-directory path))))

(defun satan-intervention--collect-events (runs-dir)
  "Collect every intervention event under RUNS-DIR.
Returns a list of plists with keys (:ts :event :payload :run_id :seq :path).
SEQ is the within-file record index, used as a tiebreaker."
  (let (out)
    (dolist (path (satan-intervention--transcript-files runs-dir))
      (let ((records (satan-jsonl-read-file path :null-object :null))
            (file-run-id (satan-intervention--run-id-from-path path))
            (seq 0))
        (dolist (rec records)
          (let ((event (plist-get rec :event)))
            (when (member event satan-audit-intervention-events)
              (push (list :ts      (plist-get rec :ts)
                          :event   event
                          :payload (plist-get rec :payload)
                          :run_id  file-run-id
                          :seq     seq
                          :path    path)
                    out)))
          (cl-incf seq))))
    (nreverse out)))

(defun satan-intervention--sort-events (events)
  "Order EVENTS by (ts, run_id, seq) ascending."
  (sort (copy-sequence events)
        (lambda (a b)
          (let ((ta (plist-get a :ts)) (tb (plist-get b :ts)))
            (cond
             ((string< ta tb) t)
             ((string< tb ta) nil)
             (t
              (let ((ra (plist-get a :run_id)) (rb (plist-get b :run_id)))
                (cond
                 ((string< ra rb) t)
                 ((string< rb ra) nil)
                 (t (< (plist-get a :seq) (plist-get b :seq)))))))))))

;; ---------- SQL generation ----------

(defun satan-intervention--quote-text (s)
  "Return the SQL literal for S; supports NULL via nil/:null."
  (cond
   ((or (null s) (eq s :null)) "NULL")
   ((stringp s)
    (concat "'" (replace-regexp-in-string "'" "''" s) "'"))
   (t (error "satan-intervention--quote-text: not stringy: %S" s))))

(defun satan-intervention--quote-jsonb (obj)
  "Serialize OBJ as JSON then wrap as an SQL literal `'…'::jsonb'.
Runs OBJ through `satan-jsonl-prepare' so post-JSON-parse lists
become vectors before serialization."
  (let* ((prepared (satan-jsonl-prepare (or obj :null)))
         (coded (json-serialize prepared
                                :null-object :null
                                :false-object :false)))
    (concat (satan-intervention--quote-text coded) "::jsonb")))

(defun satan-intervention--insert-created-sql (payload)
  "Return SQL INSERT for an intervention.created PAYLOAD."
  (concat
   "INSERT INTO satan_interventions ("
   "id, run_id, ts, mode, kind, target_surface, message, "
   "related_motive_id, cue_handles_json, percept_handles_json, "
   "expected_outcome, outcome_window_minutes, severity) VALUES ("
   (mapconcat
    #'identity
    (list (satan-intervention--quote-text (plist-get payload :intervention_id))
          (satan-intervention--quote-text (plist-get payload :run_id))
          (concat (satan-intervention--quote-text (plist-get payload :ts))
                  "::timestamptz")
          (satan-intervention--quote-text (plist-get payload :mode))
          (satan-intervention--quote-text (plist-get payload :kind))
          (satan-intervention--quote-text (plist-get payload :target_surface))
          (satan-intervention--quote-text (plist-get payload :message))
          (satan-intervention--quote-text (plist-get payload :related_motive_id))
          (satan-intervention--quote-jsonb (or (plist-get payload :cue_handles) (vector)))
          (satan-intervention--quote-jsonb (or (plist-get payload :percept_handles) (vector)))
          (satan-intervention--quote-text (plist-get payload :expected_outcome))
          (number-to-string (plist-get payload :outcome_window_minutes))
          (satan-intervention--quote-text (plist-get payload :severity)))
    ", ")
   ") ON CONFLICT (id) DO NOTHING;"))

(defun satan-intervention--upsert-outcome-sql (payload)
  "Return SQL UPSERT for an outcome_classified / outcome_revised PAYLOAD."
  (concat
   "INSERT INTO satan_intervention_outcomes ("
   "intervention_id, classification, confidence, evidence_json, "
   "maturity, next_revisit_at, source, classified_at, revises, "
   "marked_by, notes) VALUES ("
   (mapconcat
    #'identity
    (list (satan-intervention--quote-text (plist-get payload :intervention_id))
          (satan-intervention--quote-text (plist-get payload :classification))
          (satan-intervention--quote-text (plist-get payload :confidence))
          (satan-intervention--quote-jsonb (plist-get payload :evidence))
          (satan-intervention--quote-text (plist-get payload :maturity))
          (concat (satan-intervention--quote-text
                   (plist-get payload :next_revisit_at))
                  "::timestamptz")
          (satan-intervention--quote-text (plist-get payload :source))
          (concat (satan-intervention--quote-text
                   (plist-get payload :classified_at))
                  "::timestamptz")
          (satan-intervention--quote-text (plist-get payload :revises))
          (satan-intervention--quote-text (plist-get payload :marked_by))
          (satan-intervention--quote-text (plist-get payload :notes)))
    ", ")
   ") ON CONFLICT (intervention_id) DO UPDATE SET "
   "classification = EXCLUDED.classification, "
   "confidence = EXCLUDED.confidence, "
   "evidence_json = EXCLUDED.evidence_json, "
   "maturity = EXCLUDED.maturity, "
   "next_revisit_at = EXCLUDED.next_revisit_at, "
   "source = EXCLUDED.source, "
   "classified_at = EXCLUDED.classified_at, "
   "revises = EXCLUDED.revises, "
   "marked_by = EXCLUDED.marked_by, "
   "notes = EXCLUDED.notes;"))

(defun satan-intervention--transaction-sql (statements)
  "Return SQL STATEMENTS wrapped in one `BEGIN; … COMMIT;' transaction."
  (mapconcat #'identity `("BEGIN;" ,@statements "COMMIT;") "\n"))

(defun satan-intervention--build-rebuild-script (events)
  "Build the full rebuild transaction SQL for EVENTS (already sorted).
Wraps TRUNCATE + per-event INSERT/UPSERT in a single transaction."
  (satan-intervention--transaction-sql
   (cons "TRUNCATE satan_intervention_outcomes, satan_interventions RESTART IDENTITY;"
         (mapcar
          (lambda (ev)
            (let ((payload (plist-get ev :payload)))
              (pcase (plist-get ev :event)
                ("intervention.created"
                 (satan-intervention--insert-created-sql payload))
                ((or "intervention.outcome_classified"
                     "intervention.outcome_revised")
                 (satan-intervention--upsert-outcome-sql payload)))))
          events))))

;; ---------- public rebuild ----------

(defun satan-intervention-rebuild (&optional db runs-dir)
  "Replay every intervention audit-event under RUNS-DIR into the projection.
DB defaults to `satan-memory-migrate-database'; RUNS-DIR defaults
to `satan-runs-dir'.  Returns a plist:

  (:total N
   :created M
   :outcomes K
   :events EVENTS-LIST
   :validation-error (:idx N :reason STR)?)

On validation failure, the projection is left untouched and the
validation error is returned in the plist (no signal).  Idempotent:
a second invocation against the same audit log yields identical
projection rows.

Streams the entire script through one `psql --single-transaction'
invocation; on SQL failure the transaction rolls back and the
caller sees a `user-error'."
  (let* ((db (or db satan-memory-migrate-database))
         (runs-dir (satan-intervention--runs-dir runs-dir))
         (raw (satan-intervention--collect-events runs-dir))
         (events (satan-intervention--sort-events raw))
         (stream (mapcar (lambda (ev) (cons (plist-get ev :event)
                                            (plist-get ev :payload)))
                         events))
         (verr (satan-audit-validate-intervention-stream stream)))
    (if verr
        (list :total (length events)
              :created 0
              :outcomes 0
              :events events
              :validation-error verr)
      (let* ((script (satan-intervention--build-rebuild-script events))
             (result (satan-db-psql
                      db satan-memory-migrate-host satan-memory-migrate-psql-program
                      (list "--single-transaction" "-f" "-") script
                      :label "intervention.rebuild")))
        (pcase result
          (`(ok . ,_)
           (list :total (length events)
                 :created (cl-count-if
                           (lambda (ev) (equal (plist-get ev :event)
                                               "intervention.created"))
                           events)
                 :outcomes (cl-count-if
                            (lambda (ev) (member (plist-get ev :event)
                                                 '("intervention.outcome_classified"
                                                   "intervention.outcome_revised")))
                            events)
                 :events events
                 :validation-error nil))
          (`(error . ,msg)
           (user-error "satan-intervention-rebuild failed: %s" msg)))))))

;;;###autoload
(defun satan-rebuild-interventions (&optional db)
  "Rebuild the intervention projection from audit logs.
With prefix arg, prompt for DB."
  (interactive
   (list (if current-prefix-arg
             (read-string "Database: " satan-memory-migrate-database)
           satan-memory-migrate-database)))
  (let ((res (satan-intervention-rebuild db)))
    (if (plist-get res :validation-error)
        (let ((err (plist-get res :validation-error)))
          (message "satan-rebuild-interventions: refused — validation failed at idx %d: %s"
                   (plist-get err :idx)
                   (plist-get err :reason)))
      (message "satan-rebuild-interventions: %d events (%d created, %d outcomes)"
               (plist-get res :total)
               (plist-get res :created)
               (plist-get res :outcomes)))
    res))

;; ---------- write/read API (T7 PR 3) ----------

(defvar satan-intervention--counters (make-hash-table :test 'equal)
  "Per-run counter (run-id string -> integer) used to mint `<run-id>.iv<N>'
intervention ids inside a single emacs session.  Resets on emacs restart;
runs are bound to their broker process so a fresh session always starts
a new run with no carryover.")

(defun satan-intervention--next-counter (run-id)
  "Return the next 1-indexed counter value for RUN-ID."
  (let ((n (1+ (or (gethash run-id satan-intervention--counters) 0))))
    (puthash run-id n satan-intervention--counters)
    n))

(defun satan-intervention--mint-id (run-id)
  "Mint a stable intervention id of shape `<RUN-ID>.iv<NNN>'.
The counter is per-run; ids are dense, ordered, and emit-time-stamped
implicitly through the audit record's `:ts'."
  (format "%s.iv%03d" run-id (satan-intervention--next-counter run-id)))

(defun satan-intervention--reset-counters ()
  "Clear all per-run intervention counters.  For ert use; not for production."
  (clrhash satan-intervention--counters))

(defun satan-intervention--ctx-required (ctx)
  "Validate CTX carries a value for each key the write API depends on.
Signals otherwise.  A present but nil key fails too: the canonical
builder always writes `:time-now', and nil would stamp or query no
time at all."
  (unless (cl-every (lambda (key) (plist-get ctx key))
                    '(:id :mode-name :time-now :audit))
    (user-error
     "satan-intervention: tool-ctx missing :id/:mode-name/:time-now/:audit")))

(defun satan-intervention--exec-sql (db sql)
  "Run SQL through `psql --single-transaction'.  Signals on failure."
  (let ((result (satan-db-psql
                 db satan-memory-migrate-host satan-memory-migrate-psql-program
                 (list "--single-transaction" "-f" "-") sql)))
    (pcase result
      (`(ok . ,_) nil)
      (`(error . ,msg) (user-error "satan-intervention SQL: %s" msg)))))

;; --- create = record + project ---

(cl-defun satan-intervention-record
    (&key ctx kind target-surface message
          related-motive-id cue-handles
          expected-outcome outcome-window-minutes severity)
  "Record an intervention: validate, mint its id, append the audit line.
CTX is the broker-supplied tool-ctx plist.  Required keyword args:
KIND, TARGET-SURFACE, MESSAGE, EXPECTED-OUTCOME, OUTCOME-WINDOW-MINUTES,
SEVERITY.  Optional: RELATED-MOTIVE-ID, CUE-HANDLES (list of strings).

Appends `intervention.created' to the run's transcript — the canonical
record (REQ-003) — and touches no database.  Returns the payload plist,
which carries the minted `:intervention_id'.

Signals `user-error' on an invalid CTX or a validator failure, and
propagates an append failure; in every such case nothing is recorded."
  (satan-intervention--ctx-required ctx)
  (let* ((run-id (plist-get ctx :id))
         (payload
          (list :intervention_id        (satan-intervention--mint-id run-id)
                :run_id                 run-id
                :ts                     (plist-get ctx :time-now)
                :mode                   (plist-get ctx :mode-name)
                :kind                   kind
                :target_surface         target-surface
                :message                message
                :related_motive_id      (or related-motive-id :null)
                :cue_handles            (or cue-handles (vector))
                :percept_handles        (or (plist-get ctx :percept-handles) (vector))
                :expected_outcome       expected-outcome
                :outcome_window_minutes outcome-window-minutes
                :severity               severity))
         (verr (satan-audit-validate-intervention-event
                "intervention.created" payload
                (make-hash-table :test 'equal))))
    (when verr
      (user-error "satan-intervention-record: %s" verr))
    (satan-audit-record (plist-get ctx :audit)
                        'broker 'intervention.created payload)
    payload))

(cl-defun satan-intervention-project
    (payload &key (db satan-memory-migrate-database))
  "INSERT an `intervention.created' PAYLOAD into `satan_interventions'.
Idempotent (`ON CONFLICT (id) DO NOTHING').  Signals `user-error' on
psql failure; the record is untouched and rebuild can replay it."
  (satan-intervention--exec-sql
   db (satan-intervention--transaction-sql
       (list (satan-intervention--insert-created-sql payload)))))

(cl-defun satan-intervention-create
    (&key ctx kind target-surface message
          related-motive-id cue-handles
          expected-outcome outcome-window-minutes severity
          (db satan-memory-migrate-database))
  "Create an intervention: `satan-intervention-record' then
`satan-intervention-project' into DB (default: the migrate database).
Takes the record's keyword args.  Returns the minted intervention-id
string.  Signals `user-error' on validator or DB failure; a DB failure
leaves the canonical audit record intact for later rebuild.

For callers whose side effect does not depend on the record; an emit
that must be recorded first (notify) calls the halves itself."
  (let ((payload (satan-intervention-record
                  :ctx ctx :kind kind :target-surface target-surface
                  :message message :related-motive-id related-motive-id
                  :cue-handles cue-handles :expected-outcome expected-outcome
                  :outcome-window-minutes outcome-window-minutes
                  :severity severity)))
    (satan-intervention-project payload :db db)
    (plist-get payload :intervention_id)))

;; --- classify = lookup + classify-record + classify-project + enqueue ---

(defun satan-intervention--outcome-event (revision-p)
  "The audit event name for a verdict; a revision when REVISION-P."
  (if revision-p
      "intervention.outcome_revised"
    "intervention.outcome_classified"))

(cl-defun satan-intervention-classify-record
    (&key ctx intervention-id revision-p classification confidence evidence
          maturity next-revisit-at source classified-at marked-by notes)
  "Record an outcome verdict for INTERVENTION-ID in CTX's audit.
Appends `intervention.outcome_classified', or `intervention.outcome_revised'
with `:revises' set to INTERVENTION-ID when REVISION-P.  No database
access: the caller decides REVISION-P.  Returns the payload plist.

Signals `user-error' on an invalid CTX or a validator failure, and
propagates an append failure."
  (satan-intervention--ctx-required ctx)
  (let* ((event (satan-intervention--outcome-event revision-p))
         (payload
          (append
           (list :intervention_id  intervention-id
                 :classification   classification
                 :confidence       confidence
                 :evidence         (or evidence '())
                 :maturity         maturity
                 :next_revisit_at  next-revisit-at
                 :source           source
                 :classified_at    classified-at)
           (when revision-p (list :revises intervention-id))
           (when marked-by (list :marked_by marked-by))
           (when notes (list :notes notes))))
         ;; Single-event validation: the created/outcome stream check is
         ;; rebuild's job, so the intervention is taken as created.
         (created-ids (let ((h (make-hash-table :test 'equal)))
                        (puthash intervention-id t h)
                        h))
         (verr (satan-audit-validate-intervention-event
                event payload created-ids)))
    (when verr
      (user-error "satan-intervention-classify-record: %s" verr))
    (satan-audit-record (plist-get ctx :audit) 'broker (intern event) payload)
    payload))

(cl-defun satan-intervention-classify-project
    (payload &key (db satan-memory-migrate-database))
  "UPSERT a verdict PAYLOAD into `satan_intervention_outcomes'.
Signals `user-error' on psql failure, including a missing
`satan_interventions' parent row (foreign key)."
  (satan-intervention--exec-sql
   db (satan-intervention--transaction-sql
       (list (satan-intervention--upsert-outcome-sql payload)))))

(cl-defun satan-intervention-project-with-verdict
    (payload verdict &key (db satan-memory-migrate-database))
  "Project intervention PAYLOAD and its VERDICT payload in one transaction.
Both rows land or neither does, so the intervention never looks
pending without its verdict.  Signals `user-error' on psql failure."
  (satan-intervention--exec-sql
   db (satan-intervention--transaction-sql
       (list (satan-intervention--insert-created-sql payload)
             (satan-intervention--upsert-outcome-sql verdict)))))

(defun satan-intervention--failed (err)
  "The result note for a step that signalled ERR."
  (format "failed: %s" (error-message-string err)))

(defun satan-intervention-try-project (fn &rest payloads)
  "Call projection FN on PAYLOADS.  Never signals.
Returns nil, or `(:projection \"failed: MSG\")' when FN signalled.
Shared by every caller whose side effect must be recorded before it
happens (notify, and PHASE-06's ask handler): the record is already
durable, so a projection failure is a note, not a lost act."
  (condition-case err
      (progn (apply fn payloads) nil)
    (error (list :projection (satan-intervention--failed err)))))

(defun satan-intervention-mark-undelivered (ctx payload err)
  "Mark the recorded intervention PAYLOAD as never seen: its pop signalled ERR.
Appends an `unknown'/`high'/`mature'/`auto' verdict noted
`undelivered: ERR' to CTX's audit, then projects the intervention and
the verdict in one transaction (design sec-3, \"Both failure arms reuse
notify's existing verdict\").  Never signals: a failed step becomes a
note, and a failed verdict record skips the projection — an
intervention projected without its verdict would look pending, and
the observer would score an alert the keeper never saw.  No attribute
enqueue: an unseen alert teaches the attribute daemon nothing.

Shared by every caller whose side effect must be recorded before it
happens; moved here from `satan-tools-notify' so `notify_send' and
PHASE-06's ask handler both call it without a require cycle.

Returns the result-note plist — `:verdict' or `:projection' as a
\"failed: MSG\" string for the failed step — or nil."
  (let ((now (plist-get ctx :time-now)))
    (condition-case verr
        (let ((verdict (satan-intervention-classify-record
                        :ctx ctx
                        :intervention-id (plist-get payload :intervention_id)
                        :classification "unknown" :confidence "high"
                        :maturity "mature" :source "auto"
                        :classified-at now :next-revisit-at now
                        :notes (format "undelivered: %s"
                                       (error-message-string err)))))
          (satan-intervention-try-project
           #'satan-intervention-project-with-verdict payload verdict))
      (error (list :verdict (satan-intervention--failed verr))))))

(cl-defun satan-intervention-classify
    (&key ctx intervention-id classification confidence evidence
          maturity next-revisit-at source classified-at
          marked-by notes
          (db satan-memory-migrate-database))
  "Record and project an outcome verdict for INTERVENTION-ID.

Looks the intervention up in DB (default: the migrate database): when
the projection already carries an outcome row, the verdict is a
revision.  Then `satan-intervention-classify-record',
`satan-intervention-classify-project', and the attribute-outcome
enqueue.  CTX is the broker-supplied tool-ctx (provides the audit
handle).  Returns the audit event-name string; signals `user-error' on
validator/DB failure."
  (satan-intervention--ctx-required ctx)
  (let* ((existing (satan-intervention-lookup intervention-id db))
         (revision-p (and existing (plist-get existing :outcome)))
         (payload (satan-intervention-classify-record
                   :ctx ctx :intervention-id intervention-id
                   :revision-p revision-p
                   :classification classification :confidence confidence
                   :evidence evidence :maturity maturity
                   :next-revisit-at next-revisit-at :source source
                   :classified-at classified-at
                   :marked-by marked-by :notes notes)))
    (satan-intervention-classify-project payload :db db)
    (satan-intervention--enqueue-attribute-outcome
     (plist-get ctx :id) (plist-get ctx :time-now) intervention-id
     classification confidence revision-p existing)
    (satan-intervention--outcome-event revision-p)))

(defun satan-intervention--enqueue-attribute-outcome
    (run-id ts intervention-id classification confidence revision-p existing)
  "Forward the outcome to the attribute daemon via satan_outcome_inbox
\(design-contract §17.3).  Failures are logged but do NOT signal — the
broker's audit transcript + outcome projection write already succeeded,
and a missed enqueue is recoverable via the operator pulling rows from
the projection.  EXISTING is the prior `satan-intervention-lookup'
result; its `:intervention' slot carries the cue dimensions."
  (let* ((iv (and existing (plist-get existing :intervention)))
         (payload (satan-attribute-build-outcome-payload
                   :run-id run-id
                   :ts ts
                   :intervention-id intervention-id
                   :classification classification
                   :confidence confidence
                   :intervention-kind (and iv (plist-get iv :kind))
                   :related-motive-id (and iv (plist-get iv :related_motive_id))
                   :cue-handles (and iv (plist-get iv :cue_handles))
                   :is-revision revision-p
                   :revises (and revision-p intervention-id))))
    (pcase (satan-attribute-enqueue-outcome payload)
      (`(error . ,msg)
       (message "satan-intervention-classify: attribute enqueue failed: %s"
                msg))
      (_ nil))))

;; --- manual override writer (T1.5b PR 4) ---

(defconst satan-intervention--manual-classifications
  '("harmful" "contradicted")
  "Closed set of classifications acceptable via the manual-mark writer
\(outcome-semantics §7).  Auto kinds (`worked'/`neutral'/`ignored'/
`unknown') belong to the auto classifier and must not reach here.")

(defconst satan-intervention--manual-marked-by
  '("interactive-command" "notes-directive")
  "Closed set of `:marked_by' values the writer accepts.")

(defun satan-intervention--manual-evidence (classification reason
                                                              evidence-pointer
                                                              marked-by)
  "Build the §5 evidence plist for a manual mark.
For CLASSIFICATION = \"harmful\": carries `:reason' / `:evidence_pointer'.
For CLASSIFICATION = \"contradicted\": carries `:prior_suspicion' /
`:user_artifact'.  Both carry `:source_events ()' (manual marks consult
no audit events) and `:marked_by'."
  (cond
   ((equal classification "harmful")
    (list :source_events '()
          :reason            (or reason "")
          :marked_by         marked-by
          :evidence_pointer  (or evidence-pointer "")))
   ((equal classification "contradicted")
    (list :source_events '()
          :prior_suspicion  (or reason "")
          :user_artifact    (or evidence-pointer "")
          :marked_by        marked-by))
   (t
    (user-error
     "satan-intervention-write-manual-outcome: unsupported classification %S"
     classification))))

(defun satan-intervention--counter-memory-handles (cue-handles iv-id)
  "Build `satan-memory-store-mark' handle rows from CUE-HANDLES.
Each cue handle inherits provenance `(:rule_id
\"intervention.manual_mark\" :origin \"derived\" :evidence_pointer
\"/intervention/<iv-id>\")' so resonance can attribute the counter-
memory back to the manual mark."
  (mapcar
   (lambda (h)
     (list :handle h
           :source (list :rule_id "intervention.manual_mark"
                         :origin "derived"
                         :evidence_pointer
                         (format "/intervention/%s" (or iv-id "_")))
           :grammar_version satan-memory-grammar-current-version))
   (or cue-handles nil)))

(defun satan-intervention--counter-memory-payload (classification iv-id
                                                                     reason
                                                                     evidence-pointer)
  "Render the counter-memory trace payload string (§3.4)."
  (cond
   ((equal classification "contradicted")
    (format "SATAN suspected %s, but the user produced %s from that activity. (intervention %s)"
            (or reason "_") (or evidence-pointer "_") (or iv-id "_")))
   ((equal classification "harmful")
    (format "harmful intervention %s: %s%s"
            (or iv-id "_")
            (or reason "_")
            (if (and evidence-pointer (not (string-empty-p evidence-pointer)))
                (format " (%s)" evidence-pointer)
              "")))
   (t (format "manual mark %s for intervention %s" classification iv-id))))

(defun satan-intervention--write-counter-memory (intervention-id classification
                                                                    confidence
                                                                    reason
                                                                    evidence-pointer
                                                                    marked-by
                                                                    classified-at
                                                                    cue-handles
                                                                    mark-fn)
  "Write the §3.4 counter-memory trace for a manual mark.
Returns the result of MARK-FN (cons of `ok|error . VALUE') so callers
can surface failures.  Trace handles are CUE-HANDLES verbatim — per
the PR 4 decision the counter-memory inherits the intervention's cue
handles so resonance can later surface it on the same cue."
  (funcall mark-fn
           :kind "observation"
           :trace-origin "auto_rule"
           :source "intervention.manual_mark"
           :observed-start-at classified-at
           :observed-end-at   classified-at
           :payload (satan-intervention--counter-memory-payload
                     classification intervention-id reason evidence-pointer)
           :valence "negative"
           :grammar-version satan-memory-grammar-current-version
           :metadata-json (list :intervention_id intervention-id
                                :classification classification
                                :confidence confidence
                                :marked_by marked-by
                                :evidence_pointer (or evidence-pointer ""))
           :handles (satan-intervention--counter-memory-handles
                     cue-handles intervention-id)))

(cl-defun satan-intervention-write-manual-outcome
    (&key ctx intervention-id classification confidence
          reason evidence-pointer notes marked-by
          classified-at maturity next-revisit-at
          memory-mark-fn
          (db satan-memory-migrate-database))
  "Write a manual outcome verdict for INTERVENTION-ID.

CLASSIFICATION is the string `\"harmful\"' or `\"contradicted\"' (the
only kinds reachable by manual mark in v1; outcome-semantics §2
invariants 1+2).  CONFIDENCE is `\"low\"' | `\"medium\"' | `\"high\"'.
REASON is freeform prose; EVIDENCE-POINTER is typically a `path:line'
locator; NOTES is optional multiline freeform.

MARKED-BY is `\"interactive-command\"' or `\"notes-directive\"'.
CLASSIFIED-AT and NEXT-REVISIT-AT are ISO8601 strings the caller
derives from the broker's frozen `:time_now' (interactive command)
or from the directive consumption ts (notes handler).  MATURITY
is `\"pending\"' / `\"mature\"' / `\"stale\"'; manual marks are
allowed in every state (§7.4).

Routes through `satan-intervention-classify' with `:source
\"manual\"'.  Emits `intervention.outcome_classified' on first emit;
`intervention.outcome_revised' (with `:revises' auto-set) if a prior
outcome row exists.  Returns the audit event-name string.

Counter-memory trace (§3.4 of attributes.brief) is written via
`satan-memory-store-mark' after the verdict event succeeds; the
trace inherits the intervention's `:cue_handles' so resonance can
later surface the counter-memory when the same cue re-fires.
MEMORY-MARK-FN is the function used to write the trace; defaults to
`satan-memory-store-mark'.  Override for tests."
  (unless (member classification satan-intervention--manual-classifications)
    (user-error "manual writer: classification must be one of %S, got %S"
                satan-intervention--manual-classifications classification))
  (unless (member marked-by satan-intervention--manual-marked-by)
    (user-error "manual writer: marked-by must be one of %S, got %S"
                satan-intervention--manual-marked-by marked-by))
  (let* ((evidence (satan-intervention--manual-evidence
                    classification reason evidence-pointer marked-by))
         (event (satan-intervention-classify
                 :ctx ctx
                 :intervention-id intervention-id
                 :classification classification
                 :confidence confidence
                 :evidence evidence
                 :maturity maturity
                 :next-revisit-at next-revisit-at
                 :source "manual"
                 :classified-at classified-at
                 :marked-by marked-by
                 :notes notes
                 :db db))
         (existing (satan-intervention-lookup intervention-id db))
         (cue-handles (let ((raw (plist-get (plist-get existing :intervention)
                                            :cue_handles)))
                        (if (eq raw :null) nil raw)))
         (mark-fn (or memory-mark-fn #'satan-memory-store-mark)))
    (satan-intervention--write-counter-memory
     intervention-id classification confidence
     reason evidence-pointer marked-by classified-at
     cue-handles mark-fn)
    event))

;; --- query helpers ---

(defconst satan-intervention--lookup-columns
  '("id" "run_id" "ts" "mode" "kind" "target_surface" "message"
    "related_motive_id" "cue_handles_json" "expected_outcome"
    "outcome_window_minutes" "severity"))

(defconst satan-intervention--outcome-columns
  '("classification" "confidence" "evidence_json" "maturity"
    "next_revisit_at" "source" "classified_at" "revises"
    "marked_by" "notes"))

(defun satan-intervention--parse-jsonb (text)
  "Parse a JSONB cell TEXT into elisp; nil/empty → nil."
  (cond
   ((or (null text) (string-empty-p text)) nil)
   (t (condition-case _err
          (json-parse-string text
                             :object-type 'plist
                             :array-type 'list
                             :null-object :null
                             :false-object :false)
        (error nil)))))

(defun satan-intervention--normalize-pg-timestamp (cell)
  "Make a `psql -A' timestamptz CELL parseable by `date-to-time'.
`psql' renders a `timestamptz' as `YYYY-MM-DD HH:MM:SS+ZZ' (space
separator); the space defeats `parse-time-string', which then drops
the time-of-day and mis-shifts the date.  Replacing the first space
with `T' yields an ISO8601 form Emacs parses correctly, regardless of
the offset width.  nil / empty pass through unchanged."
  (if (and (stringp cell) (string-match " " cell))
      (replace-match "T" t t cell)
    cell))

(defun satan-intervention--row-to-intervention (cells)
  "Convert a CELLS list (column-order matches `--lookup-columns') to plist."
  (cl-destructuring-bind
      (id run_id ts mode kind target_surface message
       related_motive_id cue_handles_json expected_outcome
       outcome_window_minutes severity)
      cells
    (list :intervention_id        id
          :run_id                 run_id
          :ts                     (satan-intervention--normalize-pg-timestamp ts)
          :mode                   mode
          :kind                   kind
          :target_surface         target_surface
          :message                message
          :related_motive_id      (if (string-empty-p related_motive_id)
                                      nil
                                    related_motive_id)
          :cue_handles            (satan-intervention--parse-jsonb
                                   cue_handles_json)
          :expected_outcome       expected_outcome
          :outcome_window_minutes (string-to-number outcome_window_minutes)
          :severity               severity)))

(defun satan-intervention--row-to-outcome (cells)
  "Convert a CELLS list (column-order matches `--outcome-columns') to plist."
  (cl-destructuring-bind
      (classification confidence evidence_json maturity
       next_revisit_at source classified_at revises
       marked_by notes)
      cells
    (list :classification    classification
          :confidence        confidence
          :evidence          (satan-intervention--parse-jsonb evidence_json)
          :maturity          maturity
          :next_revisit_at   (satan-intervention--normalize-pg-timestamp
                              next_revisit_at)
          :source            source
          :classified_at     (satan-intervention--normalize-pg-timestamp
                              classified_at)
          :revises           (if (string-empty-p revises) nil revises)
          :marked_by         (if (string-empty-p marked_by) nil marked_by)
          :notes             (if (string-empty-p notes) nil notes))))

(defun satan-intervention-lookup (intervention-id &optional db)
  "Return `(:intervention ROW :outcome ROW|nil)' for INTERVENTION-ID, or nil."
  (let* ((db (or db satan-memory-migrate-database))
         (sql (concat
               "SELECT "
               (mapconcat
                (lambda (c) (concat "COALESCE(i." c "::text, '')"))
                satan-intervention--lookup-columns ", ")
               ", "
               "(o.intervention_id IS NOT NULL)::text, "
               (mapconcat
                (lambda (c) (concat "COALESCE(o." c "::text, '')"))
                satan-intervention--outcome-columns ", ")
               " FROM satan_interventions i "
               "LEFT JOIN satan_intervention_outcomes o "
               "  ON i.id = o.intervention_id "
               "WHERE i.id = "
               (satan-intervention--quote-text intervention-id)))
         (result (satan-db-psql
                  db satan-memory-migrate-host satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (let* ((line (string-trim out)))
         (when (and (not (string-empty-p line)))
           (let* ((cells (split-string line "|"))
                  (n-iv (length satan-intervention--lookup-columns))
                  (iv-cells (cl-subseq cells 0 n-iv))
                  (has-outcome (equal "true" (nth n-iv cells)))
                  (out-cells (and has-outcome
                                  (cl-subseq cells (1+ n-iv)))))
             (list :intervention (satan-intervention--row-to-intervention iv-cells)
                   :outcome (and has-outcome
                                 (satan-intervention--row-to-outcome out-cells)))))))
      (`(error . ,msg) (user-error "satan-intervention-lookup: %s" msg)))))

(defun satan-intervention-pending (now &optional db)
  "Return intervention plists whose maturity window ≤ NOW and that lack outcomes.
NOW is an ISO8601 string accepted by PostgreSQL's `timestamptz' parser.
Excludes interventions whose `created_at + outcome_window_minutes' is
later than NOW (still `:pending' — see outcome-semantics §3), whose
`created_at + outcome_window_minutes + 24h' is earlier than NOW
(already `:stale' — auto re-pass forbidden per §6.3, T1.5b PR 3),
and any intervention that already has an outcome row in the
projection."
  (let* ((db (or db satan-memory-migrate-database))
         (now-lit (concat (satan-intervention--quote-text now)
                          "::timestamptz"))
         (sql (concat
               "SELECT "
               (mapconcat
                (lambda (c) (concat "COALESCE(i." c "::text, '')"))
                satan-intervention--lookup-columns ", ")
               " FROM satan_interventions i "
               "LEFT JOIN satan_intervention_outcomes o "
               "  ON i.id = o.intervention_id "
               "WHERE o.intervention_id IS NULL "
               "  AND i.ts + (i.outcome_window_minutes * INTERVAL '1 minute') "
               "      <= " now-lit " "
               "  AND i.ts + (i.outcome_window_minutes * INTERVAL '1 minute') "
               "      + INTERVAL '24 hours' >= " now-lit " "
               "ORDER BY i.ts ASC"))
         (result (satan-db-psql
                  db satan-memory-migrate-host satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for cells = (split-string line "|")
                when (= (length cells)
                        (length satan-intervention--lookup-columns))
                collect (satan-intervention--row-to-intervention cells)))
      (`(error . ,msg) (user-error "satan-intervention-pending: %s" msg)))))

(cl-defun satan-intervention-recent
    (now &key include-stale (limit 50) (db satan-memory-migrate-database))
  "Return up to LIMIT most recently-created interventions, newest first.
NOW is an ISO8601 string; INCLUDE-STALE nil (default) filters out
interventions whose `ts + outcome_window_minutes + 24 h' is earlier
than NOW (auto-classifier-frozen per §6.3).  Each element is the
plist shape produced by `satan-intervention-lookup' under
`:intervention'."
  (let* ((now-lit (concat (satan-intervention--quote-text now)
                          "::timestamptz"))
         (where (if include-stale
                    ""
                  (concat " WHERE i.ts + "
                          "(i.outcome_window_minutes * INTERVAL '1 minute') "
                          "+ INTERVAL '24 hours' >= " now-lit " ")))
         (sql (concat
               "SELECT "
               (mapconcat
                (lambda (c) (concat "COALESCE(i." c "::text, '')"))
                satan-intervention--lookup-columns ", ")
               " FROM satan_interventions i"
               where
               " ORDER BY i.ts DESC LIMIT "
               (number-to-string limit)))
         (result (satan-db-psql
                  db satan-memory-migrate-host satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for cells = (split-string line "|")
                when (= (length cells)
                        (length satan-intervention--lookup-columns))
                collect (satan-intervention--row-to-intervention cells)))
      (`(error . ,msg) (user-error "satan-intervention-recent: %s" msg)))))

(provide 'satan-intervention)
;;; satan-intervention.el ends here
