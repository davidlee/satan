;;; satan-context.el --- Build the run input bundle -*- lexical-binding: t; -*-

;; A context function returns the input-bundle plist that gets written to
;; `bundle.json' under the run directory.  Bundle is what the harness sees;
;; it is also frozen for audit.

(require 'subr-x)
(require 'cl-lib)
(require 'json)
(require 'satan-custom)
(require 'satan-percept)
(require 'satan-resonance)
(require 'satan-motive)
(require 'satan-sensor-alerts)
(require 'satan-sensor-curiosity)
(require 'satan-sensor-content)
(require 'satan-sensor-wpm)
(require 'satan-attribute-render)
(require 'satan-trace)

(defvar satan-runs-dir)              ; defined in satan-broker.el
(defvar satan-run--iso-time-format)  ; defconst in satan-run.el
(declare-function satan-run-dir-for-id "satan-run"
                  (run-id &optional runs-dir))

;; ── Shared assembly core (DEC-13, Phase 4) ─────────────────────────────────

(defun satan-run-perceive (prepare mode dir)
  "Sense the world and thread the percept onto PREPARE; persist percept.json.
The deterministic perceive half of context assembly: build the
percept (single builder invariant — `satan-percept-build' is the
only percept constructor), persist it under DIR, and thread the
sensing keys onto PREPARE.  No resonance/motive — those are consume-side
concerns (see `satan-run-enrich') that only matter once a model runs.
Pure apart from the `percept.json' write under DIR.

Also takes the three probe read-snapshots (DR-010 §3 read/commit split):
pure reads only — no enqueue, no watermark advance, no state write.  The
snapshots are threaded onto PREPARE under `:probe_snapshots' for the
consume-side commit in `satan-broker--spawn'.  This is internal
plumbing only — the context-fn never serializes it, so `bundle.json'
stays byte-stable (the MCP boot path takes harmless pure reads).

Threaded keys (set by this function on PREPARE):
  :evidence         — evidence_window from percept.
  :percept          — plist from satan-percept-build.
  :sensor_status    — sensor_status from evidence_window.
  :probe_snapshots  — (:curiosity SNAP :content SNAP :wpm SNAP)."
  (let* ((percept (satan-percept-build prepare mode))
         (_persisted (satan-trace-stage "perceive.persist"
                       (satan-percept-persist dir percept)))
         (evidence (plist-get percept :evidence_window))
         (sensor-status (plist-get evidence :sensor_status))
         (run-id (plist-get prepare :run_id))
         (ts (plist-get prepare :time_now))
         (snapshots
          (list :curiosity (satan-trace-stage "probes.read.curiosity"
                             (satan-sensor-curiosity-probe-read
                              :run-id run-id :ts ts))
                :content (satan-trace-stage "probes.read.content"
                           (satan-sensor-content-probe-read
                            :run-id run-id :ts ts))
                :wpm (satan-trace-stage "probes.read.wpm"
                       (satan-sensor-wpm-probe-read
                        :run-id run-id :ts ts)))))
    (plist-put
     (plist-put
      (plist-put
       (plist-put prepare :evidence evidence)
       :percept percept)
      :sensor_status sensor-status)
     :probe_snapshots snapshots)))

(defun satan-run-enrich (prepare)
  "Derive resonance + motive from PREPARE's percept; thread them onto PREPARE.
The consume-side enrich half of context assembly: reads `:percept'
already on PREPARE (does NOT rebuild it — single builder invariant)
and derives the model-facing enrichment that only matters when a model
runs.  Takes only PREPARE — it neither senses nor persists.

Threaded keys (set by this function on PREPARE):
  :resonance      — plist from satan-resonance-derive over the percept.
  :motive         — plist from satan-motive-read."
  (let* ((percept (plist-get prepare :percept))
         (resonance (or (satan-trace-stage-optional "enrich.resonance"
                          (satan-resonance-derive percept))
                        (list :status 'budget-skipped :cue nil :matches nil)))
         (motive (satan-trace-stage "enrich.motive"
                   (satan-motive-read satan-motive-file))))
    (plist-put
     (plist-put prepare :resonance resonance)
     :motive motive)))

(defun satan-run-assemble-context (prepare mode dir)
  "Build percept/resonance/motive/sensor_status and thread into PREPARE.
Persists percept.json under DIR.  Returns the augmented PREPARE plist.

Composition of the perceive + enrich halves
\(`satan-run-perceive' then `satan-run-enrich'): perceive senses
and persists the percept; enrich derives resonance + motive over it.
Keeping this as the exact composition preserves the single-percept-builder
invariant and byte-stable output for existing callers.

This is the observer-independent assembly core shared by both
`broker--spawn' (batch) and `satan-context-interactive' (MCP boot).
Callers that need observer-process + probes/alerts run them around
this function.

Threaded keys (set by this function on PREPARE):
  :evidence       — evidence_window from percept (via perceive).
  :percept        — plist from satan-percept-build (via perceive).
  :sensor_status  — sensor_status from evidence_window (via perceive).
  :resonance      — plist from satan-resonance-derive (via enrich).
  :motive         — plist from satan-motive-read (via enrich).

Caller-threaded keys (NOT set by this function):
  :audit          — set by broker before calling.
  :observer       — set by broker before calling.
  :pre_spawn      — set by broker after calling."
  (satan-run-enrich (satan-run-perceive prepare mode dir)))

(defcustom satan-system-scaffold-file
  (expand-file-name "satan/system/scaffold.txt" satan-notes-root)
  "Shared system-prompt scaffold prepended to every mode prompt.
Canonical text lives under `~/notes/satan/system/'; dotfiles must
not be the source of truth for behavioural framing."
  :type 'file :group 'satan)

(defcustom satan-system-framing-file
  (expand-file-name "satan/system/framing.txt" satan-notes-root)
  "Bundle-section headers for context blocks the broker appends to `:prompt'.
Each call to a context-fn reads this file fresh to assemble the
`# Now' / `# Today (raw)' / `# Source files' headers added after the
scaffold + mode prompt.  Mind owns these strings; dotfiles only own
the value substitution."
  :type 'file :group 'satan)

(defun satan-context--read-file-or-empty (path)
  "Return contents of PATH, or empty string if missing.
Use for optional context (e.g. today's note) — never for required
model-facing text; use `satan-context--read-required' for that."
  (if (file-readable-p path)
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents path))
        (buffer-string))
    ""))

(defun satan-context--read-required (path)
  "Return contents of PATH; signal if missing.
Use for canonical model-facing text where silent emptiness would be
a misconfiguration: mode prompts, the system scaffold."
  (unless (file-readable-p path)
    (error "SATAN: required model-facing file missing: %s" path))
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents path))
    (buffer-string)))

(defun satan-context--assemble-prompt (mode-spec)
  "Return MODE-SPEC's assembled system prompt: scaffold + mode prompt.
Both halves are required; missing files signal an error so a run
cannot start with degraded behavioural framing."
  (let* ((prompt-path (plist-get mode-spec :prompt-file))
         (scaffold (string-trim-right
                    (satan-context--read-required
                     satan-system-scaffold-file)))
         (prompt (string-trim-right
                  (satan-context--read-required prompt-path))))
    (concat scaffold "\n\n" prompt)))

(defun satan-context--parse-framing (text)
  "Parse TEXT as `key=value' lines; return an alist.
Lines starting with `#' or that contain no `=' are ignored."
  (let (acc)
    (dolist (line (split-string text "\n"))
      (let ((trimmed (string-trim line)))
        (unless (or (string-empty-p trimmed)
                    (string-prefix-p "#" trimmed))
          (let ((eq (string-search "=" line)))
            (when eq
              (push (cons (string-trim (substring line 0 eq))
                          (substring line (1+ eq)))
                    acc))))))
    (nreverse acc)))

(defun satan-context--framing ()
  "Return framing alist loaded from `satan-system-framing-file'.
Required keys: `now', `today', `sources'.  Missing file signals."
  (let ((alist (satan-context--parse-framing
                (satan-context--read-required
                 satan-system-framing-file))))
    (dolist (key '("now" "today" "sources"))
      (unless (assoc key alist)
        (error "SATAN: framing.txt missing required key: %s" key)))
    alist))

(defun satan-context--render-now (framing now)
  "Return the rendered `# Now' block as a list of lines.
NOW is the bundle `:now' plist, FRAMING the parsed framing alist.
Returns nil when NOW is empty."
  (when (and (plistp now) now)
    (let* ((iso-date  (or (plist-get now :iso_date)  ""))
           (weekday   (or (plist-get now :weekday)   ""))
           (iso-week  (or (plist-get now :iso_week)  ""))
           (hm        (or (plist-get now :time)      ""))
           (tz-offset (or (plist-get now :tz_offset) ""))
           (tz-name   (or (plist-get now :tz_name)   ""))
           (suffix-bits (delq nil
                              (list (and (not (string-empty-p weekday)) weekday)
                                    (and (not (string-empty-p iso-week))
                                         (concat "ISO " iso-week)))))
           (suffix (if suffix-bits
                       (format " (%s)" (mapconcat #'identity suffix-bits ", "))
                     ""))
           (tz (string-trim
                (concat tz-offset (if (and (not (string-empty-p tz-offset))
                                           (not (string-empty-p tz-name)))
                                      " " "")
                        tz-name)))
           (lines (list (cdr (assoc "now" framing)))))
      (unless (string-empty-p iso-date)
        (push (format "date: %s%s" iso-date suffix) lines))
      (unless (string-empty-p hm)
        (push (format "time: %s%s" hm (if (string-empty-p tz) "" (concat " " tz)))
              lines))
      (nreverse lines))))

(defun satan-context--render-today (framing today-text)
  "Return rendered `# Today (raw)' block as a list of lines, or nil if empty."
  (when (and (stringp today-text) (not (string-empty-p today-text)))
    (list (cdr (assoc "today" framing)) today-text)))

(defun satan-context--render-sources (framing sources)
  "Return rendered `# Source files' block as a list of lines, or nil if empty."
  (when sources
    (let ((lines (list (cdr (assoc "sources" framing)))))
      (dolist (item sources)
        (let ((path (or (plist-get item :path) "?"))
              (content (or (plist-get item :content) "")))
          (push "" lines)
          (push (format "## %s" path) lines)
          (push "```" lines)
          (push content lines)
          (push "```" lines)))
      (nreverse lines))))

(defconst satan-context--run-id-regexp
  "\\`\\([0-9]\\{4\\}\\)\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)T\\([0-9]\\{2\\}\\)\\([0-9]\\{2\\}\\)[0-9]\\{2\\}-\\([a-z0-9-]+?\\)-[A-Za-z0-9]+\\(\\.FAILED\\)?\\'"
  "Match a SATAN run-id leaf name; capture groups: YYYY MM DD HH MM mode FAILED?")

(defconst satan-context--bucket-regexp
  "\\`[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\'"
  "Match a SATAN runs date-bucket directory name.")

(defconst satan-context--summary-clip 280
  "Max characters of `final.json' summary kept in the recent-runs block.")

(defun satan-context--list-recent-runs (n)
  "Return up to N most recent SATAN run directories, newest-first.
Globs `satan-runs-dir' for `YYYY-MM-DD' buckets in descending
order and collects run leaves until N entries are gathered.  Stray
files at the runs root (e.g. the `most-recent' symlink) are skipped.
Returns nil when the runs dir is missing or empty."
  (when (and (boundp 'satan-runs-dir)
             satan-runs-dir
             (file-directory-p satan-runs-dir))
    (let* ((buckets (cl-remove-if-not
                     (lambda (name)
                       (and (string-match-p
                             satan-context--bucket-regexp name)
                            (file-directory-p
                             (expand-file-name name satan-runs-dir))))
                     (directory-files satan-runs-dir nil nil t)))
           (buckets (sort buckets #'string>))
           collected)
      (cl-loop
       for bucket in buckets
       while (< (length collected) n)
       for bucket-dir = (expand-file-name bucket satan-runs-dir)
       for leaves = (sort
                     (cl-remove-if-not
                      (lambda (name)
                        (and (string-match-p
                              satan-context--run-id-regexp name)
                             (file-directory-p
                              (expand-file-name name bucket-dir))))
                      (directory-files bucket-dir nil nil t))
                     #'string>)
       do (cl-loop for leaf in leaves
                   while (< (length collected) n)
                   do (push (expand-file-name leaf bucket-dir) collected)))
      (nreverse collected))))

(defun satan-context--clip (s n)
  "Return S clipped to N chars with a trailing ellipsis when truncated."
  (if (<= (length s) n) s (concat (substring s 0 (max 0 (1- n))) "…")))

(defun satan-context--tally-tool-calls (transcript-path)
  "Return alist (NAME . COUNT) of tool calls in TRANSCRIPT-PATH.
Excludes `satan_final'.  Returns nil when the file is missing or
contains no tool-call lines.  Counts are in first-occurrence order."
  (when (file-readable-p transcript-path)
    (let ((counts nil))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents transcript-path))
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (point) (line-end-position))))
            (when (and (not (string-empty-p (string-trim line)))
                       (string-match-p "\"event\"[ \t]*:[ \t]*\"tool-call\""
                                       line))
              (let* ((obj (ignore-errors
                            (json-parse-string line
                                               :object-type 'plist
                                               :array-type 'list
                                               :null-object nil
                                               :false-object nil)))
                     (name (and obj (plist-get
                                     (plist-get obj :payload) :name))))
                (when (and name (not (equal name "satan_final")))
                  (let ((cell (assoc name counts)))
                    (if cell (cl-incf (cdr cell))
                      (setq counts (append counts (list (cons name 1))))))))))
          (forward-line 1)))
      counts)))

