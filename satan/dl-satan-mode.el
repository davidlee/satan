;;; dl-satan-mode.el --- SATAN mode registry -*- lexical-binding: t; -*-

;; A mode-spec is a plist (see SATAN.local.md §"Mode Contract").  Built-in
;; modes register themselves at load time.

(require 'cl-lib)
(require 'dl-notes-paths)

(defvar dl-satan-modes nil
  "Alist of (NAME . SPEC) mode registrations.")

(defcustom dl-satan-profiles
  '((claude-haiku . (:provider openrouter
                     :model "anthropic/claude-haiku-4.5"))
    (deepseek-pro . (:provider deepseek
                     :model "deepseek-v4-pro")))
  "Alist of (NAME . PLIST) provider/model profiles.
A mode-spec referring to a profile via `:profile NAME' inherits each
PLIST key that the mode-spec does not set itself.  Mode-level keys
always win, so a mode may pin `:model' while taking `:provider' from
the profile.  Currently used for `:provider' and `:model'."
  :type '(alist :key-type symbol :value-type plist)
  :group 'dl-satan)

(defun dl-satan-profile-resolve (name)
  "Return the profile plist named NAME, or signal if unknown."
  (or (cdr (assq name dl-satan-profiles))
      (error "Unknown SATAN profile: %s" name)))

(defun dl-satan-mode--apply-profile (spec)
  "If SPEC has `:profile', merge that profile's plist in, mode wins."
  (let ((profile-name (plist-get spec :profile)))
    (if (not profile-name)
        spec
      (let ((profile (dl-satan-profile-resolve profile-name))
            (merged (copy-sequence spec)))
        (cl-loop for (k v) on profile by #'cddr
                 unless (plist-member merged k)
                 do (setq merged (plist-put merged k v)))
        merged))))

