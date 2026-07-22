;;; satan-sensor-alerts-test.el --- sensor-alerts ert -*- lexical-binding: t; -*-

;; Phase 4 of perceptual-layer v0.  4.2 covers the capsule render; 4.3
;; will extend this file with cooldown + dispatch tests (A15–A17).

(require 'ert)
(require 'cl-lib)
(require 'satan-sensor-alerts)
(require 'satan-context)
(require 'satan-tools-notify)

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

(defun satan-sensor-alerts-test--mode (caps)
  "Return a stub mode-spec with CAPS as `:capabilities'."
  (list :name "test-mode" :capabilities caps))

(defun satan-sensor-alerts-test--ok-sensor ()
  (list :current_window "ok" :focus "ok"
        :browser "ok"))

(defun satan-sensor-alerts-test--silence-notify (body-fn)
  "Stub `notifications-notify' to a counter; call BODY-FN with counter ref.
Also stubs `satan-intervention-create' so the notify_send handler's
T7 intervention path does not require a live audit handle / DB."
  (let ((counter (list 0)))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest _) (cl-incf (car counter)) 42))
              ((symbol-function 'satan-intervention-create)
               (lambda (&rest _) "iv-sensor-stub-01")))
      (funcall body-fn counter))))

;; A15 — one dispatch per cause per cooldown window

(ert-deftest satan-sensor-alerts/no-degradation-no-entries ()
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (_)
       (let ((entries (satan-sensor-alerts-check
                       (satan-sensor-alerts-test--ok-sensor)
                       (satan-sensor-alerts-test--mode '(notify))
                       :time-now "2026-05-22T10:00:00+10:00"
                       :state-file path
                       :quiet-p-fn (lambda (&rest _) nil))))
         (should-not entries))))))

(ert-deftest satan-sensor-alerts/git-degraded-never-alerts ()
  "The git feed renders its status but carries NO alert cause: a
\"malformed\" git status must not dispatch (commits are bursty; a quiet
or broken feed is not page-worthy — see `--causes')."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (_)
       (let ((entries (satan-sensor-alerts-check
                       (list :current_window "ok" :focus "ok"
                             :browser "ok" :git "malformed")
                       (satan-sensor-alerts-test--mode '(notify))
                       :time-now "2026-05-22T10:00:00+10:00"
                       :state-file path
                       :quiet-p-fn (lambda (&rest _) nil))))
         (should-not entries))))))

(ert-deftest satan-sensor-alerts/stale-fires-once-then-cooldown ()
  "First call dispatches; second call within cooldown suppresses with reason `cooldown'."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (counter)
       (let* ((ss (list :current_window "stale-28m" :focus "ok"
                        :browser "ok"))
              (mode (satan-sensor-alerts-test--mode '(notify)))
              (e1 (satan-sensor-alerts-check
                   ss mode
                   :time-now "2026-05-22T10:00:00+10:00"
                   :state-file path
                   :quiet-p-fn (lambda (&rest _) nil)))
              (e2 (satan-sensor-alerts-check
                   ss mode
                   :time-now "2026-05-22T10:15:00+10:00"
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
         (should (= 1 (car counter))))))))

(ert-deftest satan-sensor-alerts/cooldown-elapsed-refires ()
  "Past 24h+ refires."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (counter)
       (let* ((ss (list :current_window "stale-28m" :focus "ok"
                        :browser "ok"))
              (mode (satan-sensor-alerts-test--mode '(notify))))
         (satan-sensor-alerts-check
          ss mode
          :time-now "2026-05-21T10:00:00+10:00"
          :state-file path
          :quiet-p-fn (lambda (&rest _) nil))
         (let ((e2 (satan-sensor-alerts-check
                    ss mode
                    :time-now "2026-05-22T11:00:00+10:00"
                    :state-file path
                    :quiet-p-fn (lambda (&rest _) nil))))
           (should (eq :false (plist-get (car e2) :suppressed)))
           (should (= 2 (car counter)))))))))

(ert-deftest satan-sensor-alerts/quiet-hours-suppress ()
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (counter)
       (let* ((ss (list :current_window "stale-28m" :focus "ok"
                        :browser "ok"))
              (mode (satan-sensor-alerts-test--mode '(notify)))
              (entries (satan-sensor-alerts-check
                        ss mode
                        :time-now "2026-05-22T03:00:00+10:00"
                        :state-file path
                        :quiet-p-fn (lambda (&rest _) t))))
         (should (= 1 (length entries)))
         (should (eq t (plist-get (car entries) :suppressed)))
         (should (equal "quiet_hours"
                        (plist-get (car entries) :reason)))
         (should (= 0 (car counter))))))))

;; A16 — every degradation produces an entry, fired or suppressed

(ert-deftest satan-sensor-alerts/every-degradation-recorded ()
  "Mix of stale + malformed → multiple entries this run."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (_)
       (let* ((ss (list :current_window "stale-28m"
                        :focus "malformed"
                        :browser "malformed"))
              (mode (satan-sensor-alerts-test--mode '(notify)))
              (entries (satan-sensor-alerts-check
                        ss mode
                        :time-now "2026-05-22T10:00:00+10:00"
                        :state-file path
                        :quiet-p-fn (lambda (&rest _) nil)))
              (causes (mapcar (lambda (e) (plist-get e :cause)) entries)))
         (should (member "panopticon_current_stale" causes))
         (should (member "panopticon_focus_malformed" causes))
         (should (member "panopticon_browser_malformed" causes))
         (should (= 3 (length entries))))))))

(ert-deftest satan-sensor-alerts/a16-one-to-one-causes-and-entries ()
  "A16 — causes touched in notified.json this run match pre_spawn entries.
Fired, suppressed-by-cooldown and suppressed-by-quiet all share the
invariant: |state.:causes keys| == |entries| with matching cause
names."
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (_)
       (let* ((ss (list :current_window "stale-28m"
                        :focus "malformed"
                        :browser "ok"))
              (mode (satan-sensor-alerts-test--mode '(notify)))
              (entries (satan-sensor-alerts-check
                        ss mode
                        :time-now "2026-05-22T10:00:00+10:00"
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
         (should (= (length entries) (length state-causes))))))))

;; A17 — dispatch routes through notify_send + capability check

(ert-deftest satan-sensor-alerts/capability-denied-when-mode-lacks-notify ()
  (satan-sensor-alerts-test--with-tmp-state path
    (satan-sensor-alerts-test--silence-notify
     (lambda (counter)
       (let* ((ss (list :current_window "stale-28m" :focus "ok"
                        :browser "ok"))
              (mode (satan-sensor-alerts-test--mode '()))
              (entries (satan-sensor-alerts-check
                        ss mode
                        :time-now "2026-05-22T10:00:00+10:00"
                        :state-file path
                        :quiet-p-fn (lambda (&rest _) nil))))
         (should (= 1 (length entries)))
         (should (eq t (plist-get (car entries) :suppressed)))
         (should (equal "capability_denied"
                        (plist-get (car entries) :reason)))
         (should (= 0 (car counter))))))))

(ert-deftest satan-sensor-alerts/dispatch-goes-through-tool-dispatch ()
  "Successful dispatch shows up as a `notifications-notify' invocation."
  (satan-sensor-alerts-test--with-tmp-state path
    (let* ((seen nil)
           (mode (satan-sensor-alerts-test--mode '(notify)))
           (ss (list :current_window "stale-28m" :focus "ok"
                     :browser "ok")))
      (cl-letf (((symbol-function 'notifications-notify)
                 (lambda (&rest args)
                   (setq seen args)
                   42))
                ((symbol-function 'satan-intervention-create)
                 (lambda (&rest _) "iv-sensor-stub-02")))
        (satan-sensor-alerts-check
         ss mode
         :time-now "2026-05-22T10:00:00+10:00"
         :state-file path
         :quiet-p-fn (lambda (&rest _) nil)))
      (should seen)
      (should (string-match-p "SATAN sensor: panopticon_current_stale"
                              (plist-get seen :title))))))

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
