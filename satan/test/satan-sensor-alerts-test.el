;;; satan-sensor-alerts-test.el --- sensor-alerts ert -*- lexical-binding: t; -*-

;; Phase 4 of perceptual-layer v0.  4.2 covers the capsule render; 4.3
;; will extend this file with cooldown + dispatch tests (A15–A17).

(require 'ert)
(require 'cl-lib)
(require 'satan-announce)
(require 'satan-sensor-alerts)
(require 'satan-context)
(require 'satan-tools-notify)
(require 'satan-audit)
(require 'satan-intervention)
(require 'satan-jsonl)
(require 'satan-run)
(require 'satan-tools-notify-test)       ; run + projection fixtures

;; ---------------------------------------------------------------------
;; --render-status (pure)
;; ---------------------------------------------------------------------

(ert-deftest satan-sensor/render-status-ok ()
  (should (equal "ok" (satan-sensor--render-status "ok"))))

(ert-deftest satan-sensor/render-status-stale ()
  (should (equal "STALE(28m)"
                 (satan-sensor--render-status "stale-28m"))))

(ert-deftest satan-sensor/render-status-missing-uppercased ()
  (should (equal "MISSING" (satan-sensor--render-status "missing"))))

(ert-deftest satan-sensor/render-status-unreachable-uppercased ()
  (should (equal "UNREACHABLE"
                 (satan-sensor--render-status "unreachable"))))

(ert-deftest satan-sensor/render-status-nil ()
  (should (equal "ok" (satan-sensor--render-status nil))))

;; ---------------------------------------------------------------------
;; --render-block
;; ---------------------------------------------------------------------

(ert-deftest satan-sensor/render-block-all-ok ()
  (let* ((framing '(("sensor_block_header" . "# Sensors")))
         (ss (list :current_window "ok" :focus "ok"
                   :browser "ok" :git "ok"))
         (lines (satan-sensor-render-block framing ss)))
    (should (equal (car lines) "# Sensors"))
    (should (equal (cadr lines)
                   "sensors: current=ok focus=ok browser=ok git=ok"))))

(ert-deftest satan-sensor/render-block-mixed-degradation ()
  (let* ((framing '(("sensor_block_header" . "# Sensors")))
         (ss (list :current_window "stale-28m" :focus "ok"
                   :browser "missing" :git "malformed"))
         (lines (satan-sensor-render-block framing ss)))
    (should (equal (cadr lines)
                   "sensors: current=STALE(28m) focus=ok browser=MISSING git=MALFORMED"))))

(ert-deftest satan-sensor/render-block-nil-when-no-header ()
  "Self-suppress when framing.txt is missing the seed key."
  (let ((framing '(("now" . "# Now"))))
    (should-not (satan-sensor-render-block
                 framing
                 (list :current_window "ok" :focus "ok"
                       :browser "ok")))))

(ert-deftest satan-sensor/render-block-nil-when-no-status ()
  (let ((framing '(("sensor_block_header" . "# Sensors"))))
    (should-not (satan-sensor-render-block framing nil))))

;; ---------------------------------------------------------------------
;; --with-prepare mirrors :sensor_status (Phase 4.2)
;; ---------------------------------------------------------------------

(ert-deftest satan-sensor/with-prepare-mirrors-sensor-status ()
  (let* ((prepare (list :run_id "r" :time_now "t"
                        :sensor_status (list :current_window "stale-28m"
                                             :focus "ok"
                                             :browser "malformed")))
         (bundle (satan-context--with-prepare (list :mode "tick-pulse") prepare)))
    (should (equal "stale-28m"
                   (plist-get (plist-get bundle :sensor_status)
                              :current_window)))
    (should (equal "malformed"
                   (plist-get (plist-get bundle :sensor_status)
                              :browser)))))

;; ---------------------------------------------------------------------
;; Phase 4.3 — cooldown + dispatch (A15, A16, A17)
;; ---------------------------------------------------------------------

(defmacro satan-sensor-alerts-test--with-tmp-state (var &rest body)
  "Bind VAR to a fresh tmp notified.json path; evaluate BODY; clean up."
  (declare (indent 1))
  `(let* ((,var (concat (make-temp-file "satan-notified-" nil ".json"))))
     (unwind-protect (progn ,@body)
       (when (file-exists-p ,var) (delete-file ,var))
       (when (file-exists-p (concat ,var ".tmp"))
         (delete-file (concat ,var ".tmp"))))))

(defconst satan-sensor-alerts-test--run-id "20260522T100000-test-mode-a1b2c3"
  "The run pre-spawn alerts join; a valid hex run-id (PHASE-02 regexp).")

(defmacro satan-sensor-alerts-test--with-run (var &rest body)
  "Bind VAR to a `satan-run' with a live audit in a tmp dir; evaluate BODY.
The run is what `satan-broker--spawn' has built by the time it checks
sensor alerts; `satan-tools-notify-test--ctx' derives each call's ctx
from it through the canonical builder."
  (declare (indent 1))
  `(satan-tools-notify-test--with-run (,var satan-sensor-alerts-test--run-id)
     ,@body))

(defun satan-sensor-alerts-test--created (run)
  "Return the payloads of RUN's `intervention.created' records."
  (satan-tools-notify-test--events run "intervention.created"))

(defun satan-sensor-alerts-test--ok-sensor ()
  (list :current_window "ok" :focus "ok"
        :browser "ok"))

(defun satan-sensor-alerts-test--silence-notify (body-fn)
  "Run BODY-FN with a live pop counter; COUNTER is a 1-cell list
incremented once per announcement that carries `:title' (i.e. an actual
pop, not a journal-only entry).  Only the projection writes are
stubbed (`satan-tools-notify-test--with-projection'); the record runs
for real against the run's audit."
  (let ((counter (list 0)))
    (satan-tools-notify-test--with-projection ()
      (let ((satan-announce-sink
             (lambda (a)
               (when (plist-get a :title) (cl-incf (car counter)))
               (satan-announce-record a)))
            (satan-announce-recorded nil))
        (funcall body-fn counter)))))

;; A15 — one dispatch per cause per cooldown window

(ert-deftest satan-sensor-alerts/no-degradation-no-entries ()
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (_)
         (let ((entries (satan-sensor-alerts-check
                         (satan-sensor-alerts-test--ok-sensor)
                         :tool-ctx (satan-tools-notify-test--ctx
                                    run '(notify) "2026-05-22T10:00:00+10:00")
                         :state-file path
                         :quiet-p-fn (lambda (&rest _) nil))))
           (should-not entries)))))))

(ert-deftest satan-sensor-alerts/git-degraded-never-alerts ()
  "The git feed renders its status but carries NO alert cause: a
\"malformed\" git status must not dispatch (commits are bursty; a quiet
or broken feed is not page-worthy — see `--causes')."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (_)
         (let ((entries (satan-sensor-alerts-check
                         (list :current_window "ok" :focus "ok"
                               :browser "ok" :git "malformed")
                         :tool-ctx (satan-tools-notify-test--ctx
                                    run '(notify) "2026-05-22T10:00:00+10:00")
                         :state-file path
                         :quiet-p-fn (lambda (&rest _) nil))))
           (should-not entries)))))))

(ert-deftest satan-sensor-alerts/stale-fires-once-then-cooldown ()
  "First call dispatches; second call within cooldown suppresses with reason `cooldown'."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (counter)
         (let* ((ss (list :current_window "stale-28m" :focus "ok"
                          :browser "ok"))
                (e1 (satan-sensor-alerts-check
                     ss
                     :tool-ctx (satan-tools-notify-test--ctx
                                run '(notify) "2026-05-22T10:00:00+10:00")
                     :state-file path
                     :quiet-p-fn (lambda (&rest _) nil)))
                (e2 (satan-sensor-alerts-check
                     ss
                     :tool-ctx (satan-tools-notify-test--ctx
                                run '(notify) "2026-05-22T10:15:00+10:00")
                     :state-file path
                     :quiet-p-fn (lambda (&rest _) nil))))
           (should (= 1 (length e1)))
           (should (equal "panopticon_current_stale"
                          (plist-get (car e1) :cause)))
           (should (eq :false (plist-get (car e1) :suppressed)))
           (should (stringp (plist-get (car e1) :dispatched_at)))
           (should (= 1 (length e2)))
           (should (eq t (plist-get (car e2) :suppressed)))
           (should (equal "cooldown" (plist-get (car e2) :reason)))
           (should (= 1 (car counter)))))))))

(ert-deftest satan-sensor-alerts/cooldown-elapsed-refires ()
  "Past 24h+ refires."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (counter)
         (let ((ss (list :current_window "stale-28m" :focus "ok"
                         :browser "ok")))
           (satan-sensor-alerts-check
            ss
            :tool-ctx (satan-tools-notify-test--ctx
                       run '(notify) "2026-05-21T10:00:00+10:00")
            :state-file path
            :quiet-p-fn (lambda (&rest _) nil))
           (let ((e2 (satan-sensor-alerts-check
                      ss
                      :tool-ctx (satan-tools-notify-test--ctx
                                 run '(notify) "2026-05-22T11:00:00+10:00")
                      :state-file path
                      :quiet-p-fn (lambda (&rest _) nil))))
             (should (eq :false (plist-get (car e2) :suppressed)))
             (should (= 2 (car counter))))))))))

(ert-deftest satan-sensor-alerts/quiet-hours-suppress ()
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (counter)
         (let ((entries (satan-sensor-alerts-check
                         (list :current_window "stale-28m" :focus "ok"
                               :browser "ok")
                         :tool-ctx (satan-tools-notify-test--ctx
                                    run '(notify) "2026-05-22T03:00:00+10:00")
                         :state-file path
                         :quiet-p-fn (lambda (&rest _) t))))
           (should (= 1 (length entries)))
           (should (eq t (plist-get (car entries) :suppressed)))
           (should (equal "quiet_hours"
                          (plist-get (car entries) :reason)))
           (should (= 0 (car counter)))))))))

;; A16 — every degradation produces an entry, fired or suppressed

(ert-deftest satan-sensor-alerts/every-degradation-recorded ()
  "Mix of stale + malformed → multiple entries this run."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (_)
         (let* ((entries (satan-sensor-alerts-check
                          (list :current_window "stale-28m"
                                :focus "malformed"
                                :browser "malformed")
                          :tool-ctx (satan-tools-notify-test--ctx
                                     run '(notify) "2026-05-22T10:00:00+10:00")
                          :state-file path
                          :quiet-p-fn (lambda (&rest _) nil)))
                (causes (mapcar (lambda (e) (plist-get e :cause)) entries)))
           (should (member "panopticon_current_stale" causes))
           (should (member "panopticon_focus_malformed" causes))
           (should (member "panopticon_browser_malformed" causes))
           (should (= 3 (length entries)))))))))

(ert-deftest satan-sensor-alerts/a16-one-to-one-causes-and-entries ()
  "A16 — causes touched in notified.json this run match pre_spawn entries.
Fired, suppressed-by-cooldown and suppressed-by-quiet all share the
invariant: |state.:causes keys| == |entries| with matching cause
names."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (_)
         (let* ((entries (satan-sensor-alerts-check
                          (list :current_window "stale-28m"
                                :focus "malformed"
                                :browser "ok")
                          :tool-ctx (satan-tools-notify-test--ctx
                                     run '(notify) "2026-05-22T10:00:00+10:00")
                          :state-file path
                          :quiet-p-fn (lambda (&rest _) nil)))
                (entry-causes (sort (mapcar (lambda (e) (plist-get e :cause))
                                            entries)
                                    #'string<))
                (state (satan-sensor-alerts--read-state path))
                (state-causes
                 (sort
                  (cl-loop for (k _) on (plist-get state :causes) by #'cddr
                           collect (substring (symbol-name k) 1))
                  #'string<)))
           (should (equal entry-causes state-causes))
           (should (= (length entries) (length state-causes)))))))))

;; SL-017 DEC-016 — the pre-spawn alert joins its run (ISS-016)

(ert-deftest satan-sensor-alerts/pre-spawn-intervention-joins-run ()
  "On the run's own tool-ctx a fired alert mints `<run-id>.iv001'.
The handler's record now succeeds: the entry is dispatched, the run's
transcript holds its `intervention.created', the projection is handed
exactly that recorded payload, and the cause's cooldown arms
\(`:last_notified_at'), which the synthetic ctx's failure never let
happen."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-tools-notify-test--with-projection (calls)
        (satan-announce-with-recorder
          (let* ((entries (satan-sensor-alerts-check
                           (list :current_window "stale-28m" :focus "ok"
                                 :browser "ok")
                           :tool-ctx (satan-tools-notify-test--ctx
                                      run '(notify) "2026-05-22T10:00:00+10:00")
                           :state-file path
                           :quiet-p-fn (lambda (&rest _) nil)))
                 (created (satan-sensor-alerts-test--created run))
                 (cs (satan-sensor-alerts--cause-state
                      (satan-sensor-alerts--read-state path)
                      "panopticon_current_stale")))
            (should (= 1 (length entries)))
            (should (eq :false (plist-get (car entries) :suppressed)))
            (should (= 1 (length satan-announce-recorded)))
            (should (= 1 (length created)))
            (should (equal (concat satan-sensor-alerts-test--run-id ".iv001")
                           (plist-get (car created) :intervention_id)))
            (should (equal satan-sensor-alerts-test--run-id
                           (plist-get (car created) :run_id)))
            (should (equal "2026-05-22T10:00:00+10:00"
                           (plist-get cs :last_notified_at)))
            (should (equal '(satan-intervention-project)
                           (satan-tools-notify-test--fns calls)))
            (should (equal created
                           (list (satan-tools-notify-test--as-recorded
                                  (cadar calls)))))))))))

;; SL-017 DEC-018 — the cooldown arms on the record (I3, I4)

(ert-deftest satan-sensor-alerts/cooldown-arms-on-record ()
  "With D-Bus and Postgres both down, the recorded alert still counts as
dispatched: the cooldown arms, the transcript marks it undelivered, and
a check inside the window records nothing more."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-tools-notify-test--with-projection
          (calls '(satan-intervention-project-with-verdict))
        (let* ((satan-announce-sink (lambda (_) (error "no D-Bus today")))
               (ss (list :current_window "stale-28m" :focus "ok"
                         :browser "ok"))
               (check (lambda (now)
                        (satan-sensor-alerts-check
                         ss
                         :tool-ctx (satan-tools-notify-test--ctx
                                    run '(notify) now)
                         :state-file path
                         :quiet-p-fn (lambda (&rest _) nil))))
               (e1 (funcall check "2026-05-22T10:00:00+10:00"))
               (cs (satan-sensor-alerts--cause-state
                    (satan-sensor-alerts--read-state path)
                    "panopticon_current_stale"))
               (e2 (funcall check "2026-05-22T10:15:00+10:00")))
          (should (eq :false (plist-get (car e1) :suppressed)))
          (should (stringp (plist-get (car e1) :dispatched_at)))
          (should (equal "2026-05-22T10:00:00+10:00"
                         (plist-get cs :last_notified_at)))
          (should (equal '("unknown")
                         (mapcar (lambda (p) (plist-get p :classification))
                                 (satan-tools-notify-test--events
                                  run "intervention.outcome_classified"))))
          (should (equal "cooldown" (plist-get (car e2) :reason)))
          (should (= 1 (length (satan-sensor-alerts-test--created run))))
          (should (equal '(satan-intervention-project-with-verdict)
                         (satan-tools-notify-test--fns calls))))))))

;; A17 — dispatch routes through notify_send + capability check

(ert-deftest satan-sensor-alerts/capability-denied-still-suppresses ()
  "A17 — the run's `:capabilities' gate the alert: no pop, no intervention."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-sensor-alerts-test--silence-notify
       (lambda (counter)
         (let ((entries (satan-sensor-alerts-check
                         (list :current_window "stale-28m" :focus "ok"
                               :browser "ok")
                         :tool-ctx (satan-tools-notify-test--ctx
                                    run '() "2026-05-22T10:00:00+10:00")
                         :state-file path
                         :quiet-p-fn (lambda (&rest _) nil))))
           (should (= 1 (length entries)))
           (should (eq t (plist-get (car entries) :suppressed)))
           (should (equal "capability_denied"
                          (plist-get (car entries) :reason)))
           (should (= 0 (car counter)))
           (should-not (satan-sensor-alerts-test--created run))))))))

(ert-deftest satan-sensor-alerts/dispatch-goes-through-tool-dispatch ()
  "Successful dispatch shows up as a recorded announcement."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--with-run run
      (satan-tools-notify-test--with-projection ()
        (satan-announce-with-recorder
          (satan-sensor-alerts-check
           (list :current_window "stale-28m" :focus "ok" :browser "ok")
           :tool-ctx (satan-tools-notify-test--ctx
                      run '(notify) "2026-05-22T10:00:00+10:00")
           :state-file path
           :quiet-p-fn (lambda (&rest _) nil))
          (should satan-announce-recorded)
          (should (string-match-p
                   "SATAN sensor: panopticon_current_stale"
                   (plist-get (car satan-announce-recorded) :title))))))))

