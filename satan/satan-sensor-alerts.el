;;; satan-sensor-alerts.el --- SATAN sensor freshness + loud failure -*- lexical-binding: t; -*-

;; Phase 4 of the perceptual-layer v0 (see docs/satan/perceptual-design.md
;; §S6, §7, §A15–A17).  Reads the `:sensor_status' plist returned by
;; `satan-memory-evidence-assemble', renders the capsule sensor line,
;; and (Phase 4.3+) decides whether to dispatch a `notify_send' tool
;; call.  Dispatch and notified-state are wired in Phase 4.3; Phase 4.2
;; only owns the substrate + render.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-tools)

;; `satan-tick-quiet-p' is the default quiet-hours predicate but
;; `satan-tick' itself requires `satan-context' which transitively
;; loads this file; declare the function and resolve at call-site so
;; the require graph stays acyclic.
(declare-function satan-tick-quiet-p "satan-tick" (&optional time))

(defcustom satan-sensor-state-file
  (expand-file-name "satan/notified.json"
                    (or (getenv "XDG_STATE_HOME")
                        (expand-file-name ".local/state" "~")))
  "Per-cause cooldown + dispatch state for sensor alerts.
Shared across runs; reads/writes go through tmp + rename for
atomicity (§S6)."
  :type 'file :group 'satan)

(defcustom satan-sensor-alerts-cooldown-seconds 86400
  "Default per-cause cooldown for sensor alerts (§S6 — 24h).
At most one dispatch per cause per cooldown window (A15)."
  :type 'integer :group 'satan)

