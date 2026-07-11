;;; dl-satan-tools.el --- Tool registry + dispatch -*- lexical-binding: t; -*-

;; The broker holds a registry of tool-specs.  A tool-spec carries
;; mechanism only — name, risk, schema, handler:
;;
;;   (:name        "org_read_context"
;;    :risk        read|low|medium|high
;;    :args-schema (KEY (:type symbol :required bool :enum (...)))*
;;    :handler     dl-satan-tool/org-read-context)
;;
;; The mode→tools allowlist is authoritative on the mode-spec
;; (`:tools' list in `dl-satan-mode.el'); `dl-satan-mode-check-tool-
;; references' enforces that every name listed there resolves in this
;; registry.  The model-facing description for each tool lives outside
;; dotfiles, under `dl-satan-tools-descriptions-dir' (default
;; `~/notes/satan/tools/<name>.md').  See `dl-satan-tool-json-schema'.
;;
;; `dl-satan-tool-dispatch' performs lookup, allowlist check, schema
;; validation, and invokes the handler.  Handler returns (ok . RESULT) or
;; (error . MESSAGE).

(require 'cl-lib)
(require 'subr-x)
(require 'dl-notes-paths)

(defcustom dl-satan-tools-descriptions-dir
  (expand-file-name "satan/tools/" dl-notes-root)
  "Directory holding model-facing tool description files.
One markdown file per tool, named `<tool-name>.md'.  Canonical
behavioural text for each tool lives here; the elisp tool-spec
carries only mechanism (schema, capability, handler)."
  :type 'directory :group 'dl-satan)

(defvar dl-satan-tools nil
  "Alist of (NAME . SPEC) tool registrations.")

