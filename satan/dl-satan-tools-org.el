;;; dl-satan-tools-org.el --- org/denote tool handlers for SATAN -*- lexical-binding: t; -*-

;; Each handler receives (ARGS TOOL-CTX) where TOOL-CTX is a plist with
;; :id :mode-name :capabilities :run-dir :hippocampus-dir built by the broker.
;;
;; Returns (ok . RESULT) | (error . MESSAGE).

(require 'cl-lib)
(require 'subr-x)
(require 'dl-notes-paths)
(require 'dl-denote-journal)
(require 'dl-satan-tools)
(require 'dl-satan-block)
(require 'dl-satan-intervention)

(defcustom dl-satan-motd-path
  (expand-file-name "satan/motd.txt" dl-notes-root)
  "Output path for `motd' mode."
  :type 'file :group 'dl-satan)

(defcustom dl-satan-proposals-dir
  (expand-file-name "satan/proposals" dl-notes-root)
  "Directory for staged proposals."
  :type 'directory :group 'dl-satan)

(defconst dl-satan-proposal-intervention-window-minutes 120
  "Default `outcome_window_minutes' for proposal interventions (outcome-semantics §3.3).
Proposals need triage time.")

(defconst dl-satan-proposal-intervention-expected-outcome
  "user accepts or rejects the staged proposal within window"
  "Default `expected_outcome' for proposal interventions (outcome-semantics §3.3).")

(defun dl-satan-tools-org--read-file (path)
  (when (file-readable-p path)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (buffer-string))))

(defun dl-satan-tool/org-read-context (args _ctx)
  "Implements org_read_context.  ARGS: (:scope today|week|inbox)."
  (let ((scope (plist-get args :scope)))
    (pcase scope
      ("today"
       (let* ((file (progn (my/journal--ensure-today)
                           (my/journal--today-file dl-notes-journal-dir "journal")))
              (content (dl-satan-tools-org--read-file file)))
         (cons 'ok (list :content (or content "") :path file))))
      ("week"
       (let* ((file (my/journal--week-file dl-notes-weekly-dir "weekly_journal"))
              (content (dl-satan-tools-org--read-file file)))
         (cons 'ok (list :content (or content "") :path file))))
      ("inbox"
       (let* ((file dl-notes-inbox-file)
              (content (dl-satan-tools-org--read-file file)))
         (cons 'ok (list :content (or content "") :path file))))
      (_ (cons 'error (format "unknown scope: %s" scope))))))

(defun dl-satan-tools-org--target-path (target)
  (pcase target
    ("today" (progn (my/journal--ensure-today)
                    (my/journal--today-file dl-notes-journal-dir "journal")))
    (_ nil)))

(defun dl-satan-tools-org--target-capability (target)
  (pcase target
    ("today" 'write-daily)
    (_ nil)))

(defun dl-satan-tool/org-update-owned-block (args ctx)
  "Implements org_update_owned_block.
ARGS: (:target today :block STR :content STR).
Refused unless TOOL-CTX `:capabilities' includes the target's capability.
Motd is no longer a valid target — motd content is owned by the broker
output handler and written from `satan_final.summary'."
  (let* ((target  (plist-get args :target))
         (block   (plist-get args :block))
         (content (plist-get args :content))
         (path    (dl-satan-tools-org--target-path target))
         (need    (dl-satan-tools-org--target-capability target))
         (caps    (plist-get ctx :capabilities)))
    (cond
     ((null path) (cons 'error (format "unknown target: %s" target)))
     ((not (memq need caps))
      (cons 'error (format "mode lacks capability %s for target %s" need target)))
     ((not (and (stringp block) (stringp content)))
      (cons 'error "block and content must be strings"))
     (t
      (unless (file-directory-p (file-name-directory path))
        (make-directory (file-name-directory path) t))
      (unless (file-exists-p path)
        (let ((coding-system-for-write 'utf-8))
          (with-temp-file path (insert ""))))
      (let ((res (dl-satan-block-replace path block content)))
        (pcase res
          ('ok (cons 'ok (list :path path :status "replaced")))
          ('none-match
           (dl-satan-block-create-at-end path block content)
           (cons 'ok (list :path path :status "created")))
          ('multi-match
           (cons 'error (format "multiple SATAN blocks named %s in %s" block path)))))))))

(defun dl-satan-tools-org--slugify (s)
  (or (dl-satan-memory-canon--slugify s) "untitled"))

(defun dl-satan-tool/proposal-stage (args ctx)
  "Implements proposal_stage.  ARGS: (:title STR :body STR).

On successful write the handler also emits a T7 `intervention.created'
\(kind=proposal, target_surface=path) via `dl-satan-intervention-create'
and surfaces the minted id in the result alongside `:path'."
  (let* ((title (plist-get args :title))
         (body  (plist-get args :body))
         (run-id (plist-get ctx :id))
         (mode-str (plist-get ctx :mode-name)))
    (cond
     ((not (and (stringp title) (stringp body)))
      (cons 'error "title and body must be strings"))
     (t
      (condition-case err
          (progn
            (unless (file-directory-p dl-satan-proposals-dir)
              (make-directory dl-satan-proposals-dir t))
            (let* ((id (format-time-string "%Y%m%dT%H%M%S" nil))
                   (slug (dl-satan-tools-org--slugify title))
                   (filename (format "%s--%s__satan_proposal.org" id slug))
                   (path (expand-file-name filename dl-satan-proposals-dir))
                   (coding-system-for-write 'utf-8))
              (with-temp-file path
                (insert "#+title:      " title "\n")
                (insert "#+date:       " (format-time-string "[%Y-%m-%d %a %H:%M]" nil) "\n")
                (insert "#+filetags:   :satan:proposal:\n")
                (insert "#+identifier: " id "\n\n")
                (insert ":PROPERTIES:\n")
                (insert ":RUN_ID: " (or run-id "") "\n")
                (insert ":MODE: "   (or mode-str "") "\n")
                (insert ":END:\n\n")
                (insert body)
                (unless (string-suffix-p "\n" body) (insert "\n")))
              (let ((iv-id (dl-satan-intervention-create
                            :ctx ctx
                            :kind "proposal"
                            :target-surface path
                            :message title
                            :expected-outcome
                            dl-satan-proposal-intervention-expected-outcome
                            :outcome-window-minutes
                            dl-satan-proposal-intervention-window-minutes
                            :severity "medium")))
                (cons 'ok (list :path path :intervention_id iv-id)))))
        (error (cons 'error (error-message-string err))))))))

;; ---- Registration ----

;; Tool specs carry mechanism only.  Model-facing descriptions live in
;; `~/notes/satan/tools/<name>.md' and are loaded at manifest assembly
;; time.

(dl-satan-tool-register
 (list :name "org_read_context"
       :risk 'read
       :args-schema '(scope (:type string :required t
                             :enum ("today" "week" "inbox")))
       :handler 'dl-satan-tool/org-read-context))

(dl-satan-tool-register
 (list :name "org_update_owned_block"
       :risk 'low
       :args-schema '(target (:type string :required t
                              :enum ("today"))
                      block  (:type string :required t)
                      content (:type string :required t))
       :handler 'dl-satan-tool/org-update-owned-block))

(dl-satan-tool-register
 (list :name "proposal_stage"
       :risk 'low
       :args-schema '(title (:type string :required t)
                      body  (:type string :required t))
       :handler 'dl-satan-tool/proposal-stage))

(provide 'dl-satan-tools-org)
;;; dl-satan-tools-org.el ends here
