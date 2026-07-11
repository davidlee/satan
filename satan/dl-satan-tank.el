;;; dl-satan-tank.el --- SATAN observation tank -*- lexical-binding: t; -*-

;; Composite read-only buffer that mirrors what SATAN sees right now.
;; Five sections refresh on a timer (`g' for manual refresh, `q' to
;; quit):
;;
;;   1. EVIDENCE WINDOW   `dl-satan-memory-evidence-assemble' output
;;                        (current panopticon window, focus / browser
;;                        segment counts, active bough nodes, git + cwd)
;;   2. ATTRIBUTES        live attribute bars from `satan_attributes'
;;   3. RECENT TRACES     `dl-satan-memory-store-recent' last N rows
;;   4. LAST RUN          summary of the newest run under
;;                        `dl-satan-runs-dir': mode, status, duration,
;;                        token spend, ordered tool calls, final text
;;   5. RECENT EVENTS     tail of run transcripts under `dl-satan-runs-dir'
;;
;; Section renderers are pure (state plist in, string out) so they are
;; tested without DB / panopticon / bough access.  Gatherers wrap the
;; impure reads and swallow errors so a degraded section never breaks
;; the buffer.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'dl-satan-broker)
(require 'dl-satan-memory-evidence)
(require 'dl-satan-memory-store)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-attribute-render)

;; ---------------------------------------------------------------------
;; Customisation
;; ---------------------------------------------------------------------

(defgroup dl-satan-tank nil
  "Composite observation surface for the SATAN broker."
  :group 'dl-satan :prefix "dl-satan-tank-")

(defcustom dl-satan-tank-refresh-interval 5
  "Seconds between automatic refreshes; nil disables the timer."
  :type '(choice (number :tag "Seconds") (const :tag "Disabled" nil))
  :group 'dl-satan-tank)

(defcustom dl-satan-tank-trace-limit 10
  "Recent-traces section displays at most this many rows."
  :type 'integer :group 'dl-satan-tank)

(defcustom dl-satan-tank-event-limit 20
  "Recent-events section displays at most this many events."
  :type 'integer :group 'dl-satan-tank)

(defcustom dl-satan-tank-event-window-runs 8
  "Number of most recent runs scanned for events."
  :type 'integer :group 'dl-satan-tank)

(defcustom dl-satan-tank-evidence-history-seconds 1800
  "How far back to anchor the evidence window when the tank is opened
outside an active SATAN run.  Default is 30 minutes."
  :type 'integer :group 'dl-satan-tank)

(defcustom dl-satan-tank-last-run-summary-width 78
  "Soft wrap width for the LAST RUN final-summary block."
  :type 'integer :group 'dl-satan-tank)

(defconst dl-satan-tank--buffer-name "*satan-tank*")

(defvar dl-satan-tank--timer nil
  "Singleton refresh timer for the tank buffer.")

;; ---------------------------------------------------------------------
;; Pure helpers
;; ---------------------------------------------------------------------

(defun dl-satan-tank--truncate (s n)
  "Truncate S to N chars, suffixing `…' when shortened."
  (if (<= (length s) n) s
    (concat (substring s 0 (max 0 (1- n))) "…")))

(defun dl-satan-tank--short-ts (ts)
  "Return the HH:MM:SS portion of an ISO8601 TS, or TS unchanged."
  (cond
   ((and (stringp ts) (string-match "T\\([0-9:]+\\)" ts))
    (match-string 1 ts))
   (t (or ts ""))))

(defun dl-satan-tank--short-run (run-id)
  "Pull the mode slug from a RUN-ID like `20260520T082808-tick-pulse-e44377'."
  (cond
   ((and (stringp run-id)
         (string-match "T[0-9]+-\\(.+\\)-[a-z0-9]+\\'" run-id))
    (match-string 1 run-id))
   (t (or run-id ""))))

