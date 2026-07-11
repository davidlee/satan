;;; satan-tools-sway.el --- sway window-border tools -*- lexical-binding: t; -*-

;; Two tools for ephemeral sway styling.  Runtime-only: no file writes;
;; `swaymsg reload' returns to the declarations in `~/.config/sway/config'.
;; Keybindings, exec lines, and other config entries are unreachable by
;; construction — the tool grammar admits only `client.<class>' commands
;; whose argument list is six-tuples of validated hex colours.

(require 'cl-lib)
(require 'satan-tools)
(require 'satan-intervention)
(require 'satan-trace)

(defcustom satan-sway-timeout-seconds 2
  "Per-call wall-clock deadline (seconds) for `swaymsg' subprocesses.
Applied via `satan-trace-call' in `satan-sway--swaymsg' so a
stuck compositor cannot hang a tool call.  A breach maps to
\(error . \"swaymsg timed out …\")."
  :type 'integer :group 'satan)

(defconst satan-sway-classes
  '("focused" "focused_inactive" "focused_tab_title"
    "unfocused" "urgent" "placeholder")
  "Sway client classes that take five-colour records.
`background' is intentionally excluded — it takes a single colour and
needs a different shape.")

(defconst satan-sway-hex-pattern
  "\\`#[0-9a-fA-F]\\{6\\}\\'"
  "Strict #RRGGBB matcher.  Anchored on both ends.")

