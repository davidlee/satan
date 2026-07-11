;;; satan-intervention-mark.el --- manual override path for intervention outcomes -*- lexical-binding: t; -*-

;; T1.5b PR 4 — interactive entry to the §7.1 manual-mark workflow.
;; The notes-directive entry lives in satan-tools-atsatan.el; both
;; surfaces route through `satan-intervention-write-manual-outcome'
;; in satan-intervention.el.
;;
;; Commands:
;;   M-x satan-mark-intervention-harmful
;;   M-x satan-mark-intervention-contradicted
;;
;; Prefix arg includes :stale interventions in the completion list
;; (per outcome-semantics §7.4 — manual marks are allowed in every
;; lifecycle state, including :stale where the auto-classifier has
;; frozen the projection row).

(require 'cl-lib)
(require 'subr-x)
(require 'satan-intervention)
(require 'satan-audit)
(require 'satan-observer-classify)  ; maturity-state util

;; Broker dependency is soft — `satan-broker-locate-run-dir' is loaded
;; into the live emacs daemon at session start.  Requiring it here would
;; pull `satan-tools-org' (and its denote chain) into ert batch runs
;; that don't need them.
(declare-function satan-broker-locate-run-dir "satan-broker")

(defconst satan-intervention-mark--confidences
  '("low" "medium" "high")
  "Confidence enum offered by the interactive command (§4).")

(defun satan-intervention-mark--run-id-of (iv-id)
  "Return the run-id half of `<RUN-ID>.iv<NNN>'.
Signals if IV-ID lacks the `.ivNNN' suffix."
  (cond
   ((not (stringp iv-id))
    (user-error "intervention id must be string"))
   ((string-match "\\`\\(.+\\)\\.iv[0-9]+\\'" iv-id)
    (match-string 1 iv-id))
   (t
    (user-error "malformed intervention id (no `.ivNNN' suffix): %s" iv-id))))

(defun satan-intervention-mark--now-iso ()
  "Return current time as the ISO8601 form the audit boundary expects."
  (format-time-string "%Y-%m-%dT%H:%M:%S%z"))

(defun satan-intervention-mark--next-revisit-at (intervention)
  "Return ISO8601 string for INTERVENTION's window-close timestamp (§6.2)."
  (let* ((ts (plist-get intervention :ts))
         (mins (or (plist-get intervention :outcome_window_minutes) 0))
         (close (time-add (date-to-time ts) (seconds-to-time (* 60 mins)))))
    (format-time-string "%Y-%m-%dT%H:%M:%S%z" close)))

(defun satan-intervention-mark--maturity (intervention now)
  "Return the §3 maturity string for INTERVENTION at NOW (ISO8601)."
  (substring (symbol-name
              (satan-observer--maturity-state intervention now))
             1))

(defun satan-intervention-mark--candidate-label (iv)
  "Render IV (intervention plist) as a completing-read candidate line."
  (let* ((id (plist-get iv :intervention_id))
         (kind (or (plist-get iv :kind) "_"))
         (ts (or (plist-get iv :ts) "_"))
         (msg (or (plist-get iv :message) "")))
    (format "%s  [%s @ %s]  %s"
            id kind ts
            (truncate-string-to-width msg 60 nil nil "…"))))

(defun satan-intervention-mark--read-iv-id (include-stale)
  "Prompt for an intervention id; return the bare id string.
INCLUDE-STALE forwards to `satan-intervention-recent'."
  (let* ((now (satan-intervention-mark--now-iso))
         (ivs (satan-intervention-recent
               now :include-stale include-stale :limit 50))
         (table (mapcar (lambda (iv)
                          (cons (satan-intervention-mark--candidate-label iv)
                                (plist-get iv :intervention_id)))
                        ivs)))
    (when (null table)
      (user-error
       "no interventions available%s"
       (if include-stale "" " (use prefix arg to include :stale)")))
    (let ((pick (completing-read
                 "Intervention: " (mapcar #'car table) nil t)))
      (or (cdr (assoc pick table)) pick))))

(defun satan-intervention-mark--default-evidence-pointer ()
  "Compose `<file>:<line>' for the current buffer, or empty string."
  (if buffer-file-name
      (format "%s:%d"
              (abbreviate-file-name buffer-file-name)
              (line-number-at-pos))
    ""))

