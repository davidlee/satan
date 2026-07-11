;;; satan-mcp.el --- SATAN MCP server over UDS for interactive pi sessions -*- lexical-binding: t; -*-

;; MCP server hosting SATAN tools over a unix-domain socket.
;; pi.dev connects via the DEC-12 TS extension (node-net UDS, no socat).
;;
;; Methods: initialize, notifications/initialized (no-op), ping, tools/list, tools/call.
;; Transport: newline-delimited JSON-RPC 2.0.
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

;; Declared in satan-run.el; re-declared for byte-compiler reference.
(defvar satan-memory-store--current-run-id)

;; Declared in satan-broker.el — used for DEC-8 mutual exclusion.
(defvar satan-broker--spawn-running nil)

;; DEC-8: mutual-exclusion flag — truthy while an interactive MCP
;; session is open.  The broker's scheduler reads this to refuse
;; spawning scheduled runs while a session is active.
(defvar satan-mcp--session-active nil)

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
  "Return the union of all registered SATAN tool names.
Excludes internal test stubs (names prefixed `test.')."
  (cl-loop for (name . _spec) in satan-tools
    unless (string-prefix-p "test." name)
    collect name))

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
  "Per-connection session state (DEC-5: one run per connection)."
  proc          ; the network connection process (UDS peer)
  run-id        ; minted run identifier
  run-dir       ; absolute run directory
  audit         ; satan-audit-handle
  tool-ctx      ; plist passed to satan-tool-dispatch
  prepare       ; the run_ctx prepare plist (for boot context)
  bufs          ; hash table of per-conn line buffers (keyed by proc)
  boot-cache    ; cached boot-context text, or nil (DEC-13)
  ;; DEC-8 mutual exclusion: mark the broker busy while this session lives.
  )

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

(defun satan-mcp--mint-session (proc)
  "Create run directory, open audit with synthetic bundle, return session.
Signals if a scheduled run is live (DEC-8 mutual exclusion)."
  (when satan-broker--spawn-running
    (error "SATAN MCP: scheduled run in progress — refuse session (DEC-8)"))
  (let* ((mode (satan-mode-resolve "interactive"))
          (start-time (current-time))
          (run-id (satan-run-mint-id "interactive" start-time))
          (time-now (format-time-string satan-run--iso-time-format start-time))
          (run-dir (satan-run-dir-for-id run-id))
          (manifest
            (let ((tools-list nil))
              (dolist (name (satan-mcp--interactive-tools))
                (let ((spec (satan-tool-lookup name)))
                  (when spec
                    (push (satan-tool-json-schema spec) tools-list))))
              (list :mode "interactive"
                    :run_id run-id
                    :tools (vconcat (nreverse tools-list)))))
          (bundle (list :run_id run-id
                    :mode "interactive"
                    :prompt "interactive MCP session (DEC-6: no satan_final in A)"
                    :context "human-supervised pi.dev session"))
          (prepare (list :run_id run-id
                     :mode_name "interactive"
                     :time_now time-now
                     :start_time start-time))
          (audit (satan-audit-open run-dir manifest bundle prepare))
          (run-struct
            (make-satan-run
              :id run-id
              :mode mode
              :start-time start-time
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
          (tool-ctx (satan-run-tool-ctx run-struct))
          (bufs (make-hash-table :test 'eq)))
    ;; DEC-8: mark broker busy while this session lives.
    (setq satan-mcp--session-active t)
    (make-satan-mcp-session
      :proc proc
      :run-id run-id
      :run-dir run-dir
      :audit audit
      :tool-ctx tool-ctx
      :prepare prepare
      :bufs bufs
      :boot-cache nil)))

(defun satan-mcp--close-session (session)
  "Close the session's audit with a synthetic final (DEC-5: status completed).
Without a synthetic final, audit-close writes :status \"invalid\"."
  (satan-audit-close
    (satan-mcp-session-audit session)
    (list :summary "interactive session" :status "completed")
    (list :applied [] :staged [] :rejected [] :failed [])
    'completed)
  ;; DEC-8: clear the mutual-exclusion flag so the scheduler can
  ;; spawn runs again.
  (setq satan-mcp--session-active nil)
  ;; Clear the bufs hash
  (clrhash (satan-mcp-session-bufs session)))

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

(defun satan-mcp--handle-message (parsed session proc)
  "Dispatch one parsed JSON-RPC message PARSED (plist) from PROC.
SESSION is the satan-mcp-session."
  (let* ((id (plist-get parsed :id))
          (method (plist-get parsed :method))
          (params (plist-get parsed :params)))
    (pcase method
      ("initialize"
        (satan-mcp--send
          proc
          (satan-mcp--result
            id
            (list :protocolVersion satan-mcp-protocol-version
              :capabilities (list :tools (make-hash-table :test 'eq))
              :serverInfo (list :name satan-mcp-server-name
                            :version "0")))))
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
              (format "Method not found: %s" method))))))))

(defun satan-mcp--tools-call (params id session proc)
  "Handle `tools/call': validate + dispatch through the shared dispatcher.
PARAMS is the MCP params plist (already parsed with :object-type 'plist).
SESSION carries the tool-ctx and audit handle."
  (let* ((tool-name (plist-get params :name))
          (arguments (plist-get params :arguments))
          (call (list :id id :name tool-name :args arguments))
          (mode (satan-mode-resolve "interactive"))
          (tool-ctx (satan-mcp-session-tool-ctx session))
          (audit (satan-mcp-session-audit session))
          (run-id (satan-mcp-session-run-id session)))
    ;; DEC-7: bind current-run-id around dispatch for memory-write attribution
    (let ((satan-memory-store--current-run-id run-id)
          (satan-mcp--current-session session))
      ;; Audit the inbound tool_call (mimics membrane :dir in)
      (satan-audit-record audit 'in 'tool-call call)
      (let ((res (satan-tool-dispatch
                   call
                   (plist-get mode :tools)
                   tool-ctx)))
        ;; Audit the outbound tool-result
        (satan-audit-record audit 'out 'tool-result res)
        (if (eq (plist-get res :ok) t)
          (let ((result-val (plist-get res :result)))
            (satan-mcp--send
              proc
              (satan-mcp--result
                id
                (list :content
                  (vector
                    (list :type "text"
                      :text (prin1-to-string result-val)))))))
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
                :isError t))))))))



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
  "Accumulate CHUNK, dispatch each complete newline-delimited JSON-RPC line."
  (let* ((session (process-get proc 'satan-mcp-session))
          (bufs (satan-mcp-session-bufs session))
          (buf (concat (gethash proc bufs "") chunk))
          (lines (split-string buf "\n")))
    (puthash proc (car (last lines)) bufs)
    (dolist (line (butlast lines))
      (let ((trimmed (string-trim line)))
        (unless (string-empty-p trimmed)
          (condition-case err
            (satan-mcp--handle-message
              (json-parse-string trimmed
                :object-type 'plist
                :array-type 'list
                :null-object nil
                :false-object :false)
              session proc)
            (error
              (message "satan-mcp: parse error on %s: %s"
                (satan-mcp-session-run-id session)
                (error-message-string err)))))))))

(defun satan-mcp--sentinel (proc event)
  "Handle connection close — finalise the session audit."
  (when (string-match-p "\\(closed\\|deleted\\|finished\\|exited\\|broken\\)" event)
    (let ((session (process-get proc 'satan-mcp-session)))
      (when session
        (condition-case err
          (satan-mcp--close-session session)
          (error
            (message "satan-mcp: audit-close failed for %s: %s"
              (satan-mcp-session-run-id session)
              (error-message-string err))))
        (process-put proc 'satan-mcp-session nil)))))

(defun satan-mcp--accept-filter (server-proc client-proc &optional _conn-info)
  "Accept a new UDS connection — mint a session bound to CLIENT-PROC."
  (condition-case err
    (let ((session (satan-mcp--mint-session client-proc)))
      (process-put client-proc 'satan-mcp-session session)
      (set-process-filter client-proc #'satan-mcp--filter)
      (set-process-sentinel client-proc #'satan-mcp--sentinel)
      (message "satan-mcp: session %s connected"
        (satan-mcp-session-run-id session)))
    (error
      ;; DEC-8: if the session was minted but wiring failed, clear the
      ;; mutual-exclusion flag so the scheduler is not permanently blocked.
      (setq satan-mcp--session-active nil)
      (message "satan-mcp: rejecting connection — %s" (error-message-string err))
      (delete-process client-proc))))

;; ── Public API ──────────────────────────────────────────────────────────────

(defvar satan-mcp--server-process nil
  "The listening server process, if any.")

;;;###autoload
(defun satan-mcp-start ()
  "Start the SATAN MCP server on a unix-domain socket.
Returns the socket path.  Refuses to start if disabled, if a scheduled
run is live (DEC-8), if a tool lacks a description (R7 fail-fast),
or if socket hardening checks fail (DEC-10)."
  (interactive)
  (unless satan-mcp-enabled
    (user-error "SATAN MCP: disabled (set `satan-mcp-enabled' non-nil)"))
  (when satan-broker--spawn-running
    (user-error "SATAN MCP: scheduled run in progress — refuse to start (DEC-8)"))
  (when (and satan-mcp--server-process
          (process-live-p satan-mcp--server-process))
    (user-error "SATAN MCP: already running"))
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
    socket-path))

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

(defun my/hello-satan ()
  "start satan mcp up if not running"
  (interactive)
  (set 'satan-mcp-enabled t)
  (or satan-mcp--server-process (satan-mcp-start)))

;; ── Global tool registration (DEC-13) ──────────────────────────────────────

(satan-tool-register
 (list :name "satan_boot_context"
       :risk 'read
       :args-schema '(refresh (:type boolean :required nil))
       :handler 'satan-mcp-tool/boot-context))

(provide 'satan-mcp)
;;; satan-mcp.el ends here
