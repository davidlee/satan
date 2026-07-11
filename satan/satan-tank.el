;;; satan-tank.el --- SATAN observation tank -*- lexical-binding: t; -*-

;; Composite read-only buffer that mirrors what SATAN sees right now.
;; Five sections refresh on a timer (`g' for manual refresh, `q' to
;; quit):
;;
;;   1. EVIDENCE WINDOW   `satan-memory-evidence-assemble' output
;;                        (current panopticon window, focus / browser
;;                        segment counts, active bough nodes, git + cwd)
;;   2. ATTRIBUTES        live attribute bars from `satan_attributes'
;;   3. RECENT TRACES     `satan-memory-store-recent' last N rows
;;   4. LAST RUN          summary of the newest run under
;;                        `satan-runs-dir': mode, status, duration,
;;                        token spend, ordered tool calls, final text
;;   5. RECENT EVENTS     tail of run transcripts under `satan-runs-dir'
;;
;; Section renderers are pure (state plist in, string out) so they are
;; tested without DB / panopticon / bough access.  Gatherers wrap the
;; impure reads and swallow errors so a degraded section never breaks
;; the buffer.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-broker)
(require 'satan-memory-evidence)
(require 'satan-memory-store)
(require 'satan-memory-grammar)
(require 'satan-attribute-render)

;; ---------------------------------------------------------------------
;; Customisation
;; ---------------------------------------------------------------------

(defgroup satan-tank nil
  "Composite observation surface for the SATAN broker."
  :group 'satan :prefix "satan-tank-")

(defcustom satan-tank-refresh-interval 5
  "Seconds between automatic refreshes; nil disables the timer."
  :type '(choice (number :tag "Seconds") (const :tag "Disabled" nil))
  :group 'satan-tank)

(defcustom satan-tank-trace-limit 10
  "Recent-traces section displays at most this many rows."
  :type 'integer :group 'satan-tank)

(defcustom satan-tank-event-limit 20
  "Recent-events section displays at most this many events."
  :type 'integer :group 'satan-tank)

(defcustom satan-tank-event-window-runs 8
  "Number of most recent runs scanned for events."
  :type 'integer :group 'satan-tank)

(defcustom satan-tank-evidence-history-seconds 1800
  "How far back to anchor the evidence window when the tank is opened
outside an active SATAN run.  Default is 30 minutes."
  :type 'integer :group 'satan-tank)

(defcustom satan-tank-last-run-summary-width 78
  "Soft wrap width for the LAST RUN final-summary block."
  :type 'integer :group 'satan-tank)

(defconst satan-tank--buffer-name "*satan-tank*")

(defvar satan-tank--timer nil
  "Singleton refresh timer for the tank buffer.")

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(defun satan-tank--truncate (s n)
  "Truncate S to N chars, suffixing `…' when shortened."
  (if (<= (length s) n) s
    (concat (substring s 0 (max 0 (1- n))) "…")))

(defun satan-tank--short-ts (ts)
  "Return the HH:MM:SS portion of an ISO8601 TS, or TS unchanged."
  (cond
   ((and (stringp ts) (string-match "T\\([0-9:]+\\)" ts))
    (match-string 1 ts))
   (t (or ts ""))))

(defun satan-tank--short-run (run-id)
  "Pull the mode slug from a RUN-ID like `20260520T082808-tick-pulse-e44377'."
  (cond
   ((and (stringp run-id)
         (string-match "T[0-9]+-\\(.+\\)-[a-z0-9]+\\'" run-id))
    (match-string 1 run-id))
   (t (or run-id ""))))

(defun satan-tank--summarize-args (args)
  "Compact one-line summary of a tool-call ARGS plist."
  (cond
   ((null args) "")
   ((stringp args) (satan-tank--truncate args 40))
   ((listp args)
    (mapconcat
     (lambda (cell)
       (format "%s=%s" (substring (symbol-name (car cell)) 1)
               (satan-tank--truncate (format "%s" (cadr cell)) 20)))
     (cl-loop for (k v) on args by #'cddr
              when (keywordp k) collect (list k v))
     " "))
   (t (format "%s" args))))

