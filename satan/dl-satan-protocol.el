;;; dl-satan-protocol.el --- SATAN JSONL protocol validator -*- lexical-binding: t; -*-

;; Validates messages crossing the broker/harness membrane.  See
;; protocol/PROTOCOL.md for the canonical spec; protocol/fixtures.json
;; holds shared exemplars consumed by both the ert suite and the python
;; unittest suite.
;;
;; Public API:
;;   (dl-satan-protocol-validate DIRECTION OBJ)
;;     DIRECTION is the symbol `in' (harness -> broker) or `out'
;;     (broker -> harness).  OBJ is the parsed plist coming out of
;;     `dl-satan-jsonl-make-filter'.  Returns nil on success, or a plist
;;     `(:type TYPE :reason STR)' on failure.
;;
;;   (dl-satan-protocol-fixtures &optional PATH)
;;     Read the shared fixtures.json into a list of plists.

(require 'cl-lib)
(require 'json)

(defconst dl-satan-protocol-types-in
  '("ready" "log" "tool_call" "final" "error")
  "Message types valid when sent from harness to broker.")

(defconst dl-satan-protocol-types-out
  '("tool_result")
  "Message types valid when sent from broker to harness.")

(defconst dl-satan-protocol-tool-name-re "\\`[a-zA-Z0-9_-]+\\'"
  "Allowed pattern for `tool_call.name'.  Must match every OpenAI-compatible
adapter's tool-name validator; see SATAN.md.")

(defun dl-satan-protocol--field-name (key)
  (substring (symbol-name key) 1))

(defun dl-satan-protocol--err (type reason)
  (list :type type :reason reason))

(defun dl-satan-protocol--object-p (v)
  "Return non-nil when V looks like a JSON object after plist parsing.
JSON `{}' parses to nil; non-empty objects parse to plists (keyword
car).  Empty objects are indistinguishable from empty arrays at this
layer — accept both."
  (or (null v)
      (and (consp v) (keywordp (car v)))))

(defun dl-satan-protocol--array-p (v)
  "Return non-nil when V is a JSON array (proper list, not a plist).
nil represents both `{}' and `[]' after parsing; accept it as the
empty array."
  (or (null v)
      (and (consp v) (not (keywordp (car v))))))

(defun dl-satan-protocol--require-string (obj key)
  (cond
   ((not (plist-member obj key))
    (format "missing required field: %s" (dl-satan-protocol--field-name key)))
   ((not (stringp (plist-get obj key)))
    (format "field %s must be string" (dl-satan-protocol--field-name key)))))

(defun dl-satan-protocol--require-bool (obj key)
  (cond
   ((not (plist-member obj key))
    (format "missing required field: %s" (dl-satan-protocol--field-name key)))
   ((not (let ((v (plist-get obj key))) (or (eq v t) (eq v :false))))
    (format "field %s must be boolean" (dl-satan-protocol--field-name key)))))

(defun dl-satan-protocol--validate-ready (obj)
  (dl-satan-protocol--require-string obj :run_id))

(defun dl-satan-protocol--validate-log (obj)
  (dl-satan-protocol--require-string obj :kind))

(defun dl-satan-protocol--validate-tool-call (obj)
  (or (dl-satan-protocol--require-string obj :id)
      (dl-satan-protocol--require-string obj :name)
      (let ((name (plist-get obj :name)))
        (unless (string-match-p dl-satan-protocol-tool-name-re name)
          "field name must match ^[a-zA-Z0-9_-]+$"))
      (cond
       ((not (plist-member obj :args))
        "missing required field: args")
       ((not (dl-satan-protocol--object-p (plist-get obj :args)))
        "field args must be object"))))

(defun dl-satan-protocol--validate-action (a)
  (cond
   ((not (dl-satan-protocol--object-p a)) "action must be object")
   ((not (plist-member a :type)) "action missing type")
   ((not (stringp (plist-get a :type))) "action type must be string")))

(defun dl-satan-protocol--validate-final (obj)
  (or (dl-satan-protocol--require-string obj :summary)
      (cond
       ((not (plist-member obj :actions))
        "missing required field: actions")
       ((not (dl-satan-protocol--array-p (plist-get obj :actions)))
        "field actions must be array"))
      (cl-loop for a in (plist-get obj :actions)
               for e = (dl-satan-protocol--validate-action a)
               when e return e)
      (when (and (plist-member obj :reason)
                 (not (stringp (plist-get obj :reason))))
        "field reason must be string")))

(defun dl-satan-protocol--validate-error (obj)
  (dl-satan-protocol--require-string obj :error))

(defun dl-satan-protocol--validate-tool-result (obj)
  (or (dl-satan-protocol--require-string obj :id)
      (dl-satan-protocol--require-bool obj :ok)
      (let ((ok (plist-get obj :ok)))
        (cond
         ((eq ok t)
          (unless (plist-member obj :result) "ok=true requires result"))
         ((eq ok :false)
          (unless (plist-member obj :error) "ok=false requires error"))))))

(defun dl-satan-protocol-validate (direction obj)
  "Validate OBJ for DIRECTION (`in' or `out').
Return nil on success, or a plist `(:type TYPE :reason STR)' on failure."
  (let ((allowed (pcase direction
                   ('in dl-satan-protocol-types-in)
                   ('out dl-satan-protocol-types-out)
                   (_ (error "dl-satan-protocol-validate: bad direction %S"
                             direction)))))
    (cond
     ((not (plist-member obj :type))
      (dl-satan-protocol--err nil "missing required field: type"))
     ((not (stringp (plist-get obj :type)))
      (dl-satan-protocol--err (plist-get obj :type) "field type must be string"))
     (t
      (let ((type (plist-get obj :type)))
        (cond
         ((not (member type allowed))
          (dl-satan-protocol--err
           type
           (if (or (member type dl-satan-protocol-types-in)
                   (member type dl-satan-protocol-types-out))
               (format "type %s not valid for direction %s" type direction)
             (format "unknown message type: %s" type))))
         (t
          (let ((reason
                 (pcase type
                   ("ready"       (dl-satan-protocol--validate-ready obj))
                   ("log"         (dl-satan-protocol--validate-log obj))
                   ("tool_call"   (dl-satan-protocol--validate-tool-call obj))
                   ("final"       (dl-satan-protocol--validate-final obj))
                   ("error"       (dl-satan-protocol--validate-error obj))
                   ("tool_result" (dl-satan-protocol--validate-tool-result obj)))))
            (when reason (dl-satan-protocol--err type reason))))))))))

(defconst dl-satan-protocol--source-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory of this file at load time; used to anchor fixture path lookup.")

(defun dl-satan-protocol-fixtures-path ()
  "Resolve the on-disk path to fixtures.json."
  (expand-file-name "protocol/fixtures.json" dl-satan-protocol--source-dir))

(defun dl-satan-protocol-fixtures (&optional path)
  "Read fixtures.json (default `dl-satan-protocol-fixtures-path') into a list."
  (let ((p (or path (dl-satan-protocol-fixtures-path))))
    (with-temp-buffer
      (insert-file-contents p)
      (let ((raw (json-parse-buffer :object-type 'plist
                                    :array-type 'list
                                    :null-object :null
                                    :false-object :false)))
        (plist-get raw :fixtures)))))

(provide 'dl-satan-protocol)
;;; dl-satan-protocol.el ends here
