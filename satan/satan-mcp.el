;;; satan-mcp.el --- SATAN MCP server over UDS for interactive pi sessions -*- lexical-binding: t; -*-

;; MCP server hosting SATAN tools over a unix-domain socket.
;; pi.dev connects via the DEC-12 TS extension (node-net UDS, no socat).
;;
;; Methods: initialize, notifications/initialized (no-op), ping, tools/list, tools/call.
;; Transport: newline-delimited JSON-RPC 2.0.
;;
;; Invariants (DEC-121, DEC-122):
;; I1. A session's identity is fixed once `initialize' succeeds or its run
;;     is minted, whichever comes first.
;; I2. A session has at most one run; every request with an id that arrives
;;     while its session is open gets exactly one response, unless the client
;;     cancelled it or the transport closed first.
;; I3. A run is finalised exactly once, and only when no call is in flight on
;;     its session.
;; I4. Every finalised MCP bundle passes `satan-audit-verify-run'.
;; I5. Memory-write attribution comes from an explicit argument, never
;;     ambient state.
;;
;; Trust boundary (POL-001): the socket speaks MCP only — no eval path.
;; Every tools/call flows through satan-tool-dispatch (name look-up,
;; mode allowlist, capability guard, schema validation, handler).

(require 'cl-lib)
(require 'subr-x)
(require 'json)
(require 'satan-run)
(require 'satan-tools)
(require 'satan-mode)
(require 'satan-audit)
(require 'satan-jsonl)

;; Dynamically bound during tools/call dispatch so handlers can
;; access the current session (e.g. boot-context needs the prepare plist).
(defvar satan-mcp--current-session nil)

;; Declared in satan-context.el — used for DEC-13 boot context.
(declare-function satan-context-interactive "satan-context"
                  (mode-spec &optional run-ctx))

;; ── Configuration ───────────────────────────────────────────────────────────

(defcustom satan-mcp-enabled nil
  "When non-nil, the MCP server may be started.
Default off — the batch path is independent and unaffected."
  :type 'boolean :group 'satan)

(defcustom satan-mcp-runtime-dir
  (let ((xdg (getenv "XDG_RUNTIME_DIR")))
    (if xdg
      (expand-file-name "satan/mcp" xdg)
      "/dev/null"))  ; force startup failure if unset (DEC-10)
  "Parent directory for the MCP unix-domain socket.
Must live under XDG_RUNTIME_DIR (no /tmp — DEC-10).
0700 perms enforced at startup."
  :type 'directory :group 'satan)

(defcustom satan-mcp-protocol-version "2025-06-18"
  "MCP protocol version advertised in initialize response."
  :type 'string :group 'satan)

(defcustom satan-mcp-socket-filename "mcp.sock"
  "Filename for the MCP unix-domain socket (inside `satan-mcp-runtime-dir').
Fixed by default so the jail bwrap bind-mount can reference a stable path.
The runtime dir is still 0700 (DEC-10)."
  :type 'string :group 'satan)

(defcustom satan-mcp-server-name "satan-mcp"
  "Server name advertised in initialize response."
  :type 'string :group 'satan)

;; ── Interactive mode-spec (DEC-9) ───────────────────────────────────────────

