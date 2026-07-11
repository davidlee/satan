;;; satan-motive.el --- SATAN motive file parser (Phase 3) -*- lexical-binding: t; -*-

;; Phase 3 of the perceptual-layer v0 (see docs/satan/perceptual-design.md
;; §S3, §S4, §7, §A7–A9).  Parses `motives.org' — a single, bounded,
;; user-and-SATAN-editable prose file at `~/notes/satan/motives.org' —
;; into the structured shape the capsule renderer and the
;; `motive_replace' write-side guard both consume.
;;
;; Public surface:
;;   (satan-motive-parse  TEXT)         -> PLIST
;;   (satan-motive-read   PATH)         -> PLIST  (silent on missing)
;;   (satan-motive-render-block FRAMING PARSED) -> LIST-OF-LINES
;;   (satan-motive-validate-for-write TEXT)     -> PLIST or nil
;;
;; Footer schema (per §S3):
;;   :cue:                   REQUIRED for active motives.  Space-separated
;;                           canonical handle strings.  Each must match
;;                           the canon handle regex AND at least one must
;;                           sit in an admitted (sensor-observed)
;;                           namespace.  Missing/invalid -> dormant.
;;   :cooldown_s:            integer seconds.
;;   :worked_count:          integer; informational only (A9).
;;   :last_intervention_at:  ISO8601.
;;   :project_cwd:           absolute path (or `~/...').  Optional;
;;                           consumed by the Phase-5 observer to scope
;;                           its positive-signal predicate.  Absent ->
;;                           motive remains correlatable by handle
;;                           overlap, but path-scoped sub-predicates
;;                           (file edits, git ref) do not fire for it.
;;                           Capsule renderer omits this field.
;;
;; `:ceiling:' is NOT a v0 field — the parser flags it and the
;; write-side guard rejects it (A8).
;;
;; Bounds (Phase 3.4, A7):
;;   ≤ 3 active motives
;;   ≤ 10 rumination lines
;;
;; Missing file -> empty parse (silent self-suppression, matches the
;; resonance pattern §S2; see handover watch-out).

(require 'cl-lib)
(require 'subr-x)
(require 'satan-custom)

;; ---------------------------------------------------------------------
;; Paths (mind-side files; defcustoms live with the substrate module so
;; the broker can `require 'satan-motive' and read them without
;; pulling the tool-handler layer in too).
;; ---------------------------------------------------------------------

(defcustom satan-motive-file
  (expand-file-name "satan/motives.org" satan-notes-root)
  "Path to the SATAN motive file.
Mind owns the content; the broker reads on every tick and the
`motive_replace' tool writes atomically.  Missing file is a valid
state — the capsule omits the block and the model sees zero
active motives in the `motive_read' summary."
  :type 'file :group 'satan)

(defcustom satan-motive-archive-file
  (expand-file-name "satan/motives.archive.org" satan-notes-root)
  "Append-only archive companion to `satan-motive-file'.
Not auto-written in v0 — the author moves text here by hand when
retiring a motive.  Reserved for a future archive helper."
  :type 'file :group 'satan)

;; ---------------------------------------------------------------------
;; Constants
;; ---------------------------------------------------------------------

(defconst satan-motive-max-active 3
  "Hard cap on active motives (§S3 / A7).")

(defconst satan-motive-max-ruminations 10
  "Hard cap on rumination lines (§S3 / A7).")

(defconst satan-motive--handle-regexp
  "\\`[a-z][a-z0-9_]*:[A-Za-z0-9][A-Za-z0-9_.+>-]*\\'"
  "Canon handle regex (mirrors `satan-memory-canon--validate-emission').
A motive `:cue:' entry that does not match is rejected.")

(defconst satan-motive--admitted-namespaces
  '("app" "surface" "surface_transition" "domain_kind" "domain_transition"
    "bough_event" "bough_node" "bough_project" "artifact"
    "topic" "phase" "focal_app")
  "Namespaces that count as sensor-observed for §S3 admission.
Parallel of the §S2 resonance gate by namespace prefix (the gate looks
at canon rule_id provenance; the motive cue is static text so we
inspect the handle's leading namespace directly).  Without ≥1 handle
from this set a motive triggers on every tick — defeats the cooldown
floor.")

(defconst satan-motive--ruminations-heading "ruminations"
  "Top-level org heading that holds rumination lines (case-folded).")

(defconst satan-motive--ceiling-field "ceiling"
  "Forbidden v0 footer field; §3 deferred (ladder design v1).")

;; ---------------------------------------------------------------------
;; Parser
;; ---------------------------------------------------------------------

(defun satan-motive--split-sections (text)
  "Return alist of (HEADING . LINES) for TEXT.
HEADING is the org heading string (text after `* '); LINES is the
list of body lines under it, in order.  Lines before any heading
are dropped.  Both HEADING and LINES are unmodified (no trim) so
the caller can preserve user formatting where it matters."
  (let ((cur-head nil) (cur-lines nil) (acc nil))
    (dolist (line (split-string text "\n"))
      (cond
       ((string-match "\\`\\* +\\(.+?\\)\\s-*\\'" line)
        (when cur-head
          (push (cons cur-head (nreverse cur-lines)) acc))
        (setq cur-head (match-string 1 line)
              cur-lines nil))
       (cur-head
        (push line cur-lines))))
    (when cur-head
      (push (cons cur-head (nreverse cur-lines)) acc))
    (nreverse acc)))

