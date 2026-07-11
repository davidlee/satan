;;; dl-satan-block.el --- SATAN-owned org-block find/replace -*- lexical-binding: t; -*-

;; A SATAN-owned block looks like:
;;
;;   #+begin_satan :block satan :owner SATAN :updated [2026-05-19 Tue 07:30]
;;   ...replaceable content...
;;   #+end_satan
;;
;; `dl-satan-block-replace' finds the unique pair where the params line has
;; both `:block NAME' and `:owner SATAN' and rewrites only the body bytes
;; plus the `:updated' parameter.  Zero matches → caller may auto-create at
;; EOF (helper provided).  Multi-match → refused; caller should stage a
;; proposal instead.

(require 'cl-lib)
(require 'subr-x)

(defconst dl-satan-block--begin-re
  "^#\\+begin_satan\\b\\([^\n]*\\)$"
  "Regex matching the SATAN block opening line.  Capture 1: params.")

(defconst dl-satan-block--end-re
  "^#\\+end_satan\\b[^\n]*$"
  "Regex matching the SATAN block closing line.")

(defun dl-satan-block--param (params key)
  "Return value of `:KEY' in PARAMS (string), or nil."
  (when (string-match
         (concat ":" (regexp-quote key) "[ \t]+\\([^ \t\n]+\\)")
         params)
    (match-string 1 params)))

(defun dl-satan-block--ts-now ()
  (format-time-string "[%Y-%m-%d %a %H:%M]" nil))

(defun dl-satan-block--find-all (block-name)
  "Return list of (BEGIN-PT BODY-BEGIN BODY-END END-PT PARAMS)
for every block in the current buffer with matching `:block BLOCK-NAME'
and `:owner SATAN'."
  (let (matches)
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward dl-satan-block--begin-re nil t)
        (let* ((begin-pt (match-beginning 0))
               (params   (match-string 1))
               (after-begin-line (line-end-position))
               (block-p  (dl-satan-block--param params "block"))
               (owner-p  (dl-satan-block--param params "owner")))
          (when (and (equal block-p block-name)
                     (equal owner-p "SATAN")
                     (re-search-forward dl-satan-block--end-re nil t))
            (push (list begin-pt
                        (1+ after-begin-line)
                        (match-beginning 0)
                        (match-end 0)
                        params)
                  matches)))))
    (nreverse matches)))

(defun dl-satan-block--render-begin-line (params)
  "Rewrite PARAMS string to set `:updated' to now."
  (let* ((stripped
          (replace-regexp-in-string
           ":updated[ \t]+\\[[^]]*\\]" "" params))
         (clean (string-trim stripped)))
    (concat "#+begin_satan "
            (if (string-empty-p clean) "" (concat clean " "))
            ":updated " (dl-satan-block--ts-now))))

(defun dl-satan-block-replace (file block-name content)
  "Replace body of the unique SATAN block named BLOCK-NAME in FILE with CONTENT.
Return one of: ok, none-match, multi-match.
On `ok' the file's `:updated' parameter is refreshed."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (insert-file-contents file))
    (let ((matches (dl-satan-block--find-all block-name)))
      (cond
       ((null matches) 'none-match)
       ((> (length matches) 1) 'multi-match)
       (t
        (cl-destructuring-bind (begin-pt body-begin body-end _end-pt params)
            (car matches)
          (goto-char body-begin)
          (delete-region body-begin body-end)
          (insert (if (string-suffix-p "\n" content) content (concat content "\n")))
          (goto-char begin-pt)
          (delete-region begin-pt (line-end-position))
          (insert (dl-satan-block--render-begin-line params)))
        (let ((coding-system-for-write 'utf-8)
              (tmp (concat file ".tmp")))
          (write-region (point-min) (point-max) tmp nil 'silent)
          (rename-file tmp file t))
        'ok)))))

(defun dl-satan-block-create-at-end (file block-name content)
  "Append a fresh SATAN block named BLOCK-NAME with CONTENT to FILE.  Returns `ok'."
  (with-temp-buffer
    (let ((coding-system-for-read 'utf-8))
      (when (file-exists-p file) (insert-file-contents file)))
    (goto-char (point-max))
    (unless (or (= (point) (point-min))
                (eq (char-before) ?\n))
      (insert "\n"))
    (insert "\n")
    (insert "#+begin_satan :block " block-name
            " :owner SATAN :updated " (dl-satan-block--ts-now) "\n")
    (insert (if (string-suffix-p "\n" content) content (concat content "\n")))
    (insert "#+end_satan\n")
    (let ((coding-system-for-write 'utf-8)
          (tmp (concat file ".tmp")))
      (write-region (point-min) (point-max) tmp nil 'silent)
      (rename-file tmp file t)))
  'ok)

(provide 'dl-satan-block)
;;; dl-satan-block.el ends here
