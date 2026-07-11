;;; dl-satan-jsonl.el --- Line-buffered JSONL filter + writer -*- lexical-binding: t; -*-

;; A `make-process' :filter that splits incoming bytes on \n, parses each
;; complete line as JSON, and calls ON-OBJECT with the parsed plist.  A
;; trailing partial line is kept in an internal accumulator until the next
;; chunk arrives.  Parse errors call ON-ERROR with (raw-line . error-msg).
;;
;; Outbound: `dl-satan-jsonl-send' serializes a plist and writes a single
;; newline-terminated line to a process's stdin.

(require 'cl-lib)
(require 'json)

(defun dl-satan-jsonl--plist-p (x)
  "Heuristic: X is a plist if it is a list whose car is a keyword."
  (and (consp x) (keywordp (car x))))

(defun dl-satan-jsonl--alist-p (x)
  "Heuristic: X is an alist of `(KEY . VAL)' dotted pairs.
Every entry must be a cons whose car is not a keyword (those belong to
plists) and whose cdr is not a list (proper lists belong to lists-of-
lists / lists-of-plists, both walked as JSON arrays).  Empty list is
not an alist."
  (and (consp x) (listp (cdr x))
       (cl-every (lambda (e)
                   (and (consp e)
                        (not (keywordp (car e)))
                        (not (listp (cdr e)))))
                 x)))

(defun dl-satan-jsonl--alist-key-to-keyword (k)
  "Coerce alist key K to a keyword `json-serialize' accepts for a plist."
  (cond
   ((keywordp k) k)
   ((stringp k)  (intern (concat ":" k)))
   ((symbolp k)  (intern (concat ":" (symbol-name k))))
   (t            (intern (format ":%S" k)))))

(defun dl-satan-jsonl-prepare (v)
  "Walk V and coerce non-plist lists into vectors so `json-serialize' accepts them.
Plists (lists whose car is a keyword) are preserved.  Alists (lists of
`(KEY . VAL)' dotted pairs) are flattened into plists so they encode as
JSON objects rather than crashing the serializer on a dotted cdr.
Vectors are walked.  Non-special symbols are stringified
(`json-serialize' rejects symbols other than t / nil / :null / :false
with `wrong-type-argument json-value-p'), so any in-memory symbol that
leaks into a bundle / percept / transcript record survives the wire
layer.  Regular symbols emit their `symbol-name'; keywords drop the
leading colon.  Unibyte strings (raw subprocess argv / child output
bytes, e.g. a `payload=…—…' element) are decoded as UTF-8 so they too
survive the wire layer instead of tripping `json-serialize' on raw
bytes; multibyte strings pass through untouched.  Other atoms pass
through untouched."
  (cond
   ((vectorp v)
    (vconcat (mapcar #'dl-satan-jsonl-prepare (append v nil))))
   ((dl-satan-jsonl--plist-p v)
    (cl-loop for (k val) on v by #'cddr
             append (list k (dl-satan-jsonl-prepare val))))
   ((dl-satan-jsonl--alist-p v)
    (cl-loop for (k . val) in v
             append (list (dl-satan-jsonl--alist-key-to-keyword k)
                          (dl-satan-jsonl-prepare val))))
   ((and (consp v) (listp (cdr v)))
    (vconcat (mapcar #'dl-satan-jsonl-prepare v)))
   ((or (eq v t) (null v) (eq v :null) (eq v :false)) v)
   ((keywordp v) (substring (symbol-name v) 1))
   ((symbolp v)  (symbol-name v))
   ((and (stringp v) (not (multibyte-string-p v)))
    (decode-coding-string v 'utf-8))
   (t v)))

(defun dl-satan-jsonl-make-filter (on-object on-error)
  "Return a stateful filter closure suitable as `make-process' :filter.
ON-OBJECT is called with one decoded plist per JSON line.
ON-ERROR  is called with (RAW-LINE . ERROR-MSG) on parse failure."
  (let ((buf ""))
    (lambda (_proc chunk)
      (setq buf (concat buf chunk))
      (let ((lines (split-string buf "\n" nil)))
        ;; All but the last element are complete lines.
        ;; The last element is the (possibly-empty) trailing partial.
        (setq buf (car (last lines)))
        (dolist (line (butlast lines))
          (let ((trimmed (string-trim-right line "\r")))
            (unless (string-empty-p (string-trim trimmed))
              (condition-case err
                  (let ((obj (json-parse-string
                              trimmed
                              :object-type 'plist
                              :array-type 'list
                              :null-object :null
                              :false-object :false)))
                    (funcall on-object obj))
                (error (funcall on-error
                                (cons trimmed (error-message-string err))))))))))))

(defun dl-satan-jsonl-send (proc obj)
  "Serialize OBJ to JSON and send one newline-terminated line to PROC stdin."
  (let ((line (json-serialize (dl-satan-jsonl-prepare obj)
                              :null-object :null :false-object :false)))
    (process-send-string proc (concat line "\n"))))

(cl-defun dl-satan-jsonl-read-file (path &key null-object)
  "Return a list of plists, one per non-empty JSON line at PATH.
nil if PATH is unreadable.  Malformed lines signal — callers that
need lenient parsing must wrap.  Decoder shape matches the inbound
filter (`:object-type plist', `:array-type list', `:null-object nil',
`:false-object :false') so the round-trip is symmetric for plists
that don't carry JSON nulls.

NULL-OBJECT is passed to `json-parse-string' (default nil).  The
audit transcript reader passes `:null' to match the writer's
`:null-object :null'."
  (when (file-readable-p path)
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (let (acc)
        (goto-char (point-min))
        (while (not (eobp))
          (let ((line (buffer-substring-no-properties
                       (point) (line-end-position))))
            (unless (string-empty-p (string-trim line))
              (push (json-parse-string line
                                       :object-type 'plist
                                       :array-type 'list
                                       :null-object (or null-object nil)
                                       :false-object :false)
                    acc)))
          (forward-line 1))
        (nreverse acc)))))

(provide 'dl-satan-jsonl)
;;; dl-satan-jsonl.el ends here
