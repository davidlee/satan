;;; satan-output.el --- Mode output handlers -*- lexical-binding: t; -*-

;; An output handler takes a validated `final' plist plus the broker
;; TOOL-CTX, applies each action against the broker-owned tool surface,
;; and returns a plist:
;;
;;   (:applied LIST :staged LIST :rejected LIST :failed LIST)
;;
;; where each LIST contains action plists (or (action . reason) for
;; rejected/failed).

(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-org)

(defun satan-output--apply-action (action ctx)
  "Apply ACTION (plist with :type :args) via the tool registry.
Returns (ok . _) | (error . MSG)."
  (let* ((type (plist-get action :type))
         (args (plist-get action :args))
         (spec (satan-tool-lookup type)))
    (if (null spec)
        (cons 'error (format "unknown action type: %s" type))
      (condition-case err
          (funcall (plist-get spec :handler) args ctx)
        (error (cons 'error (error-message-string err)))))))

(defun satan-output--partition (final allowed ctx)
  "Apply every action in FINAL whose :type ∈ ALLOWED, classify the rest as staged.
Returns the (:applied :staged :rejected :failed) plist."
  (let* ((actions (plist-get final :actions))
         applied staged failed)
    (dolist (a actions)
      (let ((type (plist-get a :type)))
        (cond
         ((not (member type allowed))
          (push a staged))
         (t
          (let ((res (satan-output--apply-action a ctx)))
            (pcase (car-safe res)
              ('ok (push a applied))
              ('error (push (list :action a :reason (cdr res)) failed))
              (_ (push (list :action a :reason "unknown handler result")
                       failed))))))))
    (list :applied  (nreverse applied)
          :staged   (nreverse staged)
          :rejected '()
          :failed   (nreverse failed))))

(defun satan-output/morning (final ctx)
  "Morning: auto-apply org_update_owned_block + proposal_stage + inbox_append."
  (satan-output--partition
   final
   '("org_update_owned_block" "proposal_stage" "inbox_append")
   ctx))

(defun satan-output/tick (final ctx)
  "Tick: auto-apply `inbox_append' only.  Notifications come through the
`notify_send' tool path during the run; the closing summary is recorded
in `final.json' for audit but does not write any surface."
  (satan-output--partition final '("inbox_append") ctx))

(defun satan-output/self-edit (final ctx)
  "Self-edit: only `proposal_stage' is allowed to auto-apply."
  (satan-output--partition final '("proposal_stage") ctx))

(defun satan-output/motd (final ctx)
  "Motd: write FINAL summary to `satan-motd-path' atomically.
`satan_final.summary' is the canonical motd content; the model has no
tool that targets the motd surface, so there is one writer (this
handler) and no race."
  (let ((partition
         (satan-output--partition
          final
          '("inbox_append")
          ctx))
        (summary (plist-get final :summary)))
    (when (stringp summary)
      (unless (file-directory-p (file-name-directory satan-motd-path))
        (make-directory (file-name-directory satan-motd-path) t))
      (let ((coding-system-for-write 'utf-8)
            (tmp (concat satan-motd-path ".tmp")))
        (with-temp-file tmp
          (insert summary)
          (unless (string-suffix-p "\n" summary) (insert "\n")))
        (rename-file tmp satan-motd-path t)))
    partition))

(defun satan-output/ruminate (final _ctx)
  "Ruminate: no auto-apply. All actions staged for review."
  (list :applied  '()
        :staged   (plist-get final :actions)
        :rejected '()
        :failed   '()))

(provide 'satan-output)
;;; satan-output.el ends here
