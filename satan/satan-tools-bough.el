;;; satan-tools-bough.el --- bough_read tool -*- lexical-binding: t; -*-

;; Read-only tool: SATAN's *only* path into the bough task tree.  No
;; direct PG access against the bough_* databases anywhere in satan
;; code — grep-lint will fail the build if it appears.  See
;; `memory.design.md' §5.4 (tool surface) and §10.2 (CLI scope mapping).
;;
;; Six scopes:
;;   node              by nanoid; full node + annotations + parent chain
;;   recent_changes    status transitions + newly-created nodes since
;;                     a window start (DR-116; closes bough gap B1)
;;   active            current active tasks
;;   day               today's day_entry + linked items
;;   week              current week (Mon..Sun day list + entries)
;;   project_subtree   by project nanoid, elisp-pruned to max_depth  (B2)
;;
;; Implementation: shell-out to `bough --json'.  JSON is parsed into
;; plists with list-typed arrays so downstream code never deals with
;; JSON-as-string.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-tools)
(require 'satan-trace)

(defcustom satan-bough-timeout-seconds 5
  "Per-call wall-clock deadline (seconds) for the `bough' subprocess.
Applied via `satan-trace-call' in `satan-bough--invoke' so a
hung bough binary cannot stall evidence assembly.  A breach maps to
\(error . \"bough timed out …\") — degrading bough_status like any
other error."
  :type 'integer :group 'satan)

(defcustom satan-bough-program
  (or (executable-find "bough")
      (expand-file-name "~/.cargo/bin/bough"))
  "Path to the `bough' CLI binary.  Pinned for stability (R2)."
  :type 'string :group 'satan)

(defcustom satan-bough-default-workspace nil
  "Default workspace slug, or nil for whatever `bough' defaults to."
  :type '(choice (const :tag "bough default" nil) string)
  :group 'satan)

(defcustom satan-bough-project-subtree-default-max-depth 3
  "Default maximum depth for `project_subtree' (B2 — elisp prune)."
  :type 'integer :group 'satan)

(defconst satan-bough--nanoid-pattern
  "\\`[A-Za-z0-9_-]+\\'"
  "Permissive nanoid matcher.  Bough nanoids are 7 chars but the substrate
does not need to encode that.")

(defconst satan-bough--workspace-pattern
  "\\`[a-z0-9][a-z0-9_-]*\\'"
  "Workspace slug matcher.")

(defconst satan-bough--date-pattern
  "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
  "ISO calendar date matcher (YYYY-MM-DD).")

(defconst satan-bough--iso8601-pattern
  "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}T[0-9]\\{2\\}:[0-9]\\{2\\}:[0-9]\\{2\\}\\(Z\\|[+-][0-9]\\{2\\}:[0-9]\\{2\\}\\)?\\'"
  "Lenient ISO8601 timestamp matcher (UTC or offset; no fractional seconds).")

(defconst satan-bough--scopes
  '("node" "recent_changes" "active" "day" "week" "project_subtree"))

;; ---------- shell out + JSON parse ----------

(defun satan-bough--parse-one (str)
  "Parse one JSON document from STR.  Return parsed value or signal."
  (json-parse-string str
                     :object-type 'plist
                     :array-type 'list
                     :null-object nil
                     :false-object :json-false))

(defun satan-bough--parse-json-output (stdout)
  "Parse bough STDOUT as either a single JSON document or NDJSON.
`bough --json day list' returns one JSON object per line; other
commands return a single document (object or array).  Return
(ok . PARSED) or (error . MSG)."
  (condition-case _
      (cons 'ok (satan-bough--parse-one stdout))
    (error
     (condition-case err
         (let ((rows
                (cl-loop for line in (split-string stdout "\n" t "[ \t\r]+")
                         collect (satan-bough--parse-one line))))
           (cons 'ok rows))
       (error (cons 'error (format "bough JSON parse: %S" err)))))))

(defun satan-bough--invoke (workspace &rest args)
  "Run `bough --json [--workspace WS] ARGS...'.
Return (ok . PARSED) or (error . MSG).  PARSED is the JSON output
decoded with plist objects and list arrays.

Routed through `satan-trace-call' so the call is ledgered and
bounded by `satan-bough-timeout-seconds'.  `trace-call' returns
only `:stdout', so stdout+stderr are captured COMBINED there; the
error message and JSON parse both read that combined output.  A
deadline breach maps to (error . \"bough timed out …\")."
  (let* ((full (append (list "--json")
                       (when workspace (list "--workspace" workspace))
                       args))
         (result (satan-trace-call
                  satan-bough-program full
                  :timeout-secs satan-bough-timeout-seconds
                  :label "evidence.bough"))
         (exit (plist-get result :exit))
         (output (plist-get result :stdout)))
    (cond
     ((plist-get result :timed-out)
      (cons 'error (format "bough timed out after %ss"
                           satan-bough-timeout-seconds)))
     ((not (and (integerp exit) (zerop exit)))
      (cons 'error (format "bough exit %s: %s" exit (string-trim output))))
     ((string-empty-p (string-trim output))
      (cons 'ok nil))
     (t
      (satan-bough--parse-json-output output)))))

(defun satan-bough--day-not-found-p (msg)
  "Detect the literal `day not found' bough error."
  (and (stringp msg) (string-match-p "day not found" msg)))

;; ---------- pure helpers ----------

(defun satan-bough--monday-of (date-str)
  "Return YYYY-MM-DD of the Monday in the ISO week containing DATE-STR."
  (let* ((time (date-to-time (concat date-str "T00:00:00")))
         (dow  (string-to-number (format-time-string "%u" time))) ; 1=Mon..7=Sun
         (delta (- 1 dow))
         (monday-time (time-add time (days-to-time delta))))
    (format-time-string "%Y-%m-%d" monday-time)))

(defun satan-bough--week-bounds (date-str)
  "Return (MON-STR . SUN-STR) for the ISO week containing DATE-STR."
  (let* ((mon (satan-bough--monday-of date-str))
         (mon-time (date-to-time (concat mon "T00:00:00")))
         (sun-time (time-add mon-time (days-to-time 6))))
    (cons mon (format-time-string "%Y-%m-%d" sun-time))))

(defun satan-bough--today ()
  (format-time-string "%Y-%m-%d"))

(defun satan-bough--prune-depth (node depth max-depth)
  "Return NODE with descendants beyond MAX-DEPTH replaced by a marker.
Root node is depth 0."
  (if (not (and (listp node) (plistp node)))
      node
    (let ((children (plist-get node :children))
          (out (copy-sequence node)))
      (cond
       ((null children) out)
       ((>= depth max-depth)
        (setq out (plist-put out :children nil))
        (plist-put out :children_truncated_count (length children)))
       (t
        (plist-put out :children
                   (mapcar (lambda (c)
                             (satan-bough--prune-depth c (1+ depth) max-depth))
                           children)))))))

;; ---------- scope implementations ----------

(defun satan-bough--scope-node (args)
  "node scope: get + annotations + parent chain (root→leaf)."
  (let* ((nanoid (plist-get args :nanoid))
         (ws     (or (plist-get args :workspace)
                     satan-bough-default-workspace))
         (node-r (satan-bough--invoke ws "node" "get" nanoid)))
    (pcase node-r
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,node)
       (let ((ann-r (satan-bough--invoke ws "node" "annotations" nanoid)))
         (pcase ann-r
           (`(error . ,msg) (cons 'error msg))
           (`(ok . ,anns)
            (let ((chain nil)
                  (cursor (plist-get node :parent_nanoid))
                  (depth 0))
              (while (and cursor (< depth 16))
                (let ((p (satan-bough--invoke ws "node" "get" cursor)))
                  (pcase p
                    (`(ok . ,pn)
                     (push pn chain)
                     (setq cursor (plist-get pn :parent_nanoid)
                           depth (1+ depth)))
                    (_ (setq cursor nil)))))
              (cons 'ok (list :scope "node"
                              :node node
                              :annotations anns
                              :parent_chain chain))))))))))

(defun satan-bough--scope-recent-changes (args)
  "recent_changes scope: peer feeds of status transitions and newly-created
nodes since SINCE.  Composes `bough --json node status-transitions
--since SINCE' with `bough --json node created --since SINCE'
(DR-116 §D18).  Both feeds DESC by `(at, seq)' / `at'."
  (let* ((since (plist-get args :since))
         (ws    (or (plist-get args :workspace)
                    satan-bough-default-workspace))
         (limit (plist-get args :limit))
         (extra (when limit (list "--limit" (number-to-string limit))))
         (trans-r (apply #'satan-bough--invoke
                         ws "node" "status-transitions" "--since" since
                         extra)))
    (pcase trans-r
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,trans)
       (let ((created-r (apply #'satan-bough--invoke
                               ws "node" "created" "--since" since
                               extra)))
         (pcase created-r
           (`(error . ,msg) (cons 'error msg))
           (`(ok . ,created)
            (cons 'ok (list :scope "recent_changes"
                            :since since
                            :semantics
                            "status transitions and newly-created nodes since"
                            :transitions (or trans '())
                            :created (or created '()))))))))))

(defun satan-bough--scope-active (args)
  "active scope: current active tasks (status in todo/doing/blocked)."
  (let* ((ws (or (plist-get args :workspace)
                 satan-bough-default-workspace))
         (r (satan-bough--invoke
             ws "node" "tree"
             "--kind" "task"
             "--status" "doing,todo,blocked")))
    (pcase r
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,tree)
       (cons 'ok (list :scope "active"
                       :nodes tree))))))

(defun satan-bough--scope-day (args)
  "day scope: bough day show -d DATE.  Translates `day not found' to ok+nil."
  (let* ((date (or (plist-get args :date) (satan-bough--today)))
         (ws   (or (plist-get args :workspace)
                   satan-bough-default-workspace))
         (r (satan-bough--invoke ws "day" "show" "-d" date)))
    (pcase r
      (`(error . ,msg)
       (if (satan-bough--day-not-found-p msg)
           (cons 'ok (list :scope "day"
                           :date date
                           :day nil
                           :note "no day entry exists for this date"))
         (cons 'error msg)))
      (`(ok . ,day)
       (cons 'ok (list :scope "day"
                       :date date
                       :day day))))))

(defun satan-bough--scope-week (args)
  "week scope: day list MONDAY SUNDAY + per-day day show for non-empty days."
  (let* ((date (or (plist-get args :date) (satan-bough--today)))
         (ws   (or (plist-get args :workspace)
                   satan-bough-default-workspace))
         (bounds (satan-bough--week-bounds date))
         (mon (car bounds))
         (sun (cdr bounds))
         (list-r (satan-bough--invoke ws "day" "list" mon sun)))
    (pcase list-r
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,days)
       (let ((entries
              (mapcar
               (lambda (d)
                 (let* ((dstr (or (plist-get d :date) (plist-get d :day))))
                   (if (not dstr)
                       (list :date nil :raw d)
                     (let ((day-r (satan-bough--invoke ws "day" "show" "-d" dstr)))
                       (pcase day-r
                         (`(ok . ,payload) (list :date dstr :day payload))
                         (`(error . ,m)
                          (if (satan-bough--day-not-found-p m)
                              (list :date dstr :day nil)
                            (list :date dstr :error m))))))))
               (or days nil))))
         (cons 'ok (list :scope "week"
                         :start_date mon
                         :end_date sun
                         :days entries)))))))

(defun satan-bough--scope-project-subtree (args)
  "project_subtree scope: full subtree, elisp-pruned to max_depth (B2)."
  (let* ((nanoid (plist-get args :nanoid))
         (ws     (or (plist-get args :workspace)
                     satan-bough-default-workspace))
         (max-depth (or (plist-get args :max_depth)
                        satan-bough-project-subtree-default-max-depth))
         (r (satan-bough--invoke ws "node" "subtree" nanoid)))
    (pcase r
      (`(error . ,msg) (cons 'error msg))
      (`(ok . ,tree)
       (let ((pruned (satan-bough--prune-depth tree 0 max-depth)))
         (cons 'ok (list :scope "project_subtree"
                         :root pruned
                         :max_depth max-depth)))))))

;; ---------- per-scope arg validation + dispatch ----------

(defun satan-bough--require (args key label)
  "Return error string if ARGS lack KEY (e.g. :nanoid), else nil."
  (unless (plist-get args key)
    (format "scope requires arg `%s'" label)))

(defun satan-bough--validate-scope-args (scope args)
  "Return nil if ARGS satisfy SCOPE's positional requirements, else error string."
  (pcase scope
    ("node"            (satan-bough--require args :nanoid "nanoid"))
    ("project_subtree" (satan-bough--require args :nanoid "nanoid"))
    ("recent_changes"  (satan-bough--require args :since  "since"))
    (_ nil)))

(defun satan-tool/bough-read (args _ctx)
  "Handler for `bough_read'.  Dispatches by `:scope'."
  (let* ((scope (plist-get args :scope))
         (err (satan-bough--validate-scope-args scope args)))
    (cond
     (err (cons 'error err))
     ((not (file-executable-p satan-bough-program))
      (cons 'error (format "bough binary not executable: %s"
                           satan-bough-program)))
     (t
      (pcase scope
        ("node"            (satan-bough--scope-node args))
        ("recent_changes"  (satan-bough--scope-recent-changes args))
        ("active"          (satan-bough--scope-active args))
        ("day"             (satan-bough--scope-day args))
        ("week"            (satan-bough--scope-week args))
        ("project_subtree" (satan-bough--scope-project-subtree args))
        (_ (cons 'error (format "unknown scope: %s" scope))))))))

;; ---------- registration ----------

(satan-tool-register
 (list :name "bough_read"
       :risk 'read
       :args-schema
       (list 'scope     (list :type 'string :required t :enum satan-bough--scopes)
             'nanoid    (list :type 'string :required nil
                              :pattern satan-bough--nanoid-pattern)
             'since     (list :type 'string :required nil
                              :pattern satan-bough--iso8601-pattern)
             'workspace (list :type 'string :required nil
                              :pattern satan-bough--workspace-pattern)
             'date      (list :type 'string :required nil
                              :pattern satan-bough--date-pattern)
             'max_depth (list :type 'integer :required nil)
             'limit     (list :type 'integer :required nil))
       :handler 'satan-tool/bough-read))

(provide 'satan-tools-bough)
;;; satan-tools-bough.el ends here