(defun satan-tank--event-summary (rec)
  "Build a one-line summary for a transcript JSONL record REC."
  (let* ((event (plist-get rec :event))
         (payload (plist-get rec :payload)))
    (pcase event
      ("tool-call"
       (let ((name (and (listp payload) (plist-get payload :name)))
             (args (and (listp payload) (plist-get payload :arguments))))
         (format "%s(%s)" (or name "?")
                 (satan-tank--summarize-args args))))
      ("tool-result"
       (let ((name (and (listp payload) (plist-get payload :name)))
             (ok (and (listp payload) (plist-get payload :ok))))
         (format "%s → %s" (or name "?")
                 (if (eq ok :false) "error" "ok"))))
      ("log"
       (let ((kind (and (listp payload) (plist-get payload :kind))))
         (pcase kind
           ("tier_changed"
            (format "tier %s→%s (%s)"
                    (plist-get payload :from_tier)
                    (plist-get payload :to_tier)
                    (or (plist-get payload :trigger) "?")))
           (_ (or kind "log")))))
      ("crash-context"
       (let ((status (and (listp payload) (plist-get payload :status))))
         (format "crash: %s" (or status "?"))))
      ("timeout"
       (format "after %ss" (and (listp payload)
                                (plist-get payload :after-seconds))))
      (_ (or event "")))))

;; ---------------------------------------------------------------------
;; Pure renderers
;; ---------------------------------------------------------------------

