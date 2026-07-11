;;; dl-satan-tools-inbox.el --- inbox_append tool -*- lexical-binding: t; -*-

;; SATAN's local inbox — append-only org headlines at
;; `~/notes/satan/inbox.org'.  Auto-applied (SATAN owns the file).  Each
;; entry is a top-level `*' headline tagged `:unread:satan:'.  A waybar /
;; user-side widget can count `:unread:' tags for a badge; the user
;; removes the tag (or archives the headline) to mark read.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-notes-paths)
(require 'dl-satan-tools)
(require 'dl-satan-intervention)

(defcustom dl-satan-inbox-file
  (expand-file-name "satan/inbox.org" dl-notes-root)
  "Path to SATAN's append-only inbox org file."
  :type 'file :group 'dl-satan)

(defconst dl-satan-inbox-intervention-window-minutes 30
  "Default `outcome_window_minutes' for inbox interventions (outcome-semantics §3.3).")

(defconst dl-satan-inbox-intervention-expected-outcome
  "user reads or processes the inbox item within window"
  "Default `expected_outcome' for inbox interventions (outcome-semantics §3.3).")

(defun dl-satan-tools-inbox--ensure-file ()
  "Create `dl-satan-inbox-file' with a header if missing or empty."
  (unless (file-directory-p (file-name-directory dl-satan-inbox-file))
    (make-directory (file-name-directory dl-satan-inbox-file) t))
  (when (or (not (file-exists-p dl-satan-inbox-file))
            (zerop (file-attribute-size
                    (file-attributes dl-satan-inbox-file))))
    (let ((coding-system-for-write 'utf-8))
      (with-temp-file dl-satan-inbox-file
        (insert "#+title:    SATAN inbox\n"
                "#+filetags: :satan:inbox:\n"
                "#+startup:  overview\n"
                "\n")))))

(defun dl-satan-tools-inbox--urgency-tag (urgency)
  (pcase urgency
    ("low"    ":low:")
    ("urgent" ":urgent:")
    (_        nil)))

(cl-defun dl-satan-tools-inbox-write
    (&key title body urgency properties)
  "Append one inbox headline.  Pure mechanism — no capability check.
TITLE and BODY are required strings.  URGENCY may be \"low\", \"normal\",
or \"urgent\".  PROPERTIES is an extra plist of (KEYWORD . STRING-VAL)
merged after the default :RUN_ID/:MODE pair.  Returns (ok :path P) or
\(error MSG)."
  (cond
   ((not (and (stringp title) (stringp body)))
    (cons 'error "title and body must be strings"))
   (t
    (dl-satan-tools-inbox--ensure-file)
    (let* ((ts (format-time-string "[%Y-%m-%d %a %H:%M]" nil))
           (extra (dl-satan-tools-inbox--urgency-tag urgency))
           (tags (if extra (concat ":unread:satan" extra) ":unread:satan:"))
           (coding-system-for-write 'utf-8))
      (with-temp-buffer
        (insert "\n* " ts " " title "  " tags "\n")
        (insert ":PROPERTIES:\n")
        (cl-loop for (k v) on properties by #'cddr
                 when (and k v)
                 do (insert (format ":%s: %s\n"
                                    (upcase (substring (symbol-name k) 1))
                                    v)))
        (insert ":END:\n")
        (insert body)
        (unless (string-suffix-p "\n" body) (insert "\n"))
        (append-to-file (point-min) (point-max) dl-satan-inbox-file))
      (cons 'ok (list :path dl-satan-inbox-file))))))

(defun dl-satan-tool/inbox-append (args ctx)
  "Implements inbox_append.
ARGS: (:title STR :body STR :urgency low|normal|urgent).  The
`inbox-write' capability is enforced by the dispatcher (spec
`:capability'), not here.  Always appends; never
mutates existing headlines.  On success the handler also emits a T7
`intervention.created' (kind=inbox, target_surface=path) via
`dl-satan-intervention-create' and surfaces the minted id on the result.
Returns (ok :path P :intervention_id IV-ID) | (error MSG)."
  (let* ((title   (plist-get args :title))
         (body    (plist-get args :body))
         (urgency (plist-get args :urgency))
         (run-id    (plist-get ctx :id))
         (mode-str  (plist-get ctx :mode-name)))
    (pcase (dl-satan-tools-inbox-write
            :title title
            :body body
            :urgency urgency
            :properties (list :run_id (or run-id "")
                              :mode   (or mode-str "")))
      (`(ok . ,info)
       (condition-case err
           (let ((iv-id (dl-satan-intervention-create
                         :ctx ctx
                         :kind "inbox"
                         :target-surface (plist-get info :path)
                         :message (format "%s — %s" title body)
                         :expected-outcome
                         dl-satan-inbox-intervention-expected-outcome
                         :outcome-window-minutes
                         dl-satan-inbox-intervention-window-minutes
                         :severity "medium")))
             (cons 'ok (append info (list :intervention_id iv-id))))
         (error (cons 'error (error-message-string err)))))
      (err err))))

(dl-satan-tool-register
 (list :name "inbox_append"
       :risk 'low
       :capability 'inbox-write
       :args-schema '(title   (:type string :required t)
                      body    (:type string :required t)
                      urgency (:type string :required nil
                               :enum ("low" "normal" "urgent")))
       :handler 'dl-satan-tool/inbox-append))

(defun my/satan-inbox ()
  "Open the SATAN inbox file."
  (interactive)
  (dl-satan-tools-inbox--ensure-file)
  (find-file dl-satan-inbox-file))

(defun my/satan-inbox-unread-count ()
  "Count `:unread:' headlines in the SATAN inbox.
Cheap; suitable for a status-bar widget called frequently."
  (if (file-readable-p dl-satan-inbox-file)
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents dl-satan-inbox-file))
        (goto-char (point-min))
        (let ((count 0))
          (while (re-search-forward "^\\* .*:unread:" nil t) (cl-incf count))
          count))
    0))

(provide 'dl-satan-tools-inbox)
;;; dl-satan-tools-inbox.el ends here
