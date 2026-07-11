;;; satan-memory-evidence.el --- evidence-window assembler (impure) -*- lexical-binding: t; -*-

;; Step 6 of memory.design.md.  Impure: reads files, runs `git', calls
;; the `bough_read' tool handler.  Produces the evidence_window plist
;; consumed by `satan-memory-canon-canonicalize' (step 5) and stored
;; verbatim (after truncation) in `traces.metadata_json' (step 7).
;;
;; Public entry point:
;;   (satan-memory-evidence-assemble CTX &optional OPTS) -> PLIST
;;
;; CTX is the canon ctx plist: :time_now (ISO8601 string), :mode_name,
;;   :run_id, :current_grammar_version.
;;
;; OPTS keys (all optional):
;;   :run_started_at         ISO8601 string limiting how far back the window reaches
;;   :cwd                    absolute path; defaults to `default-directory'
;;   :behaviour_dir          panopticon root; defaults to `satan-tools-activity-dir'
;;   :bough_workspace        passed through to `bough_read'
;;   :seg_limit              focus/browser cap (default 10)
;;   :bough_limit            bough_recent cap (default 50)
;;   :budget_target_bytes    soft byte budget (default 16384)
;;   :budget_hard_cap_bytes  hard byte cap (default 65536)
;;   :cue_only               t to skip heavy "what happened in the
;;                           window" probes (focus/browser segments,
;;                           bough_recent, bough_day).  Keeps the
;;                           "what is now" probes (current_window,
;;                           bough_active, git_state, fs_state).
;;                           Used by `memory_resonate' cue derivation.
;;
;; This module is intentionally separate from `satan-memory-canon'
;; (which is PURE per §3.5).  The canon module must never `require'
;; this one.