(defun dl-satan-tank--summarize-args (args)
  "Compact one-line summary of a tool-call ARGS plist."
  (cond
   ((null args) "")
   ((stringp args) (dl-satan-tank--truncate args 40))
   ((listp args)
    (mapconcat
     (lambda (cell)
       (format "%s=%s" (substring (symbol-name (car cell)) 1)
               (dl-satan-tank--truncate (format "%s" (cadr cell)) 20)))
     (cl-loop for (k v) on args by #'cddr
              when (keywordp k) collect (list k v))
     " "))
   (t (format "%s" args))))

(defun dl-satan-tank--event-summary (rec)
  "Build a one-line summary for a transcript JSONL record REC."
  (let* ((event (plist-get rec :event))
         (payload (plist-get rec :payload)))
    (pcase event
      ("tool-call"
       (let ((name (and (listp payload) (plist-get payload :name)))
             (args (and (listp payload) (plist-get payload :arguments))))
         (format "%s(%s)" (or name "?")
                 (dl-satan-tank--summarize-args args))))
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

(defun dl-satan-tank--section (title)
  ;; #x2500 = BOX DRAWINGS LIGHT HORIZONTAL ('─').  Emacs-overlay's elisp
  ;; parser does not accept multi-byte `?<char>' literals, so the
  ;; integer form is used here to keep `home-manager switch' working.
  (format "%s\n%s\n" title (make-string (length title) #x2500)))

(defun dl-satan-tank--header (now-iso)
  (format "═══ SATAN OBSERVATION TANK · %s ═══\n\n" now-iso))

(defun dl-satan-tank--render-bough-active (nodes max)
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
                  (dl-satan-tank--truncate (or (plist-get n :title) "") 60)
                  (or (plist-get n :nanoid) "?")))
        shown "")
       (if (> rest 0) (format "  · …%d more\n" rest) ""))))))

(defun dl-satan-tank--render-evidence (state)
  "Render the EVIDENCE WINDOW section for STATE plist."
  (concat
   (dl-satan-tank--section "EVIDENCE WINDOW")
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
                    (dl-satan-tank--truncate (or title "") 60))
          "current:       (no panopticon)\n")
        (format "focus:         %d segments\n" (length focus))
        (format "browser:       %d segments\n" (length browser))
        (format "bough_active:  %d nodes\n" (length active))
        (dl-satan-tank--render-bough-active active 4)
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

(defun dl-satan-tank--render-attributes (snapshot)
  "Render the ATTRIBUTES section.
SNAPSHOT is the result of `dl-satan-attribute-snapshot' (alist), or
the symbol `disabled' when the switch is off, or nil on query failure."
  (concat
   (dl-satan-tank--section "ATTRIBUTES")
   (cond
    ((eq snapshot 'disabled) "(disabled)\n")
    ((null snapshot) "(unavailable)\n")
    (t (mapconcat (lambda (line) (concat line "\n"))
                  (dl-satan-attribute-render--rows snapshot) "")))
   "\n"))

(defun dl-satan-tank--render-traces (rows)
  "Render the RECENT TRACES section for ROWS (list of store-recent plists)."
  (concat
   (dl-satan-tank--section
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
                  (dl-satan-tank--wrap-paragraph
                   (concat "  " (or payload ""))
                   dl-satan-tank-last-run-summary-width))))
      rows "\n")))
   "\n"))

