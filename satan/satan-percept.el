;;; satan-percept.el --- SATAN percept skeleton (Phase 1) -*- lexical-binding: t; -*-

;; Phase 1 of the perceptual-layer v0 (see docs/satan/perceptual-design.md
;; §S1, §7, §A1–A6).  Builds the percept capsule from the existing memory
;; substrate (evidence assembler + canonicalizer), persists a
;; deterministic `percept.json' next to `bundle.json', and renders a
;; compact handle block into the prompt capsule.
;;
;; Public surface:
;;   (satan-percept-build  PREPARE MODE &optional OPTS)  -> PLIST
;;   (satan-percept-persist DIR PERCEPT)                 -> PATH
;;   (satan-percept-render-block FRAMING PERCEPT)        -> LIST-OF-LINES
;;
;; PREPARE is the run_ctx plist allocated by `satan-broker--prepare'
;; (Phase 0.1): it carries the frozen `:run_id' + `:time_now' that back
;; every artifact written this run.  The percept is one of those
;; artifacts — A2 requires identical (`:run_id', `:time_now') across
;; `bundle.json' and `percept.json'.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-memory-canon)
(require 'satan-memory-evidence)
(require 'satan-memory-grammar)
(require 'satan-audit)

;; ---------------------------------------------------------------------
;; Build (impure: evidence assembly reads sensors + git)
;; ---------------------------------------------------------------------

(defun satan-percept--mode-name (mode)
  "Return MODE's `:name' as a string regardless of symbol/string storage."
  (let ((n (plist-get mode :name)))
    (cond ((stringp n) n)
          ((symbolp n) (symbol-name n))
          (t (format "%s" n)))))

(defun satan-percept--canon-ctx (prepare mode)
  "Return the canon ctx plist for PREPARE + MODE."
  (list :time_now (plist-get prepare :time_now)
        :run_id  (plist-get prepare :run_id)
        :mode_name (satan-percept--mode-name mode)
        :current_grammar_version satan-memory-grammar-current-version))

(defun satan-percept-build (prepare mode &optional opts)
  "Return the percept plist for PREPARE + MODE.
PREPARE is the broker--prepare run_ctx plist (Phase 0.1) — carries the
frozen `:run_id' and `:time_now'.  MODE is the resolved mode-spec.
OPTS forwards extra knobs to the evidence assembler (e.g.
`:behaviour_dir', `:cwd', `:bough_workspace') so tests can pin the
sensor surface.

Returned plist:
  :run_id          string  — from PREPARE.
  :time_now        string  — from PREPARE.
  :mode            string  — MODE name.
  :grammar_version int     — current canonical grammar.
  :evidence_window plist   — the assembled evidence (post-truncation).
  :handles         list    — canon's sorted handle strings.
  :handle_sources  list    — per-handle provenance, sorted by handle.

The canonicalizer is pure; the evidence assembler reads sensors, git,
and bough.  Re-running with the same frozen inputs is byte-identical
(A3) provided OPTS pin the sensor root."
  (let* ((ctx (satan-percept--canon-ctx prepare mode))
         (evidence (satan-memory-evidence-assemble ctx opts))
         (canon (satan-memory-canon-canonicalize evidence nil ctx)))
    (list :run_id (plist-get prepare :run_id)
          :time_now (plist-get prepare :time_now)
          :mode (plist-get ctx :mode_name)
          :grammar_version (plist-get ctx :current_grammar_version)
          :evidence_window evidence
          :handles (plist-get canon :handles)
          :handle_sources
          (satan-percept--sources-rows
           (plist-get canon :handles)
           (plist-get canon :handle_sources)))))

(defun satan-percept--sources-rows (handles sources-alist)
  "Convert canon's per-handle ALIST to a deterministic list of plists.
HANDLES drives iteration order so the output mirrors the (already
sorted) `:handles' list — JSON consumers can zip the two arrays."
  (mapcar
   (lambda (h)
     (let ((src (cdr (assoc h sources-alist))))
       (list :handle h
             :rule_id (plist-get src :rule_id)
             :origin (plist-get src :origin)
             :evidence_pointer (plist-get src :evidence_pointer)
             :hint_field (plist-get src :hint_field)
             :confidence (plist-get src :confidence)
             :grammar_version (plist-get src :grammar_version))))
   handles))

;; ---------------------------------------------------------------------
;; Persist
;; ---------------------------------------------------------------------

(defconst satan-percept--filename "percept.json"
  "Leaf name of the per-run percept artifact written by `--persist'.")

(defun satan-percept-persist (dir percept)
  "Write PERCEPT to `DIR/percept.json' atomically; return the path.
PERCEPT must carry `:run_id' and `:time_now' identical to the run's
`bundle.json' (acceptance A2 — checked by tests, not enforced here).
The write reuses `satan-audit--write-json' so encoding, atomicity,
and the canonical null/false sentinels match the rest of the audit
bundle."
  (unless (file-directory-p dir) (make-directory dir t))
  (let ((path (expand-file-name satan-percept--filename dir)))
    (satan-audit--write-json path percept)
    path))

;; ---------------------------------------------------------------------
;; Capsule render
;; ---------------------------------------------------------------------

(defconst satan-percept--framing-key "percept_block_header"
  "Framing.txt key that supplies the percept block's section header.
Owned by mind (`~/notes/satan/system/framing.txt'); dotfiles never
hardcode the header text — see governance §Mind/mechanism.")

(defun satan-percept-render-block (framing percept)
  "Return the rendered `# Percept' block as a list of lines, or nil.
FRAMING is the parsed framing alist (from
`satan-context--parse-framing').  PERCEPT is the build result.

A6 — only handles canon actually emitted are rendered; absence is
absence.  Empty handle lists yield nil so the renderer drops the
block entirely instead of emitting an empty header."
  (let ((handles (plist-get percept :handles))
        (header (cdr (assoc satan-percept--framing-key framing))))
    (when (and handles header)
      (cons header (mapcar (lambda (h) (concat "- " h)) handles)))))

;; ---------------------------------------------------------------------
;; Attention block — raw focus + browser segments from the evidence
;; window, rendered verbatim into the capsule.
;;
;; The handle block above is the *memory* view: closed-world, low-
;; cardinality canon tokens that persist as scars.  That deliberate
;; coarseness is wrong for live situational awareness — it can't say
;; which tab or terminal the user was actually on.  This block is the
;; *perceptual* view: it reads `evidence_window.{focus,browser}_segments'
;; (already captured with full url + title by panopticon, already
;; window-bounded + middle-truncated by the evidence assembler) and
;; renders them straight, no bucketing.  Memory stays disciplined; the
;; agent gets sight.
;; ---------------------------------------------------------------------

(defconst satan-percept--attention-framing-key "attention_block_header"
  "Framing.txt key supplying the attention block's section header.
Owned by mind (`~/notes/satan/system/framing.txt'); absent key
suppresses the block, same contract as `--framing-key'.")

(defcustom satan-percept-attention-limit 12
  "Max interleaved focus+browser segments rendered in the attention block.
The evidence assembler already caps each source; this bounds the merged
stream so a busy window can't blow the tick capsule budget."
  :type 'integer :group 'satan)

(defconst satan-percept--attention-title-max 80
  "Segment titles are truncated to this many characters in the block.")

(defconst satan-percept--attention-min-seconds 1
  "Segments shorter than this (seconds) are capture noise and dropped.
Sub-second focus/tab flickers — a window touched in passing — carry no
attention signal and only crowd the block.")

(defun satan-percept--attention-subsecond-p (seg)
  "Return non-nil when SEG's duration is below the noise floor."
  (< (or (plist-get seg :duration_s) 0)
     satan-percept--attention-min-seconds))

(defun satan-percept--format-duration (seconds)
  "Render SECONDS (a number) as a compact duration: `45s', `3m', `1h20m'."
  (let ((s (round (or seconds 0))))
    (cond ((< s 60) (format "%ds" s))
          ((< s 3600) (format "%dm" (round (/ s 60.0))))
          (t (format "%dh%dm" (/ s 3600) (round (/ (mod s 3600) 60.0)))))))

(defun satan-percept--attention-title (title)
  "Return TITLE truncated to `--attention-title-max' (ellipsis if cut),
or nil when TITLE is nil/empty."
  (when (and (stringp title) (not (string-empty-p title)))
    (if (> (length title) satan-percept--attention-title-max)
        (concat (substring title 0 satan-percept--attention-title-max) "…")
      title)))

(defun satan-percept--attention-focus-line (seg)
  "Render focus SEG as a line, or nil when its app is a browser.
Browser-app focus spans are dropped: the browser tab segments cover
them at per-URL grain, so a bare `firefox' focus line would be noise."
  (let ((app (plist-get seg :app_id)))
    (unless (equal "browser" (satan-memory-canon--app-surface app))
      (let ((ws (plist-get seg :workspace))
            (title (satan-percept--attention-title
                    (plist-get seg :last_title))))
        (concat (format "- %s  %s"
                        (satan-percept--format-duration
                         (plist-get seg :duration_s))
                        (or app "?"))
                (when ws (format "  ws%s" ws))
                (when title (format "  \"%s\"" title)))))))

(defun satan-percept--attention-browser-line (seg)
  "Render browser tab SEG as a line: duration, source, url, title."
  (let ((title (satan-percept--attention-title
                (plist-get seg :title_end))))
    (concat (format "- %s  %s  %s"
                    (satan-percept--format-duration
                     (plist-get seg :duration_s))
                    (or (plist-get seg :source) "browser")
                    (or (plist-get seg :url) (plist-get seg :domain) "?"))
            (when title (format "  \"%s\"" title)))))

(defun satan-percept-render-attention-block (framing percept)
  "Return the `# Recent attention' block as a list of lines, or nil.
FRAMING is the parsed framing alist; PERCEPT is the build result.

Interleaves PERCEPT's `evidence_window' focus + browser segments by
`:start_ts' (ascending — a timeline), keeps the most recent
`satan-percept-attention-limit', and renders each verbatim (url +
title).  Browser-app focus segments are dropped (see
`--attention-focus-line').  Returns nil when the header is absent
(mind owns it) or no segment survives — absence is absence."
  (let ((header (cdr (assoc satan-percept--attention-framing-key framing)))
        (ev (plist-get percept :evidence_window)))
    (when (and header ev)
      (let* ((focus (cl-remove-if #'satan-percept--attention-subsecond-p
                                  (plist-get ev :focus_segments)))
             (browser (cl-remove-if #'satan-percept--attention-subsecond-p
                                    (plist-get ev :browser_segments)))
             (rows
              (append
               (delq nil
                     (mapcar
                      (lambda (s)
                        (let ((line (satan-percept--attention-focus-line s)))
                          (and line (cons (plist-get s :start_ts) line))))
                      focus))
               (mapcar
                (lambda (s)
                  (cons (plist-get s :start_ts)
                        (satan-percept--attention-browser-line s)))
                browser)))
             (sorted (sort rows (lambda (a b)
                                  (string< (or (car a) "") (or (car b) "")))))
             (capped (last sorted satan-percept-attention-limit)))
        (when capped
          (cons header (mapcar #'cdr capped)))))))

(provide 'satan-percept)
;;; satan-percept.el ends here