(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'calendar)   ; calendar-absolute-from-gregorian / -gregorian-from-absolute
(require 'satan-jsonl)
(require 'satan-trace)
(require 'satan-tools-activity)
(require 'satan-tools-bough)
(require 'satan-tools-content)

;; ---------------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------------

(defcustom satan-memory-evidence-window-minutes 10
  "Window length in minutes from time_now back to start_at.
Capped further by `:run_started_at' (see §4.1)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-git-window-minutes 1440
  "Look-back horizon (minutes) for the git-activity feed.
Decoupled from `satan-memory-evidence-window-minutes' (the focus/
browser attention window) because commits are bursty: a 10-min window
almost never catches one.  Default 24h."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-git-timeout-seconds 3
  "Per-call wall-clock deadline (seconds) for git subprocesses.
Applied via `satan-trace-call' at the `--git-output' / `--git-state'
chokepoints so a hung repo cannot stall evidence assembly.  A breach
returns nil (git-output) or marks `:timed_out t' (git-state)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-seg-limit 10
  "Maximum focus/browser segments retained per source (newest)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-bough-limit 50
  "Maximum bough_recent entries retained (after dedup by nanoid)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-budget-target 16384
  "Soft byte budget for the JSON-serialised evidence (§4.3)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-budget-hard-cap 65536
  "Hard byte cap for the JSON-serialised evidence (§4.3)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-content-limit 10
  "Maximum content captures retained in the evidence window (newest)."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-recent-files-limit 8
  "Cap on `:fs_state.recent_files' entries."
  :type 'integer :group 'satan)

;; ---------------------------------------------------------------------
;; Freshness thresholds (§S6)
;;
;; Per-source seconds-old ceilings.  When a sensor's age exceeds its
;; threshold the assembler drops the affected slice from the evidence
;; window AND tags its `:sensor_status' entry as `stale-Nm' so the
;; sensor-alerts dispatcher (Phase 4.3) can decide whether to notify.
;; ---------------------------------------------------------------------

(defcustom satan-memory-evidence-current-window-stale-seconds 300
  "Seconds-old ceiling for `current/sway.json' mtime before it is stale.
Default 5 minutes per §S6 open question — tune from observed sway
focus cadence."
  :type 'integer :group 'satan)

(defcustom satan-memory-evidence-segment-stale-seconds 1800
  "Seconds-old ceiling for the newest focus/browser segment before stale."
  :type 'integer :group 'satan)

;; ---------------------------------------------------------------------
;; Sensor-status helpers (§S6)
;; ---------------------------------------------------------------------

(defun satan-memory-evidence--age-seconds (then now)
  "Return non-negative integer seconds between THEN and NOW.
THEN, NOW are Emacs time values.  Negative deltas clamp to 0 so a
clock skew on the sensor side doesn't masquerade as the future."
  (max 0 (truncate (float-time (time-subtract now then)))))

(defun satan-memory-evidence--stale-tag (age-seconds)
  "Return the `stale-Nm' string for AGE-SECONDS (integer minutes, floor).
String not symbol so the value JSON-serialises directly in the run's
`bundle.json' / `percept.json' alongside the rest of the evidence
window."
  (format "stale-%dm" (max 1 (/ age-seconds 60))))

(defun satan-memory-evidence--mtime (path)
  "Return PATH's mtime as an Emacs time, or nil when PATH is unreadable."
  (and (file-readable-p path)
       (file-attribute-modification-time (file-attributes path))))

(defun satan-memory-evidence--current-window-status (path now)
  "Return (STATUS . DATA) for `current/sway.json' at PATH.
STATUS is the JSON-friendly string `\"ok\"' / `\"stale-Nm\"' /
`\"missing\"' / `\"malformed\"'.  DATA is the parsed plist on success,
nil on stale / missing / malformed — the assembler treats nil-data
as drop-the-slice."
  (let ((mtime (satan-memory-evidence--mtime path)))
    (cond
     ((null mtime) (cons "missing" nil))
     (t (let* ((age (satan-memory-evidence--age-seconds mtime now))
               (stale (> age satan-memory-evidence-current-window-stale-seconds)))
          (condition-case _err
              (let ((data (satan-tools-activity--read-json path)))
                (if stale
                    (cons (satan-memory-evidence--stale-tag age) nil)
                  (cons "ok" data)))
            (error (cons "malformed" nil))))))))

(defun satan-memory-evidence--newest-segment-end (segments)
  "Return the :end_ts string with the latest INSTANT across SEGMENTS,
or nil when none qualify.  Segments may be appended out of order
in tests/fixtures, so the freshness check takes the max rather than
trusting file position.  Comparison is by parsed instant, not by
string: a capture-side offset transition (e.g. the firefox plugin's
UTC-`Z' → local-offset fix) leaves mixed offsets in a file, and a
`Z' instant ahead of local sorts LOWER as a string than a stale
local one — a string max would then report a false `stale-Nm'."
  (let (best best-t)
    (dolist (seg segments)
      (let ((ts (plist-get seg :end_ts)))
        (when (stringp ts)
          (let ((tt (ignore-errors (date-to-time ts))))
            (when (and tt (or (null best-t) (time-less-p best-t tt)))
              (setq best ts best-t tt))))))
    best))

(defun satan-memory-evidence--segments-status (path start end limit now)
  "Return (STATUS . SEGMENTS) for a focus/browser segments JSONL at PATH.
STATUS is the JSON-friendly string `\"ok\"' / `\"stale-Nm\"' /
`\"missing\"' / `\"malformed\"'.  SEGMENTS is the filtered tail when
STATUS is `\"ok\"' and empty otherwise — stale tails drop per §S6.
Newest entry is taken by max :end_ts so files written out of order
(or fixtures) still register correctly."
  (cond
   ((not (file-readable-p path)) (cons "missing" '()))
   (t (condition-case _err
          (let* ((all (satan-jsonl-read-file path))
                 (newest (satan-memory-evidence--newest-segment-end all))
                 (newest-t (and newest (date-to-time newest)))
                 (age (and newest-t
                           (satan-memory-evidence--age-seconds
                            newest-t now))))
            (cond
             ((or (null all) (null newest-t))
              (cons "missing" '()))
             ((> age satan-memory-evidence-segment-stale-seconds)
              (cons (satan-memory-evidence--stale-tag age) '()))
             (t
              (let* ((filt (satan-memory-evidence--filter-segments
                            all start end))
                     (tail (and filt (last filt limit))))
                (cons "ok" (or tail '()))))))
        (error (cons "malformed" '()))))))

(defun satan-memory-evidence--content-probe (limit)
  "Return (STATUS . CAPTURES) for the panopticon content store.
STATUS is `\"ok\"' / `\"missing\"' / `\"malformed\"'.
CAPTURES is the last LIMIT articles.jsonl rows, metadata only
(:hash :domain :url :title :captured_at).  Uses the lenient JSONL
reader (skips malformed lines per O-1)."
  (let* ((articles (satan-tools-content--read-articles-jsonl :skip-malformed t))
         (tail (and articles (last articles (min limit (length articles))))))
    (if (null articles)
        (cons "missing" '())
      (cons "ok"
            (mapcar (lambda (a)
                      (list :hash (plist-get a :content_hash)
                            :domain (plist-get a :domain)
                            :url (plist-get a :url)
                            :title (plist-get a :title)
                            :captured_at (plist-get a :captured_at)))
                    (or tail '()))))))

(defun satan-memory-evidence--git-commits-status (paths start end limit)
  "Return (STATUS . COMMITS) for the git-activity feed across PATHS.
PATHS is a list of `segments/git-%F.jsonl' files.  Commits are BURSTY:
a feed whose newest entry is days old is NORMAL, not a fault — so
unlike `--segments-status' this NEVER reports `stale-Nm' and never
drops the slice for age.  STATUS is `\"ok\"' (≥1 path readable with
rows), `\"missing\"' (no readable path / no rows), or `\"malformed\"'
(no path readable because the sole readable file had only parse errors).
COMMITS is the in-window tail (newest LIMIT) sorted by :end_ts ascending
so the last entry is genuinely the newest commit.  Reuses
`--filter-segments' (rows carry `:start_ts'/`:end_ts' = commit instant).

Per-file parse tolerance: a malformed line in one day-file is silently
skipped without blanking good rows from sibling files."
  (let* ((readable (cl-remove-if-not #'file-readable-p paths))
         (all nil)
         (any-error nil))
    (dolist (path readable)
      (condition-case _err
          (setq all (append all (satan-jsonl-read-file path)))
        (error (setq any-error t))))
    (cond
     ((null all)
      (cons (if any-error "malformed" "missing") '()))
     (t (let* ((filt (satan-memory-evidence--filter-segments
                      all start end))
               (sorted (and filt
                             (sort (copy-sequence filt)
                                   (lambda (a b)
                                     (time-less-p
                                      (date-to-time (plist-get a :end_ts))
                                      (date-to-time (plist-get b :end_ts)))))))
               (tail (and sorted (last sorted limit))))
          (cons "ok" (or tail '())))))))

(defun satan-memory-evidence--next-day (day-str)
  "Return the ISO date string for the calendar day after DAY-STR.
DAY-STR is `%F' (e.g. \"2026-04-05\").  Uses calendar arithmetic so
DST transitions cannot produce duplicate or skipped dates."
  (let* ((parsed (parse-iso8601-time-string (concat day-str "T00:00:00")))
         (decoded (decode-time parsed))
         (y (decoded-time-year decoded))
         (m (decoded-time-month decoded))
         (d (decoded-time-day decoded))
         (next (calendar-gregorian-from-absolute
                (1+ (calendar-absolute-from-gregorian (list m d y))))))
    (format "%04d-%02d-%02d"
            (elt next 2) (elt next 0) (elt next 1))))

(defun satan-memory-evidence--git-feed-paths (root start end)
  "Return `segments/git-%F.jsonl' paths for every calendar day in [START, END].
Enumerates day-by-day (inclusive) using calendar arithmetic, so a 24h+
horizon that spans three calendar dates correctly returns three paths.
DST transitions cannot cause duplicate or skipped dates."
  (let* ((start-day (substring start 0 10))
         (end-day (substring end 0 10))
         (day start-day)
         (acc '()))
    (while (string-lessp day end-day)
      (push (expand-file-name (format "segments/git-%s.jsonl" day) root) acc)
      (setq day (satan-memory-evidence--next-day day)))
    (push (expand-file-name (format "segments/git-%s.jsonl" end-day) root) acc)
    (nreverse acc)))

(defvar satan-memory-evidence--bough-tracking nil
  "When non-nil, `--bough-call' records reachability in the vars below.
Dynamically bound by `assemble' to derive the `:bough' sensor_status
without needing each `--bough-*' wrapper to thread the flag itself.")

(defvar satan-memory-evidence--bough-attempts 0
  "Counter incremented by `--bough-call' under `--bough-tracking'.")

(defvar satan-memory-evidence--bough-ok 0
  "Counter incremented by `--bough-call' on each successful ok payload.")

(defun satan-memory-evidence--bough-status ()
  "Synthesise the `:bough' sensor_status from tracking counters.
Returns the JSON-friendly string `\"ok\"' when at least one call
succeeded; `\"unreachable\"' when one or more were attempted but none
returned ok; `\"ok\"' (best guess) when no calls were attempted this
run (e.g. heavy probes skipped under `:cue_only')."
  (cond
   ((> satan-memory-evidence--bough-ok 0) "ok")
   ((> satan-memory-evidence--bough-attempts 0) "unreachable")
   (t "ok")))

;; ---------------------------------------------------------------------
;; Bounds (§4.1)
;; ---------------------------------------------------------------------

(defun satan-memory-evidence--iso-format (time-val)
  "Format TIME-VAL as ISO8601 with offset colon (`+10:00')."
  (format-time-string "%Y-%m-%dT%T%:z" time-val))

(defun satan-memory-evidence--bounds (time-now run-started)
  "Compute (START . END) ISO strings for the evidence window.
END is TIME-NOW; START is the later of (TIME-NOW - window-minutes)
and RUN-STARTED.  RUN-STARTED may be nil."
  (let* ((end-t (date-to-time time-now))
         (back-t (time-subtract
                  end-t
                  (seconds-to-time
                   (* 60 satan-memory-evidence-window-minutes))))
         (run-t (and run-started (date-to-time run-started)))
         (start-t (if (and run-t (time-less-p back-t run-t))
                      run-t
                    back-t)))
    (cons (if (and run-t (time-less-p back-t run-t))
              run-started
            (satan-memory-evidence--iso-format start-t))
          time-now)))

;; ---------------------------------------------------------------------
;; Panopticon reads (§4.2)
;; ---------------------------------------------------------------------

(defun satan-memory-evidence--filter-segments (segments start end)
  "Return SEGMENTS overlapping the half-open [START, END] window.
A segment overlaps if its :end_ts >= START and its :start_ts <= END."
  (let ((s-t (date-to-time start))
        (e-t (date-to-time end)))
    (cl-remove-if-not
     (lambda (seg)
       (let* ((s (plist-get seg :start_ts))
              (en (plist-get seg :end_ts))
              (s-time (and (stringp s) (date-to-time s)))
              (e-time (and (stringp en) (date-to-time en))))
         (and (or (null e-time) (not (time-less-p e-time s-t)))
              (or (null s-time) (not (time-less-p e-t s-time))))))
     segments)))

;; ---------------------------------------------------------------------
;; Bough reads via the tool handler (§5.4 — only path into bough)
;; ---------------------------------------------------------------------

(defun satan-memory-evidence--bough-call (scope &rest args)
  "Call `satan-tool/bough-read' with SCOPE and ARGS (keyword plist).
Return the payload plist on `ok', or nil on any error.

When `--bough-tracking' is non-nil (set by `assemble') each call
increments `--bough-attempts'; successful calls also increment
`--bough-ok'.  The two counters back the §S6 `:bough' sensor_status
synthesis without each `--bough-*' wrapper having to thread state."
  (let* ((arg-plist (apply #'list :scope scope args))
         (result (condition-case _err
                     (satan-tool/bough-read arg-plist nil)
                   (error nil)))
         (ok-p (and (consp result) (eq (car result) 'ok))))
    (when satan-memory-evidence--bough-tracking
      (cl-incf satan-memory-evidence--bough-attempts)
      (when ok-p (cl-incf satan-memory-evidence--bough-ok)))
    (when ok-p (cdr result))))

(defun satan-memory-evidence--flatten-tree (nodes)
  "Depth-first flatten of a tree of node plists.  Strip :children from
each emitted plist.  Accept nil for NODES."
  (let (acc)
    (cl-labels
        ((walk (xs)
           (dolist (n xs)
             (when (and n (listp n))
               (let ((children (plist-get n :children))
                     (cp (copy-sequence n)))
                 (setq cp (plist-put cp :children nil))
                 (push cp acc)
                 (when children (walk children)))))))
      (walk (or nodes '())))
    (nreverse acc)))

(defun satan-memory-evidence--bough-recent (start workspace limit)
  "Return a flat list of bough events since START.  Each transition row
becomes `(:event \"status_changed\" :nanoid :from :to :at :seq :actor)';
each created row becomes `(:event \"created\" :nanoid :kind :title
:status :parent_nanoid :at)'.  Transitions precede creations.  LIMIT
caps the combined output."
  (let* ((payload (satan-memory-evidence--bough-call
                   "recent_changes" :since start :workspace workspace))
         (transitions
          (mapcar
           (lambda (row)
             (list :event "status_changed"
                   :nanoid (plist-get row :nanoid)
                   :from (plist-get row :from_status)
                   :to (plist-get row :to_status)
                   :at (plist-get row :at)
                   :seq (plist-get row :seq)
                   :actor (plist-get row :actor)))
           (and payload (plist-get payload :transitions))))
         (created
          (mapcar
           (lambda (row)
             (list :event "created"
                   :nanoid (plist-get row :nanoid)
                   :kind (plist-get row :kind)
                   :title (plist-get row :title)
                   :status (plist-get row :status)
                   :parent_nanoid (plist-get row :parent_nanoid)
                   :at (plist-get row :at)))
           (and payload (plist-get payload :created))))
         (flat (append transitions created)))
    (if (and limit (< limit (length flat)))
        (cl-subseq flat 0 limit)
      flat)))

(defun satan-memory-evidence--bough-active (workspace)
  (let ((payload (satan-memory-evidence--bough-call
                  "active" :workspace workspace)))
    (satan-memory-evidence--flatten-tree
     (and payload (plist-get payload :nodes)))))

(defun satan-memory-evidence--bough-day (date workspace)
  (let ((payload (satan-memory-evidence--bough-call
                  "day" :date date :workspace workspace)))
    (and payload (plist-get payload :day))))

;; ---------------------------------------------------------------------
;; Git + fs (§4.2)
;; ---------------------------------------------------------------------

(defvar satan-memory-evidence--git-timed-out nil
  "Set non-nil when a routed git sub-call breaches its deadline.
Dynamically let-bound by `--git-state' around its probe set so a
timeout does not silently read as a clean repo (see `:timed_out').")

(defun satan-memory-evidence--git-output (&rest args)
  "Run `git ARGS' and return trimmed stdout, or nil on non-zero exit.
Routed through `satan-trace-call' so the call is ledgered and
bounded by `satan-memory-evidence-git-timeout-seconds'.  The
GIT_OPTIONAL_LOCKS=0 env is passed to the child via `:env' so
read-only git never writes index/ref locks.  A deadline breach both
returns nil (non-zero exit) and records the breach in
`satan-memory-evidence--git-timed-out'."
  (let* ((result (satan-trace-call
                  (or (executable-find "git") "git") args
                  :cwd default-directory
                  :env '("GIT_OPTIONAL_LOCKS=0")
                  :timeout-secs satan-memory-evidence-git-timeout-seconds
                  :label "evidence.git"))
         (exit (plist-get result :exit)))
    (when (plist-get result :timed-out)
      (setq satan-memory-evidence--git-timed-out t))
    (and (integerp exit) (zerop exit)
         (string-trim (plist-get result :stdout)))))

(defun satan-memory-evidence--git-state (cwd)
  "Return git state plist for CWD, or nil if CWD is not in a repo.
When any routed sub-call breaches its deadline the plist carries an
extra `:timed_out t' so a partial (potentially wrong \"clean\") read
is never mistaken for a genuine one."
  (when (and cwd (file-directory-p cwd))
    (let* ((default-directory (file-name-as-directory cwd))
           (satan-memory-evidence--git-timed-out nil)
           (probe (satan-trace-call
                   (or (executable-find "git") "git")
                   '("rev-parse" "--git-dir")
                   :cwd default-directory
                   :env '("GIT_OPTIONAL_LOCKS=0")
                   :timeout-secs satan-memory-evidence-git-timeout-seconds
                   :label "evidence.git"))
           (probe-exit (plist-get probe :exit)))
      (when (and (integerp probe-exit) (zerop probe-exit)
                 (not (plist-get probe :timed-out)))
        (let ((state
               (list :head_short
                     (satan-memory-evidence--git-output
                      "rev-parse" "--short" "HEAD")
                     :remote
                     (satan-memory-evidence--git-output
                      "config" "--get" "remote.origin.url")
                     :dirty
                     (not (string-empty-p
                           (or (satan-memory-evidence--git-output
                                "status" "--porcelain")
                               "")))
                     :commits
                     (split-string
                      (or (satan-memory-evidence--git-output
                           "log" "-n" "5" "--oneline")
                          "")
                      "\n" t))))
          (if satan-memory-evidence--git-timed-out
              (append state (list :timed_out t))
            state))))))

(defun satan-memory-evidence--recent-files (cwd limit)
  "Return up to LIMIT entries of `recentf-list' whose absolute path is
under CWD, relativized.  Empty list if recentf unavailable."
  (when (and cwd (boundp 'recentf-list) recentf-list)
    (let* ((prefix (expand-file-name (file-name-as-directory cwd)))
           out)
      (cl-loop for f in recentf-list
               while (< (length out) limit)
               for full = (expand-file-name f)
               when (string-prefix-p prefix full)
               do (push (file-relative-name full cwd) out))
      (nreverse out))))

(defun satan-memory-evidence--fs-state (cwd)
  (list :cwd (and cwd (abbreviate-file-name cwd))
        :recent_files
        (or (satan-memory-evidence--recent-files
             cwd satan-memory-evidence-recent-files-limit)
            '())))

;; ---------------------------------------------------------------------
;; Truncation (§4.3)
;; ---------------------------------------------------------------------

(defun satan-memory-evidence--encode-bytes (ev)
  "Return the byte length of EV's UTF-8 JSON encoding."
  (length (encode-coding-string (json-encode ev) 'utf-8)))

(defun satan-memory-evidence--truncate-segments-middle (segs)
  "Keep first 3 + last 3 with a sentinel between.  No-op when length<=6."
  (if (<= (length segs) 6)
      segs
    (let* ((head (cl-subseq segs 0 3))
           (tail (cl-subseq segs (- (length segs) 3)))
           (dropped (- (length segs) 6)))
      (append head
              (list (list :truncated t :dropped dropped))
              tail))))

(defun satan-memory-evidence--shrink-annotations (nodes max-len)
  "Replace any :annotation string longer than MAX-LEN with a placeholder.
Returns a fresh list; original NODES is not modified."
  (mapcar
   (lambda (n)
     (let ((ann (plist-get n :annotation)))
       (if (and (stringp ann) (> (length ann) max-len))
           (let ((cp (copy-sequence n)))
             (plist-put cp :annotation
                        (concat (substring ann 0 max-len) "…"))
             (plist-put cp :annotation_len_original (length ann))
             cp)
         n)))
   nodes))

(defun satan-memory-evidence--truncate (ev target hard-cap)
  "Apply deterministic truncation passes until EV fits TARGET (best
effort) or HARD-CAP (mandatory).  Returns EV with :truncated_at set
to a list of pass-name strings that fired, or nil if none did.  Names
are strings (not symbols) so the result survives `json-serialize'
when carried into `percept.json' / `bundle.json' / tool results."
  (let ((dropped nil)
        (cur ev))
    ;; Pass 1: drop bough_day body, keep linked-items only.
    (when (> (satan-memory-evidence--encode-bytes cur) target)
      (let ((day (plist-get cur :bough_day)))
        (when (and day (listp day))
          (let ((linked (plist-get day :linked)))
            (setq cur
                  (plist-put cur :bough_day
                             (list :linked (or linked '())
                                   :body_dropped t)))
            (push "bough_day_bodies" dropped)))))
    ;; Pass 2: middle-drop browser segments.
    (when (> (satan-memory-evidence--encode-bytes cur) target)
      (let ((segs (plist-get cur :browser_segments)))
        (when (and segs (> (length segs) 6))
          (setq cur (plist-put cur :browser_segments
                               (satan-memory-evidence--truncate-segments-middle
                                segs)))
          (push "browser_segments_middle" dropped))))
    ;; Pass 3: middle-drop focus segments.
    (when (> (satan-memory-evidence--encode-bytes cur) target)
      (let ((segs (plist-get cur :focus_segments)))
        (when (and segs (> (length segs) 6))
          (setq cur (plist-put cur :focus_segments
                               (satan-memory-evidence--truncate-segments-middle
                                segs)))
          (push "focus_segments_middle" dropped))))
    ;; Pass 4: shrink long bough_active annotations.
    (when (> (satan-memory-evidence--encode-bytes cur) target)
      (let ((act (plist-get cur :bough_active)))
        (when act
          (setq cur (plist-put cur :bough_active
                               (satan-memory-evidence--shrink-annotations
                                act 256)))
          (push "bough_active_annotation_bodies" dropped))))
    ;; Pass 5 (hard cap): drop bough_recent entirely.
    (when (> (satan-memory-evidence--encode-bytes cur) hard-cap)
      (setq cur (plist-put cur :bough_recent nil))
      (push "bough_recent" dropped))
    (when dropped
      (setq cur (plist-put cur :truncated_at (nreverse dropped))))
    cur))

;; ---------------------------------------------------------------------
;; Public entry point
;; ---------------------------------------------------------------------

(defun satan-memory-evidence-assemble (ctx &optional opts)
  "Assemble the evidence_window plist (§4) for canonicalization and storage.
CTX is the canon ctx plist; OPTS optional knobs (see file header).

§S6 — also computes a per-source freshness check and attaches it as
`:sensor_status' on the returned plist.  Stale slices are dropped
from the evidence window itself (so canon never sees stale data) but
the original status remains in `:sensor_status' so the sensor-alerts
dispatcher (Phase 4.3) can fire on the cause.  The canonicalizer
ignores `:sensor_status' — it's metadata about the assemble, not a
substrate input.

Thin wrapper around `satan-memory-evidence-assemble-with-bounds':
derives the [start, end] window from CTX `:time_now' and any
`:run_started_at' in OPTS.  Callers that need an arbitrary window
(e.g. the Phase-5 observer attributing a single intervention) skip
the wrapper and call the bounds-explicit form directly."
  (let* ((time-now (plist-get ctx :time_now))
         (run-started (plist-get opts :run_started_at))
         (bounds (satan-memory-evidence--bounds time-now run-started))
         (start (car bounds))
         (end (cdr bounds)))
    (satan-memory-evidence-assemble-with-bounds start end ctx opts)))

(defun satan-memory-evidence-assemble-with-bounds (start end ctx &optional opts)
  "Assemble the evidence_window plist for the explicit [START, END] window.
START / END are ISO8601 strings; CTX is the canon ctx plist; OPTS
matches `satan-memory-evidence-assemble' (the wrapper's
`:run_started_at' is irrelevant here — bounds are already fixed).

Same shape as the wrapper.  Sensor freshness probes still derive
from CTX `:time_now', which the observer's caller can either pass
as the intervention-emitted-at (treating probes as historical
metadata) or as the real clock (ignoring the probes' values).  In
practice the observer ignores `:sensor_status' — it cares only
about substrate slices."
  (let* ((time-now (plist-get ctx :time_now))
         (now-t (date-to-time time-now))
         (today (substring end 0 10))
         (root (or (plist-get opts :behaviour_dir)
                   satan-tools-activity-dir))
         (workspace (or (plist-get opts :bough_workspace)
                        satan-bough-default-workspace))
         (cwd (or (plist-get opts :cwd) default-directory))
         (seg-limit (or (plist-get opts :seg_limit)
                        satan-memory-evidence-seg-limit))
         (bough-limit (or (plist-get opts :bough_limit)
                          satan-memory-evidence-bough-limit))
         (content-limit (or (plist-get opts :content_limit)
                            satan-memory-evidence-content-limit))
         (budget-target (or (plist-get opts :budget_target_bytes)
                            satan-memory-evidence-budget-target))
         (budget-hard (or (plist-get opts :budget_hard_cap_bytes)
                          satan-memory-evidence-budget-hard-cap))
         (cue-only (plist-get opts :cue_only))
         (current-path (expand-file-name "current/sway.json" root))
         (current-probe (satan-trace-stage "evidence.current_window"
                          (satan-memory-evidence--current-window-status
                           current-path now-t)))
         (focus-probe (if cue-only
                          (cons 'ok '())
                        (satan-trace-stage "evidence.focus_segments"
                          (satan-memory-evidence--segments-status
                           (expand-file-name
                            (format "segments/focus-%s.jsonl" today) root)
                           start end seg-limit now-t))))
         (browser-probe (if cue-only
                            (cons 'ok '())
                          (satan-trace-stage "evidence.browser_segments"
                            (satan-memory-evidence--segments-status
                             (expand-file-name
                              (format "segments/browser-%s.jsonl" today) root)
                             start end seg-limit now-t))))
         (git-start (satan-memory-evidence--iso-format
                      (time-subtract (date-to-time end)
                                     (seconds-to-time
                                      (* 60 satan-memory-evidence-git-window-minutes)))))
         (git-probe (if cue-only
                        (cons "ok" '())
                      (satan-trace-stage "evidence.git_feed"
                        (satan-memory-evidence--git-commits-status
                         (satan-memory-evidence--git-feed-paths root git-start end)
                         git-start end seg-limit))))
         (content-probe (if cue-only
                            (cons "ok" '())
                          (let ((satan-tools-content-dir
                                 (expand-file-name "content/" root)))
                            (satan-trace-stage-optional "evidence.content_probe"
                              (satan-memory-evidence--content-probe
                               content-limit)))))
         (satan-memory-evidence--bough-tracking t)
         (satan-memory-evidence--bough-attempts 0)
         (satan-memory-evidence--bough-ok 0)
         (bough-recent (unless cue-only
                         (satan-trace-stage-optional "evidence.bough_recent"
                           (satan-memory-evidence--bough-recent
                            start workspace bough-limit))))
         (bough-active (satan-trace-stage "evidence.bough_active"
                         (satan-memory-evidence--bough-active workspace)))
         (bough-day (unless cue-only
                      (satan-trace-stage-optional "evidence.bough_day"
                        (satan-memory-evidence--bough-day today workspace))))
         (bough-status (satan-memory-evidence--bough-status))
         (sensor-status (list :current_window (car current-probe)
                              :focus (car focus-probe)
                              :browser (car browser-probe)
                              :bough bough-status
                              :git (car git-probe)
                              :content (if content-probe
                                           (car content-probe)
                                         "budget_skipped")))
         (raw (list
               :current_window (cdr current-probe)
               :focus_segments (cdr focus-probe)
               :browser_segments (cdr browser-probe)
               :git_commits (cdr git-probe)
               :content_recent (cdr content-probe)
               :bough_recent bough-recent
               :bough_active bough-active
               :bough_day bough-day
               :git_state (satan-trace-stage "evidence.git_state"
                            (satan-memory-evidence--git-state cwd))
               :fs_state (satan-trace-stage "evidence.fs_state"
                           (satan-memory-evidence--fs-state cwd))
               :window_start_at start
               :window_end_at end
               :git_window_start_at git-start
               :sensor_status sensor-status)))
    (satan-trace-stage "evidence.truncate"
      (satan-memory-evidence--truncate raw budget-target budget-hard))))

(provide 'satan-memory-evidence)
;;; satan-memory-evidence.el ends here
