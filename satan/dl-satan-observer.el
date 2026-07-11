;;; dl-satan-observer.el --- SATAN outcome observer (Phase 5) -*- lexical-binding: t; -*-

;; Drives outcome classification for prior-run interventions.  Reads
;; pending interventions from the projection (T7), classifies each via
;; `dl-satan-observer-classify' (§S5 P1–P4), and persists the verdict
;; through `dl-satan-intervention-classify' (audit-event +
;; `satan_intervention_outcomes' upsert).  On a positive verdict the
;; observer also bumps the motive's `:worked_count' / `:last_intervention_at'
;; (text-level rewrite) and writes an observation / auto_rule trace via
;; `dl-satan-memory-store-mark'.
;;
;; T7 PR 5 swapped the read path from `transcript.jsonl' walks +
;; observer.json dedup to the projection: `dl-satan-intervention-
;; pending' filters by maturity (`created_at + outcome_window_minutes
;; <= now') and outcome-row presence, so the observer no longer needs a
;; scan-window defcustom, a maturity gate, a dedup state file, or the
;; `applied_index'-based key.  Every verdict is committed via
;; `dl-satan-intervention-classify' which writes an `intervention.
;; outcome_classified' (or `outcome_revised') audit event into the
;; current run's transcript and UPSERTs the projection row in one
;; psql round-trip.
;;
;; **A3 boundary.** PR 5 is the sanctioned T7 break of byte-identical
;; rerun: the current run's transcript now grows by one
;; `outcome_classified' event per matured prior intervention, with
;; `:classified_at' set to the broker's frozen `:time_now' and
;; `:source_events' empty (PR 5 leaves the evidence-event-id wiring
;; for T1.5b).  No transcript-level golden test exists; the percept
;; A3 ert is unaffected.
;;
;; Verdict-shape extension belongs to T1.5b PR 1; PR 5 maps today's
;; positive/none classifier output to `worked'/`unknown' minimally
;; (single-predicate `medium' confidence on worked; `low' on unknown).

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-intervention)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-memory-store)
(require 'dl-satan-motive)
(require 'dl-satan-observer-classify)

;; Lazy require — `dl-satan-broker' will require this module to wire
;; the observer into prepare.  Declaring the broker symbols here lets
;; the byte-compiler see them; the actual `require' happens at
;; resolve-time so observer.el's load does not pull broker.el.
(declare-function dl-satan-broker-locate-run-dir "dl-satan-broker"
                  (run-id &optional runs-dir))
(defvar dl-satan-runs-dir)

;; ---------------------------------------------------------------------
;; Projection → classifier shape
;; ---------------------------------------------------------------------

(defun dl-satan-observer--run-dir-for (run-id &optional runs-dir)
  "Resolve RUN-ID's on-disk dir under RUNS-DIR (default `dl-satan-runs-dir').
Honours the bucketed layout + `.FAILED' rename.  Returns nil when no
candidate directory exists — the classifier downgrades to `:no_baseline'."
  (require 'dl-satan-broker)
  (dl-satan-broker-locate-run-dir run-id runs-dir))

(defun dl-satan-observer--applied-index-from-id (intervention-id)
  "Return the trailing `ivNNN' counter from INTERVENTION-ID as an integer.
Falls back to 0 when the suffix is missing (defensive — minted ids
always carry the suffix, but a manually-inserted row might not)."
  (if (and (stringp intervention-id)
           (string-match "\\.iv\\([0-9]+\\)\\'" intervention-id))
      (string-to-number (match-string 1 intervention-id))
    0))

(defun dl-satan-observer--projection-to-classifier-plist (row &optional runs-dir)
  "Normalise a projection ROW to the plist the classifier consumes.
ROW is a `dl-satan-intervention-pending' entry (per
`dl-satan-intervention--row-to-intervention').  Adds the slots the
predicate code reads (`:run_dir', `:intervention_emitted_at',
`:applied_index') without dropping the projection fields the
verdict-persister carries through to the trace metadata."
  (let* ((run-id (plist-get row :run_id))
         (run-dir (dl-satan-observer--run-dir-for run-id runs-dir))
         (iv-id (plist-get row :intervention_id)))
    (append row
            (list :run_dir run-dir
                  :intervention_emitted_at (plist-get row :ts)
                  :applied_index (dl-satan-observer--applied-index-from-id
                                  iv-id)))))

(defun dl-satan-observer-pending (now &optional runs-dir db)
  "Return classifier-ready intervention plists matured by NOW.
NOW is an ISO8601 string accepted by PostgreSQL's `timestamptz'
parser; RUNS-DIR overrides `dl-satan-runs-dir'; DB overrides the
migrate database.  Thin wrapper over `dl-satan-intervention-pending'
that resolves each row's `:run_dir' and shapes the plist for the
classifier."
  (mapcar (lambda (row)
            (dl-satan-observer--projection-to-classifier-plist row runs-dir))
          (dl-satan-intervention-pending now db)))

;; ---------------------------------------------------------------------
;; Verdict persistence
;; ---------------------------------------------------------------------

(defun dl-satan-observer--motive-handle-rows (motive)
  "Convert MOTIVE's `:cue' handles into memory-store-mark handle rows.
Each handle gets a `:rule_id observer.intervention_correlation'
provenance so resonance can later reason about which traces the
observer authored."
  (mapcar
   (lambda (h)
     (list :handle h
           :source (list :rule_id "observer.intervention_correlation"
                         :origin "derived"
                         :evidence_pointer
                         (format "/motive/%s/cue"
                                 (or (plist-get motive :id) "_")))
           :grammar_version dl-satan-memory-grammar-current-version))
   (or (plist-get motive :cue) nil)))

(defun dl-satan-observer--persist-positive (intervention motive verdict now opts)
  "Side-effect bundle for a positive verdict.
Increments MOTIVE's `:worked_count' via the 5.5 rewriter and writes
an `observation' / `auto_rule' trace via
`dl-satan-memory-store-mark'.

NOW is the ISO timestamp (frozen `:time_now') used as the new
`:last_intervention_at'.  OPTS may contain `:motive-path',
`:touch-footer-fn', `:memory-mark-fn' for test injection.

Returns `(:motive_written BOOL :trace_result CONS :new_worked_count
N)'."
  (let* ((motive-path (or (plist-get opts :motive-path)
                          dl-satan-motive-file))
         (touch-fn (or (plist-get opts :touch-footer-fn)
                       #'dl-satan-motive-touch-footer))
         (mark-fn (or (plist-get opts :memory-mark-fn)
                      #'dl-satan-memory-store-mark))
         (new-count (1+ (or (plist-get motive :worked_count) 0)))
         (motive-written
          (funcall touch-fn (plist-get motive :id) new-count now motive-path))
         (handles (dl-satan-observer--motive-handle-rows motive))
         (iv-id (plist-get intervention :intervention_id))
         (firers (plist-get verdict :predicates))
         (metadata
          (list :intervention_id iv-id
                :run_id (plist-get intervention :run_id)
                :motive_id (plist-get motive :id)
                :predicates firers
                :classification (plist-get verdict :classification)
                :confidence (plist-get verdict :confidence)))
         (payload (format "worked: %s → motive %s via %s"
                          iv-id
                          (plist-get motive :id)
                          (if firers
                              (mapconcat
                               (lambda (kw) (substring (symbol-name kw) 1))
                               firers ",")
                            "_")))
         (trace-result
          (funcall mark-fn
                   :kind "observation"
                   :trace-origin "auto_rule"
                   :source "observer"
                   :observed-start-at
                   (plist-get intervention :intervention_emitted_at)
                   :observed-end-at
                   (dl-satan-observer--window-end-iso intervention)
                   :payload payload
                   :grammar-version dl-satan-memory-grammar-current-version
                   :metadata-json metadata
                   :handles handles)))
    (list :motive_written motive-written
          :trace_result trace-result
          :new_worked_count new-count)))

;; ---- verdict → classify-args mapping --------------------------------

(defun dl-satan-observer--keyword-to-string (kw)
  "Return KW's name as a string without the leading colon, or nil."
  (and (keywordp kw) (substring (symbol-name kw) 1)))

(defun dl-satan-observer--next-revisit-iso (intervention)
  "Return `created_at + outcome_window_minutes' as an ISO string."
  (let* ((ts (plist-get intervention :ts))
         (mins (or (plist-get intervention :outcome_window_minutes) 0))
         (start (date-to-time ts)))
    (format-time-string "%Y-%m-%dT%T%:z"
                        (time-add start (seconds-to-time (* 60 mins))))))

(defun dl-satan-observer--verdict-classify-args (intervention verdict now)
  "Translate a classifier VERDICT plist into `intervention-classify' kwargs.

T1.5b PR 3 derives `:maturity' from the verdict (`:pending' or
`:mature' — `:stale' is filtered earlier; `observer-process' never
calls this helper for a nil/stale verdict).

  `:classification :worked'
    → classification \"worked\", confidence per verdict's
      `:confidence' (`:medium' or `:high'), evidence
      `(:source_events () :predicates (STR ...)
        :motive_id STR-or-:null)'.

  `:classification :ignored'
    → classification \"ignored\", confidence \"low\" or
      \"medium\", evidence
      `(:source_events ()
        :target_surface STR-or-:null
        :no_positive_predicates t
        :acknowledgement_checked t-or-:false
        :ack_events_found N)' (kebab→snake from the verdict's
      `:evidence' plist).

  `:classification :neutral'
    → classification \"neutral\", confidence \"low\", evidence
      `(:source_events ()
        :target_surface STR-or-:null
        :no_positive_predicates t)'.

  `:classification :unknown'
    → classification \"unknown\", confidence \"low\", evidence
      `(:source_events () :reason STR-or-:null)'.  Reached from the
      maturity (`:pending'), baseline, motive, and midnight guards
      AND from `classify-negative' when a user-facing intervention
      has `ack_events_found > 0' (per outcome-semantics §1).

Keywords cross the audit boundary as their lower-case names
without the leading colon (per `outcome-semantics.md' §1).

INTERVENTION is the classifier-shaped plist (after
`--projection-to-classifier-plist').  NOW is the broker's frozen
`:time_now' ISO string."
  (let* ((classification (plist-get verdict :classification))
         (confidence (plist-get verdict :confidence))
         (ev (plist-get verdict :evidence))
         (common (list :classification
                       (dl-satan-observer--keyword-to-string classification)
                       :confidence
                       (dl-satan-observer--keyword-to-string confidence)
                       :maturity
                       (dl-satan-observer--keyword-to-string
                        (or (plist-get verdict :maturity) :mature))
                       :next-revisit-at
                       (dl-satan-observer--next-revisit-iso intervention)
                       :source "auto"
                       :classified-at now))
         (evidence
          (pcase classification
            (:worked
             (list :source_events '()
                   :predicates
                   (mapcar #'dl-satan-observer--keyword-to-string
                           (plist-get verdict :predicates))
                   :motive_id (or (plist-get verdict :motive_id) :null)))
            (:ignored
             (list :source_events '()
                   :target_surface (or (plist-get ev :target-surface) :null)
                   :no_positive_predicates t
                   :acknowledgement_checked
                   (if (eq :false (plist-get ev :acknowledgement-checked))
                       :false
                     t)
                   :ack_events_found (or (plist-get ev :ack-events-found) 0)))
            (:neutral
             (list :source_events '()
                   :target_surface (or (plist-get ev :target-surface) :null)
                   :no_positive_predicates t))
            (_
             (list :source_events '()
                   :reason (or (dl-satan-observer--keyword-to-string
                                (plist-get verdict :reason))
                               :null))))))
    (append common (list :evidence evidence))))

(defun dl-satan-observer-persist-verdict
    (intervention motive verdict now &optional opts)
  "Persist VERDICT for INTERVENTION at NOW.

When VERDICT carries `:classification :worked' and MOTIVE is non-nil
this credits the motive: text-level rewrite of MOTIVE's
`:worked_count' + `:last_intervention_at' via
`dl-satan-motive-touch-footer'; an observation / auto_rule trace via
`dl-satan-memory-store-mark'.

Every verdict — `:worked' or otherwise — is committed through
`dl-satan-intervention-classify', which emits an `intervention.
outcome_classified' (or `outcome_revised') audit event and UPSERTs
the `satan_intervention_outcomes' row.  The classify call is LAST:
if the motive write or trace write fails, the intervention will be
retried on the next tick rather than silently lost.  v0 trade-off:
rare partial-failure may double-credit; documented and accepted.

OPTS forwards to the lower-level writers (used in tests):
  :motive-path        override `dl-satan-motive-file'
  :touch-footer-fn    stub `dl-satan-motive-touch-footer'
  :memory-mark-fn     stub `dl-satan-memory-store-mark'
  :ctx                tool-ctx plist for `dl-satan-intervention-classify'
                      (must carry `:audit', `:id', `:mode-name',
                      `:time-now').  Required when the caller is not
                      `dl-satan-observer-process'.
  :db                 override the migrate database for the classify
                      write.

Returns plist:
  (:classify_event   STR
   :motive_written   BOOL-or-nil
   :trace_result     CONS-or-nil
   :new_worked_count N-or-nil)"
  (let* ((opts (or opts '()))
         (positive (and motive (eq :worked (plist-get verdict :classification))))
         (result (when positive
                   (dl-satan-observer--persist-positive
                    intervention motive verdict now opts)))
         (ctx (plist-get opts :ctx))
         (db (plist-get opts :db))
         (classify-kw (dl-satan-observer--verdict-classify-args
                       intervention verdict now))
         (event (apply #'dl-satan-intervention-classify
                       :ctx ctx
                       :intervention-id (plist-get intervention :intervention_id)
                       (append classify-kw
                               (when db (list :db db))))))
    (list :classify_event event
          :motive_written (and result (plist-get result :motive_written))
          :trace_result (and result (plist-get result :trace_result))
          :new_worked_count (and result (plist-get result :new_worked_count)))))

;; ---------------------------------------------------------------------
;; Broker entry — observer.process(run_ctx)
;; ---------------------------------------------------------------------

(defun dl-satan-observer--lookup-motive (motive-id motives)
  "Return the motive plist with id MOTIVE-ID from MOTIVES, or nil."
  (and motive-id
       (cl-find motive-id motives
                :key (lambda (m) (plist-get m :id))
                :test #'equal)))

(defun dl-satan-observer--ctx-from-run-ctx (run-ctx)
  "Build the tool-ctx plist `dl-satan-intervention-classify' needs.
RUN-CTX is the broker prepare plist (carries `:run_id', `:time_now',
`:mode_name', and `:audit' as of T7 PR 5).  Slot names are
normalised to the kebab-case `tool-ctx' convention."
  (list :id (plist-get run-ctx :run_id)
        :mode-name (plist-get run-ctx :mode_name)
        :time-now (plist-get run-ctx :time_now)
        :audit (plist-get run-ctx :audit)))

(defun dl-satan-observer-process (run-ctx &optional opts)
  "Classify + persist every pending intervention.
RUN-CTX is the broker prepare plist; `:time_now' supplies NOW and
`:audit' supplies the live audit handle for outcome events.

Sequence:
  1. Read motive file (default `dl-satan-motive-file').
  2. Get pending interventions from the projection
     (`dl-satan-intervention-pending'), normalised with `:run_dir' +
     `:intervention_emitted_at' + `:applied_index'.
  3. For each pending intervention, run
     `dl-satan-observer-classify-for-motives' then
     `dl-satan-observer-persist-verdict' (writes the audit event +
     projection row through the intervention API, with motive bump +
     trace on a positive verdict).

Errors during a single intervention's persist are caught and
captured into that entry's `:error' slot; the loop continues so
one bad bundle (or postgres outage) does not block the rest of the
tick.

T1.5b PR 3 — the broker's frozen `:time_now' threads into
`dl-satan-observer-classify-for-motives' to drive the maturity
guard (outcome-semantics §3 + §6.1).  A nil verdict from the
classifier means `:stale' (defence-in-depth — `dl-satan-
intervention-pending' already excludes stale rows in SQL) and is
captured in the summary with `:skipped :stale' rather than
persisted.

OPTS forwards to the lower-level helpers (used in tests):
  :motive-path        override `dl-satan-motive-file'
  :runs-dir           override `dl-satan-runs-dir'
  :db                 override the migrate database
  :ctx                explicit tool-ctx (skips RUN-CTX-derived ctx)
  :motive-fn          stub `dl-satan-motive-read'
  :memory-mark-fn     stub `dl-satan-memory-store-mark'
  :touch-footer-fn    stub `dl-satan-motive-touch-footer'

Returns a summary plist for audit visibility:
  (:processed N
   :positive  N
   :verdicts  LIST-OF (:intervention_id :run_id :motive_id
                       :classification :confidence :predicates
                       :reason :maturity :classify_event
                       :skipped? :error?))"
  (let* ((opts (or opts '()))
         (now (or (plist-get run-ctx :time_now)
                  (format-time-string "%Y-%m-%dT%T%:z")))
         (motive-path (or (plist-get opts :motive-path)
                          dl-satan-motive-file))
         (runs-dir (plist-get opts :runs-dir))
         (db (plist-get opts :db))
         (motive-fn (or (plist-get opts :motive-fn)
                        #'dl-satan-motive-read))
         (parsed (funcall motive-fn motive-path))
         (motives (plist-get parsed :motives))
         (pending (condition-case _err
                      (dl-satan-observer-pending now runs-dir db)
                    (error nil)))
         (ctx (or (plist-get opts :ctx)
                  (dl-satan-observer--ctx-from-run-ctx run-ctx)))
         (persist-opts
          (append (list :ctx ctx)
                  (when db (list :db db))
                  (let ((kept '()))
                    (dolist (k '(:motive-path :touch-footer-fn :memory-mark-fn))
                      (when (plist-member opts k)
                        (setq kept (append kept (list k (plist-get opts k))))))
                    kept)))
         (verdicts nil)
         (positive 0))
    (dolist (iv pending)
      (condition-case err
          (let ((verdict (dl-satan-observer-classify-for-motives
                          iv motives now)))
            (cond
             ((null verdict)
              ;; PR 3 — `:stale' short-circuit from the classifier
              ;; (defence-in-depth; pending SQL already excluded).
              (push (list :intervention_id (plist-get iv :intervention_id)
                          :run_id (plist-get iv :run_id)
                          :skipped :stale)
                    verdicts))
             (t
              (let* ((motive (dl-satan-observer--lookup-motive
                              (plist-get verdict :motive_id) motives))
                     (out (dl-satan-observer-persist-verdict
                           iv motive verdict now persist-opts)))
                (when (eq :worked (plist-get verdict :classification))
                  (setq positive (1+ positive)))
                (push (list :intervention_id (plist-get iv :intervention_id)
                            :run_id (plist-get iv :run_id)
                            :motive_id (plist-get verdict :motive_id)
                            :classification (plist-get verdict :classification)
                            :confidence (plist-get verdict :confidence)
                            :predicates (plist-get verdict :predicates)
                            :reason (plist-get verdict :reason)
                            :maturity (plist-get verdict :maturity)
                            :classify_event (plist-get out :classify_event))
                      verdicts)))))
        (error
         (push (list :intervention_id (plist-get iv :intervention_id)
                     :run_id (plist-get iv :run_id)
                     :error (error-message-string err))
               verdicts))))
    ;; Pattern rebuild — guarded, isolated from the classification path.
    ;; Runs AFTER all verdicts are classified and persisted (including the
    ;; global-attribute enqueue inside `dl-satan-intervention-classify').
    ;; DR-009 §3.2: a broken pattern subsystem degrades to stale pattern
    ;; stats; it cannot abort the tick or block classification.  The
    ;; `require' is inside the guard so a load-time error never propagates
    ;; into the observer's classification path.
    (condition-case err
        (progn
          (require 'dl-satan-pattern)
          (dl-satan-pattern-rebuild db))
      (error
       (message "dl-satan-observer: pattern rebuild failed: %s"
                (error-message-string err))))
    (list :processed (length pending)
          :positive positive
          :verdicts (nreverse verdicts))))

(provide 'dl-satan-observer)
;;; dl-satan-observer.el ends here
