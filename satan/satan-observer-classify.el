;;; satan-observer-classify.el --- SATAN outcome classifier -*- lexical-binding: t; -*-

;; Pure classifier extracted from `satan-observer' (T1 refactor).
;; Given an intervention plist + motive plist, decides whether the
;; attribution window shows a positive outcome and which §S5 predicate
;; (if any) fired.  No state writes; the coordinator in
;; `satan-observer' routes persistence.
;;
;; Reads only:
;;   - RUN-DIR/`bundle.json' for the intervention's baseline +
;;     percept handles (`--baseline-read', `--intervention-percept-handles').
;;   - Live system probes via `satan-memory-evidence-assemble-
;;     with-bounds' to assemble the after-state.
;;
;; Symbol names retained verbatim from the pre-split monolith so
;; existing tests (`test/satan-observer-test.el') and callers
;; remain wired without renames.

(require 'cl-lib)
(require 'satan-memory-canon)
(require 'satan-memory-evidence)
(require 'satan-memory-grammar)
(require 'satan-jsonl)
(require 'satan-motive)

;; ---------------------------------------------------------------------
;; Configuration
;; ---------------------------------------------------------------------

(defcustom satan-observer-window-mature-seconds 1800
  "Seconds after `intervention_emitted_at' before an intervention is
eligible for classification (A11).  Defaults to 30 minutes per §S5.
The gate prevents a same-tick or next-tick scan from scoring an
intervention before its attribution window has actually elapsed."
  :type 'integer :group 'satan)

(defcustom satan-observer-emacs-title-suffix-re
  " - GNU Emacs at .*\\'"
  "Regex matching the trailing suffix of `frame-title-format' on this
host.  The §S5 P1 predicate strips this suffix from a focus
segment's `:last_title' to recover the buffer's file path before
prefix-matching against the motive's `:project_cwd'.  Tune when
the title format changes; unmatched titles fall through and P1
silently no-ops on them."
  :type 'regexp :group 'satan)

;; ---------------------------------------------------------------------
;; Baseline + after-state (Phase 5.4a)
;; ---------------------------------------------------------------------

(defun satan-observer--baseline-read (run-dir)
  "Return the intervention-time `evidence_window' for RUN-DIR.
Reads RUN-DIR/`bundle.json' and pulls out `:percept' →
`:evidence_window'.  Returns nil when bundle.json is missing,
unparseable, or lacks the percept slot — which happens on budget-
denied or pre-spawn-denied runs (phase 1 still skips percept.json
write under budget-denied; same caveat applies to bundle).

The classifier (5.4c) treats nil here as `:reason :no_baseline'."
  (let* ((path (expand-file-name "bundle.json" run-dir))
         (bundle (satan-jsonl-read-object-file path))
         (percept (and bundle (plist-get bundle :percept))))
    (and percept (plist-get percept :evidence_window))))

(defun satan-observer--window-end-iso (intervention)
  "Return the ISO8601 close-of-window for INTERVENTION.
Window end = `:intervention_emitted_at' +
`satan-observer-window-mature-seconds' (30 min default).
Format matches `satan-memory-evidence' helpers (%T%:z)."
  (let* ((emitted (plist-get intervention :intervention_emitted_at))
         (et (date-to-time emitted))
         (end (time-add et (seconds-to-time
                            satan-observer-window-mature-seconds))))
    (format-time-string "%Y-%m-%dT%T%:z" end)))

(defun satan-observer--window-crosses-midnight-p (intervention)
  "Return non-nil when INTERVENTION's 30-min window spans two calendar
days.  `satan-memory-evidence-assemble-with-bounds' resolves the
panopticon segment file via `(substring END 0 10)' — a cross-day
window would read tomorrow's segments and miss most of the
window.  v0 punts on multi-day windows: the classifier yields
`:reason :crosses_midnight' instead of attempting a probe."
  (let ((start (plist-get intervention :intervention_emitted_at))
        (end (satan-observer--window-end-iso intervention)))
    (not (equal (substring start 0 10) (substring end 0 10)))))

(defun satan-observer--after-state (intervention motive)
  "Assemble the after-state `evidence_window' for INTERVENTION + MOTIVE.
Calls `satan-memory-evidence-assemble-with-bounds' with
START = `:intervention_emitted_at',
END   = `--window-end-iso' (+30 min),
CWD   = MOTIVE's `:project_cwd' (default-directory when nil — git
        + fs probes still run, predicates 1+3 simply won't find
        path matches).

Caller is responsible for guarding midnight crossings; this helper
makes the call unconditionally."
  (let* ((start (plist-get intervention :intervention_emitted_at))
         (end (satan-observer--window-end-iso intervention))
         (cwd (or (plist-get motive :project_cwd) default-directory))
         (ctx (list :time_now end
                    :mode_name "observer"
                    :run_id (plist-get intervention :run_id)
                    :current_grammar_version
                    satan-memory-grammar-current-version)))
    (satan-memory-evidence-assemble-with-bounds
     start end ctx (list :cwd cwd))))

;; ---------------------------------------------------------------------
;; Positive predicates (Phase 5.4b) — §S5 P1–P4
;;
;; Each takes (baseline after motive intervention) and returns non-nil
;; on fire, nil on skip / no-signal.  All pure: no I/O, no state
;; writes.  The classifier (5.4c) runs them in order; first fire
;; wins.  Predicates 1 + 3 are scoped to MOTIVE's `:project_cwd'
;; (silent skip when absent); 2 + 4 fire regardless.
;; ---------------------------------------------------------------------

(defun satan-observer--title-to-path (title)
  "Strip the emacs frame-title suffix from TITLE; return the leading
absolute path or nil when the result isn't an absolute file path.
The `frame-title-format' shipped in phase 5.4-fmt emits
`<buffer-file-name> - GNU Emacs at <host>' when the buffer visits
a file and `<buffer-name> - GNU Emacs at <host>' otherwise; only
the former yields a path-prefix-matchable string."
  (when (stringp title)
    (let ((stripped (replace-regexp-in-string
                     satan-observer-emacs-title-suffix-re "" title)))
      (and (string-prefix-p "/" stripped) stripped))))

(defun satan-observer--predicate-editor-edit-in-window
    (_baseline after motive intervention)
  "§S5 P1 — fires when AFTER's `:focus_segments' contains an editor
segment that (a) started strictly after `:intervention_emitted_at'
and (b) carries a `:last_title' that resolves to a path under
MOTIVE's `:project_cwd'.  Silently nil when `:project_cwd' absent
or when no segment carries a last_title (e.g. panopticon segments
written before phase 5.4-pan)."
  (let ((cwd (plist-get motive :project_cwd))
        (emitted (plist-get intervention :intervention_emitted_at)))
    (when (and cwd emitted)
      (let ((prefix (file-name-as-directory (expand-file-name cwd))))
        (cl-some
         (lambda (seg)
           (let* ((surface (satan-memory-canon--app-surface
                            (plist-get seg :app_id)))
                  (start-ts (plist-get seg :start_ts))
                  (path (satan-observer--title-to-path
                         (plist-get seg :last_title))))
             (and (equal "editor" surface)
                  (stringp start-ts)
                  (string< emitted start-ts)
                  path
                  (string-prefix-p prefix path))))
         (plist-get after :focus_segments))))))

(defun satan-observer--git-row-matches-motive (row motive)
  "Return non-nil when git commit ROW belongs to MOTIVE's repo.
Matches when `:repo' normalised equals MOTIVE's `:project_cwd'
normalised, or when ROW's `:slug' is a `project:' cue token in
MOTIVE."
  (let ((cwd (plist-get motive :project_cwd)))
    (and cwd
         (or (let ((norm-repo (directory-file-name
                               (expand-file-name (plist-get row :repo))))
                    (norm-cwd (directory-file-name
                               (expand-file-name cwd))))
               (string-equal norm-repo norm-cwd))
             (let ((slug (plist-get row :slug)))
               (and (stringp slug)
                    (cl-some (lambda (h)
                               (and (string-prefix-p "project:" h)
                                    (equal slug
                                           (substring h (length "project:")))))
                             (plist-get motive :cue))))))))

(defun satan-observer--git-row-in-window (row intervention)
  "Return non-nil when git commit ROW's :end_ts lies in the attribution
window: strictly after `:intervention_emitted_at' and not after the
30-min window close."
  (let* ((emitted (plist-get intervention :intervention_emitted_at))
         (end (satan-observer--window-end-iso intervention))
         (ts (plist-get row :end_ts)))
    (and (stringp ts) (stringp emitted) (stringp end)
         (string< emitted ts)
         (not (string< end ts)))))

(defun satan-observer--predicate-git-commit-observed
    (_baseline after motive intervention)
  "§S5 P2 — fires when AFTER perceives a commit in MOTIVE's repo during
the attribution window.  Scoped (like P1/P3) to MOTIVE's `:project_cwd';
no project_cwd → no fire.  A row matches when its `:repo' is MOTIVE's
project root (path-normalised) or its `:slug' matches a `project:' cue
token, AND its `:end_ts' lies in (`:intervention_emitted_at',
window-end].  No baseline needed — the attribution window is the
anchor, so stale/pre-deploy baselines cannot misfire."
  (let ((cwd (plist-get motive :project_cwd)))
    (and cwd
         (cl-some (lambda (row)
                    (and (satan-observer--git-row-matches-motive row motive)
                         (satan-observer--git-row-in-window
                          row intervention)))
                  (plist-get after :git_commits)))))

(defun satan-observer--abs-recent (fs-state)
  "Return absolute paths for FS-STATE's `:recent_files'.
`:recent_files' entries are stored relative to FS-STATE's `:cwd'
(which may be abbreviated, e.g. `~/.emacs.d'); both legs need
expanding before comparison."
  (let ((cwd (plist-get fs-state :cwd)))
    (when cwd
      (let ((abs-cwd (expand-file-name cwd)))
        (mapcar (lambda (rel) (expand-file-name rel abs-cwd))
                (plist-get fs-state :recent_files))))))

(defun satan-observer--predicate-fs-recent-delta
    (baseline after motive _intervention)
  "§S5 P3 — fires when AFTER's `:recent_files' contains a path under
MOTIVE's `:project_cwd' that is absent from BASELINE's
`:recent_files'.  Silently nil when `:project_cwd' absent.
Per watch-out: `recentf-list' tracks visits, not edits — a file
opened (not modified) in the window will still satisfy this
predicate.  v0 accepts the looseness; a stricter mtime-delta is a
follow-up."
  (let ((cwd (plist-get motive :project_cwd)))
    (when cwd
      (let* ((after-abs (satan-observer--abs-recent
                         (plist-get after :fs_state)))
             (baseline-abs (satan-observer--abs-recent
                            (plist-get baseline :fs_state)))
             (prefix (file-name-as-directory (expand-file-name cwd))))
        (cl-some (lambda (path)
                   (and (string-prefix-p prefix path)
                        (not (member path baseline-abs))))
                 after-abs)))))

;; ---------------------------------------------------------------------
;; Goad answer predicate (SL-016 PHASE-07) — §S5 the ask's direct answer
;;
;; The first predicate that reads a fact the elicitation surface wrote
;; rather than ambient telemetry: AFTER's `:goad' slice (`satan-goad-
;; slice') carries each queued ask with its day record.  It fires when
;; this intervention's record carries a `:value' whose `:at' sits inside
;; the ask's own outcome window — emit + `:outcome_window_minutes' (60),
;; never the observer's 30-min evidence horizon (§S5, RV-007 F-10).
;; ---------------------------------------------------------------------

(defun satan-observer--goad-entry (after intervention)
  "Return AFTER's `:goad' entry for INTERVENTION's id, or nil.
The `:goad' slice is a list of queue-entry plists (`satan-goad-slice'),
each with `:record' when its emit date's day file has one."
  (let ((iid (plist-get intervention :intervention_id)))
    (and iid
         (cl-find iid (plist-get after :goad)
                  :key (lambda (e) (plist-get e :intervention_id))
                  :test #'equal))))

(defun satan-observer--ask-answer-window (intervention)
  "Return (START . END) instants for INTERVENTION's ask answer window.
START is `:intervention_emitted_at'; END is START +
`:outcome_window_minutes' (60 for an ask).  Each is a Lisp time value;
nil when the emit timestamp is missing or unparseable."
  (let* ((start-str (plist-get intervention :intervention_emitted_at))
         (mins (or (plist-get intervention :outcome_window_minutes) 0))
         (start (and (stringp start-str)
                     (condition-case nil
                         (date-to-time start-str)
                       (error nil)))))
    (and start
         (cons start (time-add start (seconds-to-time (* 60 mins)))))))

(defun satan-observer--instant-in-window-p (ts window)
  "Non-nil when TS (an ISO instant) falls within WINDOW `(START . END)'.
Inclusive on both bounds.  Nil when TS or WINDOW is absent, or TS is
unparseable.  Instants compare through `date-to-time', never their
strings (SL-016 R1)."
  (let ((at-time (and (stringp ts)
                       (condition-case nil (date-to-time ts) (error nil)))))
    (and at-time window
         (not (time-less-p at-time (car window)))
         (not (time-less-p (cdr window) at-time)))))

(defun satan-observer--predicate-goad-answer
    (_baseline after _motive intervention)
  "SL-016 — fires when the keeper answered INTERVENTION's ask in window.
Reads AFTER's `:goad' slice: the entry for this intervention must carry
a `:record' with a `:value' present and an `:at' within the ask's own
outcome window.  It never reads what the value says (DEC-025): any
answer to the form, whatever its option or fields, is an answer."
  (let* ((entry (satan-observer--goad-entry after intervention))
         (record (and entry (plist-get entry :record)))
         (at (and record (plist-get record :at))))
    (and entry
         record
         (plist-member record :value)
         (satan-observer--instant-in-window-p
          at (satan-observer--ask-answer-window intervention)))))

;; ---------------------------------------------------------------------
;; Negative classification (T1.5b PR 2) — :ignored / :neutral
;; ---------------------------------------------------------------------

(defconst satan-observer-user-facing-kinds
  '("inbox" "notify" "visible_sign" "proposal" "patch_job"
    "accuse" "ask" "surface")
  "Intervention kinds whose target surface is a place the user is
expected to notice the intervention.  When such an intervention
matures without a positive predicate firing,
`satan-observer-classify-negative' emits `:ignored' (per
outcome-semantics §1 + §10 step 2).  Anything outside this set is
non-user-facing and becomes `:neutral'.

Closed against `satan-audit-intervention-kinds'; kinds not
listed (`delay', `quarantine', plus any future
`sway_border_set'-style non-user-facing kinds) fall into the
`:neutral' bucket.")

(defun satan-observer--ack-checked-p (after)
  "Return non-nil when AFTER's panopticon focus probe succeeded.
The probe status is the string \"ok\" iff the focus-segments JSONL
was readable and fresh across the maturity window; any other
status (\"stale-Nm\", \"missing\", \"malformed\") means we cannot
assert presence or absence of acknowledgement events.  See
`satan-memory-evidence--segments-status'."
  (equal "ok" (plist-get (plist-get after :sensor_status) :focus)))

(defun satan-observer--count-ack-events (after intervention)
  "Count AFTER's `:focus_segments' starting strictly after
INTERVENTION's `:intervention_emitted_at'.  v1 does not narrow by
surface — any focus segment in the window counts (per
outcome-semantics §8 deferral).  A stricter surface mapping is a
follow-up."
  (let ((emitted (plist-get intervention :intervention_emitted_at)))
    (cl-count-if
     (lambda (seg)
       (let ((start (plist-get seg :start_ts)))
         (and (stringp start) (string< emitted start))))
     (plist-get after :focus_segments))))

;; ---------------------------------------------------------------------
;; Ask negative branch (SL-016 PHASE-09) — design sec-5
;;
;; Kind `"ask"' never consults focus telemetry: its silence is judged
;; from the same goad day record the answer predicate reads, as the
;; record stood at window end (any stamp after emit + outcome_window
;; minutes reads as absent; RV-007 F-35).  First match wins.
;; ---------------------------------------------------------------------

(defconst satan-observer-short-exposure-seconds (* 10 60)
  "The tail of an ask's outcome window that reads as `:short_exposure'.
A `:presented_at' this close to window end leaves too little time to
call the ask ignored (design sec-5, SL-016 PHASE-09).")

(defun satan-observer--ask-record (after intervention)
  "INTERVENTION's goad day record from AFTER's `:goad' slice, or nil."
  (let ((entry (satan-observer--goad-entry after intervention)))
    (and entry (plist-get entry :record))))

(defun satan-observer--ask-presented-in-window-p (record window)
  "Non-nil when RECORD's `:presented_at' falls inside WINDOW.
Inclusive on both bounds, through `satan-observer--instant-in-window-p'."
  (satan-observer--instant-in-window-p
   (plist-get record :presented_at) window))

(defun satan-observer--ask-presented-short-exposure-p (record window)
  "Non-nil when RECORD's `:presented_at' sits in WINDOW's last
`satan-observer-short-exposure-seconds' seconds."
  (let* ((ts (plist-get record :presented_at))
         (at (and (stringp ts)
                  (condition-case nil (date-to-time ts) (error nil)))))
    (and at window
         (satan-observer--instant-in-window-p ts window)
         (let ((short-start (time-subtract
                             (cdr window)
                             (seconds-to-time
                              satan-observer-short-exposure-seconds))))
           (not (time-less-p at short-start))))))

(defun satan-observer--ask-deferred-p (record window provenance)
  "Non-nil when RECORD defers in WINDOW with PROVENANCE.
PROVENANCE is the `:deferred_by' string (`\"later\"' or
`\"enough\"'); the `:deferred_at' stamp must lie inside WINDOW — a
deferral after window end reads as absent (RV-007 F-35)."
  (and (equal provenance (plist-get record :deferred_by))
       (satan-observer--instant-in-window-p
        (plist-get record :deferred_at) window)))

(defun satan-observer--ask-unknown (reason confidence)
  "An `:unknown' ask verdict with REASON and CONFIDENCE."
  (list :classification :unknown
        :confidence confidence
        :predicates nil
        :reason reason))

(defun satan-observer--ask-ignored (reason surface)
  "An `:ignored' ask verdict with REASON, for SURFACE.
The ask branch runs before the ack gate, so its evidence records the
gate as not checked rather than fabricating an acknowledgement scan."
  (list :classification :ignored
        :confidence :medium
        :predicates nil
        :reason reason
        :evidence (list :target-surface surface
                        :no-positive-predicates t
                        :acknowledgement-checked :false
                        :ack-events-found 0)))

(defun satan-observer--classify-ask-negative (intervention after)
  "Classify a no-fire `\"ask\"' scan from its goad day record.
Reads the record out of AFTER's `:goad' slice exactly as the answer
predicate does, then judges it as it stood at window end.  First match
wins (design sec-5):

  no `:presented_at' in window                 → `:unknown :high'
    `:undelivered'
  `:presented_at' in the last 10 minutes        → `:unknown :low'
    `:short_exposure'
  `:deferred_at' in window, `:deferred_by' later → `:unknown :low'
    `:deferred'
  presented in window, `:deferred_by' enough    → `:ignored :medium'
    `:dismissed'
  presented in window, nothing else             → `:ignored :medium'
    `:untouched'

The label is the verdict's `:reason' (D2).  Every verdict is an auto
kind, so `satan-observer--assert-auto-classification' stays satisfied."
  (let* ((record (satan-observer--ask-record after intervention))
         (window (satan-observer--ask-answer-window intervention))
         (surface (plist-get intervention :target_surface))
         (presented (satan-observer--ask-presented-in-window-p
                     record window)))
    (cond
     ((not presented)
      (satan-observer--ask-unknown :undelivered :high))
     ((satan-observer--ask-presented-short-exposure-p record window)
      (satan-observer--ask-unknown :short_exposure :low))
     ((satan-observer--ask-deferred-p record window "later")
      (satan-observer--ask-unknown :deferred :low))
     ((satan-observer--ask-deferred-p record window "enough")
      (satan-observer--ask-ignored :dismissed surface))
     (t
      (satan-observer--ask-ignored :untouched surface)))))

(defun satan-observer-classify-negative (intervention after)
  "Decide `:ignored' / `:neutral' / `:unknown' for a no-fire scan.
Called from `satan-observer-classify' when all P1–P4 returned
nil.  INTERVENTION is the classifier-shaped plist (carrying
`:kind' + `:target_surface' from the projection row); AFTER is
the assembled evidence window.

Dispatch (outcome-semantics §1 + §10 step 2 + T1.5b PR 2 brief):

  kind ∈ user-facing AND ack-events-found = 0
    →  `:ignored' with `:confidence :medium' when ack was
       checkable (focus probe ok), `:low' when not.

  kind ∈ user-facing AND ack-events-found > 0
    →  `:unknown :low :reason nil'.  Per §1, `:ignored' requires
       no acknowledgement event in window; presence of any focus
       segment after the emit puts the verdict outside the
       contracted gate.  v1 punts here rather than extending the
       `:unknown' reason vocabulary.

  kind ∉ user-facing
    →  `:neutral :low'.

`:harmful' and `:contradicted' are not reachable from this
function — they require manual marking (§7) and are rejected at
the classify API boundary
(`satan-observer--assert-auto-classification')."
  (let* ((kind (plist-get intervention :kind))
         (surface (plist-get intervention :target_surface))
         (user-facing (and (stringp kind)
                           (member kind
                                   satan-observer-user-facing-kinds))))
    (cond
     ((equal kind "ask")
      ;; SL-016 PHASE-09 — the ask's silence is read from its goad day
      ;; record, dispatched before the ack gate so the gate's state never
      ;; reaches an ask.
      (satan-observer--classify-ask-negative intervention after))
     (user-facing
      (let* ((checked (satan-observer--ack-checked-p after))
             (found (if checked
                        (satan-observer--count-ack-events after intervention)
                      0)))
        (cond
         ((and checked (> found 0))
          (list :classification :unknown
                :confidence :low
                :predicates nil
                :reason nil))
         (t
          (list :classification :ignored
                :confidence (if checked :medium :low)
                :predicates nil
                :reason nil
                :evidence (list :target-surface surface
                                :no-positive-predicates t
                                :acknowledgement-checked
                                (if checked t :false)
                                :ack-events-found found))))))
     (t
      (list :classification :neutral
            :confidence :low
            :predicates nil
            :reason nil
            :evidence (list :target-surface surface
                            :no-positive-predicates t))))))

(defun satan-observer--assert-auto-classification (verdict)
  "Guard the classify API boundary against `:harmful' / `:contradicted'.
Per outcome-semantics §2 invariants 1+2 those classifications
are manual-only in v1; the auto-classifier must never construct
them.  Signals on violation; returns VERDICT on success so the
guard is composable in tail position.  Nil verdict (the `:stale'
short-circuit from PR 3) passes through unchecked — there is no
classification to assert against."
  (when verdict
    (cl-check-type (plist-get verdict :classification)
                   (member :worked :neutral :ignored :unknown)))
  verdict)

;; ---------------------------------------------------------------------
;; Maturity (T1.5b PR 3) — outcome-semantics §3 + §6.1/§6.2 lifecycle
;; ---------------------------------------------------------------------

(defconst satan-observer-stale-after-seconds (* 24 60 60)
  "Seconds past the maturity window's close before a verdict freezes.
Per outcome-semantics §6.2 the `:stale' cutoff is
`created_at + outcome_window_minutes + 24h'; auto-classification is
forbidden past this point.  Matches `satan-observer-scan-window-
hours' (today's 24h re-scan horizon) so a missed-tick day does not
prematurely freeze the projection.")

(defun satan-observer--maturity-state (intervention now)
  "Return `:pending' / `:mature' / `:stale' for INTERVENTION at NOW.
INTERVENTION carries `:ts' (created_at, the intervention.created
audit-event ts) and `:outcome_window_minutes' (declared per-kind by
the handler at create time).  NOW is the broker's frozen
`:time_now' ISO8601 string.

Per outcome-semantics §3 + §6.2:

  :pending — NOW < `:ts' + `:outcome_window_minutes'
  :mature  — `:ts' + `:outcome_window_minutes' ≤ NOW
             < `:ts' + `:outcome_window_minutes' + 24 h
  :stale   — NOW ≥ that 24 h cutoff."
  (let* ((ts (plist-get intervention :ts))
         (mins (or (plist-get intervention :outcome_window_minutes) 0))
         (created (date-to-time ts))
         (mature-at (time-add created (seconds-to-time (* 60 mins))))
         (stale-at (time-add mature-at
                             (seconds-to-time
                              satan-observer-stale-after-seconds)))
         (now-time (date-to-time now)))
    (cond
     ((time-less-p now-time mature-at) :pending)
     ((time-less-p now-time stale-at) :mature)
     (t :stale))))

;; ---------------------------------------------------------------------
;; Public entry
;; ---------------------------------------------------------------------

(defconst satan-observer--predicates
  '((:editor_edit_in_window
     . satan-observer--predicate-editor-edit-in-window)
    (:git_commit_observed
     . satan-observer--predicate-git-commit-observed)
    (:fs_recent_delta
     . satan-observer--predicate-fs-recent-delta)
    (:goad_answer
     . satan-observer--predicate-goad-answer))
  "Ordered alist mapping predicate keyword → symbol.
`satan-observer-classify' runs the subset selected by
`satan-observer--predicates-for-kind'; first fire wins.
Order matters only for the `:predicate' slot recorded on the
verdict — the verdict itself is `\"positive\"' regardless.

`:goad_answer' is the ask answer predicate (SL-016): the only
positive predicate for kind `\"ask\"' and never offered to any
other kind.")

(defun satan-observer--predicates-for-kind (kind)
  "The positive predicate alist applicable to intervention KIND.
For `\"ask\"' the answer predicate is the only positive predicate —
an ask's expected outcome is an answer, and nothing ambient is
evidence of one (RV-007 F-21).  Every other kind keeps the ambient
three (`:editor_edit_in_window', `:git_commit_observed',
`:fs_recent_delta')."
  (if (equal kind "ask")
      (cl-remove-if-not (lambda (cell) (eq (car cell) :goad_answer))
                        satan-observer--predicates)
    (cl-remove-if (lambda (cell) (eq (car cell) :goad_answer))
                  satan-observer--predicates)))

(defun satan-observer-classify--unknown (reason)
  "Build an `:unknown' / `:low' verdict carrying REASON.
Per outcome-semantics §3 + §4: `:unknown' always emits at `:low'
confidence; `:predicates' is empty (no positive fired)."
  (list :classification :unknown
        :confidence :low
        :predicates nil
        :reason reason))

(defun satan-observer-classify (intervention motive &optional now)
  "Return a verdict plist for INTERVENTION against MOTIVE (§S5).
Pure: no state writes.  Reads ':run_dir'/bundle.json for baseline;
assembles after-state via '--after-state'.

Returns (:classification :worked|:ignored|:neutral|:unknown
         :confidence :low|:medium|:high  :predicates (KW ...)
         :reason KW-or-nil  :evidence PLIST  :maturity :pending|:mature).

Optional NOW (broker's ':time_now' ISO string) enables maturity
guard: nil→:mature (test convenience), :pending→early :unknown,
:stale→nil (caller skips persist), :mature→full flow.

Guard order (:mature / NOW-nil):
  1. A14 dormant motive → :unknown :motive_dormant
  2. Window crosses midnight → :crosses_midnight (kind \"ask\" exempt —
     an ask reads one record keyed by its emit date, not the
     panopticon segment file; RV-007 F-29)
  3. No baseline → :no_baseline
  4. The positive predicates for the intervention's kind; ≥1 fires →
     :worked (kind \"ask\": only the goad answer predicate)
  5. None → classify-negative → :ignored/:neutral/:unknown

Single-motive only; multi-motive correlation lands in 5.7.
Verdict asserted via '--assert-auto-classification' (no :harmful/:contradicted).

Full semantics: docs/satan/observer-classify.md"

  (let ((maturity (and now (satan-observer--maturity-state intervention now))))
    (pcase maturity
      (:stale nil)
      (:pending
       (satan-observer--assert-auto-classification
        (list :classification :unknown
              :confidence :low
              :predicates nil
              :reason :pending
              :maturity :pending)))
      (_
       (satan-observer--assert-auto-classification
        (plist-put
         (cond
          ((plist-get motive :dormant)
           (satan-observer-classify--unknown :motive_dormant))
          ((and (not (equal (plist-get intervention :kind) "ask"))
                (satan-observer--window-crosses-midnight-p intervention))
           (satan-observer-classify--unknown :crosses_midnight))
          (t
           (let ((baseline (satan-observer--baseline-read
                            (plist-get intervention :run_dir))))
             (cond
              ((null baseline)
               (satan-observer-classify--unknown :no_baseline))
              (t
               (let* ((after (satan-observer--after-state intervention motive))
                      (firers
                       (delq nil
                             (mapcar
                              (lambda (p)
                                (and (funcall (cdr p) baseline after motive intervention)
                                     (car p)))
                              (satan-observer--predicates-for-kind
                               (plist-get intervention :kind))))))
                 (if firers
                     (list :classification :worked
                           :confidence (if (> (length firers) 1) :high :medium)
                           :predicates firers
                           :reason nil)
                   (satan-observer-classify-negative intervention after))))))))
         :maturity :mature))))))

;; ---------------------------------------------------------------------
;; Multi-motive correlation (Phase 5.7) — overlap + file-order tiebreak
;; ---------------------------------------------------------------------

(defun satan-observer--intervention-percept-handles (intervention)
  "Return the percept handle list persisted with INTERVENTION's run.
Reads `bundle.json' → `:percept' → `:handles'.  Nil when bundle is
missing or lacks the slot (budget-denied / pre_spawn-denied
runs)."
  (let* ((run-dir (plist-get intervention :run_dir))
         (path (and run-dir (expand-file-name "bundle.json" run-dir)))
         (bundle (and path (satan-jsonl-read-object-file path)))
         (percept (and bundle (plist-get bundle :percept))))
    (and percept (plist-get percept :handles))))

(defalias 'satan-observer--rank-motives-by-overlap
  #'satan-motive-rank-by-overlap
  "The observer's correlator ranking — promoted to `satan-motive' (SL-016
PHASE-06) so the goad ask tool ranks by the same rule without
requiring the observer.")

(defun satan-observer--ask-motive (intervention motives)
  "The live motive INTERVENTION's ask credits at maturity, or nil.
Requires the motive's `:id' to equal the ask's `:related_motive_id',
the motive to be non-dormant, and the ask's subject (its single
`:cue_handles' entry — SL-016 A5) to still sit in the motive's
`:cue'.  Unlike every other kind the ask does not re-rank by percept
overlap: emit decided the winner once, maturity reads that decision
back (RV-007 F-28)."
  (let* ((rid (plist-get intervention :related_motive_id))
         (subject (car (plist-get intervention :cue_handles))))
    (and rid subject
         (cl-find-if (lambda (m)
                       (and (equal rid (plist-get m :id))
                            (not (plist-get m :dormant))
                            (member subject (plist-get m :cue))))
                     motives))))

(defun satan-observer--classify-ask (intervention motives now)
  "Classify an `\"ask\"' INTERVENTION against its recorded motive, or none.
Found → `satan-observer-classify' with that motive.  Not found →
`:unknown :no_correlation' (the ask's `:related_motive_id' is missing,
the motive was removed or made dormant, or it no longer cues the
subject).  The caller enqueues `ask_uncorrelated' on the latter (D1)."
  (let ((motive (satan-observer--ask-motive intervention motives)))
    (satan-observer--assert-auto-classification
     (if motive
         (let ((verdict (satan-observer-classify
                         intervention motive now)))
           (plist-put verdict :motive_id (plist-get motive :id)))
       (list :motive_id nil
             :classification :unknown
             :confidence :low
             :predicates nil
             :reason :no_correlation
             :maturity :mature)))))

(defun satan-observer-classify-for-motives (intervention motives &optional now)
  "Pick the strongest-correlated motive in MOTIVES, then classify.
For every kind but `\"ask\"' this reads INTERVENTION's
`:run_dir'/bundle.json for percept handles; intersects each motive's
`:cue' against them; highest count wins, file-order breaks ties.

Kind `\"ask\"' takes the narrower route of design sec-10: it credits
the live motive whose `:id' equals the recorded `:related_motive_id'
and still cues the subject (`:cue_handles') — `satan-observer--ask-
motive' — and never re-ranks by percept overlap.

Returns `satan-observer-classify''s verdict shape (§2)
augmented with `:motive_id'.

When no motive overlaps with the intervention's percept handles
(or motives list is empty / bundle missing percept handles),
returns the §2 `:unknown' shape with `:reason :no_correlation' and
`:motive_id' nil — `persist-verdict' still commits the verdict so
the projection retires the pending row.

T1.5b PR 3 — optional NOW (broker's frozen `:time_now') routes the
maturity guard before any motive ranking or bundle read:

  :stale   → returns nil; `observer-process' records `:skipped :stale'
             and does not persist (production never reaches here
             because `satan-intervention-pending' excludes stale
             rows in SQL; defensive only).
  :pending → returns `(:motive_id nil :classification :unknown
             :confidence :low :predicates nil :reason :pending
             :maturity :pending)' without consulting motives
             (§2 invariant 3).
  :mature  → existing flow; classify gets the same NOW threaded
             through so its internal maturity check agrees."
  (let ((maturity (and now (satan-observer--maturity-state intervention now))))
    (pcase maturity
      (:stale nil)
      (:pending
       (satan-observer--assert-auto-classification
        (list :motive_id nil
              :classification :unknown
              :confidence :low
              :predicates nil
              :reason :pending
              :maturity :pending)))
      (_
       (if (equal (plist-get intervention :kind) "ask")
           (satan-observer--classify-ask intervention motives now)
         (let* ((handles (satan-observer--intervention-percept-handles
                          intervention))
                (ranked (satan-observer--rank-motives-by-overlap
                         motives handles)))
           (satan-observer--assert-auto-classification
            (if (null ranked)
                (list :motive_id nil
                      :classification :unknown
                      :confidence :low
                      :predicates nil
                      :reason :no_correlation
                      :maturity :mature)
              (let* ((winner (plist-get (car ranked) :motive))
                     (verdict (satan-observer-classify
                               intervention winner now)))
                (plist-put verdict :motive_id (plist-get winner :id)))))))))))

(provide 'satan-observer-classify)
;;; satan-observer-classify.el ends here
