;;; satan-tools-agenda.el --- agenda_read tool handler -*- lexical-binding: t; -*-

;; Read-only window into the user's calendar via `gcalcli'.  The
;; calendar id is read from a configurable env var (default
;; `WORK_EMAIL') so the dotfile carries no identity, and the call is
;; wrapped in `timeout(1)' so a stalled gcalcli can't freeze the parent
;; Emacs (the handler runs synchronously in the broker's host process).
;;
;; Risk = `read'; no capability required.  gcalcli authenticates via the
;; user's OAuth cache and does network I/O; the broker should consider
;; that when sandboxing future tools, but the call itself is non-mutating.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-tools)

(defcustom satan-tools-agenda-program "gcalcli"
  "Executable used to fetch agenda entries."
  :type 'string :group 'satan)

(defcustom satan-tools-agenda-extra-args '("--nocolor" "agenda")
  "Args inserted before `--calendar <id>' and any window args."
  :type '(repeat string) :group 'satan)

(defcustom satan-tools-agenda-calendar-env "WORK_EMAIL"
  "Env var holding the calendar id passed to `gcalcli --calendar'."
  :type 'string :group 'satan)

(defcustom satan-tools-agenda-timeout-seconds 15
  "Hard wall-clock timeout for the gcalcli invocation (via `timeout(1)')."
  :type 'integer :group 'satan)

(defcustom satan-tools-agenda-default-days 5
  "Window (in days) when the model omits `:days'.  Matches gcalcli's default-ish."
  :type 'integer :group 'satan)

(defconst satan-tools-agenda--days-max 14
  "Hard upper bound on the day window; clamped without error.")

(defun satan-tools-agenda--window-args (days)
  "Return positional `start end' args for a DAYS-wide window from today."
  (let* ((today (current-time))
         (end   (time-add today (days-to-time days))))
    (list (format-time-string "%Y-%m-%d" today)
          (format-time-string "%Y-%m-%d" end))))

(defun satan-tool/agenda-read (args _ctx)
  "Implements agenda_read.  ARGS: (:days INT optional).
Returns (ok :text STRING) | (error MSG)."
  (let* ((cal-env satan-tools-agenda-calendar-env)
         (cal     (getenv cal-env))
         (raw-days (plist-get args :days))
         (days (cond
                ((null raw-days) satan-tools-agenda-default-days)
                ((< raw-days 1) 1)
                ((> raw-days satan-tools-agenda--days-max)
                 satan-tools-agenda--days-max)
                (t raw-days)))
         (program satan-tools-agenda-program)
         (extra   satan-tools-agenda-extra-args)
         (timeout satan-tools-agenda-timeout-seconds))
    (cond
     ((or (null cal) (string-empty-p cal))
      (cons 'error (format "env var %s is unset" cal-env)))
     (t
      (with-temp-buffer
        (let* ((window (satan-tools-agenda--window-args days))
               (argv (append (list "timeout" (number-to-string timeout) program)
                             extra
                             (list "--calendar" cal)
                             window))
               (status (apply #'call-process (car argv) nil t nil (cdr argv))))
          (cond
           ((eq status 0)
            (cons 'ok (list :text (string-trim (buffer-string))
                            :calendar cal
                            :days days)))
           ((eq status 124)
            (cons 'error (format "gcalcli timed out after %ds" timeout)))
           (t
            (cons 'error
                  (format "gcalcli exited %s: %s"
                          status
                          (string-trim (buffer-string))))))))))))

(satan-tool-register
 (list :name "agenda_read"
       :risk 'read
       :args-schema '(days (:type integer :required nil))
       :handler 'satan-tool/agenda-read))

(provide 'satan-tools-agenda)
;;; satan-tools-agenda.el ends here