(defun satan-intervention-mark--read-confidence ()
  (completing-read "Confidence: "
                   satan-intervention-mark--confidences
                   nil t nil nil "medium"))

(defun satan-intervention-mark--build-ctx (run-id audit now)
  "Build the tool-ctx plist the writer demands.
The `:mode-name' is the synthetic `manual-mark'; capabilities are
empty (manual marks bypass mode-gated tool capability checks)."
  (list :id run-id
        :mode-name "manual-mark"
        :time-now now
        :audit audit
        :capabilities '()))

(defun satan-intervention-mark--dispatch (classification include-stale)
  "Shared body of `mark-harmful' / `mark-contradicted'.
CLASSIFICATION is `\"harmful\"' or `\"contradicted\"'.  INCLUDE-STALE
toggles whether :stale interventions appear in the completion list."
  (let* ((iv-id (satan-intervention-mark--read-iv-id include-stale))
         (lookup (satan-intervention-lookup iv-id))
         (iv (and lookup (plist-get lookup :intervention))))
    (unless iv
      (user-error "intervention not in projection: %s" iv-id))
    (let* ((reason (read-string "Reason: "))
           (default-evi (satan-intervention-mark--default-evidence-pointer))
           (evi-prompt (if (string-empty-p default-evi)
                           "Evidence pointer: "
                         (format "Evidence pointer (%s): " default-evi)))
           (evidence-pointer
            (let ((raw (read-string evi-prompt nil nil default-evi)))
              (if (string-empty-p raw) nil raw)))
           (confidence (satan-intervention-mark--read-confidence))
           (notes (let ((s (read-string "Notes (optional): ")))
                    (if (string-empty-p s) nil s)))
           (now (satan-intervention-mark--now-iso))
           (run-id (satan-intervention-mark--run-id-of iv-id))
           (run-dir (satan-broker-locate-run-dir run-id))
           (_ (unless run-dir
                (user-error "no run-dir on disk for %s" run-id)))
           (audit (satan-audit-reopen run-dir))
           (ctx (satan-intervention-mark--build-ctx run-id audit now))
           (maturity (satan-intervention-mark--maturity iv now))
           (next-revisit-at
            (satan-intervention-mark--next-revisit-at iv))
           (event (satan-intervention-write-manual-outcome
                   :ctx ctx
                   :intervention-id iv-id
                   :classification classification
                   :confidence confidence
                   :reason reason
                   :evidence-pointer evidence-pointer
                   :notes notes
                   :marked-by "interactive-command"
                   :maturity maturity
                   :next-revisit-at next-revisit-at
                   :classified-at now)))
      (message "marked %s as %s (%s) — %s"
               iv-id classification confidence event)
      event)))

;;;###autoload
(defun satan-mark-intervention-harmful (&optional include-stale)
  "Manually mark an intervention as `:harmful' (outcome-semantics §7.1).
With prefix arg INCLUDE-STALE, allow choosing a `:stale' intervention."
  (interactive "P")
  (satan-intervention-mark--dispatch "harmful" include-stale))

;;;###autoload
(defun satan-mark-intervention-contradicted (&optional include-stale)
  "Manually mark an intervention as `:contradicted' (outcome-semantics §7.1).
With prefix arg INCLUDE-STALE, allow choosing a `:stale' intervention."
  (interactive "P")
  (satan-intervention-mark--dispatch "contradicted" include-stale))

(provide 'satan-intervention-mark)
;;; satan-intervention-mark.el ends here
