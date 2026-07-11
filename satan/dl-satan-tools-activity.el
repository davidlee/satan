;;; dl-satan-tools-activity.el --- activity_read tool handler -*- lexical-binding: t; -*-

;; Read-only window into the user's behaviour state, produced by
;; panopticon (~/dev/panopticon).  Files live under
;; `dl-satan-tools-activity-dir' (default `~/.local/state/behaviour/').
;;
;; Scopes:
;;   - "today"          -> today's aggregate histogram
;;                         (per-app, per-workspace, per-hour seconds)
;;   - "recent_focus"   -> last N focus segments for today, default 20,
;;                         max 200.  Each segment: app_id, workspace,
;;                         start/end timestamps, duration_s.
;;   - "recent_browser" -> last N firefox tab segments for today, same
;;                         shape contract as recent_focus.  Each segment
;;                         is returned verbatim: full url + domain +
;;                         title_start/title_end (panopticon strips only
;;                         query/fragment at capture, never to origin),
;;                         start/end timestamps, duration_s.
;;   - "current"        -> currently-focused window snapshot from sway.
;;                         {app_id, workspace, output, title, pid}.
;;                         NOTE: title is passed through verbatim and
;;                         can be sensitive (browser tab page-title,
;;                         editor file path, etc.) — see SATAN.md open
;;                         thread "current-scope title leak".
;;
;; Risk = `read'; no capability required.  Panopticon is the producer
;; that handles redaction (firefox extension strips queries/fragments
;; and drops incognito); SATAN is a downstream consumer.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools)
(require 'dl-satan-jsonl)

(defcustom dl-satan-tools-activity-dir
  (expand-file-name "~/.local/state/behaviour/")
  "Root directory holding panopticon's behaviour-state output."
  :type 'directory :group 'dl-satan)

(defcustom dl-satan-tools-activity-default-limit 20
  "Default `:limit' for the `recent_focus' scope."
  :type 'integer :group 'dl-satan)

(defconst dl-satan-tools-activity--limit-max 200
  "Hard upper bound on `:limit'; clamped without error.")

(defun dl-satan-tools-activity--today ()
  (format-time-string "%Y-%m-%d"))

(defun dl-satan-tools-activity--read-json (path)
  "Parse JSON at PATH into a plist, or return nil if unreadable/empty."
  (when (and (file-readable-p path)
             (> (file-attribute-size (file-attributes path)) 0))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (json-parse-string (buffer-string)
                         :object-type 'plist
                         :array-type 'list
                         :null-object nil
                         :false-object :false))))

(defun dl-satan-tools-activity--clamp-limit (raw)
  (cond
   ((null raw) dl-satan-tools-activity-default-limit)
   ((< raw 1) 1)
   ((> raw dl-satan-tools-activity--limit-max)
    dl-satan-tools-activity--limit-max)
   (t raw)))

(defun dl-satan-tool/activity-read (args _ctx)
  "Implements activity_read.  ARGS: (:scope today|recent_focus :limit INT?).
Returns (ok PLIST) | (error STRING)."
  (let* ((scope (plist-get args :scope))
         (today (dl-satan-tools-activity--today))
         (root  dl-satan-tools-activity-dir))
    (pcase scope
      ("today"
       (let* ((path (expand-file-name
                     (format "histograms/daily-%s.json" today) root))
              (data (dl-satan-tools-activity--read-json path)))
         (cons 'ok (list :scope "today"
                         :date today
                         :path path
                         :histogram data))))
      ("recent_focus"
       (let* ((limit (dl-satan-tools-activity--clamp-limit
                      (plist-get args :limit)))
              (path (expand-file-name
                     (format "segments/focus-%s.jsonl" today) root))
              (all  (dl-satan-jsonl-read-file path))
              (tail (last all limit)))
         (cons 'ok (list :scope "recent_focus"
                         :date today
                         :limit limit
                         :path path
                         :segments (or tail '())))))
      ("recent_browser"
       (let* ((limit (dl-satan-tools-activity--clamp-limit
                      (plist-get args :limit)))
              (path (expand-file-name
                     (format "segments/browser-%s.jsonl" today) root))
              (all  (dl-satan-jsonl-read-file path))
              (tail (last all limit)))
         (cons 'ok (list :scope "recent_browser"
                         :date today
                         :limit limit
                         :path path
                         :segments (or tail '())))))
      ("current"
       (let* ((path (expand-file-name "current/sway.json" root))
              (data (dl-satan-tools-activity--read-json path)))
         (cons 'ok (list :scope "current"
                         :path path
                         :window data))))
      (_ (cons 'error (format "unknown scope: %s" scope))))))

(dl-satan-tool-register
 (list :name "activity_read"
       :risk 'read
       :args-schema '(scope (:type string :required t
                             :enum ("today" "recent_focus"
                                    "recent_browser" "current"))
                      limit (:type integer :required nil))
       :handler 'dl-satan-tool/activity-read))

(provide 'dl-satan-tools-activity)
;;; dl-satan-tools-activity.el ends here