(defun dl-satan-tank--wrap-paragraph (text width)
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

(defun dl-satan-tank--render-last-run (state)
  "Render the LAST RUN section for STATE plist.
STATE is the gatherer plist (see `dl-satan-tank--gather-last-run');
nil means no completed runs are available yet."
  (concat
   (dl-satan-tank--section "LAST RUN")
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
              (let ((args-str (dl-satan-tank--summarize-args
                               (plist-get tc :args))))
                (format "  · %-26s %-5s %s"
                        (dl-satan-tank--truncate
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
           (dl-satan-tank--wrap-paragraph
            (concat "  " summary)
            dl-satan-tank-last-run-summary-width)
           "\n"
           (if (and (numberp actions) (> actions 0))
               (format "actions: %d\n" actions) "")))
         (t "")))))
    )
   "\n"))

(defun dl-satan-tank--render-events (events)
  "Render the RECENT EVENTS section for EVENTS (list of plists)."
  (concat
   (dl-satan-tank--section
    (format "RECENT EVENTS (last %d)" (length events)))
   (cond
    ((null events) "(no events)\n")
    (t
     (mapconcat
      (lambda (e)
        (format "%s  %-14s  %-7s  %-12s  %s"
                (dl-satan-tank--short-ts (or (plist-get e :ts) ""))
                (dl-satan-tank--truncate
                 (or (plist-get e :run) "?") 14)
                (or (plist-get e :dir) "?")
                (or (plist-get e :event) "?")
                (dl-satan-tank--truncate (or (plist-get e :summary) "") 80)))
      events "\n")))
   "\n"))

;; ---------------------------------------------------------------------
;; Gatherers (impure)
;; ---------------------------------------------------------------------

(defun dl-satan-tank--time-iso (&optional time)
  (format-time-string "%Y-%m-%dT%H:%M:%S%:z" time))

(defun dl-satan-tank--gather-evidence ()
  "Assemble the evidence window from current panopticon / bough / git state.
Returns the state plist on success; nil if any read errors."
  (condition-case _err
      (let* ((now (dl-satan-tank--time-iso))
             (back (time-subtract (current-time)
                                  dl-satan-tank-evidence-history-seconds))
             (run-started (dl-satan-tank--time-iso back))
             (ctx (list :time_now now
                        :mode_name "tank"
                        :run_id "tank"
                        :current_grammar_version
                        dl-satan-memory-grammar-current-version)))
        (dl-satan-memory-evidence-assemble
         ctx (list :run_started_at run-started :seg_limit 5)))
    (error nil)))

(defun dl-satan-tank--gather-attributes ()
  "Return attribute snapshot alist, symbol `disabled', or nil on error."
  (cond
   ((not dl-satan-attribute-updates-enabled) 'disabled)
   (t (condition-case _err
          (dl-satan-attribute-snapshot)
        (error nil)))))

(defun dl-satan-tank--gather-traces ()
  (pcase (condition-case _err
             (dl-satan-memory-store-recent
              :limit dl-satan-tank-trace-limit)
           (error nil))
    (`(ok . ,rows) rows)
    (_ nil)))

(defun dl-satan-tank--recent-runs ()
  "Most recent N run-ids under `dl-satan-runs-dir', newest first.
Walks both the bucketed layout (`<runs>/<YYYY-MM-DD>/<run-id>') and
the legacy flat layout, via `dl-satan-broker-list-run-dirs'.  The
`.FAILED' suffix (if present on the on-disk leaf) is stripped from
the returned run-ids; callers resolve to a dir via
`dl-satan-broker-run-dir-for-id'."
  (let* ((paths (dl-satan-broker-list-run-dirs dl-satan-runs-dir))
         (ids (mapcar (lambda (p)
                        (dl-satan-broker--run-id-from-leaf
                         (file-name-nondirectory p)))
                      paths))
         (sorted (sort ids #'string-greaterp)))
    (seq-take sorted dl-satan-tank-event-window-runs)))

(defun dl-satan-tank--read-run-events (run-id)
  "Read transcript.jsonl from RUN-ID, return list of event plists.
Each returned plist gains a `:run' (mode slug) and `:summary' field."
  (let ((path (let ((dir (dl-satan-broker-locate-run-dir
                          run-id dl-satan-runs-dir)))
                (and dir (expand-file-name "transcript.jsonl" dir))))
        (slug (dl-satan-tank--short-run run-id))
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
                           (dl-satan-tank--event-summary rec))
                          out)))))
            (forward-line 1)))))
    (nreverse out)))

