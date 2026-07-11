;;; dl-satan-broker.el --- SATAN broker driver -*- lexical-binding: t; -*-

;; Lifecycle:
;;   1. resolve mode-spec
;;   2. mint run-id, create runs/<run-id>/
;;   3. assemble bundle, write manifest + bundle
;;   4. open audit handle, log run-start
;;   5. spawn jailed child via make-process (pipe, line-buffered filter)
;;   6. on tool_call: dispatch through dl-satan-tool-dispatch; send tool_result
;;   7. on final: capture, defer to sentinel
;;   8. sentinel: cancel timeout, run output handler, write actions.json + status, close audit
;;   9. timeout: kill process; sentinel handles the rest

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-audit)
(require 'dl-satan-budget)
(require 'dl-satan-jsonl)
(require 'dl-satan-protocol)
(require 'dl-satan-tools)
(require 'dl-satan-tools-org)
(require 'dl-satan-mode)
(require 'dl-satan-context)
(require 'dl-satan-output)
(require 'dl-satan-percept)
(require 'dl-satan-resonance)
(require 'dl-satan-motive)
(require 'dl-satan-observer)
(require 'dl-satan-sensor-alerts)
(require 'dl-satan-sensor-curiosity)
(require 'dl-satan-sensor-content)
(require 'dl-satan-sensor-wpm)
(require 'dl-satan-ingest-cursor)
(require 'dl-satan-trace)

(defvar dl-satan-memory-store--current-run-id)

;; DEC-8: mutual-exclusion flag — truthy while broker--spawn is live.
;; MCP server reads this to refuse new sessions while a scheduled run
;; is in progress.
(defvar dl-satan-broker--spawn-running nil)

(defcustom dl-satan-runs-dir
  (expand-file-name "satan/runs" (or (bound-and-true-p dl-notes-root)
                                     (expand-file-name "~/notes")))
  "Directory holding per-run audit bundles."
  :type 'directory :group 'dl-satan)

(defcustom dl-satan-hippocampus-dir
  (expand-file-name "satan/hippocampus" (or (bound-and-true-p dl-notes-root)
                                            (expand-file-name "~/notes")))
  "Read-write scratch directory inside the jail."
  :type 'directory :group 'dl-satan)

(defcustom dl-satan-direnv-dir
  (expand-file-name user-emacs-directory)
  "Directory whose `.envrc' is sourced into the jailed-harness environment.
If non-nil and `envrc--export' is available, the broker resolves direnv
for this directory and merges the result into `process-environment'
before spawning the child.  Set to nil to disable."
  :type '(choice directory (const nil)) :group 'dl-satan)

(defvar dl-satan-broker-provider-key-vars
  '((openrouter . "OPENROUTER_API_KEY")
    (anthropic  . "ANTHROPIC_API_KEY")
    (openai     . "OPENAI_API_KEY")
    (deepseek   . "DEEPSEEK_API_KEY"))
  "Map SATAN mode `:provider' symbol to its API-key env var name.")

(declare-function my/op-read-env "dl-secret" (var &optional refresh))
(declare-function my/scrub-op-refs-env "dl-secret" (env))
(declare-function notifications-notify "notifications" (&rest args))

(defun dl-satan-broker--read-env (var)
  "Return VAR from the environment, resolving `op://' refs when possible.
Falls back to `getenv' if `my/op-read-env' is unavailable."
  (if (fboundp 'my/op-read-env)
      (my/op-read-env var)
    (getenv var)))

(cl-defstruct dl-satan-run
  id mode start-time dir bundle-path process
  pending-tool-calls tool-calls-done
  applied-actions staged-actions rejected-actions failed-actions
  final status timeout-timer audit
  stdout-log-path
  ;; Phase 0.1: the run_ctx plist built by `dl-satan-broker--prepare'.
  ;; Carries the frozen `:time_now', `:run_id', `:start_time' and v0
  ;; placeholder slots (`:evidence' `:percept' `:sensor_status'
  ;; `:pre_spawn' `:motive' `:observer') that later phases populate.
  prepare)

(declare-function envrc--export "envrc" (env-dir))
(declare-function envrc--merged-environment "envrc" (process-env pairs))

(defun dl-satan-broker--direnv-env (base-env)
  "Return BASE-ENV merged with the direnv export for `dl-satan-direnv-dir'.
If envrc is not loaded, or the directory has no .envrc, or direnv
returns no vars, BASE-ENV is returned unchanged.  Direnv errors signal."
  (if (and dl-satan-direnv-dir
           (file-directory-p dl-satan-direnv-dir)
           (file-readable-p (expand-file-name ".envrc" dl-satan-direnv-dir))
           (fboundp 'envrc--export))
      (let ((result (envrc--export dl-satan-direnv-dir)))
        (pcase result
          ('error (error "direnv failed for %s" dl-satan-direnv-dir))
          ('none base-env)
          ((pred listp) (envrc--merged-environment base-env result))
          (_ base-env)))
    base-env))

(defun dl-satan-broker--exec-path-from-env (env)
  "Extract PATH from ENV (a `process-environment' value) and split into list."
  (let ((path (cl-some (lambda (kv)
                         (and (string-prefix-p "PATH=" kv)
                              (substring kv 5)))
                       env)))
    (if path (split-string path ":" t) exec-path)))

(defun dl-satan-broker--mint-run-id (name &optional time)
  (random t)
  (format "%s-%s-%06x"
          (format-time-string "%Y%m%dT%H%M%S" time)
          name
          (random (expt 16 6))))

(defconst dl-satan-broker--iso-time-format "%Y-%m-%dT%T%:z"
  "ISO-8601 time format the broker stamps onto run_ctx and tool-ctx.")

(defun dl-satan-broker--prepare (mode)
  "Allocate run_id, freeze time_now, return the v0 run_ctx plist for MODE.
The plist is the single source of truth for the run's identity and
the frozen `time_now' that the percept builder, observer, and tool
handlers all read.  Phase-1+ slots (`:evidence' `:percept'
`:sensor_status' `:pre_spawn' `:motive' `:observer') are present-with-
nil so later phases can `plist-put' without keyword-arg ordering
surprises."
  (let* ((name (plist-get mode :name))
         (start (current-time))
         (run-id (dl-satan-broker--mint-run-id name start))
         (time-now (format-time-string
                    dl-satan-broker--iso-time-format start)))
    (list :run_id run-id
          :mode_name name
          :time_now time-now
          :start_time start
          :evidence nil
          :percept nil
          :sensor_status nil
          :pre_spawn nil
          :motive nil
          :observer nil)))

(defconst dl-satan-broker--failed-suffix ".FAILED"
  "Suffix appended to a run directory when its status is not `done'.
Lets `ls' / glob users see failures at a glance without opening the
`status' file.  Helpers in this file strip the suffix when deriving
the run-id from a leaf directory name.")

(defun dl-satan-broker--date-bucket-for-run-id (run-id)
  "Return the YYYY-MM-DD date bucket parsed from RUN-ID's prefix.
Returns nil if RUN-ID does not start with a YYYYMMDDT date stamp."
  (when (and (stringp run-id)
             (string-match
              "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
              run-id))
    (format "%s-%s-%s"
            (match-string 1 run-id)
            (match-string 2 run-id)
            (match-string 3 run-id))))

(defun dl-satan-broker--bucket-name-p (name)
  "Return non-nil when NAME matches the YYYY-MM-DD bucket-dir pattern."
  (and (stringp name)
       (string-match-p "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'" name)))

(defun dl-satan-broker--legacy-run-name-p (name)
  "Return non-nil when NAME matches the pre-bucket flat run-id layout.
Pre-bucket runs sit directly under `dl-satan-runs-dir' with names like
`20260520T163446-tick-pulse-5e8018'."
  (and (stringp name)
       (string-match-p "\\`[0-9]\\{8\\}T[0-9]\\{6\\}-" name)))

(defun dl-satan-broker--run-id-from-leaf (name)
  "Strip the trailing `.FAILED' suffix (if any) from a leaf dir NAME."
  (if (and (stringp name)
           (string-suffix-p dl-satan-broker--failed-suffix name))
      (substring name 0 (- (length name)
                           (length dl-satan-broker--failed-suffix)))
    name))

(defun dl-satan-broker-run-dir-for-id (run-id &optional runs-dir)
  "Return the absolute dir path where RUN-ID's bucket lives.
New runs go under `<runs>/<YYYY-MM-DD>/<run-id>/'.  If RUN-ID lacks
a parsable date prefix (shouldn't happen for minted ids), falls back
to the legacy flat layout."
  (let* ((base (or runs-dir dl-satan-runs-dir))
         (bucket (dl-satan-broker--date-bucket-for-run-id run-id)))
    (if bucket
        (expand-file-name (concat bucket "/" run-id) base)
      (expand-file-name run-id base))))

(defun dl-satan-broker-locate-run-dir (run-id &optional runs-dir)
  "Return the on-disk dir for RUN-ID, or nil if no candidate exists.
Probes (in order): bucketed/<run-id>, bucketed/<run-id>.FAILED,
legacy flat <run-id>, legacy flat <run-id>.FAILED.  Used by readers
that need to find a run regardless of layout migration or terminal
status."
  (let* ((base (or runs-dir dl-satan-runs-dir))
         (bucket (dl-satan-broker--date-bucket-for-run-id run-id))
         (failed dl-satan-broker--failed-suffix)
         (candidates (delq nil
                           (list
                            (and bucket
                                 (expand-file-name
                                  (concat bucket "/" run-id) base))
                            (and bucket
                                 (expand-file-name
                                  (concat bucket "/" run-id failed) base))
                            (expand-file-name run-id base)
                            (expand-file-name (concat run-id failed) base)))))
    (cl-find-if #'file-directory-p candidates)))

(defun dl-satan-broker-list-run-dirs (runs-dir)
  "Return absolute paths of every run dir under RUNS-DIR.
Walks both the bucketed layout (`<runs>/<YYYY-MM-DD>/<run-id>') and
the legacy flat layout (`<runs>/<run-id>'), with or without the
`.FAILED' suffix.  Non-run entries (the `most-recent' symlink, stray
files, malformed names) are skipped.  Order is unspecified."
  (let (acc)
    (when (file-directory-p runs-dir)
      (dolist (entry (directory-files runs-dir nil "\\`[^.]" t))
        (let ((path (expand-file-name entry runs-dir)))
          (when (file-directory-p path)
            (cond
             ((dl-satan-broker--bucket-name-p entry)
              (dolist (child (directory-files path nil "\\`[^.]" t))
                (let ((cpath (expand-file-name child path)))
                  (when (and (file-directory-p cpath)
                             (dl-satan-broker--legacy-run-name-p
                              (dl-satan-broker--run-id-from-leaf child)))
                    (push cpath acc)))))
             ((dl-satan-broker--legacy-run-name-p
               (dl-satan-broker--run-id-from-leaf entry))
              (push path acc)))))))
    acc))

(defun dl-satan-broker-run-dirs-for-date (runs-dir date-prefix)
  "Return absolute paths of run dirs under RUNS-DIR dated DATE-PREFIX.
DATE-PREFIX is YYYYMMDDT (matching the run-id's stem).  Matches both
the bucketed layout (looks under `<runs>/YYYY-MM-DD/') and the legacy
flat layout (filters by prefix on the leaf name)."
  (let ((iso-bucket
         (and (stringp date-prefix)
              (string-match "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T"
                            date-prefix)
              (format "%s-%s-%s"
                      (match-string 1 date-prefix)
                      (match-string 2 date-prefix)
                      (match-string 3 date-prefix)))))
    (cl-remove-if-not
     (lambda (path)
       (let* ((leaf (file-name-nondirectory path))
              (run-id (dl-satan-broker--run-id-from-leaf leaf))
              (parent (file-name-nondirectory (directory-file-name
                                               (file-name-directory path)))))
         (or (and iso-bucket (equal parent iso-bucket))
             (string-prefix-p date-prefix run-id))))
     (dl-satan-broker-list-run-dirs runs-dir))))

(defun dl-satan-broker--tool-ctx (run-ctx)
  "Return the tool-ctx plist handlers see.
Reads frozen `time_now' from RUN-CTX's prepare plist (allocated once
by `dl-satan-broker--prepare') rather than calling `format-time-string'
per tool call.  `run-started-at' aliases the same frozen value — a run
has exactly one starting moment.

`:audit' carries the live audit handle so the intervention write API
\(T7 PR 3) can emit `intervention.created' into transcript.jsonl on
the handler's behalf.  Handlers must not invoke `dl-satan-audit-record'
directly with arbitrary event names; the only sanctioned route is
through `dl-satan-intervention-create' (and the matching classify /
lookup APIs)."
  (let* ((mode (dl-satan-run-mode run-ctx))
         (prepare (dl-satan-run-prepare run-ctx))
         (time-now (plist-get prepare :time_now))
         (percept (plist-get prepare :percept)))
    (list :id (dl-satan-run-id run-ctx)
          :mode-name (plist-get mode :name)
          :capabilities (plist-get mode :capabilities)
          :run-dir (dl-satan-run-dir run-ctx)
          :hippocampus-dir dl-satan-hippocampus-dir
          :run-started-at time-now
          :time-now time-now
          :audit (dl-satan-run-audit run-ctx)
          :percept-handles (and percept (plist-get percept :handles)))))

(defun dl-satan-broker--tee-stdout (path chunk)
  (let ((coding-system-for-write 'utf-8))
    (write-region chunk nil path 'append 'silent)))

(defun dl-satan-broker--send-validated (run-ctx obj)
  "Send OBJ to the harness, auditing a protocol error if it's malformed.
Bad broker output is a bug, not a wire failure — we audit but still send
so the harness sees something rather than blocking on stdin."
  (let ((err (dl-satan-protocol-validate 'out obj)))
    (when err
      (dl-satan-audit-record
       (dl-satan-run-audit run-ctx) 'broker 'protocol-error
       (list :outbound t
             :type (plist-get err :type)
             :reason (plist-get err :reason)
             :raw obj))))
  (dl-satan-jsonl-send (dl-satan-run-process run-ctx) obj))

(defun dl-satan-broker--failed-action-payload (obj reason)
  "Return the canonical failed-action plist for tool-call OBJ + REASON.
Shape is `(:action (:type NAME :args ARGS) :reason MSG)' — see the
failed-action shape note in AGENTS.md.  Used by `--on-tool-call' to
audit every denied dispatch in a structure consumers can grep."
  (list :action (list :type (plist-get obj :name)
                      :args (or (plist-get obj :args) '()))
        :reason reason))

(defun dl-satan-broker--on-tool-call (run-ctx obj)
  (let* ((mode (dl-satan-run-mode run-ctx))
         (budget (plist-get mode :budget-tool-calls))
         (done (dl-satan-run-tool-calls-done run-ctx)))
    (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'in 'tool-call obj)
    (cond
     ((and (integerp budget) (>= done budget))
      (let* ((reason "tool call budget exhausted")
             (result (list :type "tool_result"
                           :id (plist-get obj :id)
                           :ok :false
                           :error reason)))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'tool-denied result)
        (dl-satan-audit-record
         (dl-satan-run-audit run-ctx) 'broker 'action-failed
         (dl-satan-broker--failed-action-payload obj reason))
        (dl-satan-broker--send-validated run-ctx result)))
     (t
      (setf (dl-satan-run-tool-calls-done run-ctx) (1+ done))
      (let* ((tool-ctx (dl-satan-broker--tool-ctx run-ctx))
             (result (dl-satan-tool-dispatch
                      obj (plist-get mode :tools) tool-ctx))
             (ok-p (eq (plist-get result :ok) t)))
        (dl-satan-audit-record
         (dl-satan-run-audit run-ctx)
         'broker
         (if ok-p 'tool-result 'tool-denied)
         result)
        (unless ok-p
          (dl-satan-audit-record
           (dl-satan-run-audit run-ctx) 'broker 'action-failed
           (dl-satan-broker--failed-action-payload
            obj (plist-get result :error))))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'out 'tool-result result)
        (dl-satan-broker--send-validated run-ctx result))))))

(defun dl-satan-broker--on-final (run-ctx obj)
  (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'in 'final obj)
  (setf (dl-satan-run-final run-ctx) obj))

(defun dl-satan-broker--on-log (run-ctx obj)
  (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'in 'log obj))

(defun dl-satan-broker--on-error (run-ctx obj)
  (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'in 'protocol-error obj)
  (setf (dl-satan-run-status run-ctx) 'failed))

(defun dl-satan-broker--dispatch (run-ctx obj)
  (let ((err (dl-satan-protocol-validate 'in obj)))
    (cond
     (err
      (dl-satan-audit-record
       (dl-satan-run-audit run-ctx) 'broker 'protocol-error
       (list :type (plist-get err :type)
             :reason (plist-get err :reason)
             :raw obj))
      (setf (dl-satan-run-status run-ctx) 'invalid-protocol))
     (t
      (pcase (plist-get obj :type)
        ("ready"     (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'in 'ready obj))
        ("log"       (dl-satan-broker--on-log run-ctx obj))
        ("tool_call" (dl-satan-broker--on-tool-call run-ctx obj))
        ("final"     (dl-satan-broker--on-final run-ctx obj))
        ("error"     (dl-satan-broker--on-error run-ctx obj)))))))

(defun dl-satan-broker--make-filter (run-ctx)
  (let ((inner (dl-satan-jsonl-make-filter
                (lambda (obj) (dl-satan-broker--dispatch run-ctx obj))
                (lambda (err)
                  (dl-satan-audit-record
                   (dl-satan-run-audit run-ctx) 'broker 'protocol-error
                   (list :raw-line (car err)
                         :error    (cdr err)))))))
    (lambda (proc chunk)
      (dl-satan-broker--tee-stdout
       (dl-satan-run-stdout-log-path run-ctx) chunk)
      (funcall inner proc chunk))))

(defun dl-satan-broker--crash-context (run-ctx)
  "Build a crash-context snapshot plist for a non-done terminal path.
Pure data assembly from run-ctx and mode spec — no I/O."
  (let* ((mode (dl-satan-run-mode run-ctx))
         (prepare (dl-satan-run-prepare run-ctx))
         (start (dl-satan-run-start-time run-ctx))
         (elapsed (and start (float-time (time-subtract nil start)))))
    (list :status (symbol-name (dl-satan-run-status run-ctx))
          :tool_calls_done (or (dl-satan-run-tool-calls-done run-ctx) 0)
          :tool_calls_budget (or (plist-get mode :budget-tool-calls) 0)
          :budget_tokens (or (plist-get mode :budget-tokens) 0)
          :max_budget_tokens (or (plist-get mode :max-budget-tokens) 1000000)
          :elapsed_seconds (and elapsed (round elapsed))
          :timeout_seconds (or (plist-get mode :timeout-seconds) 0)
          :pre_spawn_completed (not (null prepare)))))

(defun dl-satan-broker--finalize (run-ctx)
  "Output handler + audit close.  Idempotent."
  (when (eq (dl-satan-run-status run-ctx) 'running)
    (setf (dl-satan-run-status run-ctx)
          (if (dl-satan-run-final run-ctx) 'done 'failed)))
  (let* ((mode (dl-satan-run-mode run-ctx))
         (final (dl-satan-run-final run-ctx))
         (handler (plist-get mode :output-handler))
         (status (dl-satan-run-status run-ctx))
         (partition
          (when (and final (eq status 'done) handler)
            (condition-case err
                (funcall handler final (dl-satan-broker--tool-ctx run-ctx))
              (error
               (dl-satan-audit-record
                (dl-satan-run-audit run-ctx) 'broker 'action-failed
                (list :error (error-message-string err)))
               nil)))))
    (unless (eq status 'done)
      (dl-satan-audit-record
       (dl-satan-run-audit run-ctx) 'broker 'crash-context
       (dl-satan-broker--crash-context run-ctx)))
    (when partition
      (dolist (a (plist-get partition :applied))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'action-applied a))
      (dolist (a (plist-get partition :staged))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'action-staged a))
      (dolist (a (plist-get partition :rejected))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'action-rejected a))
      (dolist (a (plist-get partition :failed))
        (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'action-failed a)))
    (let* ((prepare (dl-satan-run-prepare run-ctx))
           (pre-spawn (and prepare (plist-get prepare :pre_spawn)))
           (observer (and prepare (plist-get prepare :observer)))
           (actions (or partition
                        (list :applied [] :staged [] :rejected [] :failed []))))
      (when pre-spawn
        (setq actions (plist-put actions :pre_spawn pre-spawn)))
      (when observer
        (setq actions (plist-put actions :observer observer)))
      (dl-satan-audit-close
       (dl-satan-run-audit run-ctx) final actions status))
    (dl-satan-broker--mark-failed-on-disk run-ctx)
    (setq dl-satan-memory-store--current-run-id nil)))

(defun dl-satan-broker--mark-failed-on-disk (run-ctx)
  "If RUN-CTX's status is not `done', rename its dir adding `.FAILED'.
Lets `ls runs/<YYYY-MM-DD>/' surface failures without opening each
`status' file.  Updates the in-memory dir on RUN-CTX and repoints
`runs/most-recent' so the symlink survives the rename.

Also dispatches a syslog warning + a streak-aware desktop notification
via `dl-satan-broker--announce-failure'."
  (let ((status (dl-satan-run-status run-ctx))
        (dir (dl-satan-run-dir run-ctx))
        (run-id (dl-satan-run-id run-ctx)))
    (when (and dir
               (not (eq status 'done))
               (not (string-suffix-p dl-satan-broker--failed-suffix dir))
               (file-directory-p dir))
      (let ((new-dir (concat dir dl-satan-broker--failed-suffix)))
        (unless (file-exists-p new-dir)
          (rename-file dir new-dir)
          (setf (dl-satan-run-dir run-ctx) new-dir)
          (dl-satan-broker--update-most-recent
           run-id dl-satan-broker--failed-suffix)
          (dl-satan-broker--announce-failure
           run-id
           (plist-get (dl-satan-run-mode run-ctx) :name)
           status
           (dl-satan-broker--failure-reason run-ctx)))))))

(defun dl-satan-broker--failure-reason (run-ctx)
  "Return a short reason string for RUN-CTX's failure.
Pulls from the final plist when available, else the status symbol."
  (let* ((final (dl-satan-run-final run-ctx))
         (final-reason (and final (plist-get final :reason))))
    (cond
     ((and (stringp final-reason) (not (string-empty-p final-reason)))
      final-reason)
     (t (symbol-name (dl-satan-run-status run-ctx))))))

(defcustom dl-satan-failure-syslog t
  "When non-nil, broker emits a `logger -t satan -p user.warn' line per failure.
Disable if `logger(1)' is absent or you don't want SATAN failures in
the user journal (`journalctl --user -t satan')."
  :type 'boolean :group 'dl-satan)

(defcustom dl-satan-failure-notify t
  "When non-nil, broker pops a D-Bus notification on the first failure of a streak.
Suppressed once a streak is in progress (subsequent failures are quiet
until at least one `done' run breaks the chain)."
  :type 'boolean :group 'dl-satan)

(defun dl-satan-broker--failure-streak-count (runs-dir)
  "Count consecutive `.FAILED' run dirs from newest backward in RUNS-DIR.
Walks both bucketed and legacy layouts via `dl-satan-broker-list-run-dirs'
and sorts by the run-id leaf (date-stamped, so a string sort is
monotonic-in-time enough for streak detection).  Returns 0 when the
newest run is non-failed or no runs exist."
  (let* ((paths (dl-satan-broker-list-run-dirs runs-dir))
         (sorted (sort paths
                       (lambda (a b)
                         (string-greaterp
                          (dl-satan-broker--run-id-from-leaf
                           (file-name-nondirectory a))
                          (dl-satan-broker--run-id-from-leaf
                           (file-name-nondirectory b))))))
         (streak 0))
    (cl-loop for p in sorted
             while (string-suffix-p dl-satan-broker--failed-suffix p)
             do (cl-incf streak))
    streak))

(defun dl-satan-broker--announce-failure (run-id mode-slug status reason)
  "Emit syslog + (streak-gated) notify-send for a failed run.
RUN-ID, MODE-NAME, STATUS (symbol), REASON (short string) compose the
log line and notification body."
  (let ((line (format "%s %s %s %s"
                      (symbol-name status) mode-slug run-id reason)))
    (when dl-satan-failure-syslog
      (ignore-errors
        (call-process "logger" nil 0 nil
                      "-t" "satan" "-p" "user.warn" line)))
    (when (and dl-satan-failure-notify
               (= 1 (dl-satan-broker--failure-streak-count
                     dl-satan-runs-dir)))
      (ignore-errors
        (require 'notifications)
        (notifications-notify
         :app-name "SATAN"
         :title (format "SATAN %s (%s)" (symbol-name status) mode-slug)
         :body line
         :urgency 'normal
         :timeout 6000)))))

(defun dl-satan-broker--make-sentinel (run-ctx)
  (lambda (_proc event)
    (when (string-match-p "\\(finished\\|exited\\|signal\\|broken\\|killed\\|deleted\\)" event)
      (let ((tt (dl-satan-run-timeout-timer run-ctx)))
        (when tt (cancel-timer tt)))
      (dl-satan-audit-record (dl-satan-run-audit run-ctx) 'broker 'child-exit
                             (list :event (string-trim event)))
      (dl-satan-broker--finalize run-ctx)
      ;; DEC-8: clear the mutual-exclusion flag on async completion so
      ;; a crashed/killed process does not permanently block MCP sessions.
      (setq dl-satan-broker--spawn-running nil))))

(defun dl-satan-broker--build-manifest (mode run-id)
  "Return the manifest plist for MODE and RUN-ID.
Joins mechanical metadata (tools, capabilities, jail) with the
notes-owned model-facing schemas (`:tools' carries full JSON Schemas
including descriptions read from `dl-satan-tools-descriptions-dir').
The harness consumes `:tools' verbatim."
  (let* ((tool-names (plist-get mode :tools))
         (specs (mapcar (lambda (n)
                          (or (dl-satan-tool-lookup n)
                              (error "SATAN: unknown tool in mode %s: %s"
                                     (plist-get mode :name) n)))
                        tool-names))
         (tools-schema
          (vconcat (mapcar #'dl-satan-tool-json-schema specs)
                   (list (dl-satan-tool-final-schema)))))
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

(defun dl-satan-broker--most-recent-target (run-id &optional leaf-suffix)
  "Return the relative symlink target for RUN-ID's run dir.
For a bucketed run-id (the normal case) this is `<bucket>/<run-id>'
optionally with LEAF-SUFFIX appended (e.g. \".FAILED\").  For a run-id
that does not parse as bucketed, returns just the leaf."
  (let* ((bucket (dl-satan-broker--date-bucket-for-run-id run-id))
         (leaf (concat run-id (or leaf-suffix ""))))
    (if bucket (concat bucket "/" leaf) leaf)))

(defun dl-satan-broker--update-most-recent (run-id &optional leaf-suffix)
  "Repoint `dl-satan-runs-dir/most-recent' at RUN-ID's run dir.
LEAF-SUFFIX, when non-nil, is appended to the run-id leaf so the link
follows a post-status rename (e.g. `.FAILED').

Best-effort: failures (read-only fs, race with a concurrent run) are
swallowed so a busted symlink never aborts a run.  Target is stored
relative so the runs dir stays portable."
  (let ((link (expand-file-name "most-recent" dl-satan-runs-dir))
        (target (dl-satan-broker--most-recent-target run-id leaf-suffix)))
    (ignore-errors
      (when (or (file-symlink-p link) (file-exists-p link))
        (delete-file link))
      (make-symbolic-link target link t))))

(cl-defun dl-satan-broker--write-no-child-run
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

When RENAME-ANNOUNCE is non-nil: `.FAILED'-renames the run dir, repoints
`most-recent', and dispatches `dl-satan-broker--announce-failure' with
ANNOUNCE-REASON (defaulting to REASON).  Otherwise the dir is left in
place and the run stays silent (no rename, no notification — so a
session-blocked tick does not pollute the failure-streak counter or pop a
desktop alert; DEC-8 deferral)."
  (unless (file-directory-p dir) (make-directory dir t))
  (let* ((run-id (plist-get prepare :run_id))
         (manifest (dl-satan-broker--build-manifest mode run-id))
         (bundle (append (list :percept (plist-get prepare :percept))
                         bundle-extra))
         (audit (dl-satan-audit-open dir manifest bundle prepare)))
    (dl-satan-broker--update-most-recent run-id)
    (dl-satan-audit-record audit 'broker (or event status)
                           (or event-payload (list :reason reason)))
    (dl-satan-audit-close audit final
                          (list :applied [] :staged [] :rejected [] :failed [])
                          status)
    (when rename-announce
      (let ((new-dir (concat dir dl-satan-broker--failed-suffix)))
        (when (and (file-directory-p dir)
                   (not (file-exists-p new-dir)))
          (rename-file dir new-dir)
          (dl-satan-broker--update-most-recent
           run-id dl-satan-broker--failed-suffix)
          (dl-satan-broker--announce-failure
           run-id (plist-get mode :name) status
           (or announce-reason reason)))))))

(defun dl-satan-broker--write-budget-denied-run (mode prepare dir spent ceiling)
  "Write a slim audit bundle marking the run in PREPARE as budget-exceeded.
No child is spawned; the run terminates with status `budget-exceeded'
and a synthetic final summarising the gate decision.  PREPARE is the
prepare-phase run_ctx plist allocated by `dl-satan-broker--prepare'
(carries the frozen run_id + time_now and the perceived `:percept').
Thin caller of `dl-satan-broker--write-no-child-run' (rename + announce)."
  (dl-satan-broker--write-no-child-run
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

(defun dl-satan-broker-run (name)
  "Resolve MODE-NAME, spawn jailed harness, drive it to completion.
Returns the run-id.

Single allocation site for `run_id' + `time_now': calls
`dl-satan-broker--prepare' exactly once at the start of the run.  The
returned run_ctx plist is threaded into context assembly, tool
dispatch, and audit.

Refuses to spawn when an interactive MCP session is open (DEC-8
mutual exclusion), or when today's spend has met or exceeded
`dl-satan-budget-daily-tokens'.  In both cases writes a minimal
audit bundle with the appropriate status and returns the run-id
without launching the child."
  (let* ((mode (dl-satan-mode-resolve name))
         (prepare (dl-satan-broker--prepare mode))
         (run-id (plist-get prepare :run_id))
         (dir (dl-satan-broker-run-dir-for-id run-id)))
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
    (dl-satan-trace-with-tick run-id name
      (let ((perceive-error nil))
        (condition-case err
            (setq prepare (dl-satan-run-perceive prepare mode dir))
          (error (setq perceive-error err)))
        (cond
         (perceive-error
          (dl-satan-broker--write-no-child-run
           mode prepare dir 'failed "perceive_failed"
           :final (list :summary (format "perceive failed: %s"
                                         (error-message-string perceive-error))
                        :actions []
                        :reason "perceive_failed")
           :rename-announce t)
          (dl-satan-trace-outcome "perceive_failed")
          run-id)
         ;; DEC-8: refuse to spawn while an interactive session is open.
         ;; ISSUE-001: now perceives first.  No rename, no announce — the
         ;; deferral must not pollute the failure-streak counter or alert.
         ((and (boundp 'dl-satan-mcp--session-active)
               dl-satan-mcp--session-active)
          (message "SATAN broker: interactive session active — refusing scheduled run (DEC-8)")
          (dl-satan-broker--write-no-child-run
           mode prepare dir 'failed "session_blocked"
           :final (list :summary "Scheduled run blocked by active interactive session (DEC-8)"
                        :actions []
                        :reason "session_blocked")
           :rename-announce nil)
          (dl-satan-trace-outcome "session_blocked")
          run-id)
         ((dl-satan-budget-exceeded-p dl-satan-runs-dir)
          (let ((spent (dl-satan-budget-today-total dl-satan-runs-dir)))
            (dl-satan-broker--write-budget-denied-run
             mode prepare dir spent dl-satan-budget-daily-tokens)
            (dl-satan-trace-outcome "budget_denied")
            run-id))
         (t
          (dl-satan-trace-outcome "spawned")
          (dl-satan-broker--spawn mode prepare dir)))))))

(defun dl-satan-broker--spawn (mode prepare dir)
  "Spawn the jailed harness for MODE under DIR.
PREPARE is the run_ctx plist returned by `dl-satan-broker--prepare'
(carries the frozen run_id + time_now and v0 placeholder slots).
Returns the run-id."
  ;; DEC-8: set the mutual-exclusion flag so the MCP server refuses new
  ;; sessions while this scheduled run is live.  Cleared by the child
  ;; sentinel on exit (`dl-satan-broker--make-sentinel') and by this
  ;; function's error handler if the synchronous launch itself throws.
  (setq dl-satan-broker--spawn-running t)
  (condition-case err
      (let* ((run-id (plist-get prepare :run_id))
         (bundle-path (expand-file-name "bundle.json" dir))
         (stdout-log (expand-file-name "stdout.log" dir))
         (stderr-buf (generate-new-buffer
                      (format " *satan-stderr-%s*" run-id))))
    (unless (file-directory-p dir) (make-directory dir t))
    (dl-satan-broker--update-most-recent run-id)
    (setq dl-satan-memory-store--current-run-id run-id)
    (unless (file-directory-p dl-satan-hippocampus-dir)
      (make-directory dl-satan-hippocampus-dir t))
    ;; DR-010 §3 — consume-only spawn.  Perceive (percept.build +
    ;; percept.persist, threading `:percept'/`:evidence'/`:sensor_status'
    ;; onto PREPARE) ran UNCONDITIONALLY upstream in `dl-satan-broker-run'
    ;; before the session/budget gates.  This path runs only on consume,
    ;; so it derives the model-facing enrichment (resonance + motive) via
    ;; `dl-satan-run-enrich' over the already-built percept rather than
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
    ;; valid state — `dl-satan-motive-read' returns an empty parse and the
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
    ;; has assembled it (see `dl-satan-audit-attach-bundle' below).
    ;;
    ;; Observer errors are caught so a stale bundle / postgres outage
    ;; cannot fail the tick — the run proceeds without an observer pass
    ;; when it does.
    (let* ((manifest (dl-satan-broker--build-manifest mode run-id))
           (audit (dl-satan-trace-stage "spawn.audit_open"
                    (dl-satan-audit-open dir manifest nil prepare)))
           (prepare (plist-put prepare :audit audit))
           (observer (condition-case _err
                         (dl-satan-trace-stage "spawn.observer"
                           (dl-satan-observer-process prepare))
                       (error nil)))
           (prepare (plist-put prepare :observer observer))
           ;; DR-010 §3: percept already built upstream by perceive; enrich
           ;; derives resonance + motive over PREPARE's `:percept' (consume-
           ;; only).  `:percept'/`:evidence'/`:sensor_status' are already set.
           (prepare (dl-satan-run-enrich prepare))
           (sensor-status (plist-get prepare :sensor_status))
           ;; §S6 — sensor_alerts.check runs in the pre-spawn window
           ;; alongside the rest of evidence assembly.  Returns the
           ;; per-cause pre_spawn entries (fired or suppressed); Phase
           ;; 4.4 threads them into the audit close so the run's
           ;; `actions.json' carries the produced `pre_spawn' key.
           (pre-spawn (condition-case _err
                          (dl-satan-trace-stage "spawn.sensor_alerts"
                            (dl-satan-sensor-alerts-check
                             sensor-status mode
                             :time-now (plist-get prepare :time_now)
                             :run-dir dir))
                        (error nil)))
           ;; DR-010 §3 — consume-side probe COMMIT.  The pure read-
           ;; snapshots were taken upstream by `dl-satan-run-perceive'
           ;; (unconditionally, before the gates) and threaded onto
           ;; PREPARE under `:probe_snapshots'.  Committing only here
           ;; means a budget-denied / session-blocked tick perceives but
           ;; never advances any watermark — no sensor signal is lost.
           (_probe-snapshots (plist-get prepare :probe_snapshots))
           (_curiosity-signal
            (condition-case _err
                (dl-satan-trace-stage "probes.commit.curiosity"
                  (dl-satan-sensor-curiosity-probe-commit
                   (plist-get _probe-snapshots :curiosity)))
              (error nil)))
           (_content-signal
            (condition-case _err
                (dl-satan-trace-stage "probes.commit.content"
                  (dl-satan-sensor-content-probe-commit
                   (plist-get _probe-snapshots :content)))
              (error nil)))
           (_wpm-signal
            (condition-case _err
                (dl-satan-trace-stage "probes.commit.wpm"
                  (dl-satan-sensor-wpm-probe-commit
                   (plist-get _probe-snapshots :wpm)))
              (error nil)))
           ;; DR-010 §3 (DEC-cursor-per-source-intra-day) — consume-side
           ;; ingest-cursor advance.  Reached only on a SUCCESSFUL spawn:
           ;; the perceive path and every `--write-no-child-run' denial
           ;; caller (budget-denied, session-blocked, perceive-failed)
           ;; return upstream in `dl-satan-broker-run' and never enter
           ;; `--spawn', so no denied tick advances any frontier.  Soft-
           ;; fails so a cursor write error cannot fail the tick.
           (_ingest-cursor
            (condition-case _err
                (dl-satan-trace-stage "spawn.ingest_cursor"
                  (dl-satan-ingest-cursor-advance))
              (error nil)))
           (prepare (plist-put prepare :pre_spawn pre-spawn)))
    (let* ((bundle (dl-satan-trace-stage "spawn.bundle"
                     (funcall (or (plist-get mode :context-fn) #'ignore)
                              mode prepare)))
           (_attached (dl-satan-audit-attach-bundle audit bundle))
           (run-ctx (make-dl-satan-run
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
                     :prepare prepare)))
      (let* ((cmd (plist-get (plist-get mode :harness) :cmd))
             (args (plist-get (plist-get mode :harness) :args))
             (provider (plist-get mode :provider))
             (model (plist-get mode :model))
             (budget-tokens (plist-get mode :budget-tokens))
             (max-budget-tokens (or (plist-get mode :max-budget-tokens) 1000000))
             (key-var (and provider
                           (cdr (assq provider
                                      dl-satan-broker-provider-key-vars))))
             (key-val (and key-var
                           (condition-case _err
                               (dl-satan-broker--read-env key-var)
                             (error nil))))
             (provider-env (delq nil
                                 (list
                                  (when provider
                                    (format "SATAN_PROVIDER=%s" provider))
                                  (when model
                                    (format "SATAN_MODEL=%s" model))
                                  (when budget-tokens
                                    (format "SATAN_BUDGET_TOKENS=%d" budget-tokens))
                                  (when max-budget-tokens
                                    (format "SATAN_MAX_BUDGET_TOKENS=%d" max-budget-tokens))
                                  (when (and key-var key-val)
                                    (format "%s=%s" key-var key-val)))))
             (direnv-env (dl-satan-broker--direnv-env process-environment))
             (env (my/scrub-op-refs-env
                   (append (list (format "SATAN_RUN_ID=%s" run-id)
                                 (format "SATAN_RUN_DIR=%s" dir)
                                 (format "SATAN_BUNDLE=%s" bundle-path))
                           provider-env
                           (plist-get (plist-get mode :harness) :env)
                           direnv-env)))
             (process-environment env)
             (exec-path (dl-satan-broker--exec-path-from-env env))
             (proc
              (dl-satan-trace-stage "spawn.exec"
                (make-process
                 :name (format "satan-%s" run-id)
                 :command (cons cmd args)
                 :connection-type 'pipe
                 :coding 'utf-8
                 :noquery t
                 :stderr stderr-buf
                 :filter (dl-satan-broker--make-filter run-ctx)
                 :sentinel (dl-satan-broker--make-sentinel run-ctx)))))
        (setf (dl-satan-run-process run-ctx) proc)
        (let ((to (plist-get mode :timeout-seconds)))
          (when (and (integerp to) (> to 0))
            (setf (dl-satan-run-timeout-timer run-ctx)
                  (run-with-timer
                   to nil
                   (lambda ()
                     (when (process-live-p proc)
                       (dl-satan-audit-record
                        (dl-satan-run-audit run-ctx) 'broker 'timeout
                        (list :after-seconds to))
                       (setf (dl-satan-run-status run-ctx) 'timed-out)
                       (delete-process proc)))))))
        (set-process-sentinel
         proc
         (let ((existing (process-sentinel proc)))
           (lambda (p e)
             (let ((coding-system-for-write 'utf-8))
               (with-current-buffer stderr-buf
                 (write-region (point-min) (point-max)
                               (expand-file-name "stderr.log" dir)
                               nil 'silent)))
             (funcall existing p e)
             (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf)))))
        run-id))))
    ;; DEC-8 (AUD-008 F-001): the flag must persist for the *live* run, not
    ;; just the synchronous launch window.  make-process is async, so the only
    ;; correct clear points are the child sentinel (normal/abnormal/killed
    ;; exit — see `dl-satan-broker--make-sentinel') and this error handler,
    ;; which fires only if the synchronous launch throws before a sentinel is
    ;; attached, so a failed launch cannot leave the flag stuck.
    (error
     (setq dl-satan-broker--spawn-running nil)
     (signal (car err) (cdr err)))))

(provide 'dl-satan-broker)
;;; dl-satan-broker.el ends here