(defun satan-motive--parse-footer-line (line)
  "Return (KEY . VALUE) if LINE is `  :key: value', else nil.
KEY is a downcased string without the colons; VALUE is the trimmed
remainder (may be empty)."
  (when (string-match "\\`[ \t]*:\\([A-Za-z_][A-Za-z0-9_]*\\):\\(?:[ \t]+\\(.*\\)\\)?\\s-*\\'" line)
    (cons (downcase (match-string 1 line))
          (string-trim (or (match-string 2 line) "")))))

(defun satan-motive--parse-cue (raw)
  "Return list of handle strings parsed from RAW.
RAW is the `:cue:' footer value: space-separated tokens.  Empty input
returns nil."
  (when (and (stringp raw) (not (string-empty-p (string-trim raw))))
    (split-string raw "[ \t]+" t)))

(defun satan-motive--cue-handles-well-formed-p (handles)
  "Return non-nil when every handle in HANDLES matches the canon regex."
  (and handles
       (cl-every (lambda (h)
                   (and (stringp h)
                        (string-match-p satan-motive--handle-regexp h)))
                 handles)))

(defun satan-motive--cue-admittable-p (handles)
  "Return non-nil when ≥1 handle's namespace is admitted (§S3).
Parallel of `satan-resonance--admittable-p' but inspects the
handle's leading `namespace:' prefix rather than canon rule_id (motive
cues are static text — no provenance row exists)."
  (cl-some (lambda (h)
             (when (and (stringp h) (string-match "\\`\\([a-z][a-z0-9_]*\\):" h))
               (member (match-string 1 h)
                       satan-motive--admitted-namespaces)))
           handles))

(defun satan-motive--motive-id (heading)
  "Return the motive id parsed from HEADING.
Org subheaders may carry a `kind: id' prefix (e.g. `test: docs-after-
error') — we keep the id half.  Falls back to the trimmed heading
when no colon is present."
  (let ((trimmed (string-trim heading)))
    (if (string-match "\\`[^:]+:\\s-*\\(.+?\\)\\s-*\\'" trimmed)
        (match-string 1 trimmed)
      trimmed)))

(defun satan-motive--parse-integer (raw)
  "Return RAW parsed as integer, or nil if not parseable."
  (when (and (stringp raw)
             (string-match-p "\\`-?[0-9]+\\'" (string-trim raw)))
    (string-to-number (string-trim raw))))