(defun dl-satan-tank--last-run-status (events)
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

(defun dl-satan-tank--last-run-state (run-id events)
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
          :mode (dl-satan-tank--short-run run-id)
          :status (dl-satan-tank--last-run-status events)
          :start_ts start-ts
          :end_ts end-ts
          :duration_s (and start-ts end-ts
                           (dl-satan-tank--iso-duration start-ts end-ts))
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

(defun dl-satan-tank--iso-duration (start end)
  "Seconds between two ISO8601 timestamps START and END, or nil."
  (ignore-errors
    (- (float-time (date-to-time end))
       (float-time (date-to-time start)))))

(defun dl-satan-tank--gather-last-run ()
  "Return the LAST RUN state plist for the newest non-empty run, or nil."
  (let ((runs (dl-satan-tank--recent-runs))
        result)
    (cl-loop for r in runs
             for events = (dl-satan-tank--read-run-events r)
             when events
             do (setq result (dl-satan-tank--last-run-state r events))
             and return nil)
    result))

(defun dl-satan-tank--gather-events ()
  "Tail the last N events from the most recent runs, newest first."
  (let* ((runs (dl-satan-tank--recent-runs))
         (all (cl-loop for r in runs
                       append (dl-satan-tank--read-run-events r)))
         (sorted (sort all (lambda (a b)
                             (string-greaterp
                              (or (plist-get a :ts) "")
                              (or (plist-get b :ts) ""))))))
    (cl-subseq sorted 0 (min dl-satan-tank-event-limit (length sorted)))))

;; ---------------------------------------------------------------------
;; Buffer + mode
;; ---------------------------------------------------------------------

(defvar dl-satan-tank-mode-map
  (let ((m (make-sparse-keymap)))
    (define-key m (kbd "g") #'dl-satan-tank-refresh)
    (define-key m (kbd "q") #'quit-window)
    m)
  "Keymap for `dl-satan-tank-mode'.")

(define-derived-mode dl-satan-tank-mode special-mode "SatanTank"
  "Read-only buffer surfacing live SATAN state.
\\{dl-satan-tank-mode-map}"
  (buffer-disable-undo)
  (setq-local truncate-lines t)
  (add-hook 'kill-buffer-hook #'dl-satan-tank--cancel-timer nil t))

(defun dl-satan-tank--cancel-timer ()
  (when (timerp dl-satan-tank--timer)
    (cancel-timer dl-satan-tank--timer)
    (setq dl-satan-tank--timer nil)))

(defun dl-satan-tank-refresh ()
  "Re-gather and re-render the tank buffer."
  (interactive)
  (let ((buf (get-buffer dl-satan-tank--buffer-name)))
    (when (and buf (buffer-live-p buf))
      (with-current-buffer buf
        (let ((inhibit-read-only t)
              (point-pos (point)))
          (erase-buffer)
          (insert (dl-satan-tank--header (dl-satan-tank--time-iso)))
          (insert (dl-satan-tank--render-evidence
                   (dl-satan-tank--gather-evidence)))
          (insert (dl-satan-tank--render-attributes
                   (dl-satan-tank--gather-attributes)))
          (insert (dl-satan-tank--render-traces
                   (dl-satan-tank--gather-traces)))
          (insert (dl-satan-tank--render-last-run
                   (dl-satan-tank--gather-last-run)))
          (insert (dl-satan-tank--render-events
                   (dl-satan-tank--gather-events)))
          (goto-char (min point-pos (point-max))))))))

(defun dl-satan-tank--start-timer ()
  (dl-satan-tank--cancel-timer)
  (when (and dl-satan-tank-refresh-interval
             (numberp dl-satan-tank-refresh-interval))
    (setq dl-satan-tank--timer
          (run-with-timer dl-satan-tank-refresh-interval
                          dl-satan-tank-refresh-interval
                          #'dl-satan-tank--timer-tick))))

(defun dl-satan-tank--timer-tick ()
  (let ((buf (get-buffer dl-satan-tank--buffer-name)))
    (if (and buf (buffer-live-p buf))
        (dl-satan-tank-refresh)
      (dl-satan-tank--cancel-timer))))

;;;###autoload
(defun my/satan-tank ()
  "Pop open the SATAN observation tank."
  (interactive)
  (let ((buf (get-buffer-create dl-satan-tank--buffer-name)))
    (with-current-buffer buf
      (unless (derived-mode-p 'dl-satan-tank-mode)
        (dl-satan-tank-mode)))
    (dl-satan-tank-refresh)
    (dl-satan-tank--start-timer)
    (pop-to-buffer buf)))

(provide 'dl-satan-tank)
;;; dl-satan-tank.el ends here