(defun satan-mcp--interactive-tools ()
  "Return the union of all registered SATAN tool names available in
interactive mode (`satan-tools-available').  Excludes internal test
stubs (names prefixed `test.')."
  (satan-tools-available
   (cl-loop for (name . _spec) in satan-tools
     unless (string-prefix-p "test." name)
     collect name)
   "interactive"))

(defun satan-mcp--interactive-capabilities ()
  "Return the union of all capabilities referenced by any registered tool.
Excludes internal test stubs (names prefixed `test.')."
  (delete-dups
    (cl-loop for (name . spec) in satan-tools
      unless (string-prefix-p "test." name)
      for cap = (plist-get spec :capability)
      when cap collect cap)))

(defun satan-mcp-register-interactive-mode ()
  "Register the `interactive' mode-spec (DEC-9).
:harness nil — never spawned; pi connects via MCP.
:tools = union of all registered tools.
:context-fn = satan-context-interactive (DEC-13, Phase 4)."
  (satan-mode-register
    (list :name "interactive"
      :harness nil
      :tools (satan-mcp--interactive-tools)
      :capabilities (satan-mcp--interactive-capabilities)
      :context-fn #'satan-context-interactive)))

;; ── Session state ───────────────────────────────────────────────────────────

(cl-defstruct satan-mcp-session
  "Per-connection session state (DEC-5: one run per connection).
The run slots are nil until the first `tools/call' mints the run
(DEC-122).  The line buffer is connection-scoped, so it lives on the
connection process, not here."
  proc          ; the network connection process (UDS peer)
  identity      ; (:conversation C :kind K) — nil until initialize succeeds
  run-id        ; minted run identifier — nil until the first tools/call
  run-dir       ; absolute run directory — nil until the first tools/call
  audit         ; satan-audit-handle — nil until the first tools/call
  tool-ctx      ; plist passed to satan-tool-dispatch — nil until first call
  prepare       ; the run_ctx prepare plist — nil until the first tools/call
  boot-cache    ; cached boot-context text, or nil (DEC-13)
  (in-flight 0) ; tools/call dispatches on this session not yet settled (I3)
  )

;; ── Internal: conversation identity (DEC-121) ───────────────────────────────

(defconst satan-mcp--identity-kinds '("interactive" "scheduled")
  "Conversation kinds a client may claim (DEC-121).
Descriptive only: nothing grants scope, budget or supervision status from
kind or conversation (RSK-018, RSK-019).")

(defconst satan-mcp--identity-legacy '(:conversation nil :kind "interactive")
  "The identity of a client that claims none (DEC-121).")

(defun satan-mcp--valid-conversation-p (c)
  "Return non-nil when C is a well-formed conversation id (DEC-121).
A string of 1-128 characters with no control character (below 32, or
127).  Otherwise opaque to SATAN."
  (and (stringp c)
    (<= 1 (length c) 128)
    (cl-loop for ch across c never (or (< ch 32) (= ch 127)))))

(defun satan-mcp--parse-identity (params)
  "Return the identity PARAMS claims: (:conversation C :kind K) or (error . MSG).
PARAMS is the parsed `initialize' params plist.  An absent
`capabilities.experimental.satan' is the legacy identity; a `satan' that is
not an object, or a malformed conversation or kind, is an error — the
session then stays uninitialised."
  (let ((satan (plist-get (plist-get (plist-get params :capabilities)
                              :experimental)
                  :satan)))
    (cond
     ((null satan) satan-mcp--identity-legacy)
     ((not (and (consp satan) (keywordp (car satan))))
      (cons 'error "invalid params: satan is not an object"))
     (t
      (let ((conversation (plist-get satan :conversation))
             (kind (or (plist-get satan :kind) "interactive")))
        (cond
         ((and conversation (not (satan-mcp--valid-conversation-p conversation)))
          (cons 'error "invalid params: malformed conversation"))
         ((not (member kind satan-mcp--identity-kinds))
          (cons 'error "invalid params: unknown kind"))
         (t (list :conversation conversation :kind kind))))))))

(defun satan-mcp--identity-fields (identity)
  "Return the IDENTITY fields a run artefact carries (DEC-121, design sec-6).
`:conversation' is JSON null when the client claimed none; `json-serialize'
encodes nil as {}, so the null must be spelled `:null'."
  (list :conversation (or (plist-get identity :conversation) :null)
    :kind (plist-get identity :kind)))

(defun satan-mcp--final-summary (identity)
  "Return the finalisation summary naming IDENTITY (DEC-121)."
  (let ((conversation (plist-get identity :conversation)))
    (if conversation
      (format "interactive conversation %s" conversation)
      "interactive session")))

;; ── Internal: R7 fail-fast precondition ────────────────────────────────────

(defun satan-mcp--check-tool-descriptions ()
  "Signal if any tool in the interactive mode union lacks a description file.
R7 fail-fast invariant: `satan-tool-json-schema' signals on missing
descriptions, so we check eagerly at startup rather than crashing mid-session."
  (let ((missing nil))
    (dolist (name (satan-mcp--interactive-tools))
      (let ((spec (satan-tool-lookup name)))
        (when spec
          (let ((desc-path (expand-file-name
                             (concat name ".md")
                             satan-tools-descriptions-dir)))
            (unless (file-readable-p desc-path)
              (push name missing))))))
    (when missing
      (error "SATAN MCP: %d tool(s) missing description files: %s — resolve before starting"
        (length missing)
        (mapconcat #'identity (nreverse missing) ", ")))))

;; ── Internal: socket path & hardening (DEC-10) ──────────────────────────────

(defun satan-mcp--socket-path ()
  "Return the socket path under `satan-mcp-runtime-dir'.
Filename is `satan-mcp-socket-filename' (fixed, so the flake
bwrap bind-mount can reference a stable path).  The runtime dir
is still 0700 (DEC-10)."
  (expand-file-name satan-mcp-socket-filename
    satan-mcp-runtime-dir))

(defun satan-mcp--check-socket-dir ()
  "Validate the socket parent directory (DEC-10).
Signals if XDG_RUNTIME_DIR unset, dir is a symlink, or dir can't be created.
Enforces 0700 permissions."
  (let ((dir satan-mcp-runtime-dir))
    (when (equal dir "/dev/null")
      (error "SATAN MCP: XDG_RUNTIME_DIR not set — refusing to start (DEC-10)"))
    (when (file-symlink-p dir)
      (error "SATAN MCP: runtime dir is a symlink — refusing (DEC-10): %s" dir))
    (unless (file-directory-p dir)
      (make-directory dir t))
    (set-file-modes dir #o700)))

;; ── Internal: run lifecycle (DEC-5: one run per connection) ─────────────────

(defun satan-mcp--interactive-manifest (run-id identity)
  "Return the manifest plist for an interactive RUN-ID claimed by IDENTITY."
  (let ((tools-list nil))
    (dolist (name (satan-mcp--interactive-tools))
      (let ((spec (satan-tool-lookup name)))
        (when spec
          (push (satan-tool-json-schema spec) tools-list))))
    (append (list :mode "interactive")
      (satan-mcp--identity-fields identity)
      (list :run_id run-id
        :tools (vconcat (nreverse tools-list))))))

(defun satan-mcp--interactive-bundle (run-id identity)
  "Return the synthetic bundle plist for an interactive RUN-ID claimed by IDENTITY."
  (append (list :run_id run-id :mode "interactive")
    (satan-mcp--identity-fields identity)
    (list :prompt "interactive MCP session (DEC-6: no satan_final in A)"
      :context "human-supervised pi.dev session")))

(defun satan-mcp--ensure-run (session)
  "Mint SESSION's run on first use and publish its run slots (DEC-122).
Idempotent: a session that already has a run-id is left untouched.

Failure-atomic: `satan-audit-open' writes manifest, bundle and transcript
one by one, so a failure leaves a partly written run dir behind.  Nothing
is published on the session until it returns; on any non-local exit the
run dir is deleted and the session stays run-less, so the next tools/call
retries."
  (unless (satan-mcp-session-run-id session)
    (let* ((mode (satan-mode-resolve "interactive"))
            ;; A1: the claim, or the legacy one when the client claimed none.
            (identity (or (satan-mcp-session-identity session)
                          satan-mcp--identity-legacy))
            ;; F5: one constructor for run_ctx.  The canonical 10-key shape,
            ;; not a hand-rolled 4-key clone — the six v0 placeholders reach
            ;; no on-disk artifact, since `satan-audit-open' stores run-ctx on
            ;; the handle and serialises only manifest and bundle.
            (prepare (satan-run-new-ctx mode))
            (run-id (plist-get prepare :run_id))
            (run-dir (satan-run-dir-for-id run-id))
            (published nil))
      (unwind-protect
        (let* ((audit (satan-audit-open
                        run-dir
                        (satan-mcp--interactive-manifest run-id identity)
                        (satan-mcp--interactive-bundle run-id identity)
                        prepare))
                (run-struct (make-satan-run
                              :id run-id
                              :mode mode
                              :start-time (plist-get prepare :start_time)
                              :dir run-dir
                              :audit audit
                              :prepare prepare
                              :pending-tool-calls (make-hash-table :test 'equal)
                              :tool-calls-done 0
                              :applied-actions nil
                              :staged-actions nil
                              :rejected-actions nil
                              :failed-actions nil
                              :status 'running))
                (tool-ctx (satan-run-tool-ctx run-struct)))
          (setf (satan-mcp-session-run-id session) run-id
            (satan-mcp-session-run-dir session) run-dir
            (satan-mcp-session-audit session) audit
            (satan-mcp-session-tool-ctx session) tool-ctx
            (satan-mcp-session-prepare session) prepare)
          (setq published t)
          session)
        ;; Any non-local exit (error or quit) before publishing: remove
        ;; the partly written dir; the exit propagates to the caller.
        (unless (or published (not (file-directory-p run-dir)))
          (delete-directory run-dir t))))))

(defun satan-mcp--close-session (session)
  "Finalise SESSION's run as done (DEC-122).
A session with no run — the first tools/call never came, or its mint
failed — finalises nothing.  Without a synthetic final, audit-close
writes :status \"invalid\"."
  (when (satan-mcp-session-run-id session)
    (satan-audit-close
      (satan-mcp-session-audit session)
      (list :summary (satan-mcp--final-summary
                       (or (satan-mcp-session-identity session)
                           satan-mcp--identity-legacy))
        :status "done")
      (list :applied [] :staged [] :rejected [] :failed [])
      'done)))

;; ── Internal: MCP method handlers ───────────────────────────────────────────

(defun satan-mcp--send (proc obj)
  "Serialize OBJ as one newline-delimited JSON-RPC message to PROC."
  (let ((line (json-serialize obj :null-object :null :false-object :false)))
    (process-send-string proc (concat line "\n"))))

(defun satan-mcp--result (id result)
  "Return a JSON-RPC success response plist."
  (list :jsonrpc "2.0" :id id :result result))

(defun satan-mcp--error (id code message)
  "Return a JSON-RPC error response plist."
  (list :jsonrpc "2.0" :id id
    :error (list :code code :message message)))

(defun satan-mcp--send-tool-result (proc id res)
  "Answer ID with the MCP body rendering dispatch result RES to PROC."
  (if (eq (plist-get res :ok) t)
    (satan-mcp--send
      proc
      (satan-mcp--result
        id
        (list :content
          (vector
            (list :type "text"
              :text (prin1-to-string (plist-get res :result)))))))
    ;; Error path
    (satan-mcp--send
      proc
      (satan-mcp--result
        id
        (list :content
          (vector
            (list :type "text"
              :text (or (plist-get res :error)
                      "unknown error")))
          :isError t)))))

(defun satan-mcp--initialize (id session proc params)
  "Handle `initialize': fix SESSION's identity, then answer ID as today.
The identity is fixed once it parses or once the run is minted, whichever
comes first (I1): after the mint every initialize is -32600.  A malformed
identity is -32602 and the session stays uninitialised; the same identity
again is answered as normal, a different one is -32602.

The result body is unchanged — the server advertises nothing new about the
identity (DEC-121)."
  (if (satan-mcp-session-run-id session)
      (satan-mcp--send proc
        (satan-mcp--error id -32600
          "invalid request: identity is fixed once the run is minted"))
    (let ((identity (satan-mcp--parse-identity params))
           (known (satan-mcp-session-identity session)))
      (cond
       ((eq (car-safe identity) 'error)
        (satan-mcp--send proc (satan-mcp--error id -32602 (cdr identity))))
       ((and known (not (equal identity known)))
        (satan-mcp--send proc
          (satan-mcp--error id -32602
            "invalid params: identity already fixed for this session")))
       (t
        (setf (satan-mcp-session-identity session) identity)
        (satan-mcp--send
          proc
          (satan-mcp--result
            id
            (list :protocolVersion satan-mcp-protocol-version
              :capabilities (list :tools (make-hash-table :test 'eq))
              :serverInfo (list :name satan-mcp-server-name
                            :version "0")))))))))

(defun satan-mcp--handle-message (parsed session proc)
  "Dispatch one parsed JSON-RPC message PARSED (plist) from PROC.
SESSION is the satan-mcp-session.

This is the single answer-if-it-fails point (EX-3): an uncaught error in a
request (one with an id) is answered -32603 and logged; a notification is
only logged.  A failed mint (see `satan-mcp--ensure-run') gets its -32603
here, so no handler needs a bespoke response code.  If the error cannot be
delivered, the send signals on to the caller."
  (let* ((id (plist-get parsed :id))
          (method (plist-get parsed :method))
          (params (plist-get parsed :params)))
    (condition-case err
      (pcase method
        ("initialize" (satan-mcp--initialize id session proc params))
        ;; notification — no response
        ("notifications/initialized" nil)
        ("ping"
          (satan-mcp--send
            proc
            (satan-mcp--result id (list :pong t))))
        ("tools/list"
          (let ((acc nil))
            (dolist (name (satan-mcp--interactive-tools))
              (let ((spec (satan-tool-lookup name)))
                (when spec
                  (let* ((openai (satan-tool-json-schema spec))
                         (fn (plist-get openai :function)))
                    (push (list :name (plist-get fn :name)
                                :description (plist-get fn :description)
                                :inputSchema (plist-get fn :parameters))
                          acc)))))
            (let ((tools (vconcat (nreverse acc))))
              (satan-mcp--send proc (satan-mcp--result id (list :tools tools))))))
        ("tools/call"
          (satan-mcp--tools-call params id session proc))
        (_
          ;; Unknown method → -32601; only respond to requests (have id)
          (when id
            (satan-mcp--send
              proc
              (satan-mcp--error id -32601
                (format "Method not found: %s" method))))))
      (error
        (message "satan-mcp: %s failed: %s"
          (or method "message")
          (error-message-string err))
        (when id
          (satan-mcp--send proc
            (satan-mcp--error id -32603 (error-message-string err))))))))

(defun satan-mcp--record-interrupted (audit id reason)
  "Settle the interrupted call ID: a tool-result, then `call-interrupted'.
REASON is \"error\", \"quit\" or \"exit\".  The tool-result carries the call
id because the verifier pairs on it (`satan-audit-p/calls-match-results'),
so an interrupted call never reads as an unsettled one."
  (satan-audit-record
    audit
    'out
    'tool-result
    (list :type "tool_result" :id id :ok :false
      :error (format "interrupted: %s" reason)))
  (satan-audit-record audit 'broker 'call-interrupted
    (list :id id :reason reason)))

(defun satan-mcp--tools-call (params id session proc)
  "Handle `tools/call': validate + dispatch through the shared dispatcher.
PARAMS is the MCP params plist (already parsed with :object-type 'plist).
SESSION carries the tool-ctx and audit handle, minted here on first use.

Every audited call is settled before it releases the session in-flight
count (I3): the dispatch sits inside `unwind-protect', so an error that
escapes the guard inside `satan-tool-dispatch', `quit', or a `throw' to an
outer catch still writes a tool-result for the call and a
`call-interrupted' record first."
  (satan-mcp--ensure-run session)
  (let* ((tool-name (plist-get params :name))
          (arguments (plist-get params :arguments))
          (call (list :id id :name tool-name :args arguments))
          (mode (satan-mode-resolve "interactive"))
          (tool-ctx (satan-mcp-session-tool-ctx session))
          (audit (satan-mcp-session-audit session))
          (res nil)       ; the dispatch result, when dispatch returned
          (reason nil)    ; "error" | "quit" — set when dispatch escaped
          (escaped nil)   ; the escaped error condition, re-signalled below
          (recorded nil)) ; guards against a second tool-result
    (let ((satan-mcp--current-session session))
      (setf (satan-mcp-session-in-flight session)
        (1+ (satan-mcp-session-in-flight session)))
      ;; Audit the inbound tool_call (mimics membrane :dir in)
      (satan-audit-record audit 'in 'tool-call call)
      (unwind-protect
        (progn
          ;; Only the dispatch sits inside the catcher: the response send
          ;; stays outside it, so a failed send writes no second result.
          (condition-case err
              (setq res (satan-tool-dispatch
                          call (plist-get mode :tools) tool-ctx))
            (quit (setq reason "quit"))
            (error (setq reason "error" escaped err)))
          (when res
            ;; Audit the outbound tool-result
            (satan-audit-record audit 'out 'tool-result res)
            (setq recorded t)
            (satan-mcp--send-tool-result proc id res)))
        ;; Settle: a non-local exit past the body leaves no tool-result, so
        ;; the cleanup writes one — a `throw' out of the body arrives here
        ;; as "exit".  The decrement follows the call's last audit write.
        (unless recorded
          (satan-mcp--record-interrupted audit id (or reason "exit")))
        (setf (satan-mcp-session-in-flight session)
          (1- (satan-mcp-session-in-flight session))))
      ;; The escape is re-raised once settled: an error reaches the -32603
      ;; wrapper in `satan-mcp--handle-message'; a quit closes the
      ;; transport first, so the client sees a disconnect not a timeout.
      (cond
       ((equal reason "quit")
        (when (process-live-p (satan-mcp-session-proc session))
          (delete-process (satan-mcp-session-proc session)))
        (signal 'quit nil))
       (escaped (signal (car escaped) (cdr escaped)))))))



;; ── Connection filter & sentinel ─────────────────────────────────────────────


;; ── satan_boot_context tool handler (DEC-13, Phase 4) ──────────────────────

(defun satan-mcp-tool/boot-context (args _ctx)
  "Read tool: return the per-session orientation capsule.
ARGS may include :refresh to force rebuild (cache bypass).
_CTX is the tool-ctx (unused — we read session from dynamic var).

Build-depth β: builds percept/resonance/motive/sensor_status/attributes
fresh but skips observer-process + sensor-alerts-check + probes.
Caches the result per-session; `refresh' forces rebuild.
Gracefully degrades on backend failure (returns partial capsule,
does not error the session)."
  (let* ((session satan-mcp--current-session)
         (refresh (plist-get args :refresh))
         (cached (satan-mcp-session-boot-cache session)))
    (if (and cached (not refresh))
        ;; Serve the per-session cache (AUD-008 F-002: real early return).
        (cons 'ok cached)
      ;; Load satan-context at runtime (heavy deps).
      (require 'satan-context)
      ;; Delegate to the single capsule builder (AUD-008 F-003) — it copies
      ;; the session prepare (F-004) and gracefully degrades on backend
      ;; failure.
      (let* ((mode (satan-mode-resolve "interactive"))
             (prepare (satan-mcp-session-prepare session))
             (bundle (satan-context-interactive mode prepare))
             (text (plist-get bundle :prompt)))
        (setf (satan-mcp-session-boot-cache session) text)
        (cons 'ok text)))))

(defun satan-mcp--filter (proc chunk)
  "Accumulate CHUNK, dispatch each complete newline-delimited JSON-RPC line.
The partial line is a process property (EX-5): it is connection-scoped,
not session state."
  (let* ((session (process-get proc 'satan-mcp-session))
          (buf (concat (or (process-get proc 'satan-mcp-buf) "") chunk))
          (lines (split-string buf "\n")))
    (process-put proc 'satan-mcp-buf (car (last lines)))
    (dolist (line (butlast lines))
      (let ((trimmed (string-trim line)))
        (unless (string-empty-p trimmed)
          ;; Handler errors are answered by `satan-mcp--handle-message'.
          ;; What reaches this guard is a line that does not decode (no
          ;; recoverable id) or an answer that could not be sent.
          (condition-case err
            (satan-mcp--handle-message
              (json-parse-string trimmed
                :object-type 'plist
                :array-type 'list
                :null-object nil
                :false-object :false)
              session proc)
            (error
              (message "satan-mcp: dropped line on %s: %s"
                (satan-mcp-session-run-id session)
                (error-message-string err)))))))))

(defun satan-mcp--sentinel (proc event)
  "Handle connection close — finalise the session's run, if it has one."
  (when (string-match-p "\\(closed\\|deleted\\|finished\\|exited\\|broken\\)" event)
    (let ((session (process-get proc 'satan-mcp-session)))
      (when session
        (condition-case err
          (satan-mcp--close-session session)
          (error
            (message "satan-mcp: close-session failed for %s: %s"
              (or (satan-mcp-session-run-id session) "a run-less session")
              (error-message-string err))))
        (process-put proc 'satan-mcp-session nil)))))

(defun satan-mcp--accept-filter (_server-proc client-proc &optional _conn-info)
  "Accept a new UDS connection — bind a run-less session to CLIENT-PROC.
The run is minted lazily by `satan-mcp--ensure-run' on the first
tools/call (DEC-122), so accepting cannot fail on a mint."
  (let ((session (make-satan-mcp-session :proc client-proc)))
    (process-put client-proc 'satan-mcp-session session)
    (set-process-filter client-proc #'satan-mcp--filter)
    (set-process-sentinel client-proc #'satan-mcp--sentinel)
    (message "satan-mcp: session connected")))

;; ── Public API ──────────────────────────────────────────────────────────────

(defvar satan-mcp--server-process nil
  "The listening server process, if any.")

;;;###autoload
(defun satan-mcp-start ()
  "Start the SATAN MCP server on a unix-domain socket.
Returns the socket path.  No-op when already running.  Refuses to start
if disabled, if a tool lacks a description (R7 fail-fast), or if socket
hardening checks fail (DEC-10)."
  (interactive)
  (unless satan-mcp-enabled
    (user-error "SATAN MCP: disabled (set `satan-mcp-enabled' non-nil)"))
  (if (and satan-mcp--server-process
        (process-live-p satan-mcp--server-process))
    (process-contact satan-mcp--server-process :service)
    ;; Always re-register interactive mode — picks up newly-registered tools
    ;; (satan-mode-register replaces existing entries by name).
    (satan-mcp-register-interactive-mode)
    ;; R7 fail-fast precondition: refuse if any tool lacks a description
    (satan-mcp--check-tool-descriptions)
    (satan-mcp--check-socket-dir)
    (let* ((socket-path (satan-mcp--socket-path)))
      (when (file-exists-p socket-path)
        (delete-file socket-path))
      (setq satan-mcp--server-process
        (make-network-process
          :name "satan-mcp"
          :server t
          :family 'local
          :service socket-path
          :coding 'utf-8
          :noquery t
          :log #'satan-mcp--accept-filter))
      (set-file-modes socket-path #o600)
      (message "SATAN MCP: listening on %s" socket-path)
      socket-path)))

;;;###autoload
(defun satan-mcp-stop ()
  "Stop the SATAN MCP server and remove the socket file.
Also closes any open client connections synchronously to ensure
sessions are finalized before cleanup."
  (interactive)
  ;; Close all client connections first so their sentinels fire
  ;; synchronously before we tear down the server.
  (when satan-mcp--server-process
    (dolist (child (process-list))
      (when (and (not (eq child satan-mcp--server-process))
              (process-get child 'satan-mcp-session))
        (delete-process child))))
  (when (and satan-mcp--server-process
          (process-live-p satan-mcp--server-process))
    (delete-process satan-mcp--server-process))
  (setq satan-mcp--server-process nil)
  (message "SATAN MCP: stopped"))

;;;###autoload
(defun satan-mcp-pi-session ()
  "Interactive command: start MCP server and print a session note.
Use this from M-x to start a supervised interactive session.
Calls `satan-mcp-start' and reports the socket path."
  (interactive)
  (let ((path (satan-mcp-start)))
    (message "SATAN MCP pi session active on %s — start pi with the satan extension" path)
    path))

;; ── Global tool registration (DEC-13) ──────────────────────────────────────

(satan-tool-register
 (list :name "satan_boot_context"
       :risk 'read
       :args-schema '(refresh (:type boolean :required nil))
       :handler 'satan-mcp-tool/boot-context))

(provide 'satan-mcp)
;;; satan-mcp.el ends here
