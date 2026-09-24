;;; satan-broker.el --- SATAN broker driver -*- lexical-binding: t; -*-

;; Lifecycle:
;;   1. resolve mode-spec
;;   2. mint run-id, create runs/<run-id>/
;;   3. assemble bundle, write manifest + bundle
;;   4. open audit handle, log run-start
;;   5. spawn jailed child via make-process (pipe, line-buffered filter)
;;   6. on tool_call: dispatch through satan-tool-dispatch; send tool_result
;;   7. on final: capture, defer to sentinel
;;   8. sentinel: cancel timeout, run output handler, write actions.json + status, close audit
;;   9. timeout: kill process; sentinel handles the rest

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-run)
(require 'satan-announce)
(require 'satan-credential)
(require 'satan-audit)
(require 'satan-budget)
(require 'satan-jsonl)
(require 'satan-protocol)
(require 'satan-tools)
(require 'satan-tools-org)
(require 'satan-mode)
(require 'satan-context)
(require 'satan-output)
(require 'satan-percept)
(require 'satan-resonance)
(require 'satan-motive)
(require 'satan-observer)
(require 'satan-sensor-alerts)
(require 'satan-sensor-curiosity)
(require 'satan-sensor-content)
(require 'satan-sensor-wpm)
(require 'satan-ingest-cursor)
(require 'satan-trace)

;; `satan-tick-quiet-p' is the quiet-hours predicate for the announce
;; policy (below), but `satan-tick' requires `satan-broker' (transitively,
;; via `satan-context'), so the broker cannot require it back.  Declare +
;; resolve at call-site instead; precedent: `satan-sensor-alerts.el:20'.
(declare-function satan-tick-quiet-p "satan-tick" (&optional time window))

(defvar satan-memory-store--current-run-id)

(defcustom satan-direnv-dir
  (file-name-directory (directory-file-name satan--root))
  "Directory whose `.envrc' is sourced into the jailed-harness environment.
If non-nil and `envrc--export' is available, the broker resolves direnv
for this directory and merges the result into `process-environment'
before spawning the child.  Set to nil to disable."
  :type '(choice directory (const nil)) :group 'satan)

(defvar satan-broker-provider-key-vars
  '((openrouter . "OPENROUTER_API_KEY")
    (anthropic  . "ANTHROPIC_API_KEY")
    (openai     . "OPENAI_API_KEY")
    (deepseek   . "DEEPSEEK_API_KEY"))
  "Map SATAN mode `:provider' symbol to its API-key env var name.")

(defun satan-broker--key-var (mode)
  "MODE's provider API-key env var name, or nil when it has none."
  (cdr (assq (plist-get mode :provider) satan-broker-provider-key-vars)))

(declare-function envrc--export "envrc" (env-dir))
(declare-function envrc--merged-environment "envrc" (process-env pairs))

(defun satan-broker--direnv-env (base-env)
  "Return BASE-ENV merged with the direnv export for `satan-direnv-dir'.
If envrc is not loaded, or the directory has no .envrc, or direnv
returns no vars, BASE-ENV is returned unchanged.  Direnv errors signal."
  (if (and satan-direnv-dir
           (file-directory-p satan-direnv-dir)
           (file-readable-p (expand-file-name ".envrc" satan-direnv-dir))
           (fboundp 'envrc--export))
      (let ((result (envrc--export satan-direnv-dir)))
        (pcase result
          ('error (error "direnv failed for %s" satan-direnv-dir))
          ('none base-env)
          ((pred listp) (envrc--merged-environment base-env result))
          (_ base-env)))
    base-env))

(defun satan-broker--exec-path-from-env (env)
  "Extract PATH from ENV (a `process-environment' value) and split into list."
  (let ((path (cl-some (lambda (kv)
                         (and (string-prefix-p "PATH=" kv)
                              (substring kv 5)))
                       env)))
    (if path (split-string path ":" t) exec-path)))

(defun satan-broker--tee-stdout (path chunk)
  (let ((coding-system-for-write 'utf-8))
    (write-region chunk nil path 'append 'silent)))

(defun satan-broker--send-validated (run-ctx obj)
  "Send OBJ to the harness, auditing a protocol error if it's malformed.
Bad broker output is a bug, not a wire failure — we audit but still send
so the harness sees something rather than blocking on stdin."
  (let ((err (satan-protocol-validate 'out obj)))
    (when err
      (satan-audit-record
       (satan-run-audit run-ctx) 'broker 'protocol-error
       (list :outbound t
             :type (plist-get err :type)
             :reason (plist-get err :reason)
             :raw obj))))
  (satan-jsonl-send (satan-run-process run-ctx) obj))

(defun satan-broker--failed-action-payload (obj reason)
  "Return the canonical failed-action plist for tool-call OBJ + REASON.
Shape is `(:action (:type NAME :args ARGS) :reason MSG)' — see the
failed-action shape note in AGENTS.md.  Used by `--on-tool-call' to
audit every denied dispatch in a structure consumers can grep."
  (list :action (list :type (plist-get obj :name)
                      :args (or (plist-get obj :args) '()))
        :reason reason))

(defun satan-broker--on-tool-call (run-ctx obj)
  (let* ((mode (satan-run-mode run-ctx))
         (budget (plist-get mode :budget-tool-calls))
         (done (satan-run-tool-calls-done run-ctx)))
    (satan-audit-record (satan-run-audit run-ctx) 'in 'tool-call obj)
    (cond
     ((and (integerp budget) (>= done budget))
      (let* ((reason "tool call budget exhausted")
             (result (list :type "tool_result"
                           :id (plist-get obj :id)
                           :ok :false
                           :error reason)))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'tool-denied result)
        (satan-audit-record
         (satan-run-audit run-ctx) 'broker 'action-failed
         (satan-broker--failed-action-payload obj reason))
        (satan-broker--send-validated run-ctx result)))
     (t
      (setf (satan-run-tool-calls-done run-ctx) (1+ done))
      (let* ((tool-ctx (satan-run-tool-ctx run-ctx))
             (result (satan-tool-dispatch
                      obj (plist-get mode :tools) tool-ctx))
             (ok-p (eq (plist-get result :ok) t)))
        (satan-audit-record
         (satan-run-audit run-ctx)
         'broker
         (if ok-p 'tool-result 'tool-denied)
         result)
        (unless ok-p
          (satan-audit-record
           (satan-run-audit run-ctx) 'broker 'action-failed
           (satan-broker--failed-action-payload
            obj (plist-get result :error))))
        (satan-audit-record (satan-run-audit run-ctx) 'out 'tool-result result)
        (satan-broker--send-validated run-ctx result))))))

(defun satan-broker--on-final (run-ctx obj)
  (satan-audit-record (satan-run-audit run-ctx) 'in 'final obj)
  (setf (satan-run-final run-ctx) obj))

(defun satan-broker--on-log (run-ctx obj)
  (satan-audit-record (satan-run-audit run-ctx) 'in 'log obj))

(defun satan-broker--error-class (obj)
  "Return the harness error class named in OBJ's `:error' string.
OBJ's `:error' is either the harness's JSON payload
\(`{\"class\": \"auth\", ...}') or a plain init-path string.  Returns
the parsed `:class' when it is a string, else \"unknown\" — including
when `:error' is not JSON at all."
  (or (ignore-errors
        (let ((parsed (json-parse-string (plist-get obj :error)
                                          :object-type 'plist)))
          (let ((class (plist-get parsed :class)))
            (and (stringp class) class))))
      "unknown"))

(defun satan-broker--on-error (run-ctx obj)
  (satan-audit-record (satan-run-audit run-ctx) 'in 'protocol-error obj)
  (unless (satan-run-failure-reason run-ctx)
    (setf (satan-run-failure-reason run-ctx) (satan-broker--error-class obj)))
  (setf (satan-run-status run-ctx) 'failed))

(defun satan-broker--dispatch (run-ctx obj)
  (let ((err (satan-protocol-validate 'in obj)))
    (cond
     (err
      (satan-audit-record
       (satan-run-audit run-ctx) 'broker 'protocol-error
       (list :type (plist-get err :type)
             :reason (plist-get err :reason)
             :raw obj))
      (setf (satan-run-status run-ctx) 'invalid-protocol))
     (t
      (pcase (plist-get obj :type)
        ("ready"     (satan-audit-record (satan-run-audit run-ctx) 'in 'ready obj))
        ("log"       (satan-broker--on-log run-ctx obj))
        ("tool_call" (satan-broker--on-tool-call run-ctx obj))
        ("final"     (satan-broker--on-final run-ctx obj))
        ("error"     (satan-broker--on-error run-ctx obj)))))))

(defun satan-broker--make-filter (run-ctx)
  (let ((inner (satan-jsonl-make-filter
                (lambda (obj) (satan-broker--dispatch run-ctx obj))
                (lambda (err)
                  (satan-audit-record
                   (satan-run-audit run-ctx) 'broker 'protocol-error
                   (list :raw-line (car err)
                         :error    (cdr err)))))))
    (lambda (proc chunk)
      (satan-broker--tee-stdout
       (satan-run-stdout-log-path run-ctx) chunk)
      (funcall inner proc chunk))))

(defun satan-broker--crash-context (run-ctx)
  "Build a crash-context snapshot plist for a non-done terminal path.
Pure data assembly from run-ctx and mode spec — no I/O."
  (let* ((mode (satan-run-mode run-ctx))
         (start (satan-run-start-time run-ctx))
         (elapsed (and start (float-time (time-subtract nil start)))))
    (list :status (symbol-name (satan-run-status run-ctx))
          :tool_calls_done (or (satan-run-tool-calls-done run-ctx) 0)
          :tool_calls_budget (or (plist-get mode :budget-tool-calls) 0)
          :budget_tokens (or (plist-get mode :budget-tokens) 0)
          :max_budget_tokens (or (plist-get mode :max-budget-tokens) 1000000)
          :elapsed_seconds (and elapsed (round elapsed))
          :timeout_seconds (or (plist-get mode :timeout-seconds) 0)
          :pre_spawn_completed
          (if (satan-run-pre-spawn-completed run-ctx) t :false)
          :failure_reason (satan-run-failure-reason run-ctx))))

(defun satan-broker--finalize (run-ctx)
  "Output handler + audit close.  Idempotent."
  (when (eq (satan-run-status run-ctx) 'running)
    (setf (satan-run-status run-ctx)
          (if (satan-run-final run-ctx) 'done 'failed)))
  (let* ((mode (satan-run-mode run-ctx))
         (final (satan-run-final run-ctx))
         (handler (plist-get mode :output-handler))
         (status (satan-run-status run-ctx))
         (partition
          (when (and final (eq status 'done) handler)
            (condition-case err
                (funcall handler final (satan-run-tool-ctx run-ctx))
              (error
               (satan-audit-record
                (satan-run-audit run-ctx) 'broker 'action-failed
                (list :error (error-message-string err)))
               nil)))))
    (unless (eq status 'done)
      (satan-audit-record
       (satan-run-audit run-ctx) 'broker 'crash-context
       (satan-broker--crash-context run-ctx)))
    (satan-broker--evict-on-auth run-ctx)
    (when partition
      (dolist (a (plist-get partition :applied))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'action-applied a))
      (dolist (a (plist-get partition :staged))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'action-staged a))
      (dolist (a (plist-get partition :rejected))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'action-rejected a))
      (dolist (a (plist-get partition :failed))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'action-failed a)))
    (let* ((prepare (satan-run-prepare run-ctx))
           (pre-spawn (and prepare (plist-get prepare :pre_spawn)))
           (observer (and prepare (plist-get prepare :observer)))
           (actions (or partition
                        (list :applied [] :staged [] :rejected [] :failed []))))
      (when pre-spawn
        (setq actions (plist-put actions :pre_spawn pre-spawn)))
      (when observer
        (setq actions (plist-put actions :observer observer)))
      (let ((final-for-audit
             (or final
                 (and (satan-run-failure-reason run-ctx)
                      (list :status "invalid"
                            :reason (satan-run-failure-reason run-ctx))))))
        (satan-audit-close
         (satan-run-audit run-ctx) final-for-audit actions status)))
    (satan-broker--mark-failed-on-disk run-ctx)
    (setq satan-memory-store--current-run-id nil)))

(defun satan-broker--evict-on-auth (run-ctx)
  "Evict RUN-CTX's credential refs when the provider rejected its key.
Only a `failed' run whose broker-classified `failure-reason' is exactly
\"auth\" (DEC-019) evicts; `final.json's reason is never consulted, as a
model's final may say anything.  Evicts only the refs this run was
spawned with, so the next run re-reads a rotated key instead of
replaying the dead one (SL-018 sec-6).  A failed eviction is recorded as
a `broker' `evict-failed' event and is otherwise harmless."
  (when (and (eq (satan-run-status run-ctx) 'failed)
             (equal (satan-run-failure-reason run-ctx) "auth"))
    (pcase-dolist (`(,var . ,ref) (satan-run-credential-refs run-ctx))
      (when-let* ((err (satan-credential-forget ref)))
        (satan-audit-record (satan-run-audit run-ctx) 'broker 'evict-failed
                            (list :var var
                                  :error (error-message-string err)))))))

(defun satan-broker--mark-failed-on-disk (run-ctx)
  "If RUN-CTX's status is not `done', rename its dir adding `.FAILED'.
Lets `ls runs/<YYYY-MM-DD>/' surface failures without opening each
`status' file.  Updates the in-memory dir on RUN-CTX and repoints
`runs/most-recent' so the symlink survives the rename.

Also dispatches a syslog warning + a streak-aware desktop notification
via `satan-broker--announce-failure'."
  (let ((status (satan-run-status run-ctx))
        (dir (satan-run-dir run-ctx))
        (run-id (satan-run-id run-ctx)))
    (when (and dir
               (not (eq status 'done))
               (not (string-suffix-p satan-run--failed-suffix dir))
               (file-directory-p dir))
      (let ((new-dir (concat dir satan-run--failed-suffix)))
        (unless (file-exists-p new-dir)
          (rename-file dir new-dir)
          (setf (satan-run-dir run-ctx) new-dir)
          (satan-broker--update-most-recent
           run-id satan-run--failed-suffix)
          (satan-broker--announce-failure
           run-id
           (plist-get (satan-run-mode run-ctx) :name)
           status
           (satan-broker--failure-reason run-ctx)
           new-dir))))))

(defun satan-broker--failure-reason (run-ctx)
  "Return a short reason string for RUN-CTX's failure.
Precedence: the final plist's `:reason', then the `failure-reason'
slot, else the status symbol."
  (let* ((final (satan-run-final run-ctx))
         (final-reason (and final (plist-get final :reason))))
    (cond
     ((and (stringp final-reason) (not (string-empty-p final-reason)))
      final-reason)
     ((satan-run-failure-reason run-ctx) (satan-run-failure-reason run-ctx))
     (t (symbol-name (satan-run-status run-ctx))))))

(defcustom satan-failure-syslog t
  "When non-nil, broker emits a `logger -t satan -p user.warn' line per failure.
Disable if `logger(1)' is absent or you don't want SATAN failures in
the user journal (`journalctl --user -t satan')."
  :type 'boolean :group 'satan)

(defcustom satan-failure-notify t
  "When non-nil, broker pops a D-Bus notification per the failure back-off:
positions 1, 2, 4, 8, ... of the run's same-cause failure streak (see
`satan-broker--announce-due-p').  An `auth' failure pops at every
position, at critical urgency.  A `budget-exceeded' failure pops only at
position 1.  Journalling (`satan-failure-syslog') is an independent
switch and happens for every failure regardless of this one."
  :type 'boolean :group 'satan)

(defconst satan-broker--streak-transparent-reasons
  '("session_blocked" "credential_deferred" "run_busy")
  "Reasons of runs that neither extend nor break a failure streak.")

(defun satan-broker--failure-streak (mode-slug newest)
  "MODE-SLUG's same-cause failure streak ending at outcome NEWEST.
Same cause means NEWEST's `:status'/`:reason' pair; a run whose reason
is in `satan-broker--streak-transparent-reasons' is stepped over rather
than counted or ending the walk (design sec-3)."
  (let ((cause (list (plist-get newest :status) (plist-get newest :reason))))
    (satan-run-outcome-streak
     mode-slug
     (lambda (o) (equal (list (plist-get o :status) (plist-get o :reason))
                        cause))
     (lambda (o) (satan-broker--failed-with-p
                  o satan-broker--streak-transparent-reasons)))))

(defun satan-broker--failed-with-p (outcome reasons)
  "Non-nil when OUTCOME has status `failed' and a reason in REASONS.
The status guard matters: `final.json's reason is a free string a
model's own final may carry, so a reason alone proves nothing
\(RV-013 N8)."
  (and (eq (plist-get outcome :status) 'failed)
       (member (plist-get outcome :reason) reasons)))

;; ── Credential policy (SL-018 design sec-4, sec-8; DEC-022) ────────────────

(defcustom satan-credential-escalate-after 14400
  "Seconds a `defer' mode may go on deferring before its next run prompts.
Measured from the oldest run of the mode's current `credential_deferred'
streak.  A mode's `:credential-escalate-after' overrides it."
  :type 'number :group 'satan)

(defvar satan-run-attended nil
  "Non-nil while a run was started by a human at the keyboard.
Bound only by an interactive `satan-run'; every other entry (systemd
shims, `satan-tick', timers, MCP) leaves it nil, so they are unattended
by default (fail closed).  An attended run always prompts.")

(defun satan-broker--credential-streak-age (mode-slug now)
  "Seconds from MODE-SLUG's current credential_deferred streak to NOW.
Nil when there is no streak.  `session_blocked' and `run_busy' runs are
stepped over; any other outcome ends the streak."
  (when-let* ((streak (satan-run-outcome-streak
                       mode-slug
                       (lambda (o) (satan-broker--failed-with-p
                                    o '("credential_deferred")))
                       (lambda (o) (satan-broker--failed-with-p
                                    o '("session_blocked" "run_busy")))))
              (oldest (plist-get (car (last streak)) :run-id)))
    (float-time
     (time-subtract now (or (satan-run-id-time oldest)
                            (error "SATAN: unparseable run-id %s" oldest))))))

(defun satan-broker--credential-policy (mode &optional now)
  "Effective credential policy for MODE at NOW (default: the current time).
Returns (:policy prompt|defer :context LABEL).  Attended runs and
`:credential-policy prompt' modes prompt.  Otherwise the mode defers,
unless its credential streak is at least its escalation threshold old:
then it prompts and LABEL says so.  Signals on an invalid effective
threshold (the caller's acquisition boundary records it)."
  (let* ((name (plist-get mode :name))
         (context (concat "satan broker/" name)))
    (if (or satan-run-attended
            (eq (plist-get mode :credential-policy) 'prompt))
        (list :policy 'prompt :context context)
      (let ((after (or (plist-get mode :credential-escalate-after)
                       satan-credential-escalate-after)))
        (unless (and (numberp after) (>= after 0))
          (error "SATAN: invalid credential escalation threshold %S" after))
        (let ((age (satan-broker--credential-streak-age
                    name (or now (current-time)))))
          (if (and age (>= age after))
              (list :policy 'prompt
                    :context (format "%s (escalated: deferred %s)" context
                                     (format-seconds "%hh%02mm" age)))
            (list :policy 'defer :context context)))))))

(defun satan-broker--announce-due-p (outcome position)
  "Non-nil when a desktop pop is due for OUTCOME at streak POSITION.
Pure.  `auth' reason -> always; `budget-exceeded' status -> only at
position 1; otherwise POSITION is a power of two (1, 2, 4, 8, ...)."
  (cond ((equal (plist-get outcome :reason) "auth") t)
        ((eq (plist-get outcome :status) 'budget-exceeded) (= position 1))
        (t (zerop (logand position (1- position))))))

(defun satan-broker--failure-line (status mode-slug run-id reason position
                                          first-run-id)
  "Build the journal/body line for a failure announcement.
`<status> <mode> <run-id> <reason> x<position>', plus
` since <first-run-id>' when POSITION > 1 (omitted at position 1)."
  (concat (format "%s %s %s %s x%d"
                  (symbol-name status) mode-slug run-id reason position)
          (and (> position 1) first-run-id
               (format " since %s" first-run-id))))

(defun satan-broker--quiet-p ()
  "Non-nil when `satan-tick-quiet-p' says now is within quiet hours.
Reads as not-quiet when the function is unbound."
  (and (fboundp 'satan-tick-quiet-p) (satan-tick-quiet-p)))

(defun satan-broker--announce-failure (run-id mode-slug status reason dir)
  "Emit syslog + (back-off-gated) notify-send for a failed run, via the
announce seam (`satan-announce').  RUN-ID, MODE-SLUG, STATUS (symbol),
REASON (display string) compose the log line and notification body.
DIR is the (already `.FAILED'-renamed) run directory the policy reads
its matching outcome from — `satan-run-outcome' on DIR, i.e. `final.json's
raw `:reason', never the display REASON argument (design sec-6).

Journalling and popping are independent switches: `satan-failure-syslog'
gates the journal line; `satan-failure-notify' plus the back-off policy
\(`satan-broker--announce-due-p') plus quiet hours gate the pop.
Delivery mechanics (best-effort journal) live in `satan-announce-deliver';
a pop failure propagates out of `satan-announce' by design (section 5's
contract), so this caller wraps the whole announcement in `ignore-errors',
as it did before the back-off policy existed — a failed-run notification
is not worth failing finalize over."
  (let* ((newest (or (satan-run-outcome dir)
                     (list :run-id run-id :status status :reason reason)))
         (streak (satan-broker--failure-streak mode-slug newest))
         (position (max 1 (length streak)))
         (first-id (plist-get (car (last streak)) :run-id))
         (line (satan-broker--failure-line
               status mode-slug run-id reason position first-id))
         (pop (and satan-failure-notify
                  (satan-broker--announce-due-p newest position)
                  (not (satan-broker--quiet-p)))))
    (when (or pop satan-failure-syslog)
      (ignore-errors
        (satan-announce
         :title (and pop (format "SATAN %s (%s) x%d"
                                 (symbol-name status) mode-slug position))
         :body line
         :urgency (if (equal (plist-get newest :reason) "auth")
                     'critical 'normal)
         :timeout 6000
         :journal (and satan-failure-syslog line))))))

(defun satan-broker--make-sentinel (run-ctx)
  (lambda (_proc event)
    (when (string-match-p "\\(finished\\|exited\\|signal\\|broken\\|killed\\|deleted\\)" event)
      (let ((tt (satan-run-timeout-timer run-ctx)))
        (when tt (cancel-timer tt)))
      ;; DEC-8: clear the mutual-exclusion flag on async completion so
      ;; a crashed/killed process does not permanently block MCP sessions
      ;; or, via `run_busy' (DEC-023), every scheduled run.  An unwind
      ;; form, so a signal from either step still clears it (ISS-020);
      ;; the signal itself propagates.
      (unwind-protect
          (progn
            (satan-audit-record (satan-run-audit run-ctx) 'broker 'child-exit
                                (list :event (string-trim event)))
            (satan-broker--finalize run-ctx))
        (setq satan-run--spawn-running nil)))))

(defun satan-broker--build-manifest (mode run-id)
  "Return the manifest plist for MODE and RUN-ID.
Joins mechanical metadata (tools, capabilities, jail) with the
notes-owned model-facing schemas (`:tools' carries full JSON Schemas
including descriptions read from `satan-tools-descriptions-dir').
The harness consumes `:tools' verbatim."
  (let* ((tool-names (satan-tools-available (plist-get mode :tools)))
         (specs (mapcar (lambda (n)
                          (or (satan-tool-lookup n)
                              (error "SATAN: unknown tool in mode %s: %s"
                                     (plist-get mode :name) n)))
                        tool-names))
         (tools-schema
          (vconcat (mapcar #'satan-tool-json-schema specs)
                   (list (satan-tool-final-schema)))))
    (list :run_id run-id
          :start_time (format-time-string "%Y-%m-%dT%H:%M:%S%z" nil)
          :mode (list :name (plist-get mode :name)
                      :auto_apply (symbol-name (plist-get mode :auto-apply))
                      :timeout_seconds (plist-get mode :timeout-seconds)
                      :budget_tool_calls (plist-get mode :budget-tool-calls))
          :tools_allowed tool-names
          :tools tools-schema
          :capabilities  (mapcar #'symbol-name
                                 (plist-get mode :capabilities))
          :harness (list :cmd (plist-get (plist-get mode :harness) :cmd)
                         :args (or (plist-get (plist-get mode :harness) :args)
                                   []))
          :jail_profile (symbol-name (plist-get mode :jail-profile))
          :context_summary (format "mode=%s date=%s"
                                   (plist-get mode :name)
                                   (format-time-string "%Y-%m-%d" nil)))))

(defun satan-broker--manifest-or-stub (mode run-id)
  "Return MODE's manifest for RUN-ID, or a stub when it cannot be built.
The stub is `(:run_id RUN-ID :mode (:name NAME) :manifest_error MSG)'.
Admissible for a run that spawns no child: no harness reads its
manifest, and `satan-audit-open' only writes it — so a broken mode
\(e.g. an unregistered tool) still leaves a terminal record (I7)."
  (condition-case err
      (satan-broker--build-manifest mode run-id)
    (error
     (list :run_id run-id
           :mode (list :name (plist-get mode :name))
           :manifest_error (error-message-string err)))))

(defun satan-broker--percept-bundle (prepare)
  "The bundle a run without a context bundle records: PREPARE's percept.
Consumers (the audit bundle checks, the observer's baseline) read the
percept from `bundle.json', not the `percept.json' sidecar."
  (list :percept (plist-get prepare :percept)))

(defun satan-broker--most-recent-target (run-id &optional leaf-suffix)
  "Return the relative symlink target for RUN-ID's run dir.
For a bucketed run-id (the normal case) this is `<bucket>/<run-id>'
optionally with LEAF-SUFFIX appended (e.g. \".FAILED\").  For a run-id
that does not parse as bucketed, returns just the leaf."
  (let* ((bucket (satan-run--date-bucket run-id))
         (leaf (concat run-id (or leaf-suffix ""))))
    (if bucket (concat bucket "/" leaf) leaf)))

(defun satan-broker--update-most-recent (run-id &optional leaf-suffix)
  "Repoint `satan-runs-dir/most-recent' at RUN-ID's run dir.
LEAF-SUFFIX, when non-nil, is appended to the run-id leaf so the link
follows a post-status rename (e.g. `.FAILED').

Best-effort: failures (read-only fs, race with a concurrent run) are
swallowed so a busted symlink never aborts a run.  Target is stored
relative so the runs dir stays portable."
  (let ((link (expand-file-name "most-recent" satan-runs-dir))
        (target (satan-broker--most-recent-target run-id leaf-suffix)))
    (ignore-errors
      (when (or (file-symlink-p link) (file-exists-p link))
        (delete-file link))
      (make-symbolic-link target link t))))

(cl-defun satan-broker--write-no-child-run
    (mode prepare dir status reason
          &key event event-payload bundle-extra final rename-announce
          announce-reason)
  "Write a slim terminal audit bundle for a run that spawned no child.
PREPARE is the prepare-phase run_ctx plist (carries the frozen run_id +
time_now and — post-perceive — the `:percept' the gate ran against).

Opens then closes an audit bundle, mirroring PREPARE's `:percept' into
`bundle.json' (DEC-budget-denied-mirror-percept: A2-verified consumers
read `bundle.json -> :percept', not the sidecar — without the mirror the
ISSUE-001 perceive-first fix would be cosmetic).  BUNDLE-EXTRA, when
supplied, is appended to the bundle plist.  Records a `broker' EVENT
\(defaulting to STATUS) with EVENT-PAYLOAD (defaulting to `(:reason
REASON)'), then closes with terminal STATUS and the synthetic FINAL plist.
The manifest comes from `satan-broker--manifest-or-stub', so a mode
whose manifest cannot be built still gets its terminal record (I7).

When RENAME-ANNOUNCE is non-nil: `.FAILED'-renames the run dir, repoints
`most-recent', and dispatches `satan-broker--announce-failure' with
ANNOUNCE-REASON (defaulting to REASON).  Otherwise the dir is left in
place and the run stays silent (no rename, no notification — so a
session-blocked tick does not pollute the failure-streak counter or pop a
desktop alert; DEC-8 deferral)."
  (unless (file-directory-p dir) (make-directory dir t))
  (let* ((run-id (plist-get prepare :run_id))
         (manifest (satan-broker--manifest-or-stub mode run-id))
         (bundle (append (satan-broker--percept-bundle prepare)
                         bundle-extra))
         (audit (satan-audit-open dir manifest bundle prepare)))
    (satan-broker--update-most-recent run-id)
    (satan-audit-record audit 'broker (or event status)
                           (or event-payload (list :reason reason)))
    (satan-audit-close audit final
                          (list :applied [] :staged [] :rejected [] :failed [])
                          status)
    (when rename-announce
      (let ((new-dir (concat dir satan-run--failed-suffix)))
        (when (and (file-directory-p dir)
                   (not (file-exists-p new-dir)))
          (rename-file dir new-dir)
          (satan-broker--update-most-recent
           run-id satan-run--failed-suffix)
          (satan-broker--announce-failure
           run-id (plist-get mode :name) status
           (or announce-reason reason) new-dir))))))

(defun satan-broker--write-silent-run (mode prepare dir reason summary)
  "Record a refused run: status `failed', REASON, no child, no announce.
No rename and no pop, so the refusal neither pollutes the failure streak
\(REASON is in `satan-broker--streak-transparent-reasons') nor alerts.
SUMMARY is the synthetic final's summary.  Stamps REASON as the trace
outcome and returns the run-id."
  (satan-broker--write-no-child-run
   mode prepare dir 'failed reason
   :final (list :summary summary :actions [] :reason reason)
   :rename-announce nil)
  (satan-trace-outcome reason)
  (plist-get prepare :run_id))

(defun satan-broker--write-failed-no-child-run (mode prepare dir reason err)
  "Write the terminal record of a run that failed with ERR before any child.
REASON names the failed stage in snake case (\"perceive_failed\"); it
is the `failure_reason' and, kebab-cased, the `broker' event carrying
ERR's message.  Thin caller of `satan-broker--write-no-child-run'
\(status `failed', rename + announce)."
  (let ((msg (error-message-string err)))
    (satan-broker--write-no-child-run
     mode prepare dir 'failed reason
     :event (intern (string-replace "_" "-" reason))
     :event-payload (list :error msg)
     :final (list :summary (format "%s: %s"
                                   (string-replace "_" " " reason) msg)
                  :actions []
                  :reason reason)
     :rename-announce t)))

(defun satan-broker--write-budget-denied-run (mode prepare dir spent ceiling)
  "Write a slim audit bundle marking the run in PREPARE as budget-exceeded.
No child is spawned; the run terminates with status `budget-exceeded'
and a synthetic final summarising the gate decision.  PREPARE is the
prepare-phase run_ctx plist allocated by `satan-run-new-ctx'
(carries the frozen run_id + time_now and the perceived `:percept').
Thin caller of `satan-broker--write-no-child-run' (rename + announce)."
  (satan-broker--write-no-child-run
   mode prepare dir 'budget-exceeded "budget_daily_tokens"
   :event 'budget-denied
   :event-payload (list :tokens_spent spent :tokens_ceiling ceiling)
   :bundle-extra (list :budget-denied t
                       :tokens_spent spent
                       :tokens_ceiling ceiling)
   :final (list :summary (format "budget-exceeded: %d/%d tokens spent today"
                                 spent ceiling)
                :actions []
                :reason "budget_daily_tokens"
                :tokens_spent spent
                :tokens_ceiling ceiling)
   :announce-reason (format "%d/%d tokens" spent ceiling)
   :rename-announce t))

(defun satan-broker-run (name)
  "Resolve MODE-NAME, spawn jailed harness, drive it to completion.
Returns the run-id.

Single allocation site for `run_id' + `time_now': calls
`satan-run-new-ctx' exactly once at the start of the run.  The
returned run_ctx plist is threaded into context assembly, tool
dispatch, and audit.

Refuses to spawn when an interactive MCP session is open (DEC-8
mutual exclusion), or when today's spend has met or exceeded
`satan-budget-daily-tokens'.  In both cases writes a minimal
audit bundle with the appropriate status and returns the run-id
without launching the child."
  (let* ((mode (satan-mode-resolve name))
         ;; SL-018 DEC-020: acquire BEFORE allocating, so a prompt answered
         ;; late yields a fresh run-id, time and percept.  Skipped (nil)
         ;; while a child is live: a run refused as busy never prompts.
         (cred (unless satan-run--spawn-running
                 (satan-broker--acquire mode)))
         (prepare (satan-run-new-ctx mode))
         (run-id (plist-get prepare :run_id))
         (dir (satan-run-dir-for-id run-id)))
    ;; ISSUE-001 (DR-010 §3): perceive runs UNCONDITIONALLY before both
    ;; gates so a session-blocked / budget-denied tick still senses the
    ;; world and persists `percept.json'.  The run dir must exist before
    ;; perceive (it writes `percept.json' there).  Perceive's only write
    ;; is `percept.json'; any error routes through the no-child path with
    ;; status `failed' + reason "perceive_failed" (a terminal status the
    ;; audit verifier already knows — not a new accepted status).
    (unless (file-directory-p dir) (make-directory dir t))
    ;; SL-011: one tick accumulator per run — every stage wrap below this
    ;; point (perceive, enrich, spawn) records onto it, and each `cond'
    ;; branch stamps its domain outcome before returning the run-id.
    (satan-trace-with-tick run-id name
      (let ((perceive-error nil))
        (condition-case err
            (setq prepare (satan-run-perceive prepare mode dir))
          (error (setq perceive-error err)))
        (cond
         (perceive-error
          (satan-broker--write-failed-no-child-run
           mode prepare dir "perceive_failed" perceive-error)
          (satan-trace-outcome "perceive_failed")
          run-id)
         ;; DEC-8: refuse to spawn while an interactive session is open.
         ;; ISSUE-001: now perceives first.  No rename, no announce — the
         ;; deferral must not pollute the failure-streak counter or alert.
         (satan-run--session-active
          (message "SATAN broker: interactive session active — refusing scheduled run (DEC-8)")
          (satan-broker--write-silent-run
           mode prepare dir "session_blocked"
           "Scheduled run blocked by active interactive session (DEC-8)"))
         ;; DEC-023: refuse while another run's child is live — the memory
         ;; store's current-run state is process-global and would race.
         ;; Re-checked: a trigger queued behind a blocking prompt fires the
         ;; moment it is answered.  A nil CRED (acquisition skipped as
         ;; busy) stays busy even if the child has exited since, so no run
         ;; spawns without having acquired its key.
         ((or (null cred) satan-run--spawn-running)
          (message "SATAN broker: a run's child is live — refusing scheduled run (DEC-023)")
          (satan-broker--write-silent-run
           mode prepare dir "run_busy"
           "Scheduled run refused: another run's child is live (DEC-023)"))
         ((satan-budget-exceeded-p satan-runs-dir)
          (let ((spent (satan-budget-today-total satan-runs-dir)))
            (satan-broker--write-budget-denied-run
             mode prepare dir spent satan-budget-daily-tokens)
            (satan-trace-outcome "budget_denied")
            run-id))
         ((eq (car cred) :deferred)
          (satan-broker--write-credential-deferred-run mode prepare dir))
         ((eq (car cred) :unavailable)
          (satan-broker--write-failed-no-child-run
           mode prepare dir "credential_unavailable" (cadr cred))
          (satan-trace-outcome "credential_unavailable")
          run-id)
         (t
          (satan-trace-outcome "spawned")
          (satan-broker--spawn mode prepare dir cred)))))))

(defun satan-broker--acquire (mode)
  "Acquire MODE's provider key under its effective policy (design sec-3).
Returns the `satan-credential-acquire' verdict, its `:env' form extended
with `:base', the direnv-merged environment the child is built from
\(computed once here, so the key is looked up where the child gets it).
A mode with no key var gets (:env nil :refs nil :base BASE).  One error
boundary: a signal from direnv, the policy (streak walk, threshold) or
the seam becomes (:unavailable ERR), so the run is recorded, not lost."
  (condition-case err
      (let ((base (satan-broker--direnv-env process-environment))
            (key-var (satan-broker--key-var mode)))
        (if (not key-var)
            (list :env nil :refs nil :base base)
          (let* ((policy (satan-broker--credential-policy mode))
                 (verdict (satan-credential-acquire
                           base (list key-var) (plist-get policy :policy)
                           (plist-get policy :context))))
            (if (eq (car verdict) :env)
                (append verdict (list :base base))
              verdict))))
    ((error quit) (list :unavailable err))))

(defun satan-broker--write-credential-deferred-run (mode prepare dir)
  "Record a `credential_deferred' run: silent, plus one journal line.
The line keeps a locked vault visible in `journalctl --user -t satan'
without a pop every tick (design sec-5)."
  (let ((run-id (satan-broker--write-silent-run
                 mode prepare dir "credential_deferred"
                 "No credential session; mode policy defers (DEC-022)")))
    (when satan-failure-syslog
      (satan-announce :journal (format "credential_deferred %s %s"
                                       (plist-get mode :name) run-id)))
    run-id))

(defun satan-broker--spawn (mode prepare dir cred)
  "Spawn the jailed harness for MODE under DIR.
PREPARE is the run_ctx plist returned by `satan-run-new-ctx'
(carries the frozen run_id + time_now and v0 placeholder slots).
CRED is the `satan-broker--acquire' verdict: its `:base' is the child's
base environment, its `:env' the resolved key, its `:refs' what an
`auth' failure evicts.  Returns the run-id.

An error before the child exists is recorded, not raised: the run
ends `failed' with reason `spawn_failed' (see
`satan-broker--record-spawn-failure') and the run-id is returned.
An error after `make-process' is re-signalled; the child's sentinel
owns that run's finalisation and its stderr buffer."
  ;; DEC-8: set the mutual-exclusion flag so the MCP server refuses new
  ;; sessions while this scheduled run is live.  Cleared by the child
  ;; sentinel on exit (`satan-broker--make-sentinel') and by this
  ;; function's error handler if the synchronous launch itself throws.
  (setq satan-run--spawn-running t)
  ;; SL-017: bound OUTSIDE the `condition-case' so its handler can tell
  ;; how far the spawn got.  The body assigns them with `setq' and must
  ;; never re-bind these names — an inner binding would hide the value
  ;; from the handler (no child seen → double finalise).
  (let ((run-id (plist-get prepare :run_id))
        (stderr-buf nil)
        (run-ctx nil)
        (proc nil))
  (condition-case err
      (let* ((bundle-path (expand-file-name "bundle.json" dir))
         (stdout-log (expand-file-name "stdout.log" dir)))
    (setq stderr-buf (generate-new-buffer
                      (format " *satan-stderr-%s*" run-id)))
    (unless (file-directory-p dir) (make-directory dir t))
    (satan-broker--update-most-recent run-id)
    (setq satan-memory-store--current-run-id run-id)
    (unless (file-directory-p satan-hippocampus-dir)
      (make-directory satan-hippocampus-dir t))
    ;; DR-010 §3 — consume-only spawn.  Perceive (percept.build +
    ;; percept.persist, threading `:percept'/`:evidence'/`:sensor_status'
    ;; onto PREPARE) ran UNCONDITIONALLY upstream in `satan-broker-run'
    ;; before the session/budget gates.  This path runs only on consume,
    ;; so it derives the model-facing enrichment (resonance + motive) via
    ;; `satan-run-enrich' over the already-built percept rather than
    ;; rebuilding it (single percept-builder invariant).
    ;;
    ;; Phase 2.1+2.2 — auto-resonance.  Derive a cue from the percept,
    ;; apply the §S2 gate, call `memory_resonate' when admitted (via
    ;; enrich).  Result attaches to PREPARE :resonance for the context-fn
    ;; (A4).  Memory errors return a `memory-unreachable' status; the run
    ;; proceeds without resonance rather than failing the tick.
    ;;
    ;; Phase 3.3 — motive file read (via enrich).  Pure parse of
    ;; motives.org; result attaches to PREPARE :motive.  Missing file is a
    ;; valid state — `satan-motive-read' returns an empty parse and the
    ;; capsule renderer self-suppresses the block (§S3 silent omission).
    ;;
    ;; Phase 5.8 / T7 PR 5 — observer.process must run BEFORE the motive
    ;; read so the in-tick motive snapshot sees freshly-incremented
    ;; `:worked_count' and updated `:last_intervention_at' from prior-run
    ;; interventions whose attribution window has matured.  PR 5 added
    ;; the audit handle as a prerequisite (the observer now emits
    ;; `intervention.outcome_classified' events into the current run's
    ;; transcript), so the broker opens the handle here — manifest is
    ;; built up-front, `bundle.json' is deferred until the context-fn
    ;; has assembled it (see `satan-audit-attach-bundle' below).  The
    ;; handle reaches the observer inside the run's tool-ctx (SL-017).
    ;;
    ;; Observer errors are caught so a stale bundle / postgres outage
    ;; cannot fail the tick — the run proceeds without an observer pass
    ;; when it does.
    (let* ((manifest (satan-broker--build-manifest mode run-id))
           (audit (satan-trace-stage "spawn.audit_open"
                    (satan-audit-open dir manifest nil prepare)))
           ;; SL-017 DEC-016 — the run struct exists from here on, so
           ;; every pre-spawn consumer takes `satan-run-tool-ctx' of it
           ;; (the one tool-ctx builder).  Each later rebind of PREPARE
           ;; is written back to its slot in the same binding.
           (_run-ctx (setq run-ctx (make-satan-run
                     :id run-id
                     :mode mode
                     :start-time (plist-get prepare :start_time)
                     :dir dir
                     :bundle-path bundle-path
                     :pending-tool-calls (make-hash-table :test 'equal)
                     :tool-calls-done 0
                     :applied-actions nil
                     :staged-actions nil
                     :rejected-actions nil
                     :failed-actions nil
                     :final nil
                     :status 'running
                     :audit audit
                     :stdout-log-path stdout-log
                     :prepare prepare
                     :credential-refs (plist-get cred :refs))))
           (observer (condition-case _err
                         (satan-trace-stage "spawn.observer"
                           (satan-observer-process
                            (satan-run-tool-ctx run-ctx)))
                       (error nil)))
           (prepare (setf (satan-run-prepare run-ctx)
                          (plist-put prepare :observer observer)))
           ;; DR-010 §3: percept already built upstream by perceive; enrich
           ;; derives resonance + motive over PREPARE's `:percept' (consume-
           ;; only).  `:percept'/`:evidence'/`:sensor_status' are already set.
           (prepare (setf (satan-run-prepare run-ctx)
                          (satan-run-enrich prepare)))
           (sensor-status (plist-get prepare :sensor_status))
           ;; §S6 — sensor_alerts.check runs in the pre-spawn window
           ;; alongside the rest of evidence assembly.  Returns the
           ;; per-cause pre_spawn entries (fired or suppressed); Phase
           ;; 4.4 threads them into the audit close so the run's
           ;; `actions.json' carries the produced `pre_spawn' key.
           (pre-spawn (condition-case _err
                          (satan-trace-stage "spawn.sensor_alerts"
                            (satan-sensor-alerts-check
                             sensor-status
                             :tool-ctx (satan-run-tool-ctx run-ctx)))
                        (error nil)))
           ;; DR-010 §3 — consume-side probe COMMIT.  The pure read-
           ;; snapshots were taken upstream by `satan-run-perceive'
           ;; (unconditionally, before the gates) and threaded onto
           ;; PREPARE under `:probe_snapshots'.  Committing only here
           ;; means a budget-denied / session-blocked tick perceives but
           ;; never advances any watermark — no sensor signal is lost.
           (probe-snapshots (plist-get prepare :probe_snapshots))
           (_curiosity-signal
            (condition-case _err
                (satan-trace-stage "probes.commit.curiosity"
                  (satan-sensor-curiosity-probe-commit
                   (plist-get probe-snapshots :curiosity)))
              (error nil)))
           (_content-signal
            (condition-case _err
                (satan-trace-stage "probes.commit.content"
                  (satan-sensor-content-probe-commit
                   (plist-get probe-snapshots :content)))
              (error nil)))
           (_wpm-signal
            (condition-case _err
                (satan-trace-stage "probes.commit.wpm"
                  (satan-sensor-wpm-probe-commit
                   (plist-get probe-snapshots :wpm)))
              (error nil)))
           ;; DR-010 §3 (DEC-cursor-per-source-intra-day) — consume-side
           ;; ingest-cursor advance.  Reached only on a SUCCESSFUL spawn:
           ;; the perceive path and every `--write-no-child-run' denial
           ;; caller (budget-denied, session-blocked, perceive-failed)
           ;; return upstream in `satan-broker-run' and never enter
           ;; `--spawn', so no denied tick advances any frontier.  Soft-
           ;; fails so a cursor write error cannot fail the tick.
           (_ingest-cursor
            (condition-case _err
                (satan-trace-stage "spawn.ingest_cursor"
                  (satan-ingest-cursor-advance))
              (error nil)))
           (prepare (setf (satan-run-prepare run-ctx)
                          (plist-put prepare :pre_spawn pre-spawn)))
           (_pre-spawn-completed
            (setf (satan-run-pre-spawn-completed run-ctx) t)))
    (let* ((bundle (satan-trace-stage "spawn.bundle"
                     (funcall (or (plist-get mode :context-fn) #'ignore)
                              mode prepare)))
           (_attached (satan-audit-attach-bundle audit bundle)))
      (let* ((cmd (plist-get (plist-get mode :harness) :cmd))
             (args (plist-get (plist-get mode :harness) :args))
             (provider (plist-get mode :provider))
             (model (plist-get mode :model))
             (budget-tokens (plist-get mode :budget-tokens))
             (max-budget-tokens (or (plist-get mode :max-budget-tokens) 1000000))
             (provider-env (append
                            (delq nil
                                  (list
                                   (when provider
                                     (format "SATAN_PROVIDER=%s" provider))
                                   (when model
                                     (format "SATAN_MODEL=%s" model))
                                   (when budget-tokens
                                     (format "SATAN_BUDGET_TOKENS=%d" budget-tokens))
                                   (when max-budget-tokens
                                     (format "SATAN_MAX_BUDGET_TOKENS=%d" max-budget-tokens))))
                            (plist-get cred :env)))
             ;; Fail closed (REQ-010): no credential reference reaches the
             ;; child, even one the verdict did not need.
             (env (satan-credential-scrub
                   (append (list (format "SATAN_RUN_ID=%s" run-id)
                                 (format "SATAN_RUN_DIR=%s" dir)
                                 (format "SATAN_BUNDLE=%s" bundle-path))
                           provider-env
                           (plist-get (plist-get mode :harness) :env)
                           (plist-get cred :base))))
             (process-environment env)
             (exec-path (satan-broker--exec-path-from-env env)))
        ;; `setq' INSIDE the stage: `proc' is non-nil the moment a
        ;; child exists, even if the stage's own bookkeeping throws.
        (satan-trace-stage "spawn.exec"
          (setq proc
                (make-process
                 :name (format "satan-%s" run-id)
                 :command (cons cmd args)
                 :connection-type 'pipe
                 :coding 'utf-8
                 :noquery t
                 :stderr stderr-buf
                 :filter (satan-broker--make-filter run-ctx)
                 :sentinel (satan-broker--make-sentinel run-ctx))))
        (setf (satan-run-process run-ctx) proc)
        ;; Wrap the sentinel first, before any other post-child wiring:
        ;; from here the sentinel owns STDERR-BUF (flush + kill), so an
        ;; error below leaks nothing and the handler must not kill the
        ;; buffer — that would break the live child's stderr pipe.
        (set-process-sentinel
         proc
         (let ((existing (process-sentinel proc)))
           (lambda (p e)
             (when (buffer-live-p stderr-buf)
               (let ((coding-system-for-write 'utf-8))
                 (with-current-buffer stderr-buf
                   (write-region (point-min) (point-max)
                                 (expand-file-name "stderr.log" dir)
                                 nil 'silent))))
             (funcall existing p e)
             (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf)))))
        (let ((to (plist-get mode :timeout-seconds)))
          (when (and (integerp to) (> to 0))
            (setf (satan-run-timeout-timer run-ctx)
                  (run-with-timer
                   to nil
                   (lambda ()
                     (when (process-live-p proc)
                       (satan-audit-record
                        (satan-run-audit run-ctx) 'broker 'timeout
                        (list :after-seconds to))
                       (setf (satan-run-status run-ctx) 'timed-out)
                       (delete-process proc)))))))
        run-id))))
    ;; The one pre-child handler (SL-017 I7).  DEC-8 (AUD-008 F-001): the
    ;; flag must persist for the *live* run, not just the synchronous
    ;; launch window.  make-process is async, so the only correct clear
    ;; points are the child sentinel (normal/abnormal/killed exit — see
    ;; `satan-broker--make-sentinel') and this handler, so a failed launch
    ;; cannot leave the flag stuck.  Lock and buffer are handled BEFORE
    ;; recording, so a record that itself throws still leaves neither.
    (error
     (setq satan-run--spawn-running nil)
     (if proc
         ;; The child exists: its sentinel finalises and kills STDERR-BUF.
         (signal (car err) (cdr err))
       (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))
       (satan-broker--record-spawn-failure mode prepare dir run-ctx err)
       run-id)))))

(defun satan-broker--record-spawn-failure (mode prepare dir run-ctx err)
  "Record a spawn that failed with ERR before any child existed.
RUN-CTX is the run struct when the audit is already open, else nil
\(the manifest build or `satan-audit-open' threw).  Either way the run
ends `failed' with reason `spawn_failed', `.FAILED'-renamed and
announced, and the tick trace stops calling it spawned."
  (satan-trace-outcome "spawn_failed")
  (if run-ctx
      (let ((audit (satan-run-audit run-ctx)))
        (satan-audit-record audit 'broker 'spawn-failed
                            (list :error (error-message-string err)))
        (unless (file-exists-p (satan-run-bundle-path run-ctx))
          (satan-audit-attach-bundle
           audit (satan-broker--percept-bundle (satan-run-prepare run-ctx))))
        (setf (satan-run-failure-reason run-ctx) "spawn_failed"
              (satan-run-status run-ctx) 'failed)
        (satan-broker--finalize run-ctx))
    (satan-broker--write-failed-no-child-run
     mode prepare dir "spawn_failed" err)
    ;; `--finalize' clears it on the other branch; the no-child writer
    ;; does not, and `--spawn' set it before the manifest.
    (setq satan-memory-store--current-run-id nil)))

(provide 'satan-broker)
;;; satan-broker.el ends here
