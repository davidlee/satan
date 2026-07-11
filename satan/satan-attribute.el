;;; satan-attribute.el --- Broker → daemon outcome enqueue -*- lexical-binding: t; -*-

;; Broker-side surface for the attribute layer (T-attr-1c slice 2).
;;
;; Two responsibilities:
;;
;;   1. The `attribute-updates-enabled' switch (design-contract §9 + §17.5).
;;      Forwarded to the daemon in every outcome payload so the daemon can
;;      write `disabled=true' events without UPSERTing the projection.
;;
;;   2. The enqueue helper that classify path in `satan-intervention'
;;      calls after writing its own audit + outcome projection rows.  Inserts
;;      one row into `satan_outcome_inbox' carrying the contract §17.3 v1.0
;;      payload, then `pg_notify satan_outcome_inbox <id>'.
;;
;; LISTEN consumer + transcript-write side live in
;; `satan-attribute-listener.el'.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-db)
(require 'satan-jsonl)

(defgroup satan-attribute nil
  "SATAN attribute layer broker surface."
  :group 'satan)

(defcustom satan-attribute-updates-enabled t
  "When non-nil, broker forwards outcome events to the attribute daemon.

When nil the broker still enqueues the source event (so the daemon records
a `disabled=true' row in `satan_attribute_events' — `satan-attrd rebuild
--include-disabled' can replay it later) but the daemon skips the
projection UPSERT.  Operator rollback path for the attributes tranche
\(design-contract §9)."
  :type 'boolean :group 'satan-attribute)

(defcustom satan-attribute-database "satan_memory"
  "Database name carrying the satan_outcome_inbox queue."
  :type 'string :group 'satan-attribute)

(defcustom satan-attribute-host "/run/postgresql"
  "Postgres host or socket directory."
  :type 'string :group 'satan-attribute)

(defcustom satan-attribute-psql-program
  (or (executable-find "psql") "psql")
  "Path to the `psql' binary."
  :type 'string :group 'satan-attribute)

(defconst satan-attribute-payload-schema-version "1.0"
  "Wire-shape `schema_version' the broker stamps on outbound payloads
\(design-contract §17.3).  Daemon rejects unknown major.")

;; ---------------------------------------------------------------------
;; JSON helpers (shared shape with satan-patch-store)
;; ---------------------------------------------------------------------

;; ---------------------------------------------------------------------
;; psql plumbing
;; ---------------------------------------------------------------------

;; ---------------------------------------------------------------------
;; payload construction
;; ---------------------------------------------------------------------

(cl-defun satan-attribute-build-outcome-payload
    (&key run-id ts intervention-id classification confidence
          intervention-kind related-motive-id cue-handles related-trace-ids
          is-revision revises)
  "Construct the broker → daemon outcome payload (design-contract §17.3 v1.0).

`is-revision' MUST be t or nil; `revises' MUST be the prior outcome
pointer string when `is-revision' is t.  The current
`satan-attribute-updates-enabled' value is stamped on the payload —
the daemon honours it per §17.5 (disabled events still write event rows
but skip the projection UPSERT)."
  (list :schema_version  satan-attribute-payload-schema-version
        :source          "outcome"
        :run_id          run-id
        :ts              ts
        :intervention_id intervention-id
        :classification  classification
        :confidence      confidence
        :evidence (list :intervention_kind  (or intervention-kind :null)
                        :related_motive_id  (or related-motive-id :null)
                        :cue_handles        (or cue-handles '())
                        :related_trace_ids  (or related-trace-ids '()))
        :is_revision     (if is-revision t :false)
        :revises         (or revises :null)
        :enabled         (if satan-attribute-updates-enabled t :false)))

(cl-defun satan-attribute-build-hippocampus-payload
    (&key run-id ts reason tool-name filename)
  "Construct the broker → daemon hippocampus payload (design-contract §6H.6).

No confidence, intervention-id, or revision fields.  The current
`satan-attribute-updates-enabled' value is stamped on the payload."
  (list :schema_version satan-attribute-payload-schema-version
        :source         "hippocampus"
        :run_id         run-id
        :ts             ts
        :reason         reason
        :tool_name      tool-name
        :filename       filename
        :is_revision    :false
        :enabled        (if satan-attribute-updates-enabled t :false)))

(cl-defun satan-attribute-build-sensor-payload
    (&key run-id ts reason sensor-type metric-value metric-unit)
  "Construct the broker → daemon sensor payload (design-contract §6S.6).

No confidence, intervention-id, or revision fields.  The current
`satan-attribute-updates-enabled' value is stamped on the payload."
  (list :schema_version satan-attribute-payload-schema-version
        :source         "sensor"
        :run_id         run-id
        :ts             ts
        :reason         reason
        :sensor_type    sensor-type
        :metric_value   metric-value
        :metric_unit    metric-unit
        :is_revision    :false
        :enabled        (if satan-attribute-updates-enabled t :false)))

;; ---------------------------------------------------------------------
;; enqueue
;; ---------------------------------------------------------------------

(defun satan-attribute-enqueue (payload &optional db)
  "Insert PAYLOAD into satan_outcome_inbox + NOTIFY satan_outcome_inbox.

PAYLOAD is a plist built via `satan-attribute-build-outcome-payload',
`satan-attribute-build-hippocampus-payload', or
`satan-attribute-build-sensor-payload'; serialised to JSONB.
Returns (ok . ID) carrying the inserted row id, or (error . MSG)."
  (let* ((database (or db satan-attribute-database))
         (json (json-serialize (satan-jsonl-prepare payload)))
         (sql (concat
               "WITH ins AS ("
               " INSERT INTO satan_outcome_inbox (payload_json) "
               " VALUES (:'payload'::jsonb) "
               " RETURNING id"
               ") "
               "SELECT id, pg_notify('satan_outcome_inbox', id::text) "
               "FROM ins"))
         (result (satan-db-query
                  database satan-attribute-host satan-attribute-psql-program
                  sql `(("payload" . ,json)))))
    (pcase result
      (`(ok . ,out)
       (let* ((parts (split-string out "\t"))
              (id-str (car parts)))
         (cons 'ok (and id-str (not (string-empty-p id-str))
                        (string-to-number id-str)))))
      (err err))))

(defalias 'satan-attribute-enqueue-outcome #'satan-attribute-enqueue)

;; ---------------------------------------------------------------------
;; Daemon-side decay-disable: satan_attribute_settings write surface
;; ---------------------------------------------------------------------
;;
;; Decay events are daemon-originated — no source-event payload to stamp
;; `:enabled' on (the §17.5 model that every other source uses).  Per
;; §15 Q7 → option A: the broker writes a row keyed
;; `attribute_updates_enabled' into `satan_attribute_settings' on every
;; toggle of `satan-attribute-updates-enabled', and the daemon's
;; `DecayScheduler::tick' SELECTs that row at tick start.  See
;; design-contract §17.5 "Decay path".

(defun satan-attribute--write-enabled-setting (value &optional db)
  "Upsert `attribute_updates_enabled' = VALUE into `satan_attribute_settings'.
VALUE is a Lisp boolean (`t' or `nil').  Returns (ok . _) or (error . MSG)."
  (let* ((database (or db satan-attribute-database))
         (json-value (if value "true" "false"))
         (sql (concat
               "INSERT INTO satan_attribute_settings (name, value) "
               "VALUES ('attribute_updates_enabled', :'value'::jsonb) "
               "ON CONFLICT (name) DO UPDATE "
               "  SET value = EXCLUDED.value, updated_at = NOW()")))
    (satan-db-query database satan-attribute-host satan-attribute-psql-program sql `(("value" . ,json-value)))))

(defun satan-attribute--on-enabled-change (_sym newval op _where)
  "Variable-watcher hook for `satan-attribute-updates-enabled'.
Mirrors the new value into `satan_attribute_settings' on every `set'.
Errors are logged to `*Messages*' and swallowed — a DB write failure
must not block the customize-set operation."
  (when (eq op 'set)
    (condition-case err
        (let ((result (satan-attribute--write-enabled-setting newval)))
          (pcase result
            (`(error . ,msg)
             (message "satan-attribute: settings write failed: %s" msg))
            (_ nil)))
      (error
       (message "satan-attribute: settings write raised: %S" err)))))

(add-variable-watcher 'satan-attribute-updates-enabled
                      #'satan-attribute--on-enabled-change)

;; No explicit first-load seed: the 0012 migration seeds the row at the
;; defcustom default (`true').  Operator-customised values reach the row
;; via the variable-watcher above — `custom-set-variables' (run after
;; this file loads) triggers `set' operations the watcher observes.  An
;; operator changing the defcustom AND never starting emacs is the
;; degenerate case; one start propagates the value.

(provide 'satan-attribute)
;;; satan-attribute.el ends here
