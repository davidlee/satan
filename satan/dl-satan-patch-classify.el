;;; dl-satan-patch-classify.el --- patch-vs-dispatch classifier -*- lexical-binding: t; -*-

;; Phase 3.2 of satan/patch-harness.plan.md.  Cheap keyword heuristic
;; used by the tick-agent prompt to *hint* whether an @satan directive
;; is naturally represented as a git diff (`patch') or as a SATAN
;; domain-tool call (`dispatch').  The model still decides; this is
;; one input among others.
;;
;; Public surface:
;;
;;   (dl-satan-patch-classify DIRECTIVE) -> 'patch | 'dispatch
;;   (dl-satan-patch-classify-explain DIRECTIVE) -> (CLASS . REASON)

(require 'cl-lib)
(require 'subr-x)

(defconst dl-satan-patch-classify--patch-verbs
  '("rewrite" "rewrote" "rewriting"
    "implement" "implements" "implementing"
    "refactor" "refactors" "refactoring"
    "tighten" "tightens" "tightening"
    "edit" "edits" "editing"
    "update" "updates" "updating"
    "fix" "fixes" "fixing"
    "add" "adds" "adding"
    "extract" "extracts" "extracting"
    "rename" "renames" "renaming"
    "remove" "removes" "removing"
    "delete" "deletes" "deleting"
    "create" "creates" "creating"
    "draft" "drafts" "drafting"
    "polish" "polishing"
    "distill" "distills" "distilling"
    "split" "splits" "splitting"
    "merge" "merges" "merging"
    "normalize" "normalizes" "normalizing")
  "Verbs that suggest a patch-shaped (multi-file edit / diff) directive.")

(defconst dl-satan-patch-classify--dispatch-hints
  '("read" "reads" "reading"
    "scan" "scans" "scanning"
    "show" "shows" "showing"
    "list" "lists" "listing"
    "log" "record" "records" "recording"
    "note" "notes" "noting"
    "mark" "marks" "marking"
    "summarise" "summarize" "summarises" "summarizes"
    "append" "appends" "appending"
    "notify" "notifies" "notifying"
    "remind" "reminds" "reminding")
  "Verbs that suggest a SATAN-tool dispatch (read / append / mark).")

(defun dl-satan-patch-classify--words (text)
  "Return TEXT's word tokens lowercased."
  (split-string (downcase (or text "")) "\\W+" t))

(defun dl-satan-patch-classify-explain (directive)
  "Classify DIRECTIVE and return (CLASS . REASON).
CLASS is `patch' or `dispatch'.  REASON is the first matching keyword
or a fallback string."
  (let* ((words (dl-satan-patch-classify--words directive))
         (patch-hit
          (cl-find-if (lambda (w)
                        (member w dl-satan-patch-classify--patch-verbs))
                      words))
         (dispatch-hit
          (cl-find-if (lambda (w)
                        (member w dl-satan-patch-classify--dispatch-hints))
                      words)))
    (cond
     ;; Strong patch verb wins outright; rewrites and refactors are
     ;; always git-diff-shaped regardless of any "read"-flavoured
     ;; supporting verb.
     (patch-hit (cons 'patch (format "verb: %s" patch-hit)))
     (dispatch-hit (cons 'dispatch (format "verb: %s" dispatch-hit)))
     ;; Fall back to dispatch — `dispatch' covers any directive we
     ;; cannot confidently route as a patch.  The model can still
     ;; over-ride by calling `patch_job_create' directly.
     (t (cons 'dispatch "no patch verb matched")))))

(defun dl-satan-patch-classify (directive)
  "Return `patch' or `dispatch' for DIRECTIVE.  See
`dl-satan-patch-classify-explain' for the matching keyword."
  (car (dl-satan-patch-classify-explain directive)))

(provide 'dl-satan-patch-classify)
;;; dl-satan-patch-classify.el ends here