(defun satan-motive--parse-motive (heading lines)
  "Parse a single motive section into a motive plist.
HEADING is the org heading (without leading `* '); LINES is the body."
  (let ((id (satan-motive--motive-id heading))
        (prose-lines nil)
        (cue nil) (cue-raw nil)
        (cooldown nil) (worked 0)
        (last-at nil)
        (project-cwd nil)
        (ceiling-flagged nil)
        (in-footer nil))
    (dolist (raw-line lines)
      (let ((field (satan-motive--parse-footer-line raw-line)))
        (cond
         (field
          (setq in-footer t)
          (pcase (car field)
            ("cue"
             (setq cue-raw (cdr field)
                   cue (satan-motive--parse-cue (cdr field))))
            ("cooldown_s"
             (setq cooldown (satan-motive--parse-integer (cdr field))))
            ("worked_count"
             (setq worked (or (satan-motive--parse-integer (cdr field)) 0)))
            ("last_intervention_at"
             (setq last-at (and (not (string-empty-p (cdr field)))
                                (cdr field))))
            ("project_cwd"
             ;; Phase 5.0 — observer scopes its positive predicate to
             ;; files under this cwd.  Expanded at parse so callers see
             ;; an absolute path; empty values normalise to nil.
             (setq project-cwd
                   (and (not (string-empty-p (cdr field)))
                        (expand-file-name (cdr field)))))
            ((pred (equal satan-motive--ceiling-field))
             (setq ceiling-flagged t))))
         ((not in-footer)
          (push raw-line prose-lines)))))
    (let* ((prose (string-trim
                   (mapconcat #'identity (nreverse prose-lines) "\n")))
           (well-formed (satan-motive--cue-handles-well-formed-p cue))
           (admittable (and well-formed
                            (satan-motive--cue-admittable-p cue)))
           (dormant-reason
            (cond
             ((null cue) :missing-cue)
             ((not well-formed) :malformed-cue)
             ((not admittable) :no-sensor-handle)))
           (dormant (and dormant-reason t)))
      (list :id id
            :heading heading
            :prose prose
            :cue cue
            :cue_raw cue-raw
            :cooldown_s cooldown
            :worked_count worked
            :last_intervention_at last-at
            :project_cwd project-cwd
            :dormant dormant
            :dormant_reason dormant-reason
            :ceiling_field ceiling-flagged))))

(defun satan-motive--parse-ruminations (lines)
  "Return list of rumination entry strings parsed from LINES.
Each entry is the trimmed body after a `-' bullet; empty/non-bullet
lines are dropped."
  (let (acc)
    (dolist (line lines)
      (when (string-match "\\`[ \t]*-[ \t]+\\(.+?\\)[ \t]*\\'" line)
        (push (match-string 1 line) acc)))
    (nreverse acc)))

(defun satan-motive-parse (text)
  "Parse motives.org TEXT.  Return a parse plist.

Shape:
  :motives      list of motive plists in file order.
  :ruminations  list of rumination body strings.
  :errors       list of `(:kind SYM :motive ID :detail STR)` describing
                schema violations (e.g. forbidden `:ceiling:` field).
                Parse never signals on bad fields; the renderer suppresses
                dormant motives and the write-side guard converts errors
                into the §A7 / §A8 structured-error response.

Behaviour:
  - A motive section is identified by an org top-level heading.
  - One heading whose body (case-fold) equals `ruminations' becomes
    the ruminations section; everything else is treated as a motive.
  - Prose before the first `:field:' line is captured verbatim; the
    footer is the run of `:field:' lines after it.
  - A motive without a valid `:cue:' is parsed as dormant (per §S3 —
    file-tolerated, capsule-invisible, observer-skipped)."
  (let ((sections (satan-motive--split-sections (or text "")))
        motives ruminations errors)
    (dolist (cell sections)
      (let* ((heading (car cell))
             (lines (cdr cell)))
        (if (equal (downcase (string-trim heading))
                   satan-motive--ruminations-heading)
            (setq ruminations (satan-motive--parse-ruminations lines))
          (let ((m (satan-motive--parse-motive heading lines)))
            (when (plist-get m :ceiling_field)
              (push (list :kind :forbidden-field
                          :motive (plist-get m :id)
                          :detail ":ceiling: is not a v0 field")
                    errors))
            (push m motives)))))
    (list :motives (nreverse motives)
          :ruminations ruminations
          :errors (nreverse errors))))

;; ---------------------------------------------------------------------
;; File I/O
;; ---------------------------------------------------------------------