(defun dl-satan-tool-register (spec)
  "Register or replace tool SPEC keyed by its `:name'."
  (let ((name (plist-get spec :name)))
    (setq dl-satan-tools
          (cons (cons name spec)
                (cl-remove name dl-satan-tools :key #'car :test #'equal)))))

(defun dl-satan-tool-lookup (name)
  (cdr (assoc name dl-satan-tools)))

(defun dl-satan-tool-allowed-p (name mode-tools)
  "Return non-nil if NAME is present in MODE-TOOLS (mode's :tools allowlist)."
  (and mode-tools (member name mode-tools) t))

(defun dl-satan-tool--plist-like-p (val)
  "Return non-nil if VAL is a (possibly empty) plist whose keys are keywords."
  (and (listp val)
       (or (null val)
           (and (keywordp (car val))
                (= (mod (length val) 2) 0)))))

(defun dl-satan-tool--validate-arg (args key constraints)
  "Validate ARGS[KEY] against CONSTRAINTS plist.
Return nil on success, or an error string.

Supported constraints:
  :type       string|integer|boolean|number|object|array
  :required   bool
  :enum       (list-of-values)
  :pattern    REGEXP  (string types only)
  :shape      ARGS-SCHEMA  (object types only; recursive)
  :items      SYMBOL or CONSTRAINTS-plist  (array types only)"
  (let* ((sym (intern (concat ":" (symbol-name key))))
         (val (plist-get args sym))
         (required (plist-get constraints :required)))
    (cond
     ((and required (null val))
      (format "missing required arg: %s" key))
     ((null val) nil)
     (t (dl-satan-tool--validate-value val constraints (symbol-name key))))))

(defun dl-satan-tool--validate-value (val constraints label)
  "Validate VAL (non-nil) against CONSTRAINTS plist.
LABEL is the human-readable name used in error strings (e.g. \"tags\"
or \"tags[2]\"). Returns nil on success, or an error string. Does not
re-check `:required'."
  (let ((type    (plist-get constraints :type))
        (enum    (plist-get constraints :enum))
        (pattern (plist-get constraints :pattern))
        (shape   (plist-get constraints :shape))
        (items   (plist-get constraints :items)))
    (cond
     ((and (eq type 'string) (not (stringp val)))
      (format "arg %s must be string" label))
     ((and (eq type 'integer) (not (integerp val)))
      (format "arg %s must be integer" label))
     ((and (eq type 'number) (not (numberp val)))
      (format "arg %s must be number" label))
     ((and (eq type 'object) (not (dl-satan-tool--plist-like-p val)))
      (format "arg %s must be object" label))
     ((and (eq type 'array) (not (or (listp val) (vectorp val))))
      (format "arg %s must be array" label))
     ((and enum (not (member val enum)))
      (format "arg %s must be one of %S" label enum))
     ((and pattern (stringp val) (not (string-match-p pattern val)))
      (format "arg %s must match %s" label pattern))
     ((and (eq type 'object) shape)
      (let ((cursor shape) err)
        (while (and cursor (null err))
          (setq err (dl-satan-tool--validate-arg val (car cursor) (cadr cursor)))
          (setq cursor (cddr cursor)))
        err))
     ((and (eq type 'array) items)
      (let* ((item-constraints (dl-satan-tool--items-constraints items))
             (idx 0) err)
        (cl-loop for el being the elements of val
                 while (null err)
                 do (setq err
                          (if (null el)
                              (format "arg %s[%d] must not be nil" label idx)
                            (dl-satan-tool--validate-value
                             el item-constraints
                             (format "%s[%d]" label idx))))
                 do (cl-incf idx))
        err))
     (t nil))))

(defun dl-satan-tool--items-constraints (items)
  "Coerce an `:items' spec to a constraints plist.
ITEMS is either a TYPE symbol (e.g. `string') or a constraints plist."
  (cond
   ((symbolp items) (list :type items))
   ((and (consp items) (keywordp (car items))) items)
   (t (error "SATAN: bad :items spec: %S" items))))

(defun dl-satan-tool-validate-args (spec args)
  "Return nil if ARGS conform to SPEC `:args-schema', else error string."
  (let ((schema (plist-get spec :args-schema))
        err)
    (while (and schema (null err))
      (let ((key (car schema))
            (constraints (cadr schema)))
        (setq err (dl-satan-tool--validate-arg args key constraints))
        (setq schema (cddr schema))))
    err))

(defun dl-satan-tool--capability-denied-p (spec run-ctx)
  "Return the required capability when SPEC's `:capability' is unmet by RUN-CTX.
Returns nil when SPEC declares no capability, or when the capability
is present in RUN-CTX's `:capabilities' (the tool-ctx plist threaded
through the broker)."
  (let ((required (plist-get spec :capability))
        (caps (and run-ctx (plist-get run-ctx :capabilities))))
    (when (and required (not (memq required caps)))
      required)))

(defun dl-satan-tool-dispatch (call mode-tools run-ctx)
  "Dispatch a `tool_call' plist CALL.  Return a `tool_result' plist.
MODE-TOOLS is the current mode's allowlist.  RUN-CTX is the tool-ctx
plist; the capability guard (Phase 0.2) reads `:capabilities' from it
and rejects the call BEFORE invoking the handler when the tool's
declared `:capability' is absent."
  (let* ((id   (plist-get call :id))
         (name (plist-get call :name))
         (args (plist-get call :args))
         (spec (dl-satan-tool-lookup name)))
    (cond
     ((null spec)
      (list :type "tool_result" :id id :ok :false
            :error (format "unknown tool: %s" name)))
     ((not (dl-satan-tool-allowed-p name mode-tools))
      (list :type "tool_result" :id id :ok :false
            :error (format "tool not allowed in this mode: %s" name)))
     ((let ((cap (dl-satan-tool--capability-denied-p spec run-ctx)))
        (when cap
          (list :type "tool_result" :id id :ok :false
                :error (format "capability denied: tool %s requires %s"
                               name cap)))))
     (t
      (let ((schema-err (dl-satan-tool-validate-args spec args)))
        (if schema-err
            (list :type "tool_result" :id id :ok :false :error schema-err)
          (condition-case err
              (let ((res (funcall (plist-get spec :handler) args run-ctx)))
                (if (eq (car-safe res) 'ok)
                    (list :type "tool_result" :id id :ok t :result (cdr res))
                  (list :type "tool_result" :id id :ok :false
                        :error (format "%s" (cdr res)))))
            (error
             (list :type "tool_result" :id id :ok :false
                   :error (error-message-string err))))))))))

;; ---------- Model-facing schema (manifest assembly) ----------
;;
;; The broker writes the full OpenAI-tools JSON Schema for every allowed
;; tool into `manifest.json'.  Schemas are assembled from two sources:
;;
;;   - mechanical (this file + elisp tool-spec): `:args-schema',
;;     types/required/enum, tool name.
;;   - model-facing (notes): description text under
;;     `dl-satan-tools-descriptions-dir'.
;;
;; The harness reads schemas verbatim from the manifest; no canonical
;; descriptions live in dotfiles.

(defun dl-satan-tool--description (name)
  "Return the model-facing description for tool NAME.
Reads `<dl-satan-tools-descriptions-dir>/<name>.md'; signals if
missing — a tool without a description is a misconfiguration."
  (let ((path (expand-file-name (concat name ".md")
                                dl-satan-tools-descriptions-dir)))
    (unless (file-readable-p path)
      (error "SATAN: tool description missing: %s" path))
    (with-temp-buffer
      (let ((coding-system-for-read 'utf-8))
        (insert-file-contents path))
      (string-trim (buffer-string)))))

(defun dl-satan-tool--jsonschema-type (sym)
  "Map an `:args-schema' type symbol to its JSON Schema name."
  (pcase sym
    ('string  "string")
    ('integer "integer")
    ('boolean "boolean")
    ('number  "number")
    ('object  "object")
    ('array   "array")
    (_ (error "SATAN: unsupported arg type: %S" sym))))

(defun dl-satan-tool--pattern-to-jsonschema (pattern)
  "Translate Elisp regex PATTERN to a JS-compatible regex string.
Only handles the subset of Elisp regex features we use in tool
schemas:
  \\`  → ^     (beginning-of-string anchor)
  \\'  → $     (end-of-string anchor)
  \\{  → {     (quantifier brace open)
  \\}  → }     (quantifier brace close)"
  (thread-last pattern
    (string-replace "\\`" "^")
    (string-replace "\\'" "$")
    (string-replace "\\{" "{")
    (string-replace "\\}" "}")))

(defun dl-satan-tool--args-schema-to-jsonschema (args-schema)
  "Convert an elisp `:args-schema' plist into a JSON Schema parameters dict.
Returns a plist: (:type \"object\" :properties (...) :required [...]).
Recurses into `:shape' for nested object args."
  (let ((props nil)
        (required nil)
        (cursor args-schema))
    (while cursor
      (let* ((key (car cursor))
             (constraints (cadr cursor))
             (type (plist-get constraints :type))
             (enum (plist-get constraints :enum))
             (pattern (plist-get constraints :pattern))
             (shape (plist-get constraints :shape))
             (items (plist-get constraints :items))
             (req  (plist-get constraints :required))
             (prop (cond
                    ((and (eq type 'object) shape)
                     (dl-satan-tool--args-schema-to-jsonschema shape))
                    ((eq type 'array)
                     (let ((p (list :type "array")))
                       (when items
                         (setq p (plist-put p :items
                                            (dl-satan-tool--items-jsonschema
                                             items))))
                       p))
                    (t (list :type (dl-satan-tool--jsonschema-type type))))))
        (when enum
          (setq prop (plist-put prop :enum (vconcat enum))))
        (when pattern
          (setq prop (plist-put prop :pattern
                                (dl-satan-tool--pattern-to-jsonschema pattern))))
        (push (cons (intern (concat ":" (symbol-name key))) prop) props)
        (when req
          (push (symbol-name key) required)))
      (setq cursor (cddr cursor)))
    (let ((properties (apply #'append
                             (mapcar (lambda (kv)
                                       (list (car kv) (cdr kv)))
                                     (nreverse props)))))
      (list :type "object"
            :properties properties
            :required (vconcat (nreverse required))))))

(defun dl-satan-tool--items-jsonschema (items)
  "Convert an `:items' spec to its JSON Schema fragment.
ITEMS is a TYPE symbol or a constraints plist; for `:type \\='object\\='
with `:shape', recurses to build an object schema."
  (cond
   ((symbolp items)
    (list :type (dl-satan-tool--jsonschema-type items)))
   ((and (consp items) (keywordp (car items)))
    (let* ((itype   (plist-get items :type))
           (shape   (plist-get items :shape))
           (enum    (plist-get items :enum))
           (pattern (plist-get items :pattern)))
      (cond
       ((and (eq itype 'object) shape)
        (dl-satan-tool--args-schema-to-jsonschema shape))
       (t
        (let ((p (list :type (dl-satan-tool--jsonschema-type itype))))
          (when enum    (setq p (plist-put p :enum (vconcat enum))))
          (when pattern (setq p (plist-put p :pattern pattern)))
          p)))))
   (t (error "SATAN: bad :items spec: %S" items))))

(defun dl-satan-tool-json-schema (tool-spec)
  "Return the OpenAI-tools dict for TOOL-SPEC, ready for the manifest.
Description is loaded from `dl-satan-tools-descriptions-dir'."
  (let* ((name (plist-get tool-spec :name))
         (desc (dl-satan-tool--description name))
         (params (dl-satan-tool--args-schema-to-jsonschema
                  (plist-get tool-spec :args-schema))))
    (list :type "function"
          :function (list :name name
                          :description desc
                          :parameters params))))

(defun dl-satan-tool-final-schema ()
  "Return the synthetic `satan_final' tool schema.
`satan_final' is harness-emitted (terminal signal) but its description
is canonical here so every adapter sees the same text."
  (let ((desc (dl-satan-tool--description "satan_final")))
    (list :type "function"
          :function
          (list :name "satan_final"
                :description desc
                :parameters
                (list :type "object"
                      :properties
                      (list :summary (list :type "string")
                            :actions
                            (list :type "array"
                                  :items
                                  (list :type "object"
                                        :properties
                                        (list :type (list :type "string")
                                              :args (list :type "object"))
                                        :required (vector "type"))))
                      :required (vector "summary"))))))

(provide 'dl-satan-tools)
;;; dl-satan-tools.el ends here
