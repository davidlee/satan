;;; satan-announce.el --- Announcement seam: journal + D-Bus pop -*- lexical-binding: t; -*-

;; Governed by DEC-017 (design.md sec-2).  Every emit site (broker failure
;; announcements, the notify_send and speak tools, the two LISTEN-death
;; reporters)
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

(defcustom satan-speak-program "say"
  "Program that speaks its text argument aloud, or nil to disable speech.
Called as PROGRAM -- TEXT; engine and voice are its own config."
  :type '(choice (const :tag "Disabled" nil) string) :group 'satan)

(defcustom satan-speak-environment '("PIPER_VOICE=en_GB-alan-medium")
  "\"VAR=VALUE\" strings added to `satan-speak-program''s environment.
SATAN's voice, kept apart from the keeper's own `say' defaults."
  :type '(repeat string) :group 'satan)

(defvar satan-announce-sink #'satan-announce-deliver
  "Function that delivers one announcement plist; returns a D-Bus id or nil.
Only ever let-bound (by the test harness and `satan-announce-with-recorder'),
never set: a global change would silence a live Emacs.")

(defvar satan-announce-recorded nil
  "Announcements captured by `satan-announce-record', newest first.")

(cl-defun satan-announce (&key (app satan-notify-app) title body
                                (urgency 'normal) timeout journal speech)
  "Announce to the keeper through `satan-announce-sink'.
TITLE non-nil requests a desktop pop (BODY, URGENCY, TIMEOUT, APP apply).
JOURNAL non-nil requests one journal line.  SPEECH non-nil requests it
spoken aloud.  At least one of TITLE / JOURNAL / SPEECH should be
given.  Returns the sink's value."
  (funcall satan-announce-sink
           (list :app app :title title :body body :urgency urgency
                 :timeout timeout :journal journal :speech speech)))

(defun satan-announce--journal (line)
  "Write LINE to the journal; best effort, never signals."
  (ignore-errors
    (call-process "logger" nil 0 nil "-t" "satan" "-p" "user.warn" line)))

(defun satan-announce--speak (text)
  "Start `satan-speak-program' speaking TEXT; return its process.
Asynchronous: Emacs does not wait for the speech.  Signals when the
program cannot start; a later non-zero exit is only journaled."
  (let ((process-environment (append satan-speak-environment
                                     process-environment)))
    (make-process :name "satan-speak"
                  :buffer (generate-new-buffer " *satan-speak*")
                  :command (list satan-speak-program "--" text)
                  :connection-type 'pipe
                  :noquery t
                  :sentinel #'satan-announce--speech-sentinel)))

(defun satan-announce--speech-sentinel (proc _event)
  "Once PROC exits, journal a failure with its output; drop its buffer."
  (unless (process-live-p proc)
    (let ((buf (process-buffer proc))
          (status (process-exit-status proc)))
      (unless (zerop status)
        (satan-announce--journal
         (format "speech failed (exit %d): %s" status
                 (string-trim (with-current-buffer buf (buffer-string))))))
      (kill-buffer buf))))

(defun satan-announce-deliver (a)
  "Production sink: journal line (best effort), speech, then the D-Bus pop.
A is the announcement plist built by `satan-announce'.  A journal
failure (e.g. missing `logger(1)') is swallowed; a pop or speech
start failure is not — callers that need to know the keeper never saw
an alert rely on it propagating.  Returns the pop's id, else the
speech process."
  (when (plist-get a :journal)
    (satan-announce--journal (plist-get a :journal)))
  (let ((speech (and (plist-get a :speech)
                     (satan-announce--speak (plist-get a :speech)))))
    (if (not (plist-get a :title))
        speech
      (require 'notifications)
      (notifications-notify
       :app-name (plist-get a :app)
       :title    (plist-get a :title)
       :body     (plist-get a :body)
       :urgency  (plist-get a :urgency)
       :timeout  (plist-get a :timeout)))))

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