(defun satan-context--summarize-run (run-dir)
  "Return a recent-runs entry plist for RUN-DIR.
Keys: :when, :mode, :status (\"ok\" / \"FAILED\"), :summary (or nil),
:tools (alist of (NAME . COUNT))."
  (let* ((leaf (file-name-nondirectory (directory-file-name run-dir))))
    (when (string-match satan-context--run-id-regexp leaf)
      (let* ((yyyy (match-string 1 leaf))
             (mm   (match-string 2 leaf))
             (dd   (match-string 3 leaf))
             (hh   (match-string 4 leaf))
             (mi   (match-string 5 leaf))
             (mode (match-string 6 leaf))
             (failed (match-string 7 leaf))
             (final-path (expand-file-name "final.json" run-dir))
             (summary
              (when (file-readable-p final-path)
                (ignore-errors
                  (with-temp-buffer
                    (let ((coding-system-for-read 'utf-8))
                      (insert-file-contents final-path))
                    (goto-char (point-min))
                    (let ((obj (json-parse-buffer
                                :object-type 'plist
                                :array-type 'list
                                :null-object nil
                                :false-object nil)))
                      (plist-get obj :summary))))))
             (summary-clipped
              (and summary
                   (satan-context--clip
                    (replace-regexp-in-string
                     "[\r\n]+" " " (string-trim summary))
                    satan-context--summary-clip)))
             (tools (satan-context--tally-tool-calls
                     (expand-file-name "transcript.jsonl" run-dir))))
        (list :when (format "%s-%s-%s %s:%s" yyyy mm dd hh mi)
              :mode mode
              :status (if failed "FAILED" "ok")
              :summary summary-clipped
              :tools tools)))))

(defun satan-context--recent-runs (n)
  "Return up to N summarized recent-run entries, newest-first."
  (delq nil (mapcar #'satan-context--summarize-run
                    (satan-context--list-recent-runs n))))

(defun satan-context--render-recent-runs (framing entries)
  "Return rendered `# Recent SATAN runs' block as a list of lines, or nil."
  (when entries
    (let ((header (or (cdr (assoc "recent_runs" framing))
                      "# Recent SATAN runs"))
          (lines nil))
      (push header lines)
      (dolist (e entries)
        (let* ((status (plist-get e :status))
               (mode (plist-get e :mode))
               (summary (plist-get e :summary))
               (tools (plist-get e :tools))
               (head (format "[%s] %s%s%s"
                             (plist-get e :when)
                             mode
                             (if (equal status "ok") "" (format " (%s)" status))
                             (if summary (format ": %s" summary) ""))))
          (push head lines)
          (when tools
            (push (concat "  tools: "
                          (mapconcat (lambda (kv)
                                       (format "%s×%d" (car kv) (cdr kv)))
                                     tools ", "))
                  lines))))
      (nreverse lines))))

(defun satan-context--render-prompt (assembled bundle)
  "Return the fully-rendered system prompt for the harness.
ASSEMBLED is the scaffold + mode-prompt string (no framing yet).
BUNDLE is the context plist providing `:now', `:today_text', `:sources',
`:recent_runs', `:percept', `:resonance', `:motive', `:sensor_status',
`:attributes'.
Missing framing.txt signals — there is no canonical fallback.  Block
order: `# Now' → attributes → percept → attention → resonance → motive →
sensors → mode-specific (today / sources / recent runs).  Each block self-suppresses
when its source is empty/absent (A4, A6, A8, A15)."
  (let* ((framing (satan-context--framing))
         (parts (list (string-trim-right assembled)))
         (blocks (delq nil
                       (list
                        (satan-context--render-now
                         framing (plist-get bundle :now))
                        (satan-attribute-render-block
                         framing (plist-get bundle :attributes))
                        (satan-percept-render-block
                         framing (plist-get bundle :percept))
                        (satan-percept-render-attention-block
                         framing (plist-get bundle :percept))
                        (satan-resonance-render-block
                         framing (plist-get bundle :resonance))
                        (satan-motive-render-block
                         framing
                         (plist-get bundle :motive)
                         (plist-get bundle :time_now))
                        (satan-sensor-render-block
                         framing (plist-get bundle :sensor_status))
                        (satan-context--render-today
                         framing (plist-get bundle :today_text))
                        (satan-context--render-sources
                         framing (plist-get bundle :sources))
                        (satan-context--render-recent-runs
                         framing (plist-get bundle :recent_runs))))))
    (dolist (block blocks)
      (push "" parts)
      (dolist (line block)
        (push line parts)))
    (mapconcat #'identity (nreverse parts) "\n")))

(defun satan-context-now (&optional time)
  "Return the canonical `:now' plist for TIME (default `current-time').
Every bundle includes this so the model has consistent date/time/tz
framing regardless of mode.  Keys: :iso_date, :weekday, :iso_week,
:time, :tz_offset, :tz_name."
  (let ((time (or time (current-time))))
    (list :iso_date  (format-time-string "%Y-%m-%d" time)
          :weekday   (format-time-string "%A"       time)
          :iso_week  (format-time-string "%G-W%V"   time)
          :time      (format-time-string "%H:%M"    time)
          :tz_offset (format-time-string "%z"       time)
          :tz_name   (format-time-string "%Z"       time))))

(defun satan-context--finalize-prompt (bundle assembled)
  "Replace BUNDLE's `:prompt' with the fully-rendered prompt.
ASSEMBLED is the scaffold + mode-prompt string the caller built.
Fetches the attribute snapshot and attaches it to BUNDLE before
rendering so every mode gets the `# Attributes' block.
The harness consumes `:prompt' verbatim; other bundle keys remain
for audit but are no longer read by the harness."
  (unless (plist-member bundle :attributes)
    (setq bundle (plist-put bundle :attributes
                             (satan-attribute-snapshot))))
  (plist-put bundle :prompt (satan-context--render-prompt assembled bundle)))

(defun satan-context--with-prepare (bundle prepare)
  "Mirror PREPARE's identity + percept + resonance + motive + sensor slots into BUNDLE.
Phase 1 acceptance A2 requires `bundle.json' and `percept.json' to
carry the same `:run_id' and `:time_now'.  Phase 2 extends the mirror
to `:resonance' so the rendered capsule block and the audited bundle
agree on what was injected (A4).  Phase 3 extends it again to
`:motive' — the parsed motives.org snapshot — so the §S3 block in
the capsule corresponds to a recorded artifact (A8 read-side, A9
ordering invariance).  Phase 4 extends it once more to
`:sensor_status' so the capsule's `# Sensors' line corresponds to
the freshness snapshot the assembler recorded (§S6)."
  (when (plistp prepare)
    (dolist (k '(:run_id :time_now :percept :resonance :motive :sensor_status))
      (setq bundle (plist-put bundle k (plist-get prepare k)))))
  bundle)

(defun satan-context-morning (mode-spec &optional run-ctx)
  "Bundle for the morning mode: prompt + today's note text.
RUN-CTX is the prepare-phase run_ctx plist (Phase 0.1) — when present,
its `:run_id' `:time_now' `:percept' slots are mirrored into the
bundle so audit artifacts agree (A2) and the capsule renders the
percept block."
  (let* ((today (satan-notes-today))
         (assembled (satan-context--assemble-prompt mode-spec))
         (bundle (list :prompt     ""
                       :mode       (plist-get mode-spec :name)
                       :now        (satan-context-now)
                       :today_path today
                       :today_text (satan-context--read-file-or-empty today))))
    (satan-context--finalize-prompt
     (satan-context--with-prepare bundle run-ctx) assembled)))

(defun satan-context-motd (mode-spec &optional run-ctx)
  "Bundle for the motd mode.
RUN-CTX is the prepare-phase run_ctx plist (Phase 0.1) — see
`satan-context-morning' for what gets threaded through."
  (let* ((assembled (satan-context--assemble-prompt mode-spec))
         (bundle (list :prompt ""
                       :mode   (plist-get mode-spec :name)
                       :now    (satan-context-now))))
    (satan-context--finalize-prompt
     (satan-context--with-prepare bundle run-ctx) assembled)))

(defun satan-context--recent-runs-for-spec (mode-spec)
  "Return the recent-runs entry list for MODE-SPEC, or nil when disabled."
  (let ((n (plist-get mode-spec :recent-runs)))
    (when (and (integerp n) (> n 0))
      (satan-trace-stage-optional "spawn.recent_runs"
        (satan-context--recent-runs n)))))

(defun satan-context-tick (mode-spec &optional run-ctx)
  "Bundle for a tick mode.  Same shape as motd, plus optional recent-runs.
RUN-CTX is the prepare-phase run_ctx plist (Phase 0.1); see
`satan-context-morning' for what gets threaded through."
  (let* ((assembled (satan-context--assemble-prompt mode-spec))
         (bundle (list :prompt       ""
                       :mode         (plist-get mode-spec :name)
                       :now          (satan-context-now)
                       :recent_runs  (satan-context--recent-runs-for-spec
                                      mode-spec))))
    (satan-context--finalize-prompt
     (satan-context--with-prepare bundle run-ctx) assembled)))

(defcustom satan-self-edit-mech-roots
  (list satan--root)
  "Roots whose source is included in the `self-edit-mech' bundle.
Mech = the broker / handlers / harness / tests — Emacs-side
machinery that runs the SATAN protocol."
  :type '(repeat directory) :group 'satan)

(defcustom satan-self-edit-mind-roots
  (list (expand-file-name "satan/prompts" satan-notes-root)
        (expand-file-name "satan/system"  satan-notes-root)
        (expand-file-name "satan/tools"   satan-notes-root))
  "Roots whose source is included in the `self-edit-mind' bundle.
Mind = mode prompts, the system scaffold, tool descriptions —
model-facing text under `~/notes/satan/' that shapes behaviour."
  :type '(repeat directory) :group 'satan)

(defcustom satan-self-edit-source-regexp
  "\\.\\(el\\|py\\|txt\\|md\\)\\'"
  "Regexp matching filenames included in self-edit bundles."
  :type 'regexp :group 'satan)

(defcustom satan-self-edit-exclude-regexp
  "\\(\\.elc\\'\\|\\.original\\.md\\'\\|/test/.*\\.\\(local\\|secret\\)\\.\\)"
  "Regexp matching files to skip in self-edit bundles."
  :type 'regexp :group 'satan)

(defcustom satan-self-edit-bundle-char-budget 600000
  "Maximum total character count for `:sources' in a self-edit bundle.
Roughly 1 token per 4 chars in English text + code, so the default
caps at ~150k input tokens — leaving ~50k headroom under typical
200k provider context windows for the tool schemas and the model's
own output.  Files are packed alphabetically until the budget is
exhausted; overflow lands in `:dropped-files' so the model sees
what it didn't get."
  :type 'integer :group 'satan)

(defun satan-context-self-edit--list-files (root)
  "Return absolute paths of source files under ROOT, sorted."
  (let ((all (and (file-directory-p root)
                  (directory-files-recursively
                   root satan-self-edit-source-regexp nil nil))))
    (sort (cl-remove-if
           (lambda (p)
             (string-match-p satan-self-edit-exclude-regexp p))
           all)
          #'string<)))

(defun satan-context-self-edit--pack-budgeted (files budget)
  "Pack FILES into a (sources . dropped) cons, capped at BUDGET chars.
SOURCES is a list of (:path ABBREVIATED :content STR); DROPPED is a
list of abbreviated paths that did not fit.  Greedy by alphabetical
order: keep until adding the next file would push total content
length over BUDGET.  Files larger than BUDGET themselves are skipped
into DROPPED rather than partially included (truncation is lossy
without context).  When BUDGET is nil, packs everything."
  (let ((spent 0) sources dropped)
    (dolist (f files)
      (let* ((content (satan-context--read-file-or-empty f))
             (len (length content))
             (path (abbreviate-file-name f)))
        (cond
         ((null budget)
          (push (list :path path :content content) sources)
          (setq spent (+ spent len)))
         ((<= (+ spent len) budget)
          (push (list :path path :content content) sources)
          (setq spent (+ spent len)))
         (t (push path dropped)))))
    (cons (nreverse sources) (nreverse dropped))))

(defun satan-context-self-edit (mode-spec &optional run-ctx)
  "Bundle for a self-edit mode: prompt + every source file under each
root in MODE-SPEC's `:source-roots' list, each as
\(:path ABBREVIATED :content STR).  Paths are abbreviated with `~/'
so the model sees `~/notes/satan/...' / `~/.emacs.d/satan/...' rather
than long relative dotwalks.

RUN-CTX is the prepare-phase run_ctx plist (Phase 0.1); see
`satan-context-morning' for what gets threaded through.

Total `:sources' content is capped by
`satan-self-edit-bundle-char-budget'; anything that didn't fit
lands in `:dropped-files' so the model can see what it's missing
and (e.g.) recommend a narrower mode or a targeted read."
  (let* ((roots (or (plist-get mode-spec :source-roots)
                    (let ((var (plist-get mode-spec :source-roots-var)))
                      (and (symbolp var) (boundp var) (symbol-value var)))))
         (files (cl-loop for root in roots
                         append (satan-context-self-edit--list-files root)))
         (packed (satan-context-self-edit--pack-budgeted
                  files satan-self-edit-bundle-char-budget))
         (sources (car packed))
         (dropped (cdr packed))
         (assembled (satan-context--assemble-prompt mode-spec))
         (bundle (list :prompt  ""
                       :mode    (plist-get mode-spec :name)
                       :now     (satan-context-now)
                       :roots   (mapcar #'abbreviate-file-name roots)
                       :sources sources
                       :dropped-files dropped)))
    (satan-context--finalize-prompt
     (satan-context--with-prepare bundle run-ctx) assembled)))

(defun satan-context-interactive (mode-spec &optional run-ctx)
  "Context-fn for the interactive MCP mode (DEC-13, Phase 4).
Builds the dynamic orientation capsule at build-depth β:
percept/resonance/motive/sensor_status/attributes rendered via
`satan-context--render-prompt' with an empty assembled string (no
persona scaffold — the system prompt is already in pi's SYSTEM.md).

RUN-CTX is the session's prepare plist (carries run_id, time_now).
The `# Now' block is stamped with a fresh `current-time', not the
frozen session time_now (F3).  Percept is built onto the run-dir
from the session prepare.

RUN-CTX is NOT mutated (AUD-008 F-004): a copy carries the fresh
time_now and the assembly keys, so the caller's session-frozen
time_now is preserved.

Gracefully degrades (AUD-008 F-003): if assembly fails (e.g. backend
unreachable), renders a partial capsule with `:percept' nil and a
`memory-unreachable' resonance rather than erroring the session.  This
is the single source of the interactive boot capsule — the MCP
boot-context tool delegates here.

Returns the bundle plist with `:prompt' set to the rendered text."
  (let* ((now-time (current-time))
         (run-id (plist-get run-ctx :run_id))
         ;; Resolve the session run directory from run-id
         (dir (satan-run-dir-for-id run-id))
         ;; Copy before mutating: fresh time for the # Now block (F3) must
         ;; not clobber the session's frozen time_now (AUD-008 F-004).
         (prepare (plist-put (copy-sequence run-ctx) :time_now
                             (format-time-string
                              satan-run--iso-time-format now-time)))
         ;; Build the dynamic blocks (percept/resonance/motive/sensor_status),
         ;; degrading to a partial capsule on backend failure.
         (prepare (condition-case _err
                      (satan-run-assemble-context prepare mode-spec dir)
                    (error
                     (plist-put
                      (plist-put prepare :percept nil)
                      :resonance (list :status 'memory-unreachable
                                       :cue nil :matches nil)))))
         (bundle (list :prompt     ""
                       :mode       (plist-get mode-spec :name)
                       :now        (satan-context-now now-time))))
    (satan-context--finalize-prompt
     (satan-context--with-prepare bundle prepare)
     "")))  ;; assembled="" — no persona, blocks only

(provide 'satan-context)
;;; satan-context.el ends here
