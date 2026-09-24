;;; satan-tools-goad-test.el --- ert tests for the goad_ask tool -*- lexical-binding: t; -*-

;; SL-016 PHASE-06 T3–T5: the `goad_ask' handler (design sec-3 "The
;; tool").  goad-emit is always stubbed — `satan-trace-call' is replaced
;; for every test through `satan-tools-goad-test--with-goad', so no test
;; ever rings a live goad host.  The attribute enqueue is stubbed the
;; same way.  Tests that record-and-project reuse the intervention
;; suite's `--with-db' / `--with-ctx' fixtures; refusal and suppression
;; tests need no database, and prove it by spying on every side effect.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-goad)
(require 'satan-mode)
(require 'satan-tick)
(require 'satan-goad)
(require 'satan-memory-canon)
(require 'satan-goad-fixture)
(require 'satan-intervention-test)
(require 'satan-broker)
(require 'satan-mcp)
(require 'satan-tools-vcs)

;; ── fixtures ────────────────────────────────────────────────────────────────

(defconst satan-tools-goad-test--subject "artifact:thesis-outline"
  "The perceived, non-goad handle the fixture asks are about.")

(defconst satan-tools-goad-test--percept
  '("app:emacs" "artifact:thesis-outline" "domain_kind:docs" "app:goad")
  "The fixture run's percept handles: the subject, context, and goad's own.")

(defconst satan-tools-goad-test--question "Is the outline still the next step?")

(defun satan-tools-goad-test--motive (id cue)
  "Motive-file text for one active motive ID cued on CUE (a string)."
  (format "* test: %s\n  Prose for %s.\n  :cue: %s\n  :cooldown_s: 1800\n\n"
          id id cue))

(defconst satan-tools-goad-test--thesis-motive
  (satan-tools-goad-test--motive "thesis" "artifact:thesis-outline app:emacs")
  "A motive whose cue holds the fixture subject.")

(defvar satan-tools-goad-test--rings nil
  "Each stubbed `satan-trace-call', newest first: (PROGRAM ARGS KEYS).")

(defvar satan-tools-goad-test--ring-result '(:exit 0 :stdout "" :timed-out nil)
  "What the stubbed doorbell returns.")

(defvar satan-tools-goad-test--enqueued nil
  "Each stubbed `satan-attribute-enqueue' payload, newest first.")

(defun satan-tools-goad-test--hour-window (time-now offset)
  "A one-hour quiet window starting OFFSET hours after TIME-NOW's local hour.
Offset 0 holds TIME-NOW; offset 1 excludes it — in whatever zone the
suite runs, since `satan-tick-quiet-p' reads the local hour."
  (let ((h (string-to-number
            (format-time-string
             "%H" (satan-memory-canon-parse-instant time-now)))))
    (cons (mod (+ h offset) 24) (mod (+ h offset 1) 24))))

(defun satan-tools-goad-test--doorbell-stub (trace-call)
  "A `satan-trace-call' that stubs goad-emit and passes all else to TRACE-CALL.
psql runs through `satan-trace-call' too, so only the doorbell is
stubbed: it records (PROGRAM ARGS KEYS) and returns
`satan-tools-goad-test--ring-result' (or calls it, when a function)."
  (lambda (program args &rest keys)
    (if (not (equal program satan-goad-emit-program))
        (apply trace-call program args keys)
      (push (list program args keys) satan-tools-goad-test--rings)
      (if (functionp satan-tools-goad-test--ring-result)
          (funcall satan-tools-goad-test--ring-result)
        satan-tools-goad-test--ring-result))))

(defmacro satan-tools-goad-test--with-goad (motives &rest body)
  "BODY with goad enabled outside its quiet window, a scratch queue, MOTIVES
\(motive-file text, parsed for real) as the live motive file, and the
doorbell and the attribute enqueue stubbed."
  (declare (indent 1))
  (let ((dir (make-symbol "dir")))
    `(satan-goad-fixture-with-tmp ,dir
       (let ((satan-goad-enabled t)
             (satan-goad-quiet-hours (satan-tools-goad-test--hour-window
                                      "2026-05-23T12:00:00+1000" 1))
             (satan-motive-file (expand-file-name "motives.org" ,dir))
             (satan-tools-goad-test--rings nil)
             (satan-tools-goad-test--enqueued nil)
             (satan-tools-goad--suppressed-run nil))
         (satan-goad-fixture-write satan-motive-file ,motives)
         (cl-letf (((symbol-function 'satan-trace-call)
                    (satan-tools-goad-test--doorbell-stub
                     (symbol-function 'satan-trace-call)))
                   ((symbol-function 'satan-attribute-enqueue)
                    (lambda (payload &optional _db)
                      (push payload satan-tools-goad-test--enqueued)
                      '(ok . 1))))
           ,@body)))))

(defmacro satan-tools-goad-test--spying (calls fns &rest body)
  "BODY with each function in FNS (unquoted symbols) replaced by a spy.
A spy pushes its name onto CALLS (a symbol, bound to nil around BODY)
and returns nil.  A spy never signals — an `ert-fail' raised inside the
handler could be caught by its own `condition-case' — so assert on
CALLS afterwards."
  (declare (indent 2))
  `(let ((,calls nil))
     (cl-letf ,(mapcar (lambda (fn)
                         `((symbol-function ',fn)
                           (lambda (&rest _) (push ',fn ,calls) nil)))
                       fns)
       ,@body)))

(defun satan-tools-goad-test--ctx (&optional ctx &rest overrides)
  "A tick-pulse tool-ctx perceiving the fixture percept, from CTX.
CTX defaults to a bare plist with no audit handle (nothing may record
through it); OVERRIDES (a plist) replace keys."
  (let ((c (copy-sequence
            (or ctx (list :id "20260523T120000-tick-pulse-aaaaaa"
                          :time-now "2026-05-23T12:00:00+1000")))))
    (setq c (plist-put c :mode-name "tick-pulse"))
    (setq c (plist-put c :percept-handles satan-tools-goad-test--percept))
    (cl-loop for (k v) on overrides by #'cddr
             do (setq c (plist-put c k v)))
    c))

(defun satan-tools-goad-test--ask (ctx &rest args)
  "Call the handler in CTX; ARGS (a plist) override the fixture question
and subject."
  (satan-tool/goad-ask
   (append args (list :question satan-tools-goad-test--question
                      :subject satan-tools-goad-test--subject))
   ctx))

(defmacro satan-tools-goad-test--should-refuse (result-form)
  "Assert RESULT-FORM is `(error . REASON)' and touched nothing at all."
  `(satan-tools-goad-test--spying calls
       (satan-intervention-record
        satan-attribute-enqueue satan-goad-queue-rewrite)
     (let ((result ,result-form))
       (should (eq 'error (car-safe result)))
       (should (stringp (cdr result)))
       (should-not calls)
       (should-not satan-tools-goad-test--rings)
       result)))

(defmacro satan-tools-goad-test--should-suppress (result-form)
  "Assert RESULT-FORM is a not-asked `ok', recorded nothing, rang nothing,
and enqueued exactly one `ask_suppressed' payload."
  `(satan-tools-goad-test--spying calls
       (satan-intervention-record satan-goad-queue-rewrite)
     (let ((result ,result-form))
       (should (eq 'ok (car-safe result)))
       (should (eq :false (plist-get (cdr result) :asked)))
       (should (stringp (plist-get (cdr result) :reason)))
       (should-not calls)
       (should-not satan-tools-goad-test--rings)
       (should (equal '("ask_suppressed")
                      (mapcar (lambda (p) (plist-get p :reason))
                              satan-tools-goad-test--enqueued)))
       result)))

(defun satan-tools-goad-test--recorded (ctx)
  "The `intervention.created' payloads in CTX's transcript."
  (satan-intervention-test--events-named ctx "intervention.created"))

(defun satan-tools-goad-test--boom (&rest _)
  "A failing step: signals \"boom\"."
  (error "boom"))

;; ── T3: registration ────────────────────────────────────────────────────────

(ert-deftest satan-tools-goad/registered-for-tick-pulse ()
  "`goad_ask' is registered behind the `goad-ask' capability, and
tick-pulse allowlists both the tool and the capability."
  (let ((spec (satan-tool-lookup "goad_ask"))
        (mode (satan-mode-resolve "tick-pulse")))
    (should (eq 'goad-ask (plist-get spec :capability)))
    (should (member "goad_ask" (plist-get mode :tools)))
    (should (memq 'goad-ask (plist-get mode :capabilities)))))

(ert-deftest satan-tools-goad/manifest-omits-tool-while-disabled ()
  "RV-017 F-4 — the kill switch hides `goad_ask' from the model: a run's
manifest lists it only while `satan-goad-enabled' is non-nil."
  (satan-goad-fixture-with-tmp dir
    (let ((satan-tools-descriptions-dir dir)
          (mode (list :name "t" :tools '("goad_ask" "vcs_log"))))
      (dolist (name '("goad_ask" "vcs_log" "satan_final"))
        (satan-goad-fixture-write (expand-file-name (concat name ".md") dir)
                                  "A tool."))
      (cl-flet ((names ()
                  (let ((m (satan-broker--build-manifest mode "r")))
                    (list (plist-get m :tools_allowed)
                          (mapcar (lambda (tool)
                                    (plist-get (plist-get tool :function) :name))
                                  (plist-get m :tools))))))
        (let ((satan-goad-enabled nil))
          (should (equal '(("vcs_log") ("vcs_log" "satan_final")) (names))))
        (let ((satan-goad-enabled t))
          (should (equal '(("goad_ask" "vcs_log")
                           ("goad_ask" "vcs_log" "satan_final"))
                         (names))))))))

(ert-deftest satan-tools-goad/mcp-never-offers-tool ()
  "RV-017 F-4 — the interactive MCP surface never lists `goad_ask', even
with goad enabled: the tool refuses every interactive call."
  (let ((satan-goad-enabled t))
    (should-not (member "goad_ask" (satan-mcp--interactive-tools)))
    (should (member "vcs_log" (satan-mcp--interactive-tools)))))

(ert-deftest satan-tools-goad/schema-requires-question-and-subject ()
  "The args schema requires `question' and `subject'; `form' is optional."
  (let ((spec (satan-tool-lookup "goad_ask")))
    (should (satan-tool-validate-args spec '(:subject "app:emacs")))
    (should (satan-tool-validate-args spec '(:question "q")))
    (should-not (satan-tool-validate-args
                 spec '(:question "q" :subject "app:emacs")))))

(ert-deftest satan-tools-goad/corpus-description-present ()
  "The model-facing description exists in the corpus, so the manifest
builds for every mode that allowlists `goad_ask' (design sec-3 \"Two
repos, one landing\").  Skips where the corpus is absent."
  (skip-unless (file-readable-p (expand-file-name
                                 "goad_ask.md" satan-tools-descriptions-dir)))
  (let ((fn (plist-get (satan-tool-json-schema (satan-tool-lookup "goad_ask"))
                       :function)))
    (should (string-match-p "subject" (plist-get fn :description)))
    (should (equal ["question" "subject"]
                   (plist-get (plist-get fn :parameters) :required)))))

;; ── T4: refusals touch nothing (VT-9, VT-38, VT-60) ─────────────────────────

(ert-deftest satan-tools-goad/refuses-in-mcp ()
  "VT-9 — interactive MCP mode refuses before anything else, so it never
records a false suppression either."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (satan-tools-goad-test--should-refuse
     (satan-tools-goad-test--ask
      (satan-tools-goad-test--ctx nil :mode-name "interactive")))))

(ert-deftest satan-tools-goad/quiet-window-refuses ()
  "VT-38 — inside goad's quiet window, and with goad disabled, the ask is
refused: nothing recorded, enqueued, queued or rung."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (let ((satan-goad-quiet-hours (satan-tools-goad-test--hour-window
                                   "2026-05-23T12:00:00+1000" 0)))
      (satan-tools-goad-test--should-refuse
       (satan-tools-goad-test--ask (satan-tools-goad-test--ctx))))
    (let ((satan-goad-enabled nil))
      (satan-tools-goad-test--should-refuse
       (satan-tools-goad-test--ask (satan-tools-goad-test--ctx))))))

(ert-deftest satan-tools-goad/invalid-form-refused ()
  "VT-60 — an invalid answer form is refused with the validator's reason."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (let ((result (satan-tools-goad-test--should-refuse
                   (satan-tools-goad-test--ask
                    (satan-tools-goad-test--ctx)
                    :form '((:id "Bad Id" :label "x"))))))
      (should (equal (cdr result)
                     (cdr (satan-goad-form-validate
                           '((:id "Bad Id" :label "x")))))))))

(ert-deftest satan-tools-goad/invalid-question-refused ()
  "RV-017 F-8 — goad renders the question as its view title: a blank or
over-long question is refused outright, nothing recorded."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (dolist (question (list "" "   " (make-string
                                    (1+ satan-goad-question-max-chars) ?x)))
      (satan-tools-goad-test--should-refuse
       (satan-tools-goad-test--ask (satan-tools-goad-test--ctx)
                                   :question question)))))

;; ── T5: the subject gate (VT-6, VT-13) ──────────────────────────────────────

(ert-deftest satan-tools-goad/suppressed-enqueues-attribute ()
  "VT-6 — no live motive's cue holds the subject: nothing recorded, one
`ask_suppressed' attribute payload for this run."
  (satan-tools-goad-test--with-goad
      (satan-tools-goad-test--motive "elsewhere" "app:firefox")
    (satan-tools-goad-test--should-suppress
     (satan-tools-goad-test--ask (satan-tools-goad-test--ctx)))
    (let ((payload (car satan-tools-goad-test--enqueued)))
      (should (equal "20260523T120000-tick-pulse-aaaaaa"
                     (plist-get payload :run_id))))))

(ert-deftest satan-tools-goad/dormant-motive-does-not-correlate ()
  "A dormant motive whose cue holds the subject does not correlate."
  (satan-tools-goad-test--with-goad
      ;; `project:' is not a sensor-observed namespace, so it goes dormant.
      "* test: stale\n  Prose.\n  :cue: project:x\n  :cooldown_s: 1800\n"
    (satan-tools-goad-test--should-suppress
     (satan-tools-goad-test--ask (satan-tools-goad-test--ctx)
                                 :subject "project:x"))))

(ert-deftest satan-tools-goad/unperceived-subject-suppressed ()
  "A subject outside the run's percept is suppressed even when a motive
cues it: SATAN may only ask about what it already perceives."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (satan-tools-goad-test--should-suppress
     (satan-tools-goad-test--ask
      (satan-tools-goad-test--ctx nil :percept-handles '("app:emacs"))))))

(defun satan-tools-goad-test--sources (&rest pairs)
  "Frozen-percept `:handle_sources' rows from PAIRS of HANDLE RULE-ID."
  (cl-loop for (h rule) on pairs by #'cddr
           collect (list :handle h :rule_id rule :origin "observed")))

(ert-deftest satan-tools-goad/goad-subject-refused ()
  "VT-13 — a goad-minted subject cannot correlate, even perceived and cued:
`app:goad', and a `topic:' the run's frozen percept sourced from
`goad.outstanding'.  The gate reads the percept, never live goad state:
here the queue is empty — as if the keeper answered while the run was in
flight (RV-017 F-5) — and the topic is still refused.  Both are
suppressions (orchestrator OQ-1): no record, one `ask_suppressed'."
  (let* ((topic (satan-goad-subject-topic "artifact:thesis-outline"))
         (percept (append (list topic) satan-tools-goad-test--percept)))
    (satan-tools-goad-test--with-goad
        (satan-tools-goad-test--motive "goad-watch" (concat "app:goad " topic))
      (dolist (subject (list "app:goad" topic))
        (setq satan-tools-goad-test--enqueued nil)
        (satan-tools-goad-test--should-suppress
         (satan-tools-goad-test--ask
          (satan-tools-goad-test--ctx
           nil :percept-handles percept
           :percept-sources (satan-tools-goad-test--sources
                             "app:goad" "goad.outstanding"
                             topic "goad.outstanding")
           :id (format "20260523T120000-tick-pulse-%s"
                       (if (equal subject "app:goad") "aaaaaa" "bbbbbb")))
          :subject subject))))))

(ert-deftest satan-tools-goad/suppression-enqueued-once-per-run ()
  "RV-017 F-7 — suppression is a condition of the run, not a count of the
model's retries: repeated suppressed asks in one run enqueue one
`ask_suppressed'; a later run enqueues again."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (let ((unperceived (satan-tools-goad-test--ctx
                        nil :percept-handles '("app:emacs"))))
      (dotimes (_ 3)
        (should (eq :false (plist-get (cdr (satan-tools-goad-test--ask
                                             unperceived))
                                      :asked))))
      (should (= 1 (length satan-tools-goad-test--enqueued)))
      (satan-tools-goad-test--ask
       (satan-tools-goad-test--ctx
        nil :percept-handles '("app:emacs")
        :id "20260523T123000-tick-pulse-cccccc"))
      (should (= 2 (length satan-tools-goad-test--enqueued))))))

(ert-deftest satan-tools-goad/failed-suppression-enqueue-retried ()
  "RV-017 F-7 — a failed `ask_suppressed' enqueue is reported and does not
count: the run's next suppression tries again."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (let ((ctx (satan-tools-goad-test--ctx nil :percept-handles '("app:emacs")))
          (attempts 0))
      (cl-letf (((symbol-function 'satan-attribute-enqueue)
                 (lambda (&rest _)
                   (setq attempts (1+ attempts))
                   (if (= attempts 1) '(error . "db down") '(ok . 1)))))
        (should (plist-get (cdr (satan-tools-goad-test--ask ctx)) :enqueue))
        (should-not (plist-get (cdr (satan-tools-goad-test--ask ctx)) :enqueue))
        (satan-tools-goad-test--ask ctx)
        (should (= 2 attempts))))))

(ert-deftest satan-tools-goad/independently-perceived-topic-askable ()
  "RV-017 F-5 — a `topic:' the frozen percept sourced from a rule other
than `goad.outstanding' is askable, whatever the queue holds: the gate
refuses exactly what goad minted into this run's percept."
  (let* ((queued "artifact:thesis-outline")
         (topic (satan-goad-subject-topic queued))
         (percept (cons topic satan-tools-goad-test--percept)))
    (satan-intervention-test--with-db
      (satan-intervention-test--with-ctx ctx
        (satan-tools-goad-test--with-goad
            (satan-tools-goad-test--motive "topic" topic)
          (satan-goad-fixture-write-queue
           (list (satan-goad-fixture-ask :subject queued)))
          (let ((result (satan-tools-goad-test--ask
                         (satan-tools-goad-test--ctx
                          ctx :percept-handles percept
                          :percept-sources (satan-tools-goad-test--sources
                                            topic "hint.topic"))
                         :subject topic)))
            (should (eq t (plist-get (cdr result) :asked)))))))))

(ert-deftest satan-tools-goad/first-ask-correlates ()
  "VT-13 — with an empty queue, a motive whose cue holds a perceived
`artifact:' subject correlates: the ask is recorded against that motive,
cued on the subject alone, with a 60-minute window."
  (satan-intervention-test--with-db
    (satan-intervention-test--with-ctx ctx
      (satan-tools-goad-test--with-goad
          (concat (satan-tools-goad-test--motive "other" "app:firefox")
                  satan-tools-goad-test--thesis-motive)
        (let* ((result (satan-tools-goad-test--ask
                        (satan-tools-goad-test--ctx ctx)))
               (created (car (satan-tools-goad-test--recorded ctx))))
          (should (eq 'ok (car result)))
          (should (eq t (plist-get (cdr result) :asked)))
          (should (equal "thesis" (plist-get created :related_motive_id)))
          (should (equal (list satan-tools-goad-test--subject)
                         (plist-get created :cue_handles)))
          (should (equal "ask" (plist-get created :kind)))
          (should (equal "goad" (plist-get created :target_surface)))
          (should (= 60 (plist-get created :outcome_window_minutes)))
          (should (equal (list (plist-get created :intervention_id))
                         (satan-goad-fixture-iids
                          (satan-goad-read-queue)))))))))

(ert-deftest satan-tools-goad/goad-motive-cannot-absorb ()
  "VT-29 — with an ask outstanding, a motive cued on goad's own handles
overlaps the percept more, yet only motives cueing the subject compete:
B is credited, not A."
  (let* ((queued "domain_kind:docs")
         (topic (satan-goad-subject-topic queued))
         (percept (append (list topic) satan-tools-goad-test--percept)))
    (satan-intervention-test--with-db
      (satan-intervention-test--with-ctx ctx
        (satan-tools-goad-test--with-goad
            (concat (satan-tools-goad-test--motive
                     "a" (concat "app:goad " topic " app:emacs"))
                    (satan-tools-goad-test--motive
                     "b" "artifact:thesis-outline"))
          (satan-goad-fixture-write-queue
           (list (satan-goad-fixture-ask :subject queued)))
          (satan-tools-goad-test--ask
           (satan-tools-goad-test--ctx ctx :percept-handles percept))
          (should (equal "b" (plist-get (car (satan-tools-goad-test--recorded
                                              ctx))
                                        :related_motive_id))))))))

(ert-deftest satan-tools-goad/form-recorded-rebuilt ()
  "A valid form is recorded as the validator rebuilt it, and queued."
  (satan-intervention-test--with-db
    (satan-intervention-test--with-ctx ctx
      (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
        (let ((form (vector (list :label "Rate it" :id "rate"
                                  :fields (vector (list :kind "number"
                                                        :id "energy"
                                                        :label "Energy"
                                                        :max 10 :min 0)))
                            (list :id "skip" :label "Not now"))))
          (satan-tools-goad-test--ask (satan-tools-goad-test--ctx ctx)
                                      :form form)
          (let ((rebuilt (cdr (satan-goad-form-validate form))))
            (should (equal rebuilt (plist-get
                                    (car (satan-tools-goad-test--recorded ctx))
                                    :form)))
            (should (equal (satan-goad-fixture-json-canon rebuilt)
                           (satan-goad-fixture-json-canon
                            (plist-get (car (satan-goad-read-queue))
                                       :form))))))))))

;; ── T5: record, project, rewrite, ring (VT-5, VT-11, VT-41) ─────────────────

(defconst satan-tools-goad-test--ring-results
  '((:exit 0 :stdout "" :timed-out nil)
    (:exit 1 :stdout "goad-emit: refused: too_soon\n" :timed-out nil)
    (:exit 2 :stdout "goad-emit: no host\n" :timed-out nil)
    (:exit 124 :stdout "" :timed-out t))
  "The doorbell's four outcomes: taken, refused, unrung, timed out.")

(ert-deftest satan-tools-goad/no-ask-when-record-fails ()
  "A failed transcript record is `(error . MSG)': nothing projected,
queued, marked or rung — there is no record to hang any of it on."
  (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
    (satan-tools-goad-test--spying calls
        (satan-intervention-project satan-goad-queue-rewrite
         satan-intervention-mark-undelivered)
      (cl-letf (((symbol-function 'satan-intervention-record)
                 #'satan-tools-goad-test--boom))
        (should (equal '(error . "boom")
                       (satan-tools-goad-test--ask
                        (satan-tools-goad-test--ctx)))))
      (should-not calls)
      (should-not satan-tools-goad-test--rings))))

(ert-deftest satan-tools-goad/refused-ring-keeps-queue ()
  "VT-5 — a refused (1), failed (2) or timed-out doorbell leaves the ask
recorded, projected and queued: the queue is the durable carrier."
  (dolist (ring (cdr satan-tools-goad-test--ring-results))
    (satan-intervention-test--with-db
      (satan-intervention-test--with-ctx ctx
        (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
          (let* ((satan-tools-goad-test--ring-result ring)
                 (result (satan-tools-goad-test--ask
                          (satan-tools-goad-test--ctx ctx)))
                 (iid (plist-get (cdr result) :intervention_id)))
            (should (= 1 (length satan-tools-goad-test--rings)))
            (should (satan-intervention-lookup iid))
            (should-not (plist-get (satan-intervention-lookup iid) :outcome))
            (should (equal (list iid)
                           (satan-goad-fixture-iids
                            (satan-goad-read-queue))))))))))

(ert-deftest satan-tools-goad/rings-goad-emit ()
  "VT-41 — the doorbell is `goad-emit --source satan --kind ask', bounded by
`satan-goad-emit-timeout' through the ledgered `satan-trace-call'; its
outcome — any exit, a timeout, or a signal — never changes the tool
result."
  (let ((satan-goad-emit-program "goad-emit-test")
        (satan-goad-emit-timeout 7)
        results)
    (dolist (ring (append satan-tools-goad-test--ring-results
                          (list (lambda () (error "No such program")))))
      (satan-intervention-test--with-ctx ctx
        (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
          (cl-letf (((symbol-function 'satan-intervention-project) #'ignore)
                    ((symbol-function 'satan-goad-queue-rewrite) #'ignore))
            (let ((satan-tools-goad-test--ring-result ring))
              (push (satan-tools-goad-test--ask
                     (satan-tools-goad-test--ctx ctx))
                    results)
              (pcase-let ((`(,program ,args ,keys)
                           (car satan-tools-goad-test--rings)))
                (should (equal "goad-emit-test" program))
                (should (equal "satan" (cadr (member "--source" args))))
                (should (equal "ask" (cadr (member "--kind" args))))
                (should (= 7 (plist-get keys :timeout-secs)))))))))
    (should (eq 'ok (car (car results))))
    (should (= 1 (length (delete-dups results))))))

(defun satan-tools-goad-test--undelivered-case (failing)
  "Ask with each function in FAILING signalling; assert the ask is marked
undelivered, never rung, and keeps its verdict through a rebuild.
Runs inside `satan-intervention-test--with-db' (a test-body macro)."
  (satan-intervention-test--with-ctx (ctx root)
    (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
      (dolist (fn failing)
        (advice-add fn :override #'satan-tools-goad-test--boom))
      (let* ((result (unwind-protect
                         (satan-tools-goad-test--ask
                          (satan-tools-goad-test--ctx ctx))
                       (dolist (fn failing)
                         (advice-remove fn #'satan-tools-goad-test--boom))))
             (iid (plist-get (cdr result) :intervention_id)))
        (should (eq 'ok (car result)))
        (should (eq :false (plist-get (cdr result) :delivered)))
        (should-not satan-tools-goad-test--rings)
        (satan-intervention-rebuild satan-intervention-test--db root)
        (should (equal "unknown"
                       (plist-get (plist-get (satan-intervention-lookup iid)
                                             :outcome)
                                  :classification)))
        (should-not (member iid (mapcar (lambda (r)
                                          (plist-get r :intervention_id))
                                        (satan-intervention-pending
                                         "2026-05-23T13:30:00+1000"))))))))

(ert-deftest satan-tools-goad/projection-failure-undelivered ()
  "VT-11 — a failed projection (the database down: both projection
writes signal), or a failed queue rewrite, marks the ask undelivered and
never rings; after `satan-rebuild-interventions' it carries its verdict
and is not pending past its window."
  (satan-intervention-test--with-db
    (satan-tools-goad-test--undelivered-case
     '(satan-intervention-project satan-intervention-project-with-verdict))
    (satan-intervention-test--reset-and-migrate)
    (satan-tools-goad-test--undelivered-case '(satan-goad-queue-rewrite))))

(provide 'satan-tools-goad-test)
;;; satan-tools-goad-test.el ends here