;; ---------------------------------------------------------------------
;; SL-002 PHASE-04 — retired-cause state prune (RN-17)
;; ---------------------------------------------------------------------

(ert-deftest satan-sensor-alerts/no-bough-segment-in-sensor-line ()
  "VT-1 — the capsule sensor line carries no bough segment, and a
`:bough' key surviving in a persisted `sensor_status' is simply not
rendered (the source order no longer names it)."
  (let* ((framing '(("sensor_block_header" . "# Sensors")))
         (ss (list :current_window "ok" :focus "ok" :browser "ok"
                   :bough "unreachable" :git "ok"))
         (lines (satan-sensor-render-block framing ss)))
    (should (equal (cadr lines)
                   "sensors: current=ok focus=ok browser=ok git=ok"))
    (should-not (string-match-p "bough" (cadr lines)))))

(ert-deftest satan-sensor-alerts/no-bough-cause-derivable ()
  "VT-1 — an `unreachable' bough status derives no cause at all."
  (let ((causes (satan-sensor-alerts--derive-causes
                 (list :current_window "ok" :focus "ok" :browser "ok"
                       :bough "unreachable"))))
    (should (null causes))))

(ert-deftest satan-sensor-alerts/read-state-prunes-retired-cause-residue ()
  "VT-2 (RN-17) — persisted state outlives the code that wrote it.
A `notified.json' pre-seeded with a retired cause's `:causes' entry and
its `:streaks' counter, read through the post-removal path, comes back
with both gone and every live cause's state intact.

The prune is deliberately generic — it names no retired cause, it drops
whatever is outside the currently-derivable set — so this test doubles
as the guard for the next retirement."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts--write-state
     path
     '(:causes (:bough_unreachable
                (:last_notified_at "2026-05-20T09:00:00+10:00")
                :panopticon_current_stale
                (:last_notified_at "2026-05-21T09:00:00+10:00"))
       :streaks (:bough_unreachable 5)))
    (let* ((state (satan-sensor-alerts--read-state path))
           (causes (plist-get state :causes)))
      ;; retired residue gone, both slots
      (should-not (plist-member causes :bough_unreachable))
      (should-not (plist-member state :streaks))
      ;; unrelated live sensor state untouched
      (should (equal "2026-05-21T09:00:00+10:00"
                     (plist-get (plist-get causes :panopticon_current_stale)
                                :last_notified_at))))))

(ert-deftest satan-sensor-alerts/known-causes-covers-every-table-entry ()
  "The prune's allow-set is derived from `--causes', not transcribed —
so a cause added to the table can never be pruned as residue."
  (let ((known (satan-sensor-alerts--known-causes)))
    (should (member "panopticon_current_stale" known))
    (should (member "panopticon_current_missing" known))
    (should (member "panopticon_current_malformed" known))
    (should (member "panopticon_focus_malformed" known))
    (should (member "panopticon_browser_malformed" known))
    (should-not (cl-find-if (lambda (c) (string-match-p "bough" c)) known))))

(provide 'satan-sensor-alerts-test)
;;; satan-sensor-alerts-test.el ends here
