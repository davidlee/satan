;;; satan-patch-adapter-pi.el --- jailed-pi adapter -*- lexical-binding: t; -*-

;; Phase 2.2 of satan/patch-harness.plan.md.  Drives `jailed-pi' in
;; headless JSON mode inside a prepared worktree.  All process work is
;; asynchronous; results flow back via the `:on-finish' callback the
;; runner provides.
;;
;; Invocation shape:
;;
;;   jailed-pi
;;     [--provider <P>] [--model <M>]
;;     --mode json --no-session --no-context-files
;;     --tools read,write,edit,bash,grep,find,ls
;;     --system-prompt <PROMPT-CONTENTS>
;;     -p <DIRECTIVE>
;;
;; The jail itself is the safety boundary; pi inside the jail cannot
;; write outside the bound worktree.  We do not pass `--accept-all'
;; because current pi has no such flag; `--mode json -p' is
;; non-interactive by construction.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-patch-adapter)
(require 'satan-credential)

(defcustom satan-patch-adapter-pi-program "jailed-pi"
  "Executable name (or absolute path) of the jailed-pi wrapper."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-adapter-pi-api-key-vars
  '("ANTHROPIC_API_KEY" "OPENROUTER_API_KEY" "DEEPSEEK_API_KEY"
    "OPENAI_API_KEY" "GEMINI_API_KEY" "MISTRAL_API_KEY"
    "VOYAGE_API_KEY")
  "Env vars whose credential refs are resolved before spawning jailed-pi.
The patch runner checks readiness over these before claiming a job and
resolves them through `satan-credential-resolve' after (SL-018 design sec-7);
the bwrap wrapper forwards each var into the jail via
`--setenv VAR \"$VAR\"'.  Requires jailed-pi to be built with
`useOpEnv = false; passApiKeysFromEnv = true'.  Narrow this to the
provider pi is configured for: a cold ref to an unused provider still
holds jobs back until a credential session is live."
  :type '(repeat string) :group 'satan-patch)

(defcustom satan-patch-adapter-pi-tools
  "read,write,edit,bash,grep,find,ls"
  "Comma-separated tool allowlist passed via pi's `--tools'."
  :type 'string :group 'satan-patch)

(defcustom satan-patch-adapter-pi-extra-args nil
  "Extra arguments appended verbatim before `-p DIRECTIVE'.
Useful for `--thinking', `--api-key', etc.  No shell quoting."
  :type '(repeat string) :group 'satan-patch)

;; ---------------------------------------------------------------------
;; per-run state captured by filter / sentinel
;; ---------------------------------------------------------------------

(defun satan-patch-adapter-pi--make-state (job-id log-path max-bytes)
  "Allocate the mutable per-run state plist."
  (list :job-id job-id
        :log-path log-path
        :max-bytes max-bytes
        :written 0
        :line-buf ""
        :truncated nil
        :last-assistant-text ""
        :error-event nil
        :start-time (float-time)))