(defun satan-motive-read (path)
  "Return the parse of PATH.
Missing or unreadable PATH yields an empty parse (silent self-
suppression — the missing-file path is a valid run state per §S3 and
the handover watch-out)."
  (if (and path (file-readable-p path))
      (satan-motive-parse
       (with-temp-buffer
         (let ((coding-system-for-read 'utf-8))
           (insert-file-contents path))
         (buffer-string)))
    (list :motives nil :ruminations nil :errors nil)))

;; ---------------------------------------------------------------------
;; Capsule render
;; ---------------------------------------------------------------------

(defconst satan-motive--framing-key "motive_block_header"
  "Framing.txt key supplying the motive block's section header.
Mind owns the text under `~/notes/satan/system/framing.txt'; elisp
never hardcodes the header (governance §Mind/mechanism).")

(defun satan-motive--active-motives (parsed)
  "Return PARSED's motives filtered to non-dormant entries."
  (cl-remove-if (lambda (m) (plist-get m :dormant))
                (plist-get parsed :motives)))

(defun satan-motive--cooling-down-remaining (motive now-t)
  "Return remaining cooldown seconds (positive number) when MOTIVE's
floor has not yet elapsed at NOW-T, else nil.

NOW-T is an emacs time value.  Returns nil when MOTIVE lacks a positive
`:cooldown_s', lacks `:last_intervention_at', the timestamp fails to
parse, or the window has already elapsed (motive is actionable)."
  (let ((cooldown (plist-get motive :cooldown_s))
        (last-at  (plist-get motive :last_intervention_at)))
    (when (and (integerp cooldown)
               (> cooldown 0)
               (stringp last-at)
               (not (string-empty-p last-at)))
      (let ((last-t (condition-case _ (date-to-time last-at) (error nil))))
        (when last-t
          (let ((remaining (- cooldown
                              (float-time (time-subtract now-t last-t)))))
            (when (> remaining 0) remaining)))))))

(defun satan-motive--coerce-time (now)
  "Coerce NOW (nil / ISO string / emacs time value) to an emacs time
value or nil.  Malformed ISO strings yield nil (caller treats as
\"no cooldown check\")."
  (cond
   ((null now) nil)
   ((stringp now) (condition-case _ (date-to-time now) (error nil)))
   (t now)))

(defun satan-motive-render-block (framing parsed &optional now)
  "Return the rendered `# Motive' block as a list of lines, or nil.
FRAMING is the parsed framing alist; PARSED is `satan-motive-parse'
output.  Returns nil when no active motive is present (block self-
suppresses — capsule placement is between resonance and today per §S1).

NOW is the frozen tick time (ISO string or emacs time value).  When
supplied, motives whose `(now - :last_intervention_at) < :cooldown_s'
are annotated `cooling-down (Nm remaining)' on their `## id' header
per §S4 (Phase 6 cooldown floor).  Nil NOW disables the check.

Each motive renders as:

  ## <id>[  [cooling-down (Nm remaining)]]
    <prose-first-line>
    cue: handle1 handle2 …
    cooldown_s: N  worked_count: N  last_intervention_at: ISO

`:worked_count:' is exposed (A9 — informational, observable) but does
not influence ordering: motives render in file order."
  (let ((header  (cdr (assoc satan-motive--framing-key framing)))
        (actives (satan-motive--active-motives parsed))
        (now-t   (satan-motive--coerce-time now)))
    (when (and header actives)
      (let ((lines (list header)))
        (dolist (m actives)
          (let* ((remaining (and now-t
                                 (satan-motive--cooling-down-remaining
                                  m now-t)))
                 (suffix (if remaining
                             (format "  [cooling-down (%dm remaining)]"
                                     (ceiling (/ remaining 60.0)))
                           "")))
            (push (format "## %s%s" (plist-get m :id) suffix) lines))
          (let ((prose (plist-get m :prose)))
            (unless (string-empty-p prose)
              (dolist (pline (split-string prose "\n"))
                (let ((trimmed (string-trim pline)))
                  (unless (string-empty-p trimmed)
                    (push (concat "  " trimmed) lines))))))
          (push (concat "  cue: "
                        (mapconcat #'identity (plist-get m :cue) " "))
                lines)
          (push (format "  cooldown_s: %s  worked_count: %s%s"
                        (or (plist-get m :cooldown_s) "?")
                        (plist-get m :worked_count)
                        (if (plist-get m :last_intervention_at)
                            (format "  last_intervention_at: %s"
                                    (plist-get m :last_intervention_at))
                          ""))
                lines))
        (nreverse lines)))))

;; ---------------------------------------------------------------------
;; Write-side guard (Phase 3.4 / A7 / A8)
;; ---------------------------------------------------------------------

(defconst satan-motive-bound-precedence
  '(:forbidden-field :too-many-active :too-many-ruminations :invalid-cue)
  "Order in which `satan-motive-validate-for-write' reports breaches.
Document-visible precedence: the first breach in this list wins when
a payload trips more than one (A7 — caller sees one actionable error
per turn).  Forbidden-field beats count caps so the author can't hide
a `:ceiling:' inside an already-bloated file; count caps beat
per-motive `:cue:' validity so author trims first, fixes second.")

(defun satan-motive-validate-for-write (text)
  "Validate TEXT (a proposed motives.org replacement).
Return nil when acceptable, else a structured-error plist:

  (:bound :too-many-active     :limit N :got K)
  (:bound :too-many-ruminations :limit N :got K)
  (:bound :forbidden-field      :motive ID :field STR)
  (:bound :invalid-cue          :motive ID :reason SYM)

The motive_replace handler maps this onto a `(error . MSG)` tool
result.  Precedence is `satan-motive-bound-precedence' — the
first breach in that order wins so the caller sees one actionable
error per turn (A7)."
  (let* ((parsed (satan-motive-parse text))
         (motives (plist-get parsed :motives))
         (actives (satan-motive--active-motives parsed))
         (ruminations (plist-get parsed :ruminations))
         (parse-errors (plist-get parsed :errors)))
    (or
     (let ((forbidden (cl-find :forbidden-field parse-errors
                               :key (lambda (e) (plist-get e :kind)))))
       (when forbidden
         (list :bound :forbidden-field
               :motive (plist-get forbidden :motive)
               :field satan-motive--ceiling-field)))
     (when (> (length actives) satan-motive-max-active)
       (list :bound :too-many-active
             :limit satan-motive-max-active
             :got (length actives)))
     (when (> (length ruminations) satan-motive-max-ruminations)
       (list :bound :too-many-ruminations
             :limit satan-motive-max-ruminations
             :got (length ruminations)))
     (cl-some (lambda (m)
                (when (plist-get m :dormant_reason)
                  ;; Active-on-paper motives with a bad cue are the
                  ;; write-side failure case the author needs to see
                  ;; (A8).  A motive that's *intended* dormant has no
                  ;; cue at all (`:missing-cue'); we accept that.
                  (unless (eq (plist-get m :dormant_reason) :missing-cue)
                    (list :bound :invalid-cue
                          :motive (plist-get m :id)
                          :reason (plist-get m :dormant_reason)))))
              motives))))