(defun dl-satan-mode-register (spec)
  "Register or replace mode SPEC keyed by `:name'.
If SPEC has a `:profile' key, profile defaults are merged in at
registration time (mode-level keys win)."
  (let* ((expanded (dl-satan-mode--apply-profile spec))
         (name (plist-get expanded :name)))
    (setq dl-satan-modes
          (cons (cons name expanded)
                (cl-remove name dl-satan-modes :key #'car :test #'equal)))))

(defun dl-satan-mode-resolve (name)
  "Return the mode-spec named NAME, or signal if unknown."
  (or (cdr (assoc name dl-satan-modes))
      (error "Unknown SATAN mode: %s" name)))

(defun dl-satan-mode-names ()
  (mapcar #'car dl-satan-modes))

(defun dl-satan-mode-check-tool-references ()
  "Signal when any mode-spec's `:tools' names an unregistered tool.
The mode-spec `:tools' list is the authoritative mode→tools
allowlist; T4 removed the documentary `:modes' field from tool
specs.  This load-time guard turns the missing convention into a
hard error so typos surface at startup rather than at dispatch."
  (let ((registered (mapcar #'car dl-satan-tools))
        (errors nil))
    (dolist (entry dl-satan-modes)
      (let* ((mode-name (car entry))
             (spec (cdr entry)))
        (dolist (tool-name (plist-get spec :tools))
          (unless (member tool-name registered)
            (push (format "mode %S references unregistered tool %S"
                          mode-name tool-name)
                  errors)))))
    (when errors
      (error "SATAN mode/tool consistency check failed: %s"
             (mapconcat #'identity (nreverse errors) "; ")))))

(defvar dl-satan-prompts-dir
  (expand-file-name "satan/prompts/" dl-notes-root)
  "Directory holding mode prompt files.
Canonical model-facing text lives under `~/notes/satan/prompts/'.
Dotfiles must not be the source of truth for prompt content.")

(dl-satan-mode-register
 (list :name "morning"
       :prompt-file (expand-file-name "morning.txt" dl-satan-prompts-dir)
       :context-fn 'dl-satan-context-morning
       :tools '("org_read_context" "org_update_owned_block"
                "proposal_stage" "notify_send"
                "hippocampus_list" "hippocampus_read" "hippocampus_write"
                "hippocampus_overwrite" "hippocampus_delete"
                "hippocampus_grep" "hippocampus_rename"
                "inbox_append" "agenda_read" "activity_read"
                "notes_recent" "notes_at_satan_scan"
                "sway_border_set" "sway_border_reset"
                "bough_read" "memory_mark" "memory_resonate"
                "memory_show_trace"
                "motive_read" "motive_replace"
                "vcs_log"
                "docs_list" "docs_search" "docs_read")
       :capabilities '(write-daily stage-proposal notify hippocampus-write
                       inbox-write memory-write motive-write)
       :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
       :jail-profile 'specDev
       :profile 'claude-haiku
       :budget-tokens 300000
       :output-handler 'dl-satan-output/morning
       :auto-apply 'owned
       :timeout-seconds 1800
       :budget-tool-calls 100))

(dl-satan-mode-register
 (list :name "motd"
       :prompt-file (expand-file-name "motd.txt" dl-satan-prompts-dir)
       :context-fn 'dl-satan-context-motd
       :tools '("org_read_context" "notify_send" "inbox_append"
                "hippocampus_list" "hippocampus_read" "hippocampus_write"
                "hippocampus_overwrite" "hippocampus_delete"
                "hippocampus_grep" "hippocampus_rename"
                "agenda_read" "activity_read" "notes_recent"
                "sway_border_set" "sway_border_reset"
                "bough_read" "memory_mark" "memory_resonate"
                "memory_show_trace"
                "motive_read" "motive_replace"
                "vcs_log")
       :capabilities '(notify inbox-write memory-write motive-write
                       hippocampus-write)
       :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
       :jail-profile 'specDev
       :profile 'claude-haiku
       :budget-tokens 100000
       :output-handler 'dl-satan-output/motd
       :auto-apply 'owned
       :timeout-seconds 1800
       :budget-tool-calls 100))

(dl-satan-mode-register
 (list :name "self-edit-mech"
       :prompt-file (expand-file-name "self-edit-mech.txt" dl-satan-prompts-dir)
       :context-fn 'dl-satan-context-self-edit
       :source-roots-var 'dl-satan-self-edit-mech-roots
       :tools '("proposal_stage" "sway_border_set" "sway_border_reset"
                "hippocampus_list" "hippocampus_read" "hippocampus_write"
                "hippocampus_overwrite" "hippocampus_delete"
                "hippocampus_grep" "hippocampus_rename"
                "bough_read" "memory_resonate" "memory_show_trace"
                "patch_job_create" "patch_job_status"
                "vcs_log"
                "docs_list" "docs_search" "docs_read")
       :capabilities '(stage-proposal hippocampus-write)
       :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
       :jail-profile 'specDev
       :profile 'claude-haiku
       :budget-tokens 300000
       :output-handler 'dl-satan-output/self-edit
       :auto-apply 'none
       :timeout-seconds 1800
       :budget-tool-calls 100))

(dl-satan-mode-register
 (list :name "self-edit-mind"
       :prompt-file (expand-file-name "self-edit-mind.txt" dl-satan-prompts-dir)
       :context-fn 'dl-satan-context-self-edit
       :source-roots-var 'dl-satan-self-edit-mind-roots
       :tools '("proposal_stage" "sway_border_set" "sway_border_reset"
                "hippocampus_list" "hippocampus_read" "hippocampus_write"
                "hippocampus_overwrite" "hippocampus_delete"
                "hippocampus_grep" "hippocampus_rename"
                "bough_read" "memory_resonate" "memory_show_trace"
                "patch_job_create" "patch_job_status"
                "vcs_log"
                "docs_list" "docs_search" "docs_read")
       :capabilities '(stage-proposal hippocampus-write)
       :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
       :jail-profile 'specDev
       :profile 'claude-haiku
       :budget-tokens 300000
       :output-handler 'dl-satan-output/self-edit
       :auto-apply 'none
       :timeout-seconds 1800
       :budget-tool-calls 100))

(dl-satan-mode-register
 (list :name "ruminate"
       :prompt-file (expand-file-name "ruminate.txt" dl-satan-prompts-dir)
       :context-fn 'dl-satan-context-motd
       :tools '("hippocampus_list" "hippocampus_read" "hippocampus_write"
                "hippocampus_overwrite" "hippocampus_delete"
                "hippocampus_grep" "hippocampus_rename"
                "memory_mark" "memory_resonate" "memory_show_trace"
                "motive_read" "bough_read"
                "notes_recent"
                "vcs_log"
                "docs_list" "docs_search" "docs_read")
       :capabilities '(hippocampus-write memory-write)
       :harness '(:cmd "jailed-satan-gptel-harness" :args () :env nil)
       :jail-profile 'specDev
       :profile 'claude-haiku
       :budget-tokens 400000
       :output-handler 'dl-satan-output/ruminate
       :auto-apply 'none
       :timeout-seconds 1800
       :budget-tool-calls 100))

(provide 'dl-satan-mode)
;;; dl-satan-mode.el ends here
