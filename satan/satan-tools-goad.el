;;; satan-tools-goad.el --- goad_ask tool handler -*- lexical-binding: t; -*-

;; SL-016 PROMPT (design sec-3 "The tool").  SATAN asks the keeper a
;; question through goad: record the ask, project its row, rewrite the
;; queue goad renders from, ring goad's doorbell.  The handler is a
;; pipeline of the design's eight steps:
;;
;;   1-3  refuse   interactive MCP, goad off or quiet, invalid form
;;                 -> (error . REASON); nothing recorded, enqueued,
;;                    queued or rung
;;   4    gate     subject perceived, not goad-minted, cued by a live
;;                 motive; no winner -> suppression: `ask_suppressed'
;;                 enqueued, nothing recorded, (ok :asked :false ...)
;;   5    record   the transcript line; a failure -> (error . MSG)
;;   6-7  publish  project the row, rewrite the queue; a failure ->
;;                 undelivered verdict, no ring
;;   8    ring     `goad-emit' through the ledgered `satan-trace-call';
;;                 its outcome never changes the tool result
;;
;; A refusal decided nothing about the question; a suppression did —
;; it is an outcome, and lands where it is perceptible (design sec-1,
;; sec-7).

;;; Code:

(require 'cl-lib)
(require 'satan-custom)
(require 'satan-tools)
(require 'satan-goad)
(require 'satan-intervention)
(require 'satan-attribute)
(require 'satan-motive)
(require 'satan-memory-canon)
(require 'satan-trace)
(require 'satan-tick)                   ; `satan-tick-quiet-p'

(defconst satan-tools-goad-window-minutes 60
  "The ask's `outcome_window_minutes' (design sec-3, RV-007 F-10).")

(defconst satan-tools-goad-severity "low"
  "An ask's intervention severity: a question the keeper may ignore.")

(defconst satan-tools-goad-expected-outcome
  "keeper answers the question in goad within window"
  "An ask's `expected_outcome'.")

(defconst satan-tools-goad-emit-args '("--source" "satan" "--kind" "ask")
  "goad-emit's argv: `--source' and `--kind' are required, `--data' is not
\(goad-emit `args.rs'); `host' is reserved, so SATAN names itself.")

;; ── steps 1-3: refusals ─────────────────────────────────────────────────────

(defun satan-tools-goad--refusal (ctx)
  "Why the ask must be refused outright in CTX, or nil.
Interactive MCP first (RV-007 F-12, F-26), then goad's kill switch and
its quiet window at the run's frozen `:time-now'."
  (cond
   ((equal (plist-get ctx :mode-name) "interactive")
    "goad_ask is refused in interactive MCP sessions: no percept to ask from")
   ((not satan-goad-enabled)
    "goad is disabled (satan-goad-enabled is nil)")
   ((satan-tick-quiet-p (satan-memory-canon-parse-instant
                         (plist-get ctx :time-now))
                        satan-goad-quiet-hours)
    "inside goad's quiet window (satan-goad-quiet-hours)")))

(defun satan-tools-goad--form (args)
  "`(ok . REBUILT)' for ARGS' form, `(ok)' when it has none, or
`(error . REASON)'.  A present form is validated even when empty — a
JSON `[]' decodes to nil, and a present form must not be empty."
  (let ((form (plist-member args :form)))
    (if form (satan-goad-form-validate (cadr form)) (list 'ok))))

;; ── step 4: the subject gate (design sec-1) ─────────────────────────────────

(defun satan-tools-goad--goad-minted-p (subject sources)
  "Non-nil when SUBJECT is a handle goad minted: `app:goad', or a handle
SOURCES (the run's frozen `:handle_sources') attributes to canon's
`goad.outstanding' rule.  The percept, not live goad state, decides —
an ask answered while the run is in flight must not free its own topic
to be asked about (RV-017 F-5, RV-007 F-20)."
  (or (equal subject "app:goad")
      (equal (symbol-name 'goad.outstanding)
             (plist-get (cl-find subject sources
                                 :key (lambda (s) (plist-get s :handle))
                                 :test #'equal)
                        :rule_id))))

(defun satan-tools-goad--ungrounded (subject ctx)
  "Why SUBJECT gives no grounds to ask in CTX, before motives are
consulted, or nil."
  (cond
   ((not (member subject (plist-get ctx :percept-handles)))
    "subject is not in this run's percept")
   ((satan-tools-goad--goad-minted-p subject (plist-get ctx :percept-sources))
    "subject is goad-minted: a goad handle cannot correlate")))

(defun satan-tools-goad--winner (subject percept motives)
  "The live motive credited with an ask about SUBJECT, or nil.
Only MOTIVES whose cue holds SUBJECT compete, ranked by overlap with
PERCEPT, ties by file order (`satan-motive-rank-by-overlap') — so a
motive cued on goad's own handles cannot absorb the ask (RV-007 F-28)."
  (plist-get (car (satan-motive-rank-by-overlap
                   (cl-remove-if-not (lambda (m)
                                       (member subject (plist-get m :cue)))
                                     motives)
                   percept))
             :motive))

(defvar satan-tools-goad--suppressed-run nil
  "The id of the last run whose `ask_suppressed' enqueue succeeded.
Suppression is a condition of the run, not a count of the model's
retries, so a run enqueues it at most once (RV-017 F-7).")

(defun satan-tools-goad--enqueue-suppression (ctx)
  "Enqueue this run's `ask_suppressed' attribute payload, once per run.
nil, or `(:enqueue \"failed: MSG\")'.  Never signals: the suppression
is decided either way."
  (let ((run-id (plist-get ctx :id)))
    (unless (equal run-id satan-tools-goad--suppressed-run)
      (pcase (satan-attribute-enqueue-ask
              run-id (plist-get ctx :time-now) "ask_suppressed")
        (`(error . ,msg) (list :enqueue (format "failed: %s" msg)))
        (_ (setq satan-tools-goad--suppressed-run run-id) nil)))))

(defun satan-tools-goad--suppress (ctx reason)
  "Suppress the ask in CTX for REASON: enqueue it, record nothing."
  (cons 'ok (append (list :asked :false :reason reason)
                    (satan-tools-goad--enqueue-suppression ctx))))

;; ── steps 5-8: record, publish, ring ────────────────────────────────────────

(defun satan-tools-goad--error-of (fn &rest args)
  "Call FN with ARGS: nil, or the error it signalled."
  (condition-case err (progn (apply fn args) nil) (error err)))

(defun satan-tools-goad--publish (payload now)
  "Project PAYLOAD's row, then rewrite the queue from the asks open at NOW.
nil, or the first error — a later step never runs after a failed one."
  (or (satan-tools-goad--error-of #'satan-intervention-project payload)
      (satan-tools-goad--error-of #'satan-goad-queue-rewrite now)))

(defun satan-tools-goad--ring ()
  "Ring goad's doorbell.  Its outcome is ledgered by `satan-trace-call' and
never interpreted (design sec-4): exit 0 does not mean delivered, and a
refused or failed ring loses nothing — the queue carries the ask."
  (condition-case err
      (satan-trace-call satan-goad-emit-program satan-tools-goad-emit-args
                        :timeout-secs satan-goad-emit-timeout
                        :label "goad-emit")
    (error (message "satan-tools-goad: goad-emit signalled: %s"
                    (error-message-string err)))))

(defun satan-tools-goad--record (ctx question subject form motive-id)
  "Record the ask in CTX's transcript, credited to MOTIVE-ID and cued on
SUBJECT alone; its payload.  Signals on failure."
  (satan-intervention-record
   :ctx ctx :kind "ask" :target-surface "goad"
   :message question
   :expected-outcome satan-tools-goad-expected-outcome
   :related-motive-id motive-id
   :cue-handles (list subject)
   :outcome-window-minutes satan-tools-goad-window-minutes
   :severity satan-tools-goad-severity
   :form form))

(defun satan-tools-goad--deliver (ctx payload)
  "Publish the recorded PAYLOAD and ring goad; the tool result.
A failed publish marks it undelivered and does not ring: the question
is not reliably queued.  Never signals."
  (let ((asked (list :asked t
                     :intervention_id (plist-get payload :intervention_id)))
        (perr (satan-tools-goad--publish payload (plist-get ctx :time-now))))
    (if (null perr)
        (progn (satan-tools-goad--ring)
               (cons 'ok asked))
      (cons 'ok (append asked
                        (list :delivered :false
                              :error (error-message-string perr))
                        (satan-intervention-mark-undelivered
                         ctx payload perr))))))

(defun satan-tools-goad--ask (ctx question subject form motive-id)
  "Record the ask, then deliver it; the tool result.
A failed record is `(error . MSG)', and nothing else happens."
  (let ((recorded (condition-case rerr
                      (cons 'ok (satan-tools-goad--record
                                 ctx question subject form motive-id))
                    (error (cons 'error (error-message-string rerr))))))
    (if (eq (car recorded) 'error)
        recorded
      (satan-tools-goad--deliver ctx (cdr recorded)))))

;; ── the handler ─────────────────────────────────────────────────────────────

(defun satan-tool/goad-ask (args ctx)
  "Ask the keeper QUESTION about SUBJECT through goad (design sec-3).

ARGS:  (:question STR :subject HANDLE [:form FORM]).
CTX:   broker-supplied tool-ctx: `:id', `:mode-name', `:time-now',
       `:audit', `:percept-handles', `:percept-sources'.

Returns:
  (error . REASON)                       refused — nothing happened;
  (ok :asked :false :reason R [:enqueue ...])   suppressed — no motive
                                         correlates; recorded as an attribute;
  (ok :asked t :intervention_id IV)      asked, queued and rung;
  (ok :asked t :intervention_id IV :delivered :false :error ERR
      [:verdict ...] [:projection ...])  recorded but never queued."
  (let ((refusal (or (satan-tools-goad--refusal ctx)
                     (satan-goad-question-invalid
                      (plist-get args :question)))))
    (if refusal
        (cons 'error refusal)
      (pcase (satan-tools-goad--form args)
        (`(error . ,reason) (cons 'error reason))
        (`(ok . ,form)
         (let* ((subject (plist-get args :subject))
                (percept (plist-get ctx :percept-handles))
                (winner (satan-tools-goad--winner
                         subject percept
                         (plist-get (satan-motive-read satan-motive-file)
                                    :motives)))
                (reason (or (satan-tools-goad--ungrounded subject ctx)
                            (and (null winner)
                                 "no live motive's cue holds the subject"))))
           (if reason
               (satan-tools-goad--suppress ctx reason)
             (satan-tools-goad--ask ctx (plist-get args :question) subject
                                    form (plist-get winner :id)))))))))

(satan-tool-register
 (list :name "goad_ask"
       :risk 'low
       :capability 'goad-ask
       ;; Offered only where it can ask: never in interactive MCP,
       ;; and only while goad is enabled (RV-017 F-4).
       :available-p (lambda (mode)
                      (and satan-goad-enabled
                           (not (equal mode "interactive"))))
       :args-schema '(question (:type string :required t)
                      subject  (:type string :required t)
                      form     (:type array :required nil :items object))
       :handler 'satan-tool/goad-ask))

(provide 'satan-tools-goad)
;;; satan-tools-goad.el ends here
