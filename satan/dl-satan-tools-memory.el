;;; dl-satan-tools-memory.el --- memory_* tool handlers -*- lexical-binding: t; -*-

;; Step 8 of memory.design.md.  Three tools:
;;
;;   memory_mark        (risk: low,  capability: memory-write)
;;   memory_resonate    (risk: read, capability: none)
;;   memory_show_trace  (risk: read, capability: none)
;;
;; Handlers wire the existing memory subsystem (evidence assembler,
;; canonicalizer, store backend) into the broker's tool surface.
;; Registration only — mode-allowlist wiring happens in
;; `dl-satan-mode.el' via each mode-spec's `:tools'.
;;
;; Sweep items still open (`satan/HANDOVER.md'):
;;   - schema lacks `:type 'array' for some hint subfields (topic, links,
;;     kinds, cue.handles are declared without type and validated in the
;;     handler).

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-tools)
(require 'dl-satan-memory-grammar)
(require 'dl-satan-memory-canon)
(require 'dl-satan-memory-evidence)
(require 'dl-satan-memory-store)

;; ---------------------------------------------------------------------
;; Closed-world enum values (for `:enum' constraints on hint subfields)
;; ---------------------------------------------------------------------

(defconst dl-satan-tools-memory--valence-values
  '("positive" "negative" "neutral" "mixed" "unknown"))

(defconst dl-satan-tools-memory--kind-values
  '("observation" "intervention" "prediction" "outcome"))

(defconst dl-satan-tools-memory--nanoid-pattern
  "\\`[A-Za-z0-9_-]+\\'")

;; ---------------------------------------------------------------------
;; Helpers
;; ---------------------------------------------------------------------

(defun dl-satan-tools-memory--now ()
  "ISO8601 timestamp for canon `:time_now'.  Indirected for stubbing."
  (format-time-string "%Y-%m-%dT%T%:z"))

(defun dl-satan-tools-memory--mode-name (raw)
  "Normalize a broker tool-ctx `:mode-name' to a plain string or nil."
  (cond ((null raw) nil)
        ((symbolp raw) (symbol-name raw))
        ((stringp raw) raw)
        (t (format "%s" raw))))

(defun dl-satan-tools-memory--ctx-from (tool-ctx)
  "Build the canon ctx plist (§3.1) from the broker's TOOL-CTX.
Reads `:time-now' and `:run-started-at' from TOOL-CTX when present
so the evidence window is bounded by the run start.  Falls back to
the wall clock for `:time_now' when the tool-ctx omits it (older
callers and unit fixtures); `:run_started_at' stays nil and the
assembler applies the 10-minute default."
  (list :time_now (or (plist-get tool-ctx :time-now)
                      (dl-satan-tools-memory--now))
        :run_started_at (plist-get tool-ctx :run-started-at)
        :mode_name (dl-satan-tools-memory--mode-name
                    (plist-get tool-ctx :mode-name))
        :run_id (plist-get tool-ctx :id)
        :current_grammar_version dl-satan-memory-grammar-current-version))

;; ---------------------------------------------------------------------
;; Handler-side validation (compensates for the missing `:type 'array')
;; ---------------------------------------------------------------------

(defun dl-satan-tools-memory--validate-string-list (xs label)
  "Return nil if XS is nil or a list of strings, else error string."
  (catch 'err
    (when xs
      (unless (listp xs)
        (throw 'err (format "%s must be array" label)))
      (dolist (x xs)
        (unless (stringp x)
          (throw 'err (format "%s entries must be strings" label)))))
    nil))

(defun dl-satan-tools-memory--validate-links (links)
  "Return nil if LINKS is nil or a list of `{relation, target_trace_id}',
else an error string."
  (catch 'err
    (when links
      (unless (listp links)
        (throw 'err "links must be array"))
      (dolist (l links)
        (unless (dl-satan-tool--plist-like-p l)
          (throw 'err "links entries must be objects"))
        (let ((rel (plist-get l :relation))
              (tgt (plist-get l :target_trace_id)))
          (unless (and (stringp rel) (not (string-empty-p rel)))
            (throw 'err "links entry missing relation"))
          (unless (and (stringp tgt) (not (string-empty-p tgt)))
            (throw 'err "links entry missing target_trace_id")))))
    nil))

(defun dl-satan-tools-memory--validate-hints (hints)
  "Return nil if HINTS is nil or a plist with a well-shaped `:topic',
else an error string.  Closed-world scalar fields are schema-enforced
upstream; this only catches the array entry whose type the registry
cannot express yet."
  (cond
   ((null hints) nil)
   ((not (dl-satan-tool--plist-like-p hints)) "hints must be object")
   (t (dl-satan-tools-memory--validate-string-list
       (plist-get hints :topic) "hints.topic"))))

;; ---------------------------------------------------------------------
;; memory_mark
;; ---------------------------------------------------------------------

(defun dl-satan-tool/memory-mark (args tool-ctx)
  "Handler for `memory_mark'.  See §5.1 of memory.design.md."
  (let* ((payload (plist-get args :payload))
         (raw-hints (plist-get args :hints))
         (top-valence (plist-get args :valence))
         (links (plist-get args :links))
         (err (cond
               ((not (stringp payload)) "payload must be string")
               ((string-empty-p payload) "payload must be non-empty")
               (t (or (dl-satan-tools-memory--validate-hints raw-hints)
                      (dl-satan-tools-memory--validate-links links))))))
    (if err
        (cons 'error err)
      (dl-satan-tools-memory--mark-impl
       payload raw-hints top-valence links tool-ctx))))

(defun dl-satan-tools-memory--mark-impl (payload raw-hints top-valence links tool-ctx)
  "Assemble, canonicalize, store; return the §5.1 result."
  (let* ((ctx (dl-satan-tools-memory--ctx-from tool-ctx))
         (evidence (dl-satan-memory-evidence-assemble
                    ctx (list :run_started_at
                              (plist-get ctx :run_started_at))))
         (canon (dl-satan-memory-canon-canonicalize-from-raw
                 evidence raw-hints ctx))
         (handles (plist-get canon :handles))
         (sources (plist-get canon :handle_sources))
         (rejected (plist-get canon :rejected))
         (normalized (plist-get canon :normalized))
         (kind (or (plist-get normalized :kind) "observation"))
         (valence (or top-valence (plist-get normalized :valence)))
         (gv (plist-get ctx :current_grammar_version))
         (mode-name (plist-get ctx :mode_name))
         (handle-rows
          (mapcar
           (lambda (h)
             (list :handle h
                   :source (cdr (assoc h sources))
                   :grammar_version gv))
           handles))
         (metadata
          (list :evidence evidence
                :hints (or raw-hints '())
                :normalized_hints (or normalized '())
                :ctx ctx
                :truncated_at (plist-get evidence :truncated_at)))
         (result
          (dl-satan-memory-store-mark
           :kind kind
           :trace-origin "llm_mark"
           :source (format "memory_mark@%s" (or mode-name "unknown"))
           :observed-start-at (plist-get evidence :window_start_at)
           :observed-end-at   (plist-get evidence :window_end_at)
           :payload payload
           :valence valence
           :grammar-version gv
           :metadata-json metadata
           :handles handle-rows
           :links links)))
    (pcase result
      (`(ok . ,tid)
       (cons 'ok (list :trace_id tid
                       :handles handles
                       :rejected rejected)))
      (err err))))

;; ---------------------------------------------------------------------
;; memory_resonate
;; ---------------------------------------------------------------------

(defun dl-satan-tool/memory-resonate (args tool-ctx)
  "Handler for `memory_resonate'.  See §5.2 of memory.design.md."
  (let* ((cue (plist-get args :cue))
         (limit (or (plist-get args :limit) 5))
         (kinds (plist-get args :kinds))
         (min-score (or (plist-get args :min_score) 0.0))
         (err
          (cond
           ((and cue (not (dl-satan-tool--plist-like-p cue)))
            "cue must be object")
           (t
            (or (dl-satan-tools-memory--validate-hints
                 (plist-get cue :hints))
                (dl-satan-tools-memory--validate-string-list
                 (plist-get cue :handles) "cue.handles")
                (dl-satan-tools-memory--validate-string-list
                 kinds "kinds")
                (and (or (not (integerp limit))
                         (< limit 1)
                         (> limit 25))
                     "limit must be integer 1..25"))))))
    (if err
        (cons 'error err)
      (dl-satan-tools-memory--resonate-impl
       cue limit kinds min-score tool-ctx))))

(defun dl-satan-tools-memory--resonate-impl (cue limit kinds min-score tool-ctx)
  "Resolve cue handles and call the store."
  (let* ((explicit (plist-get cue :handles))
         (cue-handles
          (or explicit
              (dl-satan-tools-memory--derive-cue-handles
               (plist-get cue :hints) tool-ctx)))
         (result
          (dl-satan-memory-store-resonate
           :cue-handles cue-handles
           :grammar-version dl-satan-memory-grammar-current-version
           :limit limit
           :kinds kinds
           :min-score min-score)))
    (pcase result
      (`(ok . ,matches)
       (cons 'ok (list :matches matches
                       :cue_handles cue-handles)))
      (err err))))

(defun dl-satan-tools-memory--derive-cue-handles (hints tool-ctx)
  "Run the evidence + canon pipeline with HINTS to produce a cue list.
Passes `:cue_only t' to the assembler so the heavy \"what happened\"
probes (focus/browser segments, bough_recent, bough_day) are
skipped — cue derivation only needs the current-moment context."
  (let* ((ctx (dl-satan-tools-memory--ctx-from tool-ctx))
         (evidence (dl-satan-memory-evidence-assemble
                    ctx (list :run_started_at
                              (plist-get ctx :run_started_at)
                              :cue_only t)))
         (canon (dl-satan-memory-canon-canonicalize-from-raw
                 evidence hints ctx)))
    (plist-get canon :handles)))

;; ---------------------------------------------------------------------
;; memory_show_trace
;; ---------------------------------------------------------------------

(defun dl-satan-tool/memory-show-trace (args _tool-ctx)
  "Handler for `memory_show_trace'.  See §5.3 of memory.design.md."
  (let ((tid (plist-get args :trace_id)))
    (cond
     ((not (stringp tid))    (cons 'error "trace_id must be string"))
     ((string-empty-p tid)   (cons 'error "trace_id must be non-empty"))
     (t (dl-satan-memory-store-show tid)))))

;; ---------------------------------------------------------------------
;; Registration
;; ---------------------------------------------------------------------

(let* ((hints-shape
        (list 'kind        (list :type 'string
                                 :enum dl-satan-tools-memory--kind-values)
              'phase       (list :type 'string)
              'topic       (list :type 'array :items 'string)
              'focal_app   (list :type 'string)
              'focal_bough_nanoid
                           (list :type 'string
                                 :pattern dl-satan-tools-memory--nanoid-pattern)
              'valence     (list :type 'string
                                 :enum dl-satan-tools-memory--valence-values)
              'outcome_for (list :type 'string)))
       (cue-shape
        (list 'handles (list :type 'array :items 'string)
              'hints   (list :type 'object :shape hints-shape))))

  (dl-satan-tool-register
   (list :name "memory_mark"
         :risk 'low
         :capability 'memory-write
         :args-schema
         (list 'payload (list :type 'string :required t)
               'hints   (list :type 'object :shape hints-shape)
               'valence (list :type 'string
                              :enum dl-satan-tools-memory--valence-values)
               'links   (list :type 'array :items 'string))
         :handler 'dl-satan-tool/memory-mark))

  (dl-satan-tool-register
   (list :name "memory_resonate"
         :risk 'read
         :args-schema
         (list 'cue       (list :type 'object :shape cue-shape)
               'limit     (list :type 'integer)
               'kinds     (list :type 'array :items 'string)
               'min_score (list :type 'number))
         :handler 'dl-satan-tool/memory-resonate))

  (dl-satan-tool-register
   (list :name "memory_show_trace"
         :risk 'read
         :args-schema (list 'trace_id (list :type 'string :required t))
         :handler 'dl-satan-tool/memory-show-trace)))

(provide 'dl-satan-tools-memory)
;;; dl-satan-tools-memory.el ends here
