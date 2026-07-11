;;; satan-protocol.el --- SATAN JSONL protocol validator -*- lexical-binding: t; -*-

;; Validates messages crossing the broker/harness membrane.  See
;; protocol/PROTOCOL.md for the canonical spec; protocol/fixtures.json
;; holds shared exemplars consumed by both the ert suite and the python
;; unittest suite.
;;
;; Public API:
;;   (satan-protocol-validate DIRECTION OBJ)
;;     DIRECTION is the symbol `in' (harness -> broker) or `out'
;;     (broker -> harness).  OBJ is the parsed plist coming out of
;;     `satan-jsonl-make-filter'.  Returns nil on success, or a plist
;;     `(:type TYPE :reason STR)' on failure.
;;
;;   (satan-protocol-fixtures &optional PATH)
;;     Read the shared fixtures.json into a list of plists.

(require 'cl-lib)
(require 'json)

(defconst satan-protocol-types-in
  '("ready" "log" "tool_call" "final" "error")
  "Message types valid when sent from harness to broker.")

(defconst satan-protocol-types-out
  '("tool_result")
  "Message types valid when sent from broker to harness.")

(defconst satan-protocol-tool-name-re "\\`[a-zA-Z0-9_-]+\\'"
  "Allowed pattern for `tool_call.name'.  Must match every OpenAI-compatible
adapter's tool-name validator; see SATAN.md.")

(defun satan-protocol--field-name (key)
  (substring (symbol-name key) 1))

(defun satan-protocol--err (type reason)
  (list :type type :reason reason))

(defun satan-protocol--object-p (v)
  "Return non-nil when V looks like a JSON object after plist parsing.
JSON `{}' parses to nil; non-empty objects parse to plists (keyword
car).  Empty objects are indistinguishable from empty arrays at this
layer — accept both."
  (or (null v)
      (and (consp v) (keywordp (car v)))))

(defun satan-protocol--array-p (v)
  "Return non-nil when V is a JSON array (proper list, not a plist).
nil represents both `{}' and `[]' after parsing; accept it as the
empty array."
  (or (null v)
      (and (consp v) (not (keywordp (car v))))))

(defun satan-protocol--require-string (obj key)
  (cond
   ((not (plist-member obj key))
    (format "missing required field: %s" (satan-protocol--field-name key)))
   ((not (stringp (plist-get obj key)))
    (format "field %s must be string" (satan-protocol--field-name key)))))

(defun satan-protocol--require-bool (obj key)
  (cond
   ((not (plist-member obj key))
    (format "missing required field: %s" (satan-protocol--field-name key)))
   ((not (let ((v (plist-get obj key))) (or (eq v t) (eq v :false))))
    (format "field %s must be boolean" (satan-protocol--field-name key)))))

(defun satan-protocol--validate-ready (obj)
  (satan-protocol--require-string obj :run_id))

(defun satan-protocol--validate-log (obj)
  (satan-protocol--require-string obj :kind))

(defun satan-protocol--validate-tool-call (obj)
  (or (satan-protocol--require-string obj :id)
      (satan-protocol--require-string obj :name)
      (let ((name (plist-get obj :name)))
        (unless (string-match-p satan-protocol-tool-name-re name)
          "field name must match ^[a-zA-Z0-9_-]+$"))
      (cond
       ((not (plist-member obj :args))
        "missing required field: args")
       ((not (satan-protocol--object-p (plist-get obj :args)))
        "field args must be object"))))

(defun satan-protocol--validate-action (a)
  (cond
   ((not (satan-protocol--object-p a)) "action must be object")
   ((not (plist-member a :type)) "action missing type")
   ((not (stringp (plist-get a :type))) "action type must be string")))

(defun satan-protocol--validate-final (obj)
  (or (satan-protocol--require-string obj :summary)
      (cond
       ((not (plist-member obj :actions))
        "missing required field: actions")
       ((not (satan-protocol--array-p (plist-get obj :actions)))
        "field actions must be array"))
      (cl-loop for a in (plist-get obj :actions)
               for e = (satan-protocol--validate-action a)
               when e return e)
      (when (and (plist-member obj :reason)
                 (not (stringp (plist-get obj :reason))))
        "field reason must be string")))

(defun satan-protocol--validate-error (obj)
  (satan-protocol--require-string obj :error))

(defun satan-protocol--validate-tool-result (obj)
  (or (satan-protocol--require-string obj :id)
      (satan-protocol--require-bool obj :ok)
      (let ((ok (plist-get obj :ok)))
        (cond
         ((eq ok t)
          (unless (plist-member obj :result) "ok=true requires result"))
         ((eq ok :false)
          (unless (plist-member obj :error) "ok=false requires error"))))))

(defun satan-protocol-validate (direction obj)
  "Validate OBJ for DIRECTION (`in' or `out').
Return nil on success, or a plist `(:type TYPE :reason STR)' on failure."
  (let ((allowed (pcase direction
                   ('in satan-protocol-types-in)
                   ('out satan-protocol-types-out)
                   (_ (error "satan-protocol-validate: bad direction %S"
                             direction)))))
    (cond
     ((not (plist-member obj :type))
      (satan-protocol--err nil "missing required field: type"))
     ((not (stringp (plist-get obj :type)))
      (satan-protocol--err (plist-get obj :type) "field type must be string"))
     (t
      (let ((type (plist-get obj :type)))
        (cond
         ((not (member type allowed))
          (satan-protocol--err
           type
           (if (or (member type satan-protocol-types-in)
                   (member type satan-protocol-types-out))
               (format "type %s not valid for direction %s" type direction)
             (format "unknown message type: %s" type))))
         (t
          (let ((reason
                 (pcase type
                   ("ready"       (satan-protocol--validate-ready obj))
                   ("log"         (satan-protocol--validate-log obj))
                   ("tool_call"   (satan-protocol--validate-tool-call obj))
                   ("final"       (satan-protocol--validate-final obj))
                   ("error"       (satan-protocol--validate-error obj))
                   ("tool_result" (satan-protocol--validate-tool-result obj)))))
            (when reason (satan-protocol--err type reason))))))))))

(defconst satan-protocol--source-dir
  (file-name-directory (or load-file-name buffer-file-name))
  "Directory of this file at load time; used to anchor fixture path lookup.")

(defun satan-protocol-fixtures-path ()
  "Resolve the on-disk path to fixtures.json."
  (expand-file-name "protocol/fixtures.json" satan-protocol--source-dir))

(defun satan-protocol-fixtures (&optional path)
  "Read fixtures.json (default `satan-protocol-fixtures-path') into a list."
  (let ((p (or path (satan-protocol-fixtures-path))))
    (with-temp-buffer
      (insert-file-contents p)
      (let ((raw (json-parse-buffer :object-type 'plist
                                    :array-type 'list
                                    :null-object :null
                                    :false-object :false)))
        (plist-get raw :fixtures)))))

(provide 'satan-protocol)
;;; satan-protocol.el ends here