(defcustom satan-sensor-alerts-bough-streak-threshold 3
  "Consecutive unreachable ticks required before a bough alert fires (§S6).
Below the threshold the streak counter advances but the entry
records as suppressed with `reason: streak_below_threshold'."
  :type 'integer :group 'satan)

;; ---------------------------------------------------------------------
;; Capsule render (§S6)
;; ---------------------------------------------------------------------

(defconst satan-sensor--framing-key "sensor_block_header"
  "Framing.txt key supplying the sensor block's section header.
Owned by mind (`~/notes/satan/system/framing.txt'); when the key
is absent the block self-suppresses so a missing seed doesn't
block a run.")

(defconst satan-sensor--source-order
  '(:current_window :focus :browser :bough :git)
  "Canonical render order for the sensors.
Stable order keeps capsule diffs readable across runs even when
one source flips status.  `:git' (the git-activity feed) renders
last; it carries NO alert cause — see `satan-sensor-alerts--causes'.")

(defun satan-sensor--source-label (key)
  "Return the short capsule label for source KEY."
  (pcase key
    (:current_window "current")
    (:focus          "focus")
    (:browser        "browser")
    (:bough          "bough")
    (:git            "git")
    (_ (substring (symbol-name key) 1))))

(defun satan-sensor--render-status (status)
  "Return the capsule-friendly rendering of a status string STATUS.
`ok' stays lowercase; degradations render uppercase so a glance
distinguishes them: `stale-28m' → `STALE(28m)', `missing' →
`MISSING', etc."
  (cond
   ((or (null status) (equal status "ok")) "ok")
   ((and (stringp status) (string-prefix-p "stale-" status))
    (format "STALE(%s)" (substring status 6)))
   ((stringp status) (upcase status))
   (t (format "%S" status))))

(defun satan-sensor-render-block (framing sensor-status)
  "Return the rendered `# Sensors' block as a list of lines, or nil.
FRAMING is the parsed framing alist (from
`satan-context--parse-framing'); SENSOR-STATUS is the plist
attached to the evidence window by Phase 4.1.

Self-suppresses (returns nil) when either the framing key or the
sensor-status plist is absent — same pattern as the other capsule
blocks (A6 / A8).  When rendered, emits a single line of the form
`sensors: current=ok focus=ok browser=ok bough=ok' regardless of
how many sources are degraded; constant shape keeps capsule diffs
diff-friendly."
  (let ((header (cdr (assoc satan-sensor--framing-key framing))))
    (when (and header sensor-status)
      (let ((segments
             (mapcar
              (lambda (k)
                (format "%s=%s"
                        (satan-sensor--source-label k)
                        (satan-sensor--render-status
                         (plist-get sensor-status k))))
              satan-sensor--source-order)))
        (list header
              (concat "sensors: "
                      (mapconcat #'identity segments " ")))))))

;; ---------------------------------------------------------------------
;; Cause derivation (§S6 trigger list)
;; ---------------------------------------------------------------------

(defconst satan-sensor-alerts--causes
  '((:current_window
     ("stale"     . ("panopticon_current_stale" "warning"
                     "panopticon current_window stale; daemon may be dead"
                     "systemctl --user status panopticon-sway"))
     ("missing"   . ("panopticon_current_missing" "warning"
                     "panopticon current_window missing"
                     "systemctl --user status panopticon-sway"))
     ("malformed" . ("panopticon_current_malformed" "warning"
                     "panopticon current_window JSON is malformed"
                     "head -1 ~/.local/state/behaviour/current/sway.json")))
    (:focus
     ("malformed" . ("panopticon_focus_malformed" "warning"
                     "panopticon focus segments JSON is malformed"
                     "head ~/.local/state/behaviour/segments/focus-$(date +%F).jsonl")))
    (:browser
     ("malformed" . ("panopticon_browser_malformed" "warning"
                     "panopticon browser segments JSON is malformed"
                     "head ~/.local/state/behaviour/segments/browser-$(date +%F).jsonl")))
    (:bough
     ("unreachable" . ("bough_unreachable" "warning"
                       "bough tool unreachable"
                       "bough active"))))
  "Map of (SENSOR-KEY KIND-STRING . (CAUSE SEVERITY MESSAGE REMEDIATION)).
KIND-STRING is matched against the sensor_status value: a status of
`stale-28m' matches kind `stale' by prefix; `missing' / `malformed' /
`unreachable' match exactly.  Only the listed combinations fire.")

(defun satan-sensor-alerts--match-kind (status)
  "Return the cause kind string matching STATUS, or nil when STATUS is `ok'.
Accepts `stale-Nm' / `missing' / `malformed' / `unreachable'."
  (cond
   ((null status) nil)
   ((equal status "ok") nil)
   ((and (stringp status) (string-prefix-p "stale-" status)) "stale")
   ((member status '("missing" "malformed" "unreachable")) status)))

(defun satan-sensor-alerts--lookup-cause (sensor-key kind)
  "Return the (CAUSE SEVERITY MESSAGE REMEDIATION) tuple for SENSOR-KEY+KIND."
  (let ((rules (cdr (assq sensor-key satan-sensor-alerts--causes))))
    (cdr (assoc kind rules))))

(defun satan-sensor-alerts--derive-causes (sensor-status)
  "Walk SENSOR-STATUS and return a list of cause tuples for current degradation.
Each element is a plist: (:cause :severity :message :remediation
:sensor :status).  Returns nil when every sensor is `ok'."
  (cl-loop
   for key in satan-sensor--source-order
   for status = (plist-get sensor-status key)
   for kind = (satan-sensor-alerts--match-kind status)
   for tuple = (and kind (satan-sensor-alerts--lookup-cause key kind))
   when tuple
   collect (cl-destructuring-bind (cause severity message remediation) tuple
             (list :cause cause
                   :severity severity
                   :message message
                   :remediation remediation
                   :sensor (substring (symbol-name key) 1)
                   :status status))))

;; ---------------------------------------------------------------------
;; State file I/O (atomic tmp + rename, like satan-audit--write-json)
;; ---------------------------------------------------------------------

(defun satan-sensor-alerts--read-state (path)
  "Return the parsed notified.json plist at PATH, or an empty seed.
Missing file / malformed JSON both seed to `(:causes ())' so the run
proceeds — sensor state corruption must not block dispatch."
  (cond
   ((not (file-readable-p path)) (list :causes nil))
   (t (condition-case _err
          (with-temp-buffer
            (let ((coding-system-for-read 'utf-8))
              (insert-file-contents path))
            (goto-char (point-min))
            (let ((obj (json-parse-buffer :object-type 'plist
                                          :array-type 'list
                                          :null-object nil
                                          :false-object :false)))
              (or obj (list :causes nil))))
        (error (list :causes nil))))))

(defun satan-sensor-alerts--write-state (path state)
  "Atomically write STATE plist to PATH as JSON.
Ensures parent dir exists; uses tmp + rename per §S6."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (let ((tmp (concat path ".tmp"))
        (coding-system-for-write 'utf-8))
    (with-temp-file tmp
      (insert (json-serialize state :null-object :null :false-object :false)))
    (rename-file tmp path t)))

(defun satan-sensor-alerts--cause-state (state cause)
  "Return the per-CAUSE plist inside STATE.`:causes', or nil when absent."
  (plist-get (plist-get state :causes) (intern (concat ":" cause))))

(defun satan-sensor-alerts--update-cause-state (state cause new)
  "Return STATE with cause CAUSE's substate replaced by NEW (a plist).
Lives under the `:causes' slot so the A16 one-to-one invariant
(causes touched this run ↔ pre_spawn entries) holds independent of
the `:streaks' bookkeeping."
  (let* ((sym (intern (concat ":" cause)))
         (causes (or (plist-get state :causes) '()))
         (updated (plist-put (copy-sequence causes) sym new)))
    (plist-put (copy-sequence state) :causes updated)))

(defun satan-sensor-alerts--streak (state name)
  "Return the streak counter under STATE.`:streaks'.<NAME> as an integer."
  (or (plist-get (plist-get state :streaks)
                 (intern (concat ":" name)))
      0))

(defun satan-sensor-alerts--set-streak (state name value)
  "Return STATE with streak NAME set to VALUE (integer) under `:streaks'."
  (let* ((sym (intern (concat ":" name)))
         (streaks (or (plist-get state :streaks) '()))
         (updated (plist-put (copy-sequence streaks) sym value)))
    (plist-put (copy-sequence state) :streaks updated)))

;; ---------------------------------------------------------------------
;; Cooldown + suppression decisions
;; ---------------------------------------------------------------------

(defun satan-sensor-alerts--iso->time (s)
  "Return Emacs time for ISO string S, or nil when S is not a string."
  (and (stringp s) (not (string-empty-p s))
       (ignore-errors (date-to-time s))))

(defun satan-sensor-alerts--cooldown-elapsed-p (cause-state now)
  "Return non-nil when the cause's cooldown window has elapsed.
A never-fired cause (no `:last_notified_at') is always elapsed."
  (let* ((last (satan-sensor-alerts--iso->time
                (plist-get cause-state :last_notified_at)))
         (cooldown (or (plist-get cause-state :cooldown_seconds)
                       satan-sensor-alerts-cooldown-seconds)))
    (or (null last)
        (>= (float-time (time-subtract now last)) cooldown))))

(defun satan-sensor-alerts--bump-bough-streak (state status)
  "Return STATE with the bough_unreachable streak counter updated.
Reset to 0 when STATUS is anything other than `unreachable'.  The
counter lives under `:streaks' (not `:causes') so updates here
don't pollute the A16 one-to-one count between `:causes' and
pre_spawn entries."
  (let* ((count (satan-sensor-alerts--streak state "bough_unreachable"))
         (next (if (equal status "unreachable") (1+ count) 0)))
    (satan-sensor-alerts--set-streak state "bough_unreachable" next)))

;; ---------------------------------------------------------------------
;; Dispatch (§S6 — same path as model-side notify_send, A17)
;; ---------------------------------------------------------------------

(defun satan-sensor-alerts--notify-call (cause message)
  "Return a synthetic tool_call obj for `notify_send' targeting CAUSE+MESSAGE.
The broker's pre-spawn dispatch reuses the normal tool pipeline so
the capability check + audit semantics match model-side calls
verbatim."
  (list :type "tool_call"
        :id (format "pre-spawn-%s" cause)
        :name "notify_send"
        :args (list :title (format "SATAN sensor: %s" cause)
                    :body message
                    :urgency "normal")))

(defun satan-sensor-alerts--dispatch (cause message tool-ctx)
  "Dispatch the alert through `satan-tool-dispatch'.
Returns (DISPATCHED-P . REASON-STRING).  DISPATCHED-P is t on a
successful notify_send; nil otherwise with REASON-STRING carrying
the dispatcher's error (e.g. `capability denied: tool notify_send
requires notify')."
  (let* ((call (satan-sensor-alerts--notify-call cause message))
         (result (satan-tool-dispatch
                  call '("notify_send") tool-ctx)))
    (if (eq (plist-get result :ok) t)
        (cons t nil)
      (cons nil (or (plist-get result :error) "dispatch failed")))))

(defun satan-sensor-alerts--capability-denied-p (reason)
  "Return non-nil when REASON-STRING looks like a capability denial."
  (and (stringp reason)
       (string-match-p "\\`capability denied" reason)))

;; ---------------------------------------------------------------------
;; Public entry — sensor_alerts.check (§S1, Phase 4.3)
;; ---------------------------------------------------------------------

(defun satan-sensor-alerts--make-tool-ctx (mode time-now run-dir)
  "Return a pre-spawn synthetic tool-ctx mirroring MODE's :capabilities.
Removing `notify' from the actual mode-spec propagates to the synthetic
ctx, which makes the dispatcher refuse with `capability_denied' (A17)."
  (list :id (format "pre-spawn-%s" (or (plist-get mode :name) "?"))
        :mode-name (concat (or (plist-get mode :name) "?") "/pre-spawn")
        :capabilities (plist-get mode :capabilities)
        :run-dir run-dir
        :hippocampus-dir nil
        :run-started-at time-now
        :time-now time-now))

(defun satan-sensor-alerts--entry (cause base &rest extras)
  "Compose a pre_spawn entry plist from BASE + EXTRAS.
BASE is the cause tuple plist from `--derive-causes'; EXTRAS are
appended keyword overrides."
  (let ((entry (list :kind "sensor_alert"
                     :cause cause
                     :severity (plist-get base :severity)
                     :message (plist-get base :message)
                     :remediation (plist-get base :remediation))))
    (cl-loop for (k v) on extras by #'cddr
             do (setq entry (plist-put entry k v)))
    entry))

(cl-defun satan-sensor-alerts-check
    (sensor-status mode &key time-now run-dir state-file quiet-p-fn)
  "Compute the pre_spawn entries for SENSOR-STATUS under MODE.
For each degraded sensor:
  - quiet hours suppress dispatch (entry recorded with reason `quiet_hours');
  - per-cause cooldown suppresses dispatch (`cooldown');
  - bough sub-threshold streak suppresses dispatch (`streak_below_threshold');
  - capability gate suppresses dispatch (`capability_denied');
  - otherwise dispatch through `notify_send' and stamp `:dispatched_at'.

Updates the notified.json state file in-place; returns the list of
pre_spawn entries (one per degraded cause; never nil unless every
sensor was `ok')."
  (let* ((now (and time-now (date-to-time time-now)))
         (now (or now (current-time)))
         (now-iso (or time-now (format-time-string "%Y-%m-%dT%T%:z" now)))
         (path (or state-file satan-sensor-state-file))
         (quiet-p (funcall (or quiet-p-fn #'satan-tick-quiet-p) now))
         (state (satan-sensor-alerts--read-state path))
         (state (satan-sensor-alerts--bump-bough-streak
                 state (plist-get sensor-status :bough)))
         (tool-ctx (satan-sensor-alerts--make-tool-ctx
                    mode now-iso run-dir))
         (causes (satan-sensor-alerts--derive-causes sensor-status))
         entries)
    (dolist (base causes)
      (let* ((cause (plist-get base :cause))
             (msg (plist-get base :message))
             (cs (or (satan-sensor-alerts--cause-state state cause) '()))
             (streak (and (equal cause "bough_unreachable")
                          (satan-sensor-alerts--streak
                           state "bough_unreachable")))
             (entry nil)
             (next-cs (copy-sequence cs)))
        (cond
         ;; A15 — quiet hours suppress regardless of cooldown.
         (quiet-p
          (setq entry (satan-sensor-alerts--entry
                       cause base :suppressed t :reason "quiet_hours")))
         ;; Bough streak threshold (§S6 — ≥ 3 ticks before fire).
         ((and (equal cause "bough_unreachable")
               (< streak satan-sensor-alerts-bough-streak-threshold))
          (setq entry (satan-sensor-alerts--entry
                       cause base :suppressed t
                       :reason "streak_below_threshold")))
         ;; A15 — cooldown not elapsed.
         ((not (satan-sensor-alerts--cooldown-elapsed-p cs now))
          (setq entry (satan-sensor-alerts--entry
                       cause base :suppressed t :reason "cooldown")))
         (t
          (let* ((res (satan-sensor-alerts--dispatch cause msg tool-ctx))
                 (ok (car res)) (reason (cdr res)))
            (cond
             (ok
              (setq entry (satan-sensor-alerts--entry
                           cause base
                           :suppressed :false
                           :dispatched_at now-iso))
              (setq next-cs (plist-put next-cs :last_notified_at now-iso)))
             ((satan-sensor-alerts--capability-denied-p reason)
              (setq entry (satan-sensor-alerts--entry
                           cause base :suppressed t
                           :reason "capability_denied")))
             (t
              (setq entry (satan-sensor-alerts--entry
                           cause base :suppressed t
                           :reason (format "dispatch_failed: %s" reason))))))))
        ;; A16 — every entry (fired or suppressed) corresponds to a
        ;; `:causes' update this run; stamp :last_evaluated_at so the
        ;; one-to-one invariant holds independent of dispatch outcome.
        (setq next-cs (plist-put next-cs :last_evaluated_at now-iso))
        (setq state (satan-sensor-alerts--update-cause-state
                     state cause next-cs))
        (push entry entries)))
    (satan-sensor-alerts--write-state path state)
    (nreverse entries)))

(provide 'satan-sensor-alerts)
;;; satan-sensor-alerts.el ends here
