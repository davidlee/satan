;;; dl-satan-intervention.el --- intervention projection rebuild + API -*- lexical-binding: t; -*-

;; T7 — first-class intervention records.
;;
;; This module owns the projection of intervention audit-events into
;; the `satan_interventions' / `satan_intervention_outcomes' tables
;; created by migration 0006_interventions.sql.  The audit log
;; (transcript.jsonl per run) is the source of truth; the tables are
;; rebuildable.
;;
;; PR 2 lands the rebuild CLI:
;;   - `dl-satan-intervention-rebuild' replays every intervention event
;;     across all runs into the projection in (ts, run-id, seq) order.
;;     Idempotent: a second rebuild yields byte-identical rows.
;;   - `my/satan-rebuild-interventions' is the interactive command;
;;     `satan/bin/satan-rebuild-interventions' is the CLI wrapper.
;;
;; PR 3 adds the write/read API used by handlers and the observer:
;;
;;   (dl-satan-intervention-create &key CTX KIND TARGET-SURFACE MESSAGE
;;                                      RELATED-MOTIVE-ID CUE-HANDLES
;;                                      EXPECTED-OUTCOME OUTCOME-WINDOW-MINUTES
;;                                      SEVERITY)
;;     Mint a stable `<run-id>.iv<NNN>' id, emit `intervention.created' into
;;     the run's transcript.jsonl, and INSERT into `satan_interventions'
;;     (ON CONFLICT DO NOTHING).  Returns the intervention-id string.
;;
;;   (dl-satan-intervention-classify &key CTX INTERVENTION-ID CLASSIFICATION
;;                                        CONFIDENCE EVIDENCE MATURITY
;;                                        NEXT-REVISIT-AT SOURCE CLASSIFIED-AT
;;                                        MARKED-BY NOTES)
;;     Audit-emit + UPSERT a verdict.  Emits `intervention.outcome_classified'
;;     when no prior outcome row exists; `intervention.outcome_revised' (with
;;     `:revises' set to the intervention-id) otherwise.  Returns `ok' or
;;     signals on validation/DB failure.
;;
;;   (dl-satan-intervention-lookup INTERVENTION-ID &optional DB)
;;     Return `(:intervention <row-plist> :outcome <row-plist-or-nil>)' or nil.
;;
;;   (dl-satan-intervention-pending NOW &optional DB)
;;     Return list of intervention plists whose maturity window has elapsed
;;     and which have no outcome row.  NOW is an ISO8601 string.
;;
;; **Transaction discipline:** audit-emit happens first (canonical); the
;; projection INSERT is a separate psql round-trip in the same handler
;; call.  An audit-only success with a failed projection insert is
;; recoverable via `my/satan-rebuild-interventions'.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-audit)             ; validators + closed-set constants
(require 'dl-satan-jsonl)              ; prepare arrays/alists for json-serialize
(require 'dl-satan-memory-migrate)    ; psql runner + database defcustoms
(require 'dl-satan-memory-grammar)    ; grammar-current-version (counter-memory)
(require 'dl-satan-memory-store)      ; memory-store-mark (counter-memory)
(require 'dl-satan-attribute)         ; outcome → satan_outcome_inbox enqueue

;; ---------- runs-dir resolution ----------

(defun dl-satan-intervention--runs-dir (&optional override)
  "Return the runs root directory.  OVERRIDE wins; else `dl-satan-runs-dir'."
  (or override
      (and (boundp 'dl-satan-runs-dir) dl-satan-runs-dir)
      (user-error
       "dl-satan-intervention: no runs-dir (set `dl-satan-runs-dir' or pass override)")))

(defun dl-satan-intervention--transcript-files (runs-dir)
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



(defun dl-satan-intervention--run-id-from-path (path)
  "Derive a run-id from PATH (parent directory name)."
  (file-name-nondirectory
   (directory-file-name (file-name-directory path))))

(defun dl-satan-intervention--collect-events (runs-dir)
  "Collect every intervention event under RUNS-DIR.
Returns a list of plists with keys (:ts :event :payload :run_id :seq :path).
SEQ is the within-file record index, used as a tiebreaker."
  (let (out)
    (dolist (path (dl-satan-intervention--transcript-files runs-dir))
      (let ((records (dl-satan-jsonl-read-file path :null-object :null))
            (file-run-id (dl-satan-intervention--run-id-from-path path))
            (seq 0))
        (dolist (rec records)
          (let ((event (plist-get rec :event)))
            (when (member event dl-satan-audit-intervention-events)
              (push (list :ts      (plist-get rec :ts)
                          :event   event
                          :payload (plist-get rec :payload)
                          :run_id  file-run-id
                          :seq     seq
                          :path    path)
                    out)))
          (cl-incf seq))))
    (nreverse out)))

(defun dl-satan-intervention--sort-events (events)
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

(defun dl-satan-intervention--quote-text (s)
  "Return the SQL literal for S; supports NULL via nil/:null."
  (cond
   ((or (null s) (eq s :null)) "NULL")
   ((stringp s)
    (concat "'" (replace-regexp-in-string "'" "''" s) "'"))
   (t (error "dl-satan-intervention--quote-text: not stringy: %S" s))))

(defun dl-satan-intervention--quote-jsonb (obj)
  "Serialize OBJ as JSON then wrap as an SQL literal `'…'::jsonb'.
Runs OBJ through `dl-satan-jsonl-prepare' so post-JSON-parse lists
become vectors before serialization."
  (let* ((prepared (dl-satan-jsonl-prepare (or obj :null)))
         (coded (json-serialize prepared
                                :null-object :null
                                :false-object :false)))
    (concat (dl-satan-intervention--quote-text coded) "::jsonb")))

(defun dl-satan-intervention--insert-created-sql (payload)
  "Return SQL INSERT for an intervention.created PAYLOAD."
  (concat
   "INSERT INTO satan_interventions ("
   "id, run_id, ts, mode, kind, target_surface, message, "
   "related_motive_id, cue_handles_json, percept_handles_json, "
   "expected_outcome, outcome_window_minutes, severity) VALUES ("
   (mapconcat
    #'identity
    (list (dl-satan-intervention--quote-text (plist-get payload :intervention_id))
          (dl-satan-intervention--quote-text (plist-get payload :run_id))
          (concat (dl-satan-intervention--quote-text (plist-get payload :ts))
                  "::timestamptz")
          (dl-satan-intervention--quote-text (plist-get payload :mode))
          (dl-satan-intervention--quote-text (plist-get payload :kind))
          (dl-satan-intervention--quote-text (plist-get payload :target_surface))
          (dl-satan-intervention--quote-text (plist-get payload :message))
          (dl-satan-intervention--quote-text (plist-get payload :related_motive_id))
          (dl-satan-intervention--quote-jsonb (or (plist-get payload :cue_handles) (vector)))
          (dl-satan-intervention--quote-jsonb (or (plist-get payload :percept_handles) (vector)))
          (dl-satan-intervention--quote-text (plist-get payload :expected_outcome))
          (number-to-string (plist-get payload :outcome_window_minutes))
          (dl-satan-intervention--quote-text (plist-get payload :severity)))
    ", ")
   ") ON CONFLICT (id) DO NOTHING;"))

(defun dl-satan-intervention--upsert-outcome-sql (payload)
  "Return SQL UPSERT for an outcome_classified / outcome_revised PAYLOAD."
  (concat
   "INSERT INTO satan_intervention_outcomes ("
   "intervention_id, classification, confidence, evidence_json, "
   "maturity, next_revisit_at, source, classified_at, revises, "
   "marked_by, notes) VALUES ("
   (mapconcat
    #'identity
    (list (dl-satan-intervention--quote-text (plist-get payload :intervention_id))
          (dl-satan-intervention--quote-text (plist-get payload :classification))
          (dl-satan-intervention--quote-text (plist-get payload :confidence))
          (dl-satan-intervention--quote-jsonb (plist-get payload :evidence))
          (dl-satan-intervention--quote-text (plist-get payload :maturity))
          (concat (dl-satan-intervention--quote-text
                   (plist-get payload :next_revisit_at))
                  "::timestamptz")
          (dl-satan-intervention--quote-text (plist-get payload :source))
          (concat (dl-satan-intervention--quote-text
                   (plist-get payload :classified_at))
                  "::timestamptz")
          (dl-satan-intervention--quote-text (plist-get payload :revises))
          (dl-satan-intervention--quote-text (plist-get payload :marked_by))
          (dl-satan-intervention--quote-text (plist-get payload :notes)))
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

(defun dl-satan-intervention--build-rebuild-script (events)
  "Build the full rebuild transaction SQL for EVENTS (already sorted).
Wraps TRUNCATE + per-event INSERT/UPSERT in a single transaction."
  (let ((lines (list "BEGIN;"
                     "TRUNCATE satan_intervention_outcomes, satan_interventions RESTART IDENTITY;")))
    (dolist (ev events)
      (let ((event (plist-get ev :event))
            (payload (plist-get ev :payload)))
        (push (pcase event
                ("intervention.created"
                 (dl-satan-intervention--insert-created-sql payload))
                ((or "intervention.outcome_classified"
                     "intervention.outcome_revised")
                 (dl-satan-intervention--upsert-outcome-sql payload)))
              lines)))
    (push "COMMIT;" lines)
    (mapconcat #'identity (nreverse lines) "\n")))

;; ---------- public rebuild ----------

(defun dl-satan-intervention-rebuild (&optional db runs-dir)
  "Replay every intervention audit-event under RUNS-DIR into the projection.
DB defaults to `dl-satan-memory-migrate-database'; RUNS-DIR defaults
to `dl-satan-runs-dir'.  Returns a plist:

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
  (let* ((db (or db dl-satan-memory-migrate-database))
         (runs-dir (dl-satan-intervention--runs-dir runs-dir))
         (raw (dl-satan-intervention--collect-events runs-dir))
         (events (dl-satan-intervention--sort-events raw))
         (stream (mapcar (lambda (ev) (cons (plist-get ev :event)
                                            (plist-get ev :payload)))
                         events))
         (verr (dl-satan-audit-validate-intervention-stream stream)))
    (if verr
        (list :total (length events)
              :created 0
              :outcomes 0
              :events events
              :validation-error verr)
      (let* ((script (dl-satan-intervention--build-rebuild-script events))
             (result (dl-satan-db-psql
                      db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
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
           (user-error "dl-satan-intervention-rebuild failed: %s" msg)))))))

;;;###autoload
(defun my/satan-rebuild-interventions (&optional db)
  "Rebuild the intervention projection from audit logs.
With prefix arg, prompt for DB."
  (interactive
   (list (if current-prefix-arg
             (read-string "Database: " dl-satan-memory-migrate-database)
           dl-satan-memory-migrate-database)))
  (let ((res (dl-satan-intervention-rebuild db)))
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

(defvar dl-satan-intervention--counters (make-hash-table :test 'equal)
  "Per-run counter (run-id string -> integer) used to mint `<run-id>.iv<N>'
intervention ids inside a single emacs session.  Resets on emacs restart;
runs are bound to their broker process so a fresh session always starts
a new run with no carryover.")

(defun dl-satan-intervention--next-counter (run-id)
  "Return the next 1-indexed counter value for RUN-ID."
  (let ((n (1+ (or (gethash run-id dl-satan-intervention--counters) 0))))
    (puthash run-id n dl-satan-intervention--counters)
    n))

(defun dl-satan-intervention--mint-id (run-id)
  "Mint a stable intervention id of shape `<RUN-ID>.iv<NNN>'.
The counter is per-run; ids are dense, ordered, and emit-time-stamped
implicitly through the audit record's `:ts'."
  (format "%s.iv%03d" run-id (dl-satan-intervention--next-counter run-id)))

(defun dl-satan-intervention--reset-counters ()
  "Clear all per-run intervention counters.  For ert use; not for production."
  (clrhash dl-satan-intervention--counters))

(defun dl-satan-intervention--ctx-required (ctx)
  "Validate CTX exposes the keys the write API depends on; signal otherwise."
  (unless (and (plist-member ctx :id)
               (plist-member ctx :mode-name)
               (plist-member ctx :time-now)
               (plist-member ctx :audit))
    (user-error
     "dl-satan-intervention: tool-ctx missing :id/:mode-name/:time-now/:audit")))

(defun dl-satan-intervention--exec-sql (db sql)
  "Run SQL through `psql --single-transaction'.  Signals on failure."
  (let ((result (dl-satan-db-psql
                 db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                 (list "--single-transaction" "-f" "-") sql)))
    (pcase result
      (`(ok . ,_) nil)
      (`(error . ,msg) (user-error "dl-satan-intervention SQL: %s" msg)))))

;; --- create ---

(cl-defun dl-satan-intervention-create
    (&key ctx kind target-surface message
          related-motive-id cue-handles
          expected-outcome outcome-window-minutes severity
          (db dl-satan-memory-migrate-database))
  "Create an intervention.  CTX is the broker-supplied tool-ctx plist.
Required keyword args: KIND, TARGET-SURFACE, MESSAGE, EXPECTED-OUTCOME,
OUTCOME-WINDOW-MINUTES, SEVERITY.  Optional: RELATED-MOTIVE-ID,
CUE-HANDLES (list of strings).  DB defaults to the migrate database.

On success: emits `intervention.created' to the run's transcript and
INSERTs the row into the `satan_interventions' projection
\(`ON CONFLICT (id) DO NOTHING' for retry-idempotency).  Returns the
minted intervention-id string.

Signals `user-error' on validator failure or DB failure.  The audit
record is canonical; a DB-side failure leaves the run's audit log
intact for later rebuild."
  (dl-satan-intervention--ctx-required ctx)
  (let* ((run-id (plist-get ctx :id))
         (ts (plist-get ctx :time-now))
         (mode (plist-get ctx :mode-name))
         (audit (plist-get ctx :audit))
         (iv-id (dl-satan-intervention--mint-id run-id))
         (payload
          (list :intervention_id        iv-id
                :run_id                 run-id
                :ts                     ts
                :mode                   mode
                :kind                   kind
                :target_surface         target-surface
                :message                message
                :related_motive_id      (or related-motive-id :null)
                :cue_handles            (or cue-handles (vector))
                :percept_handles        (or (plist-get ctx :percept-handles) (vector))
                :expected_outcome       expected-outcome
                :outcome_window_minutes outcome-window-minutes
                :severity               severity))
         (verr (dl-satan-audit-validate-intervention-event
                "intervention.created" payload
                (make-hash-table :test 'equal))))
    (when verr
      (user-error "dl-satan-intervention-create: %s" verr))
    (dl-satan-audit-record audit 'broker 'intervention.created payload)
    (dl-satan-intervention--exec-sql
     db (concat "BEGIN;\n"
                (dl-satan-intervention--insert-created-sql payload)
                "\nCOMMIT;\n"))
    iv-id))

;; --- classify ---

(cl-defun dl-satan-intervention-classify
    (&key ctx intervention-id classification confidence evidence
          maturity next-revisit-at source classified-at
          marked-by notes
          (db dl-satan-memory-migrate-database))
  "Record an outcome verdict for INTERVENTION-ID.

When the projection already carries an outcome row for INTERVENTION-ID,
this is a revision: emits `intervention.outcome_revised' with `:revises'
set to INTERVENTION-ID.  Otherwise emits `intervention.outcome_classified'.

CTX is the broker-supplied tool-ctx (provides the audit handle).
DB defaults to the migrate database.  Returns the audit event-name
string on success; signals `user-error' on validator/DB failure."
  (dl-satan-intervention--ctx-required ctx)
  (let* ((run-id (plist-get ctx :id))
         (ts (plist-get ctx :time-now))
         (audit (plist-get ctx :audit))
         (existing (dl-satan-intervention-lookup intervention-id db))
         (revision-p (and existing (plist-get existing :outcome)))
         (event (if revision-p
                    "intervention.outcome_revised"
                  "intervention.outcome_classified"))
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
         (created-ids (let ((h (make-hash-table :test 'equal)))
                        (puthash intervention-id t h)
                        h))
         (verr (dl-satan-audit-validate-intervention-event
                event payload created-ids)))
    (when verr
      (user-error "dl-satan-intervention-classify: %s" verr))
    (dl-satan-audit-record audit 'broker (intern event) payload)
    (dl-satan-intervention--exec-sql
     db (concat "BEGIN;\n"
                (dl-satan-intervention--upsert-outcome-sql payload)
                "\nCOMMIT;\n"))
    (dl-satan-intervention--enqueue-attribute-outcome
     run-id ts intervention-id classification confidence revision-p existing)
    event))

(defun dl-satan-intervention--enqueue-attribute-outcome
    (run-id ts intervention-id classification confidence revision-p existing)
  "Forward the outcome to the attribute daemon via satan_outcome_inbox
\(design-contract §17.3).  Failures are logged but do NOT signal — the
broker's audit transcript + outcome projection write already succeeded,
and a missed enqueue is recoverable via the operator pulling rows from
the projection.  EXISTING is the prior `dl-satan-intervention-lookup'
result; its `:intervention' slot carries the cue dimensions."
  (let* ((iv (and existing (plist-get existing :intervention)))
         (payload (dl-satan-attribute-build-outcome-payload
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
    (pcase (dl-satan-attribute-enqueue-outcome payload)
      (`(error . ,msg)
       (message "dl-satan-intervention-classify: attribute enqueue failed: %s"
                msg))
      (_ nil))))

;; --- manual override writer (T1.5b PR 4) ---

(defconst dl-satan-intervention--manual-classifications
  '("harmful" "contradicted")
  "Closed set of classifications acceptable via the manual-mark writer
\(outcome-semantics §7).  Auto kinds (`worked'/`neutral'/`ignored'/
`unknown') belong to the auto classifier and must not reach here.")

(defconst dl-satan-intervention--manual-marked-by
  '("interactive-command" "notes-directive")
  "Closed set of `:marked_by' values the writer accepts.")

(defun dl-satan-intervention--manual-evidence (classification reason
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
     "dl-satan-intervention-write-manual-outcome: unsupported classification %S"
     classification))))

(defun dl-satan-intervention--counter-memory-handles (cue-handles iv-id)
  "Build `dl-satan-memory-store-mark' handle rows from CUE-HANDLES.
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
           :grammar_version dl-satan-memory-grammar-current-version))
   (or cue-handles nil)))

(defun dl-satan-intervention--counter-memory-payload (classification iv-id
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

(defun dl-satan-intervention--write-counter-memory (intervention-id classification
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
           :payload (dl-satan-intervention--counter-memory-payload
                     classification intervention-id reason evidence-pointer)
           :valence "negative"
           :grammar-version dl-satan-memory-grammar-current-version
           :metadata-json (list :intervention_id intervention-id
                                :classification classification
                                :confidence confidence
                                :marked_by marked-by
                                :evidence_pointer (or evidence-pointer ""))
           :handles (dl-satan-intervention--counter-memory-handles
                     cue-handles intervention-id)))

(cl-defun dl-satan-intervention-write-manual-outcome
    (&key ctx intervention-id classification confidence
          reason evidence-pointer notes marked-by
          classified-at maturity next-revisit-at
          memory-mark-fn
          (db dl-satan-memory-migrate-database))
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

Routes through `dl-satan-intervention-classify' with `:source
\"manual\"'.  Emits `intervention.outcome_classified' on first emit;
`intervention.outcome_revised' (with `:revises' auto-set) if a prior
outcome row exists.  Returns the audit event-name string.

Counter-memory trace (§3.4 of attributes.brief) is written via
`dl-satan-memory-store-mark' after the verdict event succeeds; the
trace inherits the intervention's `:cue_handles' so resonance can
later surface the counter-memory when the same cue re-fires.
MEMORY-MARK-FN is the function used to write the trace; defaults to
`dl-satan-memory-store-mark'.  Override for tests."
  (unless (member classification dl-satan-intervention--manual-classifications)
    (user-error "manual writer: classification must be one of %S, got %S"
                dl-satan-intervention--manual-classifications classification))
  (unless (member marked-by dl-satan-intervention--manual-marked-by)
    (user-error "manual writer: marked-by must be one of %S, got %S"
                dl-satan-intervention--manual-marked-by marked-by))
  (let* ((evidence (dl-satan-intervention--manual-evidence
                    classification reason evidence-pointer marked-by))
         (event (dl-satan-intervention-classify
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
         (existing (dl-satan-intervention-lookup intervention-id db))
         (cue-handles (let ((raw (plist-get (plist-get existing :intervention)
                                            :cue_handles)))
                        (if (eq raw :null) nil raw)))
         (mark-fn (or memory-mark-fn #'dl-satan-memory-store-mark)))
    (dl-satan-intervention--write-counter-memory
     intervention-id classification confidence
     reason evidence-pointer marked-by classified-at
     cue-handles mark-fn)
    event))

;; --- query helpers ---

(defconst dl-satan-intervention--lookup-columns
  '("id" "run_id" "ts" "mode" "kind" "target_surface" "message"
    "related_motive_id" "cue_handles_json" "expected_outcome"
    "outcome_window_minutes" "severity"))

(defconst dl-satan-intervention--outcome-columns
  '("classification" "confidence" "evidence_json" "maturity"
    "next_revisit_at" "source" "classified_at" "revises"
    "marked_by" "notes"))

(defun dl-satan-intervention--parse-jsonb (text)
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

(defun dl-satan-intervention--normalize-pg-timestamp (cell)
  "Make a `psql -A' timestamptz CELL parseable by `date-to-time'.
`psql' renders a `timestamptz' as `YYYY-MM-DD HH:MM:SS+ZZ' (space
separator); the space defeats `parse-time-string', which then drops
the time-of-day and mis-shifts the date.  Replacing the first space
with `T' yields an ISO8601 form Emacs parses correctly, regardless of
the offset width.  nil / empty pass through unchanged."
  (if (and (stringp cell) (string-match " " cell))
      (replace-match "T" t t cell)
    cell))

(defun dl-satan-intervention--row-to-intervention (cells)
  "Convert a CELLS list (column-order matches `--lookup-columns') to plist."
  (cl-destructuring-bind
      (id run_id ts mode kind target_surface message
       related_motive_id cue_handles_json expected_outcome
       outcome_window_minutes severity)
      cells
    (list :intervention_id        id
          :run_id                 run_id
          :ts                     (dl-satan-intervention--normalize-pg-timestamp ts)
          :mode                   mode
          :kind                   kind
          :target_surface         target_surface
          :message                message
          :related_motive_id      (if (string-empty-p related_motive_id)
                                      nil
                                    related_motive_id)
          :cue_handles            (dl-satan-intervention--parse-jsonb
                                   cue_handles_json)
          :expected_outcome       expected_outcome
          :outcome_window_minutes (string-to-number outcome_window_minutes)
          :severity               severity)))

(defun dl-satan-intervention--row-to-outcome (cells)
  "Convert a CELLS list (column-order matches `--outcome-columns') to plist."
  (cl-destructuring-bind
      (classification confidence evidence_json maturity
       next_revisit_at source classified_at revises
       marked_by notes)
      cells
    (list :classification    classification
          :confidence        confidence
          :evidence          (dl-satan-intervention--parse-jsonb evidence_json)
          :maturity          maturity
          :next_revisit_at   (dl-satan-intervention--normalize-pg-timestamp
                              next_revisit_at)
          :source            source
          :classified_at     (dl-satan-intervention--normalize-pg-timestamp
                              classified_at)
          :revises           (if (string-empty-p revises) nil revises)
          :marked_by         (if (string-empty-p marked_by) nil marked_by)
          :notes             (if (string-empty-p notes) nil notes))))

(defun dl-satan-intervention-lookup (intervention-id &optional db)
  "Return `(:intervention ROW :outcome ROW|nil)' for INTERVENTION-ID, or nil."
  (let* ((db (or db dl-satan-memory-migrate-database))
         (sql (concat
               "SELECT "
               (mapconcat
                (lambda (c) (concat "COALESCE(i." c "::text, '')"))
                dl-satan-intervention--lookup-columns ", ")
               ", "
               "(o.intervention_id IS NOT NULL)::text, "
               (mapconcat
                (lambda (c) (concat "COALESCE(o." c "::text, '')"))
                dl-satan-intervention--outcome-columns ", ")
               " FROM satan_interventions i "
               "LEFT JOIN satan_intervention_outcomes o "
               "  ON i.id = o.intervention_id "
               "WHERE i.id = "
               (dl-satan-intervention--quote-text intervention-id)))
         (result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (let* ((line (string-trim out)))
         (when (and (not (string-empty-p line)))
           (let* ((cells (split-string line "|"))
                  (n-iv (length dl-satan-intervention--lookup-columns))
                  (iv-cells (cl-subseq cells 0 n-iv))
                  (has-outcome (equal "true" (nth n-iv cells)))
                  (out-cells (and has-outcome
                                  (cl-subseq cells (1+ n-iv)))))
             (list :intervention (dl-satan-intervention--row-to-intervention iv-cells)
                   :outcome (and has-outcome
                                 (dl-satan-intervention--row-to-outcome out-cells)))))))
      (`(error . ,msg) (user-error "dl-satan-intervention-lookup: %s" msg)))))

(defun dl-satan-intervention-pending (now &optional db)
  "Return intervention plists whose maturity window ≤ NOW and that lack outcomes.
NOW is an ISO8601 string accepted by PostgreSQL's `timestamptz' parser.
Excludes interventions whose `created_at + outcome_window_minutes' is
later than NOW (still `:pending' — see outcome-semantics §3), whose
`created_at + outcome_window_minutes + 24h' is earlier than NOW
(already `:stale' — auto re-pass forbidden per §6.3, T1.5b PR 3),
and any intervention that already has an outcome row in the
projection."
  (let* ((db (or db dl-satan-memory-migrate-database))
         (now-lit (concat (dl-satan-intervention--quote-text now)
                          "::timestamptz"))
         (sql (concat
               "SELECT "
               (mapconcat
                (lambda (c) (concat "COALESCE(i." c "::text, '')"))
                dl-satan-intervention--lookup-columns ", ")
               " FROM satan_interventions i "
               "LEFT JOIN satan_intervention_outcomes o "
               "  ON i.id = o.intervention_id "
               "WHERE o.intervention_id IS NULL "
               "  AND i.ts + (i.outcome_window_minutes * INTERVAL '1 minute') "
               "      <= " now-lit " "
               "  AND i.ts + (i.outcome_window_minutes * INTERVAL '1 minute') "
               "      + INTERVAL '24 hours' >= " now-lit " "
               "ORDER BY i.ts ASC"))
         (result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for cells = (split-string line "|")
                when (= (length cells)
                        (length dl-satan-intervention--lookup-columns))
                collect (dl-satan-intervention--row-to-intervention cells)))
      (`(error . ,msg) (user-error "dl-satan-intervention-pending: %s" msg)))))

(cl-defun dl-satan-intervention-recent
    (now &key include-stale (limit 50) (db dl-satan-memory-migrate-database))
  "Return up to LIMIT most recently-created interventions, newest first.
NOW is an ISO8601 string; INCLUDE-STALE nil (default) filters out
interventions whose `ts + outcome_window_minutes + 24 h' is earlier
than NOW (auto-classifier-frozen per §6.3).  Each element is the
plist shape produced by `dl-satan-intervention-lookup' under
`:intervention'."
  (let* ((now-lit (concat (dl-satan-intervention--quote-text now)
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
                dl-satan-intervention--lookup-columns ", ")
               " FROM satan_interventions i"
               where
               " ORDER BY i.ts DESC LIMIT "
               (number-to-string limit)))
         (result (dl-satan-db-psql
                  db dl-satan-memory-migrate-host dl-satan-memory-migrate-psql-program
                  (list "-A" "-t" "-F" "|" "-c" sql))))
    (pcase result
      (`(ok . ,out)
       (cl-loop for line in (split-string out "\n" t)
                for cells = (split-string line "|")
                when (= (length cells)
                        (length dl-satan-intervention--lookup-columns))
                collect (dl-satan-intervention--row-to-intervention cells)))
      (`(error . ,msg) (user-error "dl-satan-intervention-recent: %s" msg)))))

(provide 'dl-satan-intervention)
;;; dl-satan-intervention.el ends here