(defun satan-tank--section (title)
  ;; #x2500 = BOX DRAWINGS LIGHT HORIZONTAL ('─').  Emacs-overlay's elisp
  ;; parser does not accept multi-byte `?<char>' literals, so the
  ;; integer form is used here to keep `home-manager switch' working.
  (format "%s\n%s\n" title (make-string (length title) #x2500)))

(defun satan-tank--header (now-iso)
  (format "═══ SATAN OBSERVATION TANK · %s ═══\n\n" now-iso))

(defun satan-tank--render-bough-active (nodes max)
  (cond
   ((null nodes) "")
   (t
    (let* ((shown (cl-subseq nodes 0 (min max (length nodes))))
           (rest (max 0 (- (length nodes) max))))
      (concat
       (mapconcat
        (lambda (n)
          (format "  · %-6s %s  (%s)\n"
                  (or (plist-get n :status) "?")
                  (satan-tank--truncate (or (plist-get n :title) "") 60)
                  (or (plist-get n :nanoid) "?")))
        shown "")
       (if (> rest 0) (format "  · …%d more\n" rest) ""))))))

(defun satan-tank--render-evidence (state)
  "Render the EVIDENCE WINDOW section for STATE plist."
  (concat
   (satan-tank--section "EVIDENCE WINDOW")
   (cond
    ((null state) "(unavailable)\n")
    (t
     (let* ((start (plist-get state :window_start_at))
            (end (plist-get state :window_end_at))
            (cw (plist-get state :current_window))
            (focus (plist-get state :focus_segments))
            (browser (plist-get state :browser_segments))
            (active (plist-get state :bough_active))
            (gc (plist-get state :git_commits))
            (fs (plist-get state :fs_state))
            (truncated (plist-get state :truncated_at))
            (app (and cw (or (plist-get cw :app_id) (plist-get cw :app))))
            (title (and cw (plist-get cw :title)))
            (workspace (and cw (plist-get cw :workspace))))
       (concat
        (format "window:        %s → %s\n" (or start "-") (or end "-"))
        (if cw
            (format "current:       %s · ws=%s · %s\n"
                    (or app "?") (or workspace "?")
                    (satan-tank--truncate (or title "") 60))
          "current:       (no panopticon)\n")
        (format "focus:         %d segments\n" (length focus))
        (format "browser:       %d segments\n" (length browser))
        (format "bough_active:  %d nodes\n" (length active))
        (satan-tank--render-bough-active active 4)
        (format "git:           %d commit(s) since %s%s\n"
                (length gc)
                (or (plist-get state :git_window_start_at) "?")
                (if gc (format " · newest %s" (plist-get (car (last gc)) :sha)) ""))
        (format "cwd:           %s\n" (or (and fs (plist-get fs :cwd)) "?"))
        (if truncated
            (format "truncated_at:  %s\n"
                    (mapconcat (lambda (s) (format "%s" s)) truncated " "))
          "")))))
   "\n"))

(defun satan-tank--render-attributes (snapshot)
  "Render the ATTRIBUTES section.
SNAPSHOT is the result of `satan-attribute-snapshot' (alist), or
the symbol `disabled' when the switch is off, or nil on query failure."
  (concat
   (satan-tank--section "ATTRIBUTES")
   (cond
    ((eq snapshot 'disabled) "(disabled)\n")
    ((null snapshot) "(unavailable)\n")
    (t (mapconcat (lambda (line) (concat line "\n"))
                  (satan-attribute-render--rows snapshot) "")))
   "\n"))

(defun satan-tank--render-traces (rows)
  "Render the RECENT TRACES section for ROWS (list of store-recent plists)."
  (concat
   (satan-tank--section
    (format "RECENT TRACES (last %d)" (length rows)))
   (cond
    ((null rows) "(no traces)\n")
    (t
     (mapconcat
      (lambda (r)
        (let* ((kind (plist-get r :kind))
               (val (plist-get r :valence))
               (end (plist-get r :observed_end_at))
               (payload (plist-get r :payload))
               (handles (plist-get r :handles)))
          (format "%s  %-12s %s\n  [%s]\n%s\n"
                  (or end "-") (or kind "?") (or val "·")
                  (mapconcat #'identity (or handles '()) " ")
                  (satan-tank--wrap-paragraph
                   (concat "  " (or payload ""))
                   satan-tank-last-run-summary-width))))
      rows "\n")))
   "\n"))

(defun satan-tank--wrap-paragraph (text width)
  "Soft-wrap TEXT at WIDTH, returning the wrapped string with `\\n's."
  (cond
   ((or (null text) (string-empty-p text)) "")
   (t
    (with-temp-buffer
      (insert text)
      (let ((fill-column width)
            (fill-prefix "  "))
        (fill-region (point-min) (point-max)))
      (buffer-string)))))

(defun satan-tank--render-last-run (state)
  "Render the LAST RUN section for STATE plist.
STATE is the gatherer plist (see `satan-tank--gather-last-run');
nil means no completed runs are available yet."
  (concat
   (satan-tank--section "LAST RUN")
   (cond
    ((null state) "(no runs yet)\n")
    (t
     (let* ((run-id (plist-get state :run_id))
            (mode (plist-get state :mode))
            (status (plist-get state :status))
            (dur (plist-get state :duration_s))
            (ttot (plist-get state :tokens_total))
            (tcalls (plist-get state :tool_calls))
            (summary (plist-get state :final_summary))
            (actions (plist-get state :final_actions))
            (err (plist-get state :error_msg))
            (max-tier (plist-get state :max_tier))
            (tiers (plist-get state :tier_transitions))
            (crash (plist-get state :crash_context)))
       (concat
        (format "%s\n" (or run-id "-"))
        (format "mode: %s  ·  status: %s  ·  dur: %s\n"
                (or mode "?")
                (or status "?")
                (if (numberp dur) (format "%.1fs" dur) "?"))
        (format "tokens: %s cumulative  ·  tcalls: %d\n"
                (or ttot "?") (length tcalls))
        (if (and (integerp max-tier) (> max-tier 0))
            (format "tier: %d  ·  transitions: %s\n"
                    max-tier
                    (mapconcat
                     (lambda (tr) (format "%s→%s(%s)"
                                          (plist-get tr :from)
                                          (plist-get tr :to)
                                          (or (plist-get tr :trigger) "?")))
                     tiers " "))
          "")
        (cond
         ((null tcalls) "")
         (t
          (concat
           "\ntools:\n"
           (mapconcat
            (lambda (tc)
              (let ((args-str (satan-tank--summarize-args
                               (plist-get tc :args))))
                (format "  · %-26s %-5s %s"
                        (satan-tank--truncate
                         (or (plist-get tc :name) "?") 26)
                        (if (plist-get tc :ok) "ok" "error")
                        args-str)))
            tcalls "\n")
           "\n")))
        (if crash
            (let ((cs (plist-get crash :status))
                  (tc-done (plist-get crash :tool_calls_done))
                  (tc-budget (plist-get crash :tool_calls_budget))
                  (budget (plist-get crash :budget_tokens))
                  (elapsed (plist-get crash :elapsed_seconds))
                  (timeout (plist-get crash :timeout_seconds)))
              (format "\ncrash context:\n  status: %s  ·  tcalls: %s/%s\n  budget: %s tokens  ·  elapsed: %ss/%ss\n"
                      (or cs "?")
                      (or tc-done "?") (or tc-budget "?")
                      (or budget "?")
                      (or elapsed "?") (or timeout "?")))
          "")
        (cond
         (err (format "\nerror: %s\n" err))
         (summary
          (concat
           "\nfinal summary:\n"
           (satan-tank--wrap-paragraph
            (concat "  " summary)
            satan-tank-last-run-summary-width)
           "\n"
           (if (and (numberp actions) (> actions 0))
               (format "actions: %d\n" actions) "")))
         (t "")))))
    )
   "\n"))

(defun satan-tank--render-events (events)
  "Render the RECENT EVENTS section for EVENTS (list of plists)."
  (concat
   (satan-tank--section
    (format "RECENT EVENTS (last %d)" (length events)))
   (cond
    ((null events) "(no events)\n")
    (t
     (mapconcat
      (lambda (e)
        (format "%s  %-14s  %-7s  %-12s  %s"
                (satan-tank--short-ts (or (plist-get e :ts) ""))
                (satan-tank--truncate
                 (or (plist-get e :run) "?") 14)
                (or (plist-get e :dir) "?")
                (or (plist-get e :event) "?")
                (satan-tank--truncate (or (plist-get e :summary) "") 80)))
      events "\n")))
   "\n"))

;; ---------------------------------------------------------------------
;; Gatherers (impure)
;; ---------------------------------------------------------------------

(defun satan-tank--time-iso (&optional time)
  (format-time-string "%Y-%m-%dT%H:%M:%S%:z" time))

(defun satan-tank--gather-evidence ()
  "Assemble the evidence window from current panopticon / bough / git state.
Returns the state plist on success; nil if any read errors."
  (condition-case _err
      (let* ((now (satan-tank--time-iso))
             (back (time-subtract (current-time)
                                  satan-tank-evidence-history-seconds))
             (run-started (satan-tank--time-iso back))
             (ctx (list :time_now now
                        :mode_name "tank"
                        :run_id "tank"
                        :current_grammar_version
                        satan-memory-grammar-current-version)))
        (satan-memory-evidence-assemble
         ctx (list :run_started_at run-started :seg_limit 5)))
    (error nil)))

(defun satan-tank--gather-attributes ()
  "Return attribute snapshot alist, symbol `disabled', or nil on error."
  (cond
   ((not satan-attribute-updates-enabled) 'disabled)
   (t (condition-case _err
          (satan-attribute-snapshot)
        (error nil)))))

(defun satan-tank--gather-traces ()
  (pcase (condition-case _err
             (satan-memory-store-recent
              :limit satan-tank-trace-limit)
           (error nil))
    (`(ok . ,rows) rows)
    (_ nil)))

(defun satan-tank--recent-runs ()
  "Most recent N run-ids under `satan-runs-dir', newest first.
Walks both the bucketed layout (`<runs>/<YYYY-MM-DD>/<run-id>') and
the legacy flat layout, via `satan-broker-list-run-dirs'.  The
`.FAILED' suffix (if present on the on-disk leaf) is stripped from
the returned run-ids; callers resolve to a dir via
`satan-broker-run-dir-for-id'."
  (let* ((paths (satan-broker-list-run-dirs satan-runs-dir))
         (ids (mapcar (lambda (p)
                        (satan-broker--run-id-from-leaf
                         (file-name-nondirectory p)))
                      paths))
         (sorted (sort ids #'string-greaterp)))
    (seq-take sorted satan-tank-event-window-runs)))

(defun satan-tank--read-run-events (run-id)
  "Read transcript.jsonl from RUN-ID, return list of event plists.
Each returned plist gains a `:run' (mode slug) and `:summary' field."
  (let ((path (let ((dir (satan-broker-locate-run-dir
                          run-id satan-runs-dir)))
                (and dir (expand-file-name "transcript.jsonl" dir))))
        (slug (satan-tank--short-run run-id))
        out)
    (when (and path (file-readable-p path))
      (let ((coding-system-for-read 'utf-8))
        (with-temp-buffer
          (insert-file-contents path)
          (goto-char (point-min))
          (while (not (eobp))
            (let ((line (buffer-substring-no-properties
                         (point) (line-end-position))))
              (unless (string-empty-p (string-trim line))
                (let ((rec (ignore-errors
                             (json-parse-string
                              line :object-type 'plist
                              :array-type 'list
                              :null-object :null :false-object :false))))
                  (when rec
                    (push (plist-put
                           (plist-put (copy-sequence rec) :run slug)
                           :summary
                           (satan-tank--event-summary rec))
                          out)))))
            (forward-line 1)))))
    (nreverse out)))

(defun satan-tank--last-run-status (events)
  "Derive a run-level status symbol from transcript EVENTS.
Returns one of: `final', `timeout', `error', `in-progress'."
  (cond
   ((cl-some (lambda (e) (equal (plist-get e :event) "timeout")) events)
    'timeout)
   ((cl-some (lambda (e) (equal (plist-get e :event) "protocol-error"))
             events)
    'error)
   ((cl-some (lambda (e) (equal (plist-get e :event) "final")) events)
    'final)
   (t 'in-progress)))

(defun satan-tank--last-run-state (run-id events)
  "Aggregate transcript EVENTS into the LAST RUN state plist for RUN-ID."
  (let* ((start-ts nil)
         (end-ts nil)
         (last-usage nil)
         (tool-calls nil)
         (tool-results (make-hash-table :test 'equal))
         (final nil)
         (err nil)
         (max-tier 0)
         (tier-transitions nil)
         (crash-ctx nil))
    (dolist (e events)
      (let ((ts (plist-get e :ts))
            (event (plist-get e :event))
            (payload (plist-get e :payload)))
        (when (and ts (or (null start-ts) (string-lessp ts start-ts)))
          (setq start-ts ts))
        (when (and ts (or (null end-ts) (string-greaterp ts end-ts)))
          (setq end-ts ts))
        (pcase event
          ("log"
           (when (listp payload)
             (pcase (plist-get payload :kind)
               ("usage" (setq last-usage payload))
               ("tier_changed"
                (let ((to (plist-get payload :to_tier)))
                  (when (and (integerp to) (> to max-tier))
                    (setq max-tier to))
                  (push (list :from (plist-get payload :from_tier)
                              :to to
                              :trigger (plist-get payload :trigger))
                        tier-transitions))))))
          ("tool-call"
           (let ((id (and (listp payload) (plist-get payload :id)))
                 (name (and (listp payload) (plist-get payload :name)))
                 (args (and (listp payload) (plist-get payload :arguments))))
             (push (list :id id :name name :args args) tool-calls)))
          ("tool-result"
           (let ((id (and (listp payload) (plist-get payload :id)))
                 (ok (and (listp payload) (plist-get payload :ok))))
             (when id (puthash id (not (eq ok :false)) tool-results))))
          ("final"
           (setq final payload))
          ("crash-context"
           (setq crash-ctx payload))
          ("protocol-error"
           (setq err (and (listp payload) (plist-get payload :error)))))))
    (setq tool-calls (nreverse tool-calls))
    (dolist (tc tool-calls)
      (let ((id (plist-get tc :id)))
        (plist-put tc :ok (gethash id tool-results nil))))
    (list :run_id run-id
          :mode (satan-tank--short-run run-id)
          :status (satan-tank--last-run-status events)
          :start_ts start-ts
          :end_ts end-ts
          :duration_s (and start-ts end-ts
                           (satan-tank--iso-duration start-ts end-ts))
          :tokens_in (and last-usage (plist-get last-usage :tokens_in))
          :tokens_out (and last-usage (plist-get last-usage :tokens_out))
          :tokens_total (and last-usage (plist-get last-usage :tokens_total))
          :tool_calls tool-calls
          :final_summary (and (listp final) (plist-get final :summary))
          :final_actions (and (listp final)
                              (length (plist-get final :actions)))
          :error_msg err
          :max_tier max-tier
          :tier_transitions (nreverse tier-transitions)
          :crash_context crash-ctx)))

(defun satan-tank--iso-duration (start end)
  "Seconds between two ISO8601 timestamps START and END, or nil."
  (ignore-errors
    (- (float-time (date-to-time end))
       (float-time (date-to-time start)))))

(defun satan-tank--gather-last-run ()
  "Return the LAST RUN state plist for the newest non-empty run, or nil."
  (let ((runs (satan-tank--recent-runs))
        result)
    (cl-loop for r in runs
             for events = (satan-tank--read-run-events r)
             when events
             do (setq result (satan-tank--last-run-state r events))
             and return nil)
    result))

(defun satan-tank--gather-events ()
  "Tail the last N events from the most recent runs, newest first."
  (let* ((runs (satan-tank--recent-runs))
         (all (cl-loop for r in runs
                       append (satan-tank--read-run-events r)))
         (sorted (sort all (lambda (a b)
                             (string-greaterp
                              (or (plist-get a :ts) "")
                              (or (plist-get b :ts) ""))))))
    (cl-subseq sorted 0 (min satan-tank-event-limit (length sorted)))))

;; ---------------------------------------------------------------------
;; Buffer + mode
;; ---------------------------------------------------------------------

(defvar satan-tank-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "g") #'satan-tank-refresh)
    (define-key m (kbd "q") #'quit-window)
    m)
  "Keymap for `satan-tank-mode'.")

(define-derived-mode satan-tank-mode special-mode "SatanTank"
  "Read-only buffer surfacing live SATAN state.
\\{satan-tank-mode-map}"
  (buffer-disable-undo)
  (setq-local truncate-lines t)
  (add-hook 'kill-buffer-hook #'satan-tank--cancel-timer nil t))

(defun satan-tank--cancel-timer ()
  (when (timerp satan-tank--timer)
    (cancel-timer satan-tank--timer)
    (setq satan-tank--timer nil)))

(defun satan-tank-refresh ()
  "Re-gather and re-render the tank buffer."
  (interactive)
  (let ((buf (get-buffer satan-tank--buffer-name)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (let ((inhibit-read-only t)
              (point-pos (point)))
          (erase-buffer)
          (insert (satan-tank--header (satan-tank--time-iso)))
          (insert (satan-tank--render-evidence
                   (satan-tank--gather-evidence)))
          (insert (satan-tank--render-attributes
                   (satan-tank--gather-attributes)))
          (insert (satan-tank--render-traces
                   (satan-tank--gather-traces)))
          (insert (satan-tank--render-last-run
                   (satan-tank--gather-last-run)))
          (insert (satan-tank--render-events
                   (satan-tank--gather-events)))
          (goto-char (min point-pos (point-max))))))))

(defun satan-tank--start-timer ()
  (satan-tank--cancel-timer)
  (when (and satan-tank-refresh-interval
             (numberp satan-tank-refresh-interval))
    (setq satan-tank--timer
          (run-with-timer satan-tank-refresh-interval
                          satan-tank-refresh-interval
                          #'satan-tank--timer-tick))))

(defun satan-tank--timer-tick ()
  (let ((buf (get-buffer satan-tank--buffer-name)))
    (if (and buf (buffer-live-p buf))
        (satan-tank-refresh)
      (satan-tank--cancel-timer))))

;;;###autoload
(defun satan-tank ()
  "Pop open the SATAN observation tank."
  (interactive)
  (let ((buf (get-buffer-create satan-tank--buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'satan-tank-mode)
        (satan-tank-mode)))
    (satan-tank-refresh)
    (satan-tank--start-timer)
    (pop-to-buffer buf)))

(provide 'satan-tank)
;;; satan-tank.el ends here