(defconst satan-sway-intervention-target-surface "sway-mainbar"
  "Default `target_surface' for sway_border_set interventions (outcome-semantics §3.3).
Kind `visible_sign'; the actual surface is the sway bar / window borders.")

(defconst satan-sway-intervention-window-minutes 30
  "Default `outcome_window_minutes' for visible_sign interventions (outcome-semantics §3.3).")

(defconst satan-sway-intervention-expected-outcome
  "user notices the border-colour change as an ambient signal"
  "Default `expected_outcome' for visible_sign interventions (outcome-semantics §3.3).")

(defcustom satan-sway-swaymsg-program
  (or (executable-find "swaymsg") "swaymsg")
  "Path to the `swaymsg' binary."
  :type 'string :group 'satan)

(defun satan-sway--swaymsg (&rest args)
  "Invoke `swaymsg' with ARGS.  No shell.
Routed through `satan-trace-call' so the call is ledgered and
bounded by `satan-sway-timeout-seconds'.  Return (ok . OUTPUT) on
success, (error . MSG) on non-zero exit; a deadline breach maps to
\(error . \"swaymsg timed out …\")."
  (let* ((result (satan-trace-call
                  satan-sway-swaymsg-program args
                  :timeout-secs satan-sway-timeout-seconds
                  :label "sway"))
         (exit (plist-get result :exit))
         (output (plist-get result :stdout)))
    (cond
     ((plist-get result :timed-out)
      (cons 'error (format "swaymsg timed out after %ss"
                           satan-sway-timeout-seconds)))
     ((and (integerp exit) (zerop exit))
      (cons 'ok (string-trim output)))
     (t
      (cons 'error (format "swaymsg exit %s: %s" exit (string-trim output)))))))

(defun satan-sway--class-args (record)
  "Return the positional colour argv for sway's `client.<class>' command.
RECORD is a plist with :border, :background, :text, optionally
:indicator and :child_border.  Schema validation has already
enforced types and hex format; this fn only enforces sway's grammar:
border, background, text are required; indicator and child_border
are optional but child_border requires indicator."
  (let ((border (plist-get record :border))
        (bg     (plist-get record :background))
        (text   (plist-get record :text))
        (ind    (plist-get record :indicator))
        (child  (plist-get record :child_border)))
    (cond
     ((not (and border bg text))
      (cons 'error "each class requires border, background, text"))
     ((and child (null ind))
      (cons 'error "child_border requires indicator"))
     (t
      (cons 'ok (delq nil (list border bg text ind child)))))))

(defun satan-tool/sway-border-set (args ctx)
  "Batched border setter.  Issues one swaymsg per declared class.
ARGS: (:classes (:CLASS (:border ... :background ... :text ...
        [:indicator ...] [:child_border ...]) ...)).
At least one class must be declared.  On full success the handler
also emits a T7 `intervention.created' (kind=visible_sign,
target_surface=`sway-mainbar') via `satan-intervention-create' and
surfaces the minted id alongside `:applied'.  Returns
  (ok :applied (CLASS ...) :intervention_id IV-ID)
or
  (error MSG)
on first failure; classes already applied stay applied (sway has
no atomic transaction).  The error includes which class failed."
  (let ((classes (plist-get args :classes)))
    (cond
     ((not (and (listp classes) classes))
      (cons 'error "classes must be a non-empty object"))
     (t
      (let ((applied nil)
            (err nil)
            (cursor classes))
        (while (and cursor (null err))
          (let* ((key (car cursor))
                 (record (cadr cursor))
                 (class-name (substring (symbol-name key) 1)))
            (cond
             ((not (member class-name satan-sway-classes))
              (setq err (format "unknown class: %s" class-name)))
             ((null record)
              (setq err (format "class %s: empty record" class-name)))
             (t
              (let ((argv (satan-sway--class-args record)))
                (if (eq (car argv) 'error)
                    (setq err (format "class %s: %s" class-name (cdr argv)))
                  (let ((res (apply #'satan-sway--swaymsg
                                    (concat "client." class-name)
                                    (cdr argv))))
                    (if (eq (car res) 'error)
                        (setq err (format "class %s: %s" class-name (cdr res)))
                      (push class-name applied))))))))
          (setq cursor (cddr cursor)))
        (cond
         (err (cons 'error err))
         (t
          (condition-case ierr
              (let* ((applied-list (nreverse applied))
                     (iv-id (satan-intervention-create
                             :ctx ctx
                             :kind "visible_sign"
                             :target-surface satan-sway-intervention-target-surface
                             :message (format "border set on: %s"
                                              (mapconcat #'identity applied-list ", "))
                             :expected-outcome
                             satan-sway-intervention-expected-outcome
                             :outcome-window-minutes
                             satan-sway-intervention-window-minutes
                             :severity "low")))
                (cons 'ok (list :applied applied-list :intervention_id iv-id)))
             (error (cons 'error (error-message-string ierr)))))))))))

(defun satan-tool/sway-border-reset (_args _ctx)
  "Re-read `~/.config/sway/config' via `swaymsg reload'.
Reverts every border declaration to its sway.conf value."
  (let ((res (satan-sway--swaymsg "reload")))
    (if (eq (car res) 'ok)
        (cons 'ok (list :reloaded t))
      res)))

(let ((colour-field
       (list :type 'string
             :required t
             :pattern satan-sway-hex-pattern))
      (colour-field-optional
       (list :type 'string
             :required nil
             :pattern satan-sway-hex-pattern)))
  (let* ((class-shape
          (list 'border       colour-field
                'background   colour-field
                'text         colour-field
                'indicator    colour-field-optional
                'child_border colour-field-optional))
         (classes-shape
          (apply #'append
                 (mapcar (lambda (cls)
                           (list (intern cls)
                                 (list :type 'object
                                       :required nil
                                       :shape class-shape)))
                         satan-sway-classes))))
    (satan-tool-register
     (list :name "sway_border_set"
           :risk 'medium
           :args-schema (list 'classes
                              (list :type 'object
                                    :required t
                                    :shape classes-shape))
           :handler 'satan-tool/sway-border-set))))

(satan-tool-register
 (list :name "sway_border_reset"
       :risk 'medium
       :args-schema nil
       :handler 'satan-tool/sway-border-reset))

(provide 'satan-tools-sway)
;;; satan-tools-sway.el ends here
