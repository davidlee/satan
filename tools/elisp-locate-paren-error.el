;;; elisp-locate-paren-error.el --- JSON paren locator for agents -*- lexical-binding: t; -*-

(require 'json)

(defun agent-parens--line-text ()
  (buffer-substring-no-properties
    (line-beginning-position)
    (line-end-position)))

(defun agent-parens--pos-info (pos)
  (save-excursion
    (goto-char pos)
    `((pos . ,pos)
       (line . ,(line-number-at-pos))
       (column . ,(current-column))
       (char . ,(unless (eobp) (char-to-string (char-after))))
       (text . ,(agent-parens--line-text))
       (toplevel . ,(agent-parens--toplevel-info pos)))))

(defun agent-parens--toplevel-info (pos)
  (save-excursion
    (goto-char pos)
    (condition-case nil
      (progn
        (beginning-of-defun)
        (let ((start (point)))
          (end-of-defun)
          `((start . ,start)
             (end . ,(point))
             (start_line . ,(save-excursion
                              (goto-char start)
                              (line-number-at-pos)))
             (end_line . ,(line-number-at-pos)))))
      (error nil))))

(defun agent-parens--open-stack (&optional bound)
  "Return parens still open at BOUND (default point-max), innermost first.

Each entry is the unclosed opener that is on the parser stack at BOUND.
For a missing-closer error this is the smoking gun: the innermost entry
is the opener whose `)' was never written."
  (save-excursion
    (let* ((bound (or bound (point-max)))
            (state (parse-partial-sexp (point-min) bound))
            ;; Parser state slot 9 is the stack of open paren positions.
            ;; Slot 1 is the innermost containing list, used as a fallback.
            (positions (or (nth 9 state)
                         (when (nth 1 state)
                           (list (nth 1 state))))))
      ;; Most useful for repair is the innermost opener first.
      (mapcar #'agent-parens--pos-info (reverse positions)))))

(defun agent-parens--diagnose (err-pos)
  "Classify a paren error at ERR-POS.

`check-parens' leaves point either ON a stray closer (parser depth is
already 0 there) or ON an opener whose closer is missing.  Returns a
plist: :kind, :hint, :stack — where :stack is the open-paren stack at
the bound that is most useful for THIS kind of repair."
  (let* ((before (condition-case nil
                   (agent-parens--open-stack err-pos)
                   (error nil)))
          (char (save-excursion
                  (goto-char err-pos)
                  (unless (eobp) (char-after))))
          (closer (memq char '(?\) ?\] ?\}))))
    (if (and closer (null before))
      ;; Depth already 0 at this closer: it is extra, OR a closer earlier
      ;; in this top-level form is missing. Stack BEFORE the closer shows
      ;; the (empty here) enclosing context; the defun bounds the repair.
      (list :kind "unmatched-closing-delimiter"
        :hint (concat "Extra closing delimiter here, or a missing closer "
                "earlier in this top-level form. Restrict repairs to "
                "toplevel.start_line..toplevel.end_line.")
        :stack before)
      ;; ERR-POS is the opener that never closed. Parse THROUGH it so the
      ;; opener itself is the innermost open_stack entry.
      (list :kind "unclosed-opener"
        :hint (concat "Delimiter opened here is never closed. The "
                "innermost open_stack entry is the offending opener; "
                "add its closer (often at the end of this top-level form).")
        :stack (condition-case nil
                 (agent-parens--open-stack (min (point-max) (1+ err-pos)))
                 (error nil))))))

(defun agent-parens--report ()
  (emacs-lisp-mode)
  ;; NB: no `save-excursion' around `check-parens' — on error it leaves point
  ;; ON the offending delimiter, and we need that point in the handler.
  (goto-char (point-min))
  (condition-case err
    (progn
      (check-parens)
      (let ((stack (agent-parens--open-stack)))
        (if stack
          `((ok . :json-false)
             (kind . "eof-with-open-parens")
             (message . "Buffer ends with unclosed parens")
             (open_stack . ,(vconcat stack)))
          `((ok . t)))))
    (error
      (let* ((err-pos (point))
              (diag (agent-parens--diagnose err-pos)))
        `((ok . :json-false)
           (kind . ,(plist-get diag :kind))
           (message . ,(error-message-string err))
           (hint . ,(plist-get diag :hint))
           (error . ,(agent-parens--pos-info err-pos))
           (open_stack . ,(vconcat (plist-get diag :stack))))))))

(defun agent-parens-check-file (file)
  (with-temp-buffer
    (insert-file-contents file)
    (let ((report (agent-parens--report)))
      (princ (json-encode report))
      (terpri)
      (unless (eq t (alist-get 'ok report))
        (kill-emacs 2)))))

(let ((file (car command-line-args-left)))
  (unless file
    (princ "{\"ok\":false,\"message\":\"usage: emacs -Q --batch -l tools/elisp-locate-paren-error.el FILE\"}\n")
    (kill-emacs 64))
  (agent-parens-check-file file))

(provide 'dl-elisp-locate-paren-error)
;;; dl-elisp-locate-paren-error.el ends here