(defun satan-motive-format-write-error (err)
  "Format a `validate-for-write' ERR plist as a short message.
Used by the tool handler to ship one line back through the
`tool_result' error channel."
  (pcase (plist-get err :bound)
    (:forbidden-field
     (format "motive `%s' uses forbidden field `:%s:' (not a v0 field)"
             (plist-get err :motive) (plist-get err :field)))
    (:too-many-active
     (format "too many active motives: limit %d, got %d"
             (plist-get err :limit) (plist-get err :got)))
    (:too-many-ruminations
     (format "too many rumination lines: limit %d, got %d"
             (plist-get err :limit) (plist-get err :got)))
    (:invalid-cue
     (format "motive `%s' has invalid :cue: (%s)"
             (plist-get err :motive)
             (pcase (plist-get err :reason)
               (:malformed-cue "handle does not match canon regex")
               (:no-sensor-handle
                "no sensor-observed handle (≥1 of app/surface/bough/topic required)")
               (other (format "%s" other)))))
    (other (format "motive validation failed: %s" other))))

;; ---------------------------------------------------------------------
;; Footer rewriter (Phase 5.5)
;;
;; Observer correlates an intervention to a motive (5.4 + 5.7), then
;; the broker (5.6+5.8) credits the motive by bumping
;; `:worked_count:' and stamping `:last_intervention_at:'.  The
;; rewriter is text-level: it edits the footer fields in place and
;; preserves prose, ruminations, other footer fields, indentation,
;; and section ordering verbatim.  Re-rendering through the parser
;; would lose all of those.
;; ---------------------------------------------------------------------

(defun satan-motive--heading-id-from-line (line)
  "Return the motive id when LINE is a `* HEADING'; else nil."
  (when (string-match "\\`\\* +\\(.+?\\)[ \t]*\\'" line)
    (satan-motive--motive-id (match-string 1 line))))

