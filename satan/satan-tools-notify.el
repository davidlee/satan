;;; satan-tools-notify.el --- notify_send tool handler -*- lexical-binding: t; -*-

;; Desktop notification via D-Bus, through the announce seam
;; (`satan-announce').  Visible to the user immediately, so risk is `low'
;; but never `read': included in the audit transcript like any other tool
;; call.

(require 'cl-lib)
(require 'satan-announce)
(require 'satan-tools)
(require 'satan-intervention)

(defcustom satan-notify-default-timeout 8000
  "Default notification timeout in milliseconds."
  :type 'integer :group 'satan)

(defconst satan-notify-intervention-window-minutes 30
  "Default `outcome_window_minutes' for notify interventions (outcome-semantics §3.3).")

(defun satan-notify--severity-for-urgency (urgency)
  "Map a `notify_send' urgency string to an intervention severity (§3.1)."
  (pcase urgency
    ("low"      "low")
    ("critical" "high")
    (_          "medium")))

(defun satan-notify--announce-urgency (urgency)
  "Map a `notify_send' urgency string to a `satan-announce' urgency."
  (pcase urgency
    ("low"      'low)
    ("critical" 'critical)
    (_          'normal)))

(defun satan-tool/notify-send (args ctx)
  "Send a desktop notification, recorded as a T7 intervention first.

ARGS:  (:title STR :body STR :urgency low|normal|critical :timeout INT-MS).
CTX:   broker-supplied tool-ctx with `:id', `:mode-name', `:time-now',
       and `:audit'.

Side effects, in order (SL-017 DEC-018):
  1. `satan-intervention-record' appends `intervention.created' to the
     run's transcript.  If it signals, nothing is shown.
  2. `satan-announce' pops the notification.
  3. `satan-intervention-project' INSERTs into `satan_interventions';
     its failure is only a note.  If the pop signalled instead,
     `satan-intervention-mark-undelivered' records and projects an
     undelivered verdict.

Returns:
  (ok :id N :intervention_id IV [:projection \"failed: MSG\"])  shown;
  (ok :id :null :intervention_id IV :delivered :false :error ERR
      [:verdict ...] [:projection ...])                       not shown;
  (error . MSG) on bad args or a failed record — nothing shown.
Every recorded intervention returns `ok', so a sensor cooldown arms on
the record."
  (let* ((title   (plist-get args :title))
         (body    (plist-get args :body))
         (urgency (plist-get args :urgency))
         (timeout (or (plist-get args :timeout)
                      satan-notify-default-timeout)))
    (if (not (and (stringp title) (stringp body)))
        (cons 'error "title and body must be strings")
      (condition-case rerr
          (let* ((payload (satan-intervention-record
                           :ctx ctx
                           :kind "notify"
                           :target-surface "dbus"
                           :message (format "%s — %s" title body)
                           :expected-outcome "user reads or acknowledges the notification within window"
                           :outcome-window-minutes
                           satan-notify-intervention-window-minutes
                           :severity (satan-notify--severity-for-urgency urgency)))
                 (iv-id (plist-get payload :intervention_id)))
            (condition-case perr
                (let ((notify-id (satan-announce
                                  :title title
                                  :body body
                                  :urgency (satan-notify--announce-urgency urgency)
                                  :timeout timeout)))
                  (cons 'ok
                        (append
                         (list :id notify-id :intervention_id iv-id)
                         (satan-intervention-try-project
                          #'satan-intervention-project payload))))
              (error
               (cons 'ok
                     (append
                      (list :id :null :intervention_id iv-id
                            :delivered :false
                            :error (error-message-string perr))
                      (satan-intervention-mark-undelivered ctx payload perr))))))
        (error (cons 'error (error-message-string rerr)))))))

(satan-tool-register
 (list :name "notify_send"
       :risk 'low
       :capability 'notify
       :args-schema '(title   (:type string :required t)
                      body    (:type string :required t)
                      urgency (:type string :required nil
                               :enum ("low" "normal" "critical"))
                      timeout (:type integer :required nil))
       :handler 'satan-tool/notify-send))

(provide 'satan-tools-notify)
;;; satan-tools-notify.el ends here
