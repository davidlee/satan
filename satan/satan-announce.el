;;; satan-announce.el --- Announcement seam: journal + D-Bus pop -*- lexical-binding: t; -*-

;; Governed by DEC-017 (design.md sec-2).  Every emit site (broker failure
;; announcements, the notify_send tool, the two LISTEN-death reporters)
;; routes through `satan-announce' instead of calling `notifications-notify'
;; / `call-process "logger"' directly.  This module decides only HOW an
;; announcement is delivered; WHETHER one is due stays with each caller's own
;; policy (kill switches, streak gates, capability checks).
;;
;; Test hermeticity: `satan-announce-sink' is the seam's only mutable
;; surface, and it is only ever let-bound — by `dev/satan-test.el' around
;; the whole batch run, and by `satan-announce-with-recorder' for a single
;; test.  It is never `setq', so running the suite inside a live Emacs
;; cannot silence that Emacs's real alerts once the run ends.

;;; Code:

(require 'cl-lib)
(require 'satan-custom)

(declare-function notifications-notify "notifications" (&rest args))

(defcustom satan-notify-app "SATAN"
  "Application name shown in SATAN's desktop notifications."
  :type 'string :group 'satan)

(defvar satan-announce-sink #'satan-announce-deliver
  "Function that delivers one announcement plist; returns a D-Bus id or nil.
Only ever let-bound (by the test harness and `satan-announce-with-recorder'),
never set: a global change would silence a live Emacs.")

(defvar satan-announce-recorded nil
  "Announcements captured by `satan-announce-record', newest first.")

(cl-defun satan-announce (&key (app satan-notify-app) title body
                                (urgency 'normal) timeout journal)
  "Announce to the keeper through `satan-announce-sink'.
TITLE non-nil requests a desktop pop (BODY, URGENCY, TIMEOUT, APP apply).
JOURNAL non-nil requests one journal line.  At least one of TITLE /
JOURNAL should be given.  Returns the sink's value."
  (funcall satan-announce-sink
           (list :app app :title title :body body :urgency urgency
                 :timeout timeout :journal journal)))

(defun satan-announce-deliver (a)
  "Production sink: journal line (best effort), then the D-Bus pop.
A is the announcement plist built by `satan-announce'.  A journal
failure (e.g. missing `logger(1)') is swallowed; a pop failure is not
— callers that need to know the keeper never saw an alert rely on it
propagating."
  (when (plist-get a :journal)
    (ignore-errors
      (call-process "logger" nil 0 nil
                    "-t" "satan" "-p" "user.warn" (plist-get a :journal))))
  (when (plist-get a :title)
    (require 'notifications)
    (notifications-notify
     :app-name (plist-get a :app)
     :title    (plist-get a :title)
     :body     (plist-get a :body)
     :urgency  (plist-get a :urgency)
     :timeout  (plist-get a :timeout))))

(defun satan-announce-record (a)
  "Test sink: push A onto `satan-announce-recorded'; return a fake id."
  (push a satan-announce-recorded)
  (length satan-announce-recorded))

(defmacro satan-announce-with-recorder (&rest body)
  "Run BODY with the recording sink and a fresh `satan-announce-recorded'."
  (declare (indent 0))
  `(let ((satan-announce-sink #'satan-announce-record)
         (satan-announce-recorded nil))
     ,@body))

(provide 'satan-announce)
;;; satan-announce.el ends here