(defun satan-motive--section-bounds (buf id)
  "Return `(START . END)' char positions for motive ID's section in BUF.
START is the BOL of the section's heading; END is the BOL of the
next `* ' heading or `point-max'.  Returns nil when no section
matches.  ID is the motive identifier as `--motive-id' parses it."
  (with-current-buffer buf
    (save-excursion
      (goto-char (point-min))
      (let (start)
        (while (and (null start)
                    (re-search-forward "^\\* +\\(.+?\\)[ \t]*$" nil t))
          (when (equal (satan-motive--motive-id (match-string 1)) id)
            (setq start (line-beginning-position))))
        (when start
          (goto-char start)
          (forward-line 1)
          (let ((end (if (re-search-forward "^\\* " nil t)
                         (line-beginning-position)
                       (point-max))))
            (cons start end)))))))

(defun satan-motive--rewrite-section-footer
    (buf section-start section-end worked-count last-at)
  "Rewrite footer fields in BUF's [SECTION-START, SECTION-END).
Sets `:worked_count:' = WORKED-COUNT and `:last_intervention_at:'
= LAST-AT.  Existing lines are replaced (indentation + spacing
preserved on the key/colon prefix; only the value changes).
Missing lines are appended after the last existing footer line
(or at section end when no footer exists).  Returns nothing
useful — mutation is in BUF."
  (with-current-buffer buf
    (let ((end-marker (copy-marker section-end nil))
          (last-footer-marker nil)
          (wc-set nil)
          (la-set nil))
      (save-excursion
        (goto-char section-start)
        (forward-line 1)  ; past heading
        (while (< (point) end-marker)
          (cond
           ((and (not wc-set)
                 (looking-at "^\\([ \t]*\\):worked_count:\\(.*\\)$"))
            (replace-match
             (format "\\1:worked_count: %d" worked-count)
             nil nil)
            (setq wc-set t
                  last-footer-marker (copy-marker (line-end-position))))
           ((and (not la-set)
                 (looking-at "^\\([ \t]*\\):last_intervention_at:\\(.*\\)$"))
            (replace-match
             (format "\\1:last_intervention_at: %s" last-at)
             nil nil)
            (setq la-set t
                  last-footer-marker (copy-marker (line-end-position))))
           ((looking-at "^[ \t]*:[A-Za-z_][A-Za-z0-9_]*:")
            ;; Some other footer line — track for insert position.
            (setq last-footer-marker (copy-marker (line-end-position)))))
          (forward-line 1)))
      ;; Append any missing fields.
      (when (or (not wc-set) (not la-set))
        (cond
         (last-footer-marker
          (goto-char last-footer-marker)
          (unless wc-set
            (insert (format "\n:worked_count: %d" worked-count)))
          (unless la-set
            (insert (format "\n:last_intervention_at: %s" last-at))))
         (t
          ;; No footer line existed at all (rare — active motives
          ;; require `:cue:' so an active motive always has ≥1 footer).
          ;; Insert at the very end of the section content, leaving the
          ;; trailing newline between this section and the next intact.
          (goto-char end-marker)
          (if (= (point) (point-min))
              ;; Empty buffer — shouldn't happen since we found a
              ;; heading, but defensive.
              (progn
                (unless wc-set
                  (insert (format ":worked_count: %d\n" worked-count)))
                (unless la-set
                  (insert (format ":last_intervention_at: %s\n" last-at))))
            (backward-char 1)
            (unless wc-set
              (insert (format "\n:worked_count: %d" worked-count)))
            (unless la-set
              (insert (format "\n:last_intervention_at: %s" last-at))))))))))

(defun satan-motive--write-atomic (path text)
  "Atomically replace PATH's contents with TEXT.
Writes to PATH.tmp + rename; ensures parent dir exists; uses utf-8."
  (let ((dir (file-name-directory path)))
    (unless (file-directory-p dir) (make-directory dir t)))
  (let ((tmp (concat path ".tmp"))
        (coding-system-for-write 'utf-8))
    (with-temp-file tmp (insert text))
    (rename-file tmp path t)))

(defun satan-motive-touch-footer (id worked-count last-at &optional path)
  "Rewrite PATH so motive ID's footer carries WORKED-COUNT + LAST-AT.
WORKED-COUNT is an integer (absolute, not delta — caller computes
old+1 from `satan-motive-parse').  LAST-AT is an ISO8601 string.
PATH defaults to `satan-motive-file'.

Text-level mutation: prose, ruminations, other footer fields,
ordering, and indentation are preserved verbatim.  Existing
`:worked_count:' / `:last_intervention_at:' lines are replaced in
place; missing lines are appended after the section's last
footer line (or at section end when no footer exists).

Atomic: tmp file + rename.  Returns t when ID matched a section,
nil when PATH is missing/unreadable or ID didn't match."
  (let ((path (or path satan-motive-file)))
    (when (and path (file-readable-p path))
      (with-temp-buffer
        (let ((coding-system-for-read 'utf-8))
          (insert-file-contents path))
        (let ((bounds (satan-motive--section-bounds (current-buffer) id)))
          (when bounds
            (satan-motive--rewrite-section-footer
             (current-buffer) (car bounds) (cdr bounds)
             worked-count last-at)
            (satan-motive--write-atomic path (buffer-string))
            t))))))

(provide 'satan-motive)
;;; satan-motive.el ends here