(defun satan-patch-adapter-pi--append-log (state chunk)
  "Append CHUNK bytes to STATE's log file, respecting :max-bytes."
  (let* ((written (plist-get state :written))
         (max     (plist-get state :max-bytes))
         (room    (- max written)))
    (cond
     ((<= room 0)
      (plist-put state :truncated t))
     ((<= (length chunk) room)
      (let ((coding-system-for-write 'utf-8))
        (write-region chunk nil (plist-get state :log-path) 'append 'silent))
      (plist-put state :written (+ written (length chunk))))
     (t
      (let ((trimmed (substring chunk 0 room)))
        (let ((coding-system-for-write 'utf-8))
          (write-region trimmed nil (plist-get state :log-path)
                        'append 'silent))
        (plist-put state :written max)
        (plist-put state :truncated t))))))

(defun satan-patch-adapter-pi--scan-event (state json-line on-log)
  "Inspect one parsed pi JSON event.  Mutates STATE; calls ON-LOG if given."
  (let ((obj (condition-case _err
                 (json-parse-string json-line
                                    :object-type 'plist
                                    :array-type 'list
                                    :null-object nil
                                    :false-object :false)
               (error nil))))
    (when obj
      (pcase (plist-get obj :type)
        ("error"
         (plist-put state :error-event obj))
        ("message_end"
         (let* ((msg (plist-get obj :message))
                (role (plist-get msg :role)))
           (when (equal role "assistant")
             (let* ((content (plist-get msg :content))
                    (text-parts
                     (cl-loop for part in (or content '())
                              when (equal (plist-get part :type) "text")
                              collect (or (plist-get part :text) ""))))
               (when text-parts
                 (plist-put state :last-assistant-text
                            (mapconcat #'identity text-parts "\n")))))))))
    (when on-log
      (funcall on-log json-line))))

(defun satan-patch-adapter-pi--filter (state on-log)
  "Return a `make-process' :filter closure that streams to STATE's log
and feeds parsed JSON lines through ON-LOG."
  (lambda (_proc chunk)
    (satan-patch-adapter-pi--append-log state chunk)
    (let* ((buf (concat (plist-get state :line-buf) chunk))
           (lines (split-string buf "\n"))
           (last (car (last lines)))
           (full-lines (butlast lines)))
      (plist-put state :line-buf last)
      (dolist (line full-lines)
        (when (and (stringp line)
                   (not (string-empty-p (string-trim line))))
          (satan-patch-adapter-pi--scan-event state line on-log))))))

;; ---------------------------------------------------------------------
;; build-args
;; ---------------------------------------------------------------------

(defun satan-patch-adapter-pi--build-args (input)
  "Construct the pi argv from the INPUT plist."
  (let* ((provider (plist-get input :provider))
         (model    (plist-get input :model))
         (prompt-file (plist-get input :system-prompt-file))
         (directive (plist-get input :directive)))
    (append
     (when provider (list "--provider" provider))
     (when model (list "--model" model))
     (list "--mode" "json"
           "--no-session"
           "--no-context-files"
           "--tools" satan-patch-adapter-pi-tools)
     ;; Pi 0.75.x dropped --system-prompt-file; the supported flag is
     ;; --system-prompt <text>.  Read the file contents and pass them
     ;; inline so the patch-agent's harness prompt fully replaces pi's
     ;; default coding-assistant prompt (mirrors prior semantics).
     (when (and prompt-file (file-readable-p prompt-file))
       (list "--system-prompt"
             (with-temp-buffer
               (insert-file-contents prompt-file)
               (buffer-string))))
     satan-patch-adapter-pi-extra-args
     (list "-p" directive))))

;; ---------------------------------------------------------------------
;; sentinel -> on-finish bridge
;; ---------------------------------------------------------------------

(defun satan-patch-adapter-pi--sentinel (state on-finish stderr-buf)
  "Return a process sentinel that resolves ON-FINISH once the process
exits.  STATE accumulates streaming data; STDERR-BUF holds pi's
stderr."
  (lambda (proc _event)
    (unless (process-live-p proc)
      ;; flush trailing partial line through the scanner
      (let ((tail (plist-get state :line-buf)))
        (when (and (stringp tail) (not (string-empty-p (string-trim tail))))
          (satan-patch-adapter-pi--scan-event state tail nil)))
      (let* ((exit-code (process-exit-status proc))
             (elapsed (- (float-time) (plist-get state :start-time)))
             (stderr-text
              (and (buffer-live-p stderr-buf)
                   (with-current-buffer stderr-buf (buffer-string))))
             (summary (plist-get state :last-assistant-text))
             (error-event (plist-get state :error-event))
             (timed-out (plist-get state :timed-out))
             (stderr-path
              (let ((p (plist-get state :log-path)))
                (and p (concat (file-name-sans-extension p) ".stderr.log"))))
             (status (cond
                      (timed-out 'failure)
                      (error-event 'failure)
                      ((not (zerop exit-code)) 'failure)
                      (t 'success)))
             (result
              (list :status status
                    :summary summary
                    :changed-files nil
                    :checks nil
                    :warnings (delq nil
                                    (list
                                     (when (plist-get state :truncated)
                                       "adapter output truncated at cap")
                                     (when (and stderr-text
                                                (not (string-empty-p
                                                      (string-trim stderr-text))))
                                       (format "stderr: %s"
                                               (string-trim stderr-text)))))
                    :raw-output (plist-get state :log-path)
                    :exit-code exit-code
                    :elapsed-seconds elapsed
                    :error (cond
                            (timed-out "timeout")
                            (error-event
                             (or (plist-get error-event :error)
                                 (plist-get error-event :message)
                                 "adapter_error_event"))
                            ((not (zerop exit-code))
                             (format "pi exit %s" exit-code))))))
        (when (and stderr-path stderr-text
                   (not (string-empty-p stderr-text)))
          (ignore-errors
            (with-temp-file stderr-path
              (insert stderr-text))))
        (when (buffer-live-p stderr-buf) (kill-buffer stderr-buf))
        (when on-finish (funcall on-finish result))))))

;; ---------------------------------------------------------------------
;; invoke
;; ---------------------------------------------------------------------

(cl-defun satan-patch-adapter-pi-invoke
    (job-spec input &key on-finish on-log)
  "Run jailed-pi against JOB-SPEC's worktree with INPUT.  Returns the
spawned process handle, or signals on a setup failure (e.g. missing
executable).  See `satan-patch-adapter' for the protocol."
  (unless (executable-find satan-patch-adapter-pi-program)
    (when on-finish
      (funcall on-finish
               (list :status 'failure
                     :error "jailed-pi executable not found"
                     :summary ""
                     :warnings '()
                     :raw-output nil
                     :exit-code -1
                     :elapsed-seconds 0)))
    (cl-return-from satan-patch-adapter-pi-invoke nil))
  (let* ((wt (plist-get job-spec :worktree_path))
         (job-id (plist-get job-spec :id))
         (log-path (plist-get input :log-path))
         (max-bytes (or (plist-get input :max-output-bytes) (* 8 1024 1024)))
         (timeout (or (plist-get input :timeout-seconds) 1800))
         (args (satan-patch-adapter-pi--build-args input))
         (state (satan-patch-adapter-pi--make-state
                 job-id log-path max-bytes))
         (stderr-buf (generate-new-buffer
                      (format " *satan-patch-pi-stderr-%s*" job-id)))
         (default-directory (file-name-as-directory wt))
         ;; INPUT's :env holds the runner's resolved keys; they shadow
         ;; the refs, and the scrub drops every ref left over.
         (process-environment
          (satan-credential-scrub
           (append (plist-get input :env) process-environment))))
    ;; reset log file
    (with-temp-file log-path (insert ""))
    (let* ((proc
            (make-process
             :name (format "satan-patch-pi-%s" job-id)
             :command (cons satan-patch-adapter-pi-program args)
             :connection-type 'pipe
             :coding 'utf-8
             :noquery t
             :stderr stderr-buf
             :filter (satan-patch-adapter-pi--filter state on-log)
             :sentinel (satan-patch-adapter-pi--sentinel
                        state on-finish stderr-buf))))
      ;; Pi with `--mode json -p DIRECTIVE' is non-interactive but still
      ;; reads from stdin and blocks waiting for EOF.  CLI invocations
      ;; pick this up via `< /dev/null'; `make-process' leaves stdin as
      ;; an open pipe, so we close it explicitly here to unblock pi.
      (when (process-live-p proc)
        (process-send-eof proc))
      (when (and (integerp timeout) (> timeout 0))
        (run-with-timer
         timeout nil
         (lambda ()
           (when (process-live-p proc)
             (plist-put state :timed-out t)
             (delete-process proc)))))
      proc)))

(satan-patch-adapter-register
 "pi" #'satan-patch-adapter-pi-invoke)

(provide 'satan-patch-adapter-pi)
;;; satan-patch-adapter-pi.el ends here
