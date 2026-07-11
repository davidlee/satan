;;; satan-resonance.el --- SATAN auto-resonance (Phase 2) -*- lexical-binding: t; -*-

;; Phase 2 of the perceptual-layer v0 (see docs/satan/perceptual-design.md
;; §S2, §7, §A4–A5).  Derives a cue from the run's percept, applies the
;; §S2 anti-generic-recall gate, calls `memory_resonate', and returns a
;; resonance plist the broker attaches to the run_ctx.
;;
;; Public surface:
;;   (satan-resonance-derive PERCEPT &optional OPTS)   -> PLIST or nil
;;   (satan-resonance-render-block FRAMING RESONANCE)  -> LIST-OF-LINES
;;
;; PERCEPT is the plist returned by `satan-percept-build' — supplies
;; the cue handles and per-handle `:rule_id' provenance the gate reads.
;;
;; The §S2 gate excludes cues that contain ONLY ctx-derived handles
;; (`mode:*' from `ctx.mode'; `day:*' / `week:*' from `time.day_week';
;; `project:*' from `cwd.project'; `file_kind:*' from `cwd.file_kind').
;; At least one handle from a non-excluded rule must be present — those
;; are the sensor-observed signals (panopticon, bough, hints, artifact).
;; Without that bar resonance retrieves generic moments and drowns the
;; capsule in low-signal recall (§S2 rationale).
;;
;; A4 — the capsule renders a resonance block IFF (i) gate passes,
;;       (ii) memory reachable, (iii) ≥1 match returned.  The status
;;       slot on the result plist carries the failing condition so
;;       audit consumers can tell `gate-skip' apart from `psql-down'.
;; A5 — gate exclusion list is closed (the four rule_ids below); a
;;       fixture asserts every combination of only-excluded handles
;;       fails to admit.

(require 'cl-lib)
(require 'subr-x)
(require 'satan-memory-store)

(defconst satan-resonance--excluded-rule-ids
  '("ctx.mode" "time.day_week" "cwd.project" "cwd.file_kind")
  "Canon rule ids whose handles do NOT count toward §S2 admission.
A cue with handles from these rules only is too generic to retrieve
useful recurrence — every prior moment matches `day:*' / `mode:*' /
`project:emacs.d' when the user always works in this repo (§S2).
Sensor-observed rules (panopticon.*, bough.*, hint.*) are everything
else and admit the cue automatically.")

(defconst satan-resonance--default-limit 3
  "Max matches injected into the capsule per tick (design §S2: top 1–3).")

(defun satan-resonance--admittable-p (sources)
  "Return non-nil when SOURCES (per-handle rows from percept) contain
at least one handle whose `:rule_id' is NOT in the §S2 exclude list.
That handle is what makes the cue worth resonating on."
  (cl-some (lambda (row)
             (not (member (plist-get row :rule_id)
                          satan-resonance--excluded-rule-ids)))
           sources))

(defun satan-resonance-derive (percept &optional opts)
  "Return the resonance result plist for PERCEPT, or nil to omit the block.
PERCEPT is the build result from `satan-percept-build'.  OPTS forwards
test knobs:
  :limit          int        — cap on matches (default 3)
  :store-resonate function   — stub for tests (called with :cue-handles …)

Result plist shape:
  :status   symbol  — `ok' / `gate-skip' / `memory-unreachable' / `no-match'
  :cue      list    — handles passed to the store (gate-admit case only)
  :matches  list    — store rows, each
                      `(:trace_id :score :matched_handles :payload)';
                      `:payload' rides through verbatim to the renderer

The renderer only emits a block when `:status' is `ok' (A4); the other
statuses are present so audit can see why a tick produced no block.
Memory errors return `memory-unreachable' rather than signalling: a
psql blip should not fail the run (handover watch-out)."
  (let* ((handles (plist-get percept :handles))
         (sources (plist-get percept :handle_sources))
         (limit (or (plist-get opts :limit)
                    satan-resonance--default-limit))
         (call (or (plist-get opts :store-resonate)
                   #'satan-memory-store-resonate)))
    (cond
     ((or (null handles) (null sources))
      (list :status 'gate-skip :cue nil :matches nil))
     ((not (satan-resonance--admittable-p sources))
      (list :status 'gate-skip :cue handles :matches nil))
     (t
      (pcase (funcall call :cue-handles handles :limit limit)
        (`(ok . ,matches)
         (list :status (if matches 'ok 'no-match)
               :cue handles
               :matches matches))
        (`(error . ,_)
         (list :status 'memory-unreachable :cue handles :matches nil))
        ;; Defensive: any other shape (shouldn't happen with the
        ;; current store API) is treated as unreachable so the run
        ;; proceeds without resonance.
        (_ (list :status 'memory-unreachable :cue handles :matches nil)))))))

;; ---------------------------------------------------------------------
;; Capsule render
;; ---------------------------------------------------------------------

(defconst satan-resonance--framing-key "resonance_block_header"
  "Framing.txt key supplying the resonance block's section header.
Mind owns the text under `~/notes/satan/system/framing.txt'; elisp
never hardcodes the header (governance §Mind/mechanism).")

(defconst satan-resonance--payload-max 120
  "Recalled payload text is truncated to this many characters in the block.
Bounds one match's third line so a long payload can't blow the tick
capsule budget (mirrors `satan-percept--attention-title-max').")

(defun satan-resonance--payload-line (payload)
  "Return the indented, quoted payload line for PAYLOAD, or nil.
Nil/empty PAYLOAD self-suppresses the line.  Over-long PAYLOAD is
truncated with an ellipsis to `--payload-max'."
  (when (and (stringp payload) (not (string-empty-p payload)))
    (let ((text (if (> (length payload) satan-resonance--payload-max)
                    (concat (substring payload 0 satan-resonance--payload-max)
                            "…")
                  payload)))
      (format "    \"%s\"" text))))

(defun satan-resonance--score-format (score)
  "Format SCORE like the design's `score N.N' example.
Falls back to a printf `%g' when SCORE is non-numeric — defensive
against a future store shape change."
  (if (numberp score)
      (format "%.1f" score)
    (format "%s" score)))

(defun satan-resonance-render-block (framing resonance)
  "Return the rendered `# Resonance' block as a list of lines, or nil.
FRAMING is the parsed framing alist; RESONANCE is the derive result.
Returns nil unless `:status' is `ok' and at least one match is present
(A4).  Shape per design §S2:

  # Resonance
  - <trace_id>  score N.N
      matched: handle1, handle2, …
      \"<recalled payload text>\"

The payload line self-suppresses when the match carries no payload."
  (let ((header (cdr (assoc satan-resonance--framing-key framing)))
        (status (plist-get resonance :status))
        (matches (plist-get resonance :matches)))
    (when (and header (eq status 'ok) matches)
      (let ((lines (list header)))
        (dolist (m matches)
          (push (format "- %s  score %s"
                        (plist-get m :trace_id)
                        (satan-resonance--score-format
                         (plist-get m :score)))
                lines)
          (push (concat "    matched: "
                        (mapconcat #'identity
                                   (plist-get m :matched_handles)
                                   ", "))
                lines)
          (let ((payload-line (satan-resonance--payload-line
                               (plist-get m :payload))))
            (when payload-line (push payload-line lines))))
        (nreverse lines)))))

(provide 'satan-resonance)
;;; satan-resonance.el ends here
