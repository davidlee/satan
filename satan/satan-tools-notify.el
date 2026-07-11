;;; satan-tools-notify.el --- notify_send tool handler -*- lexical-binding: t; -*-

;; Desktop notification via D-Bus.  Thin wrapper around
;; `notifications-notify' (built-in).  Visible to the user immediately,
;; so risk is `low' but never `read': included in the audit transcript
;; like any other tool call.

(require 'cl-lib)
(require 'notifications)
(require 'satan-tools)
(require 'satan-intervention)

(defcustom satan-notify-app "SATAN"
  "Application name shown in D-Bus notifications."
  :type 'string :group 'satan)

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

(defun satan-tool/notify-send (args ctx)
  "Send a desktop notification via D-Bus and record a T7 intervention.

ARGS:  (:title STR :body STR :urgency low|normal|critical :timeout INT-MS).
CTX:   broker-supplied tool-ctx with `:id', `:mode-name', `:time-now',
       and `:audit'.

Side effects:
  - Fires the D-Bus notification (`notifications-notify').
  - Emits `intervention.created' into the run's transcript and INSERTs
    the row into `satan_interventions' via `satan-intervention-create'.

Returns (ok :id N :intervention_id IV-ID) on success;
(error MSG) on schema mismatch or D-Bus failure.  Intervention-create
failures propagate as user-error from the intervention layer."
  (let* ((title   (plist-get args :title))
         (body    (plist-get args :body))
         (urgency (plist-get args :urgency))
         (timeout (or (plist-get args :timeout)
                      satan-notify-default-timeout)))
    (cond
     ((not (and (stringp title) (stringp body)))
      (cons 'error "title and body must be strings"))
     (t
      (condition-case err
          (let ((notify-id (notifications-notify
                            :title title
                            :body body
                            :app-name satan-notify-app
                            :urgency (pcase urgency
                                       ("low"      'low)
                                       ("critical" 'critical)
                                       (_          'normal))
                            :timeout timeout)))
            (let ((iv-id (satan-intervention-create
                          :ctx ctx
                          :kind "notify"
                          :target-surface "dbus"
                          :message (format "%s — %s" title body)
                          :expected-outcome "user reads or acknowledges the notification within window"
                          :outcome-window-minutes
                          satan-notify-intervention-window-minutes
                          :severity (satan-notify--severity-for-urgency urgency))))
              (cons 'ok (list :id notify-id :intervention_id iv-id))))
        (error (cons 'error (error-message-string err))))))))

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
