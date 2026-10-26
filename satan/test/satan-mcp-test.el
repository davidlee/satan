;;; satan-mcp-test.el --- ert tests for satan-mcp MCP server -*- lexical-binding: t; -*-

;; Run from CLI, at the repo root:
;;   emacs --batch \
;;     -L satan -L dev -L satan/test \
;;     -l satan-mcp-test.el -f ert-run-tests-batch-and-exit

;; A stray `.elc' under satan/ would otherwise shadow a newer `.el' when this
;; file is loaded standalone (dev/satan-test.el sets the same flag).
(setq load-prefer-newer t)

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-tools)
(require 'satan-mode)
(require 'satan-audit)
(require 'satan-mcp)
;; Dynamic variables and the `trace_marked' enqueue the identity tests stub.
(require 'satan-attribute)
;; `satan-mcp-tool/boot-context' requires satan-context lazily.  Load it here,
;; before any env binds `satan-tools' to nil: a later require would both
;; clobber a stubbed `satan-context-interactive' and register tools the temp
;; description dir cannot satisfy.
(require 'satan-context)

;; ── Test helpers ────────────────────────────────────────────────────────────

(defvar satan-mcp-test--tmp nil
  "Temporary directory for the test run.")
(defvar satan-mcp-test--runs-dir nil
  "Temporary runs directory.")
(defvar satan-mcp-test--desc-dir nil
  "Temporary tool descriptions directory.")

(defmacro satan-mcp-test--with-tmp-env (&rest body)
  "Run BODY with temporary XDG_RUNTIME_DIR, runs dir, and description dir.
Registers stub tools and the interactive mode."
  `(let* ((satan-mcp-test--tmp (make-temp-file "satan-mcp-test-" t))
          (satan-mcp-test--runs-dir
           (expand-file-name "runs" satan-mcp-test--tmp))
          (satan-mcp-test--desc-dir
           (expand-file-name "descs" satan-mcp-test--tmp))
          (satan-mcp-runtime-dir
           (expand-file-name "mcp" satan-mcp-test--tmp))
          (satan-runs-dir satan-mcp-test--runs-dir)
          (satan-tools-descriptions-dir satan-mcp-test--desc-dir)
          ;; Reset tool registry per test
          (satan-tools nil)
          (satan-modes nil))
     (setenv "XDG_RUNTIME_DIR" satan-mcp-runtime-dir)
     (make-directory satan-mcp-runtime-dir t)
     (set-file-modes satan-mcp-runtime-dir #o700)
     (make-directory satan-mcp-test--desc-dir t)
     (unwind-protect
         (progn ,@body)
       (setenv "XDG_RUNTIME_DIR" nil)
       (satan-mcp-test--stop)
       (when (file-directory-p satan-mcp-test--tmp)
         (delete-directory satan-mcp-test--tmp t)))))

(defun satan-mcp-test--register-stub (name &optional args-schema capability)
  "Register a stub tool NAME with a handler that echoes its args.
ARGS-SCHEMA is an `:args-schema' plist; nil means no args.
CAPABILITY is an optional capability symbol."
  (let ((handler (lambda (args _ctx)
                   (cons 'ok (format "stub:%s args=%S" name args)))))
    (satan-tool-register
     (list :name name
           :risk 'read
           :args-schema args-schema
           :handler handler
           :capability capability))))

(defun satan-mcp-test--write-desc (name text)
  "Write a tool description file for NAME."
  (with-temp-file (expand-file-name (concat name ".md") satan-mcp-test--desc-dir)
    (insert text)))

(defun satan-mcp-test--register-boot-context ()
  "Register `satan_boot_context' as `satan-mcp.el' does at load time.
The test env binds `satan-tools' to nil, so the global registration is
gone; the description file is needed for the R7 startup check."
  (satan-mcp-test--write-desc "satan_boot_context" "Interactive boot context.")
  (satan-tool-register
   (list :name "satan_boot_context"
         :risk 'read
         :args-schema '(refresh (:type boolean :required nil))
         :handler 'satan-mcp-tool/boot-context)))

(defun satan-mcp-test--start ()
  "Start the MCP server in the test env and return the socket path.
Enables the server, registers interactive mode, removes stub socket."
  (setq satan-mcp-enabled t)
  (when (and satan-mcp--server-process
             (process-live-p satan-mcp--server-process))
    (delete-process satan-mcp--server-process)
    (setq satan-mcp--server-process nil))
  (satan-mcp-register-interactive-mode)
  (satan-mcp-start))

(defun satan-mcp-test--stop ()
  "Stop the MCP server."
  (satan-mcp-stop)
  (setq satan-mcp-enabled nil))

(defun satan-mcp-test--connect (socket-path)
  "Connect to the MCP server at SOCKET-PATH; return the client process."
  (make-network-process
   :name "mcp-test-client"
   :family 'local
   :service socket-path
   :coding 'utf-8
   :noquery t))

(defvar satan-mcp-test--last-request-id nil
  "The id of the most recent request sent by `satan-mcp-test--request-response'.")

(defun satan-mcp-test--request-response (proc method &optional params timeout)
  "Send a JSON-RPC request to PROC; return the parsed response, or nil.
Uses a unique id (remembered in `satan-mcp-test--last-request-id').
Blocks until one complete response line arrives or TIMEOUT seconds
\(default 5) elapse.  A nil return means the server never answered, so a
caller that expects no response (e.g. a silent error path) gets nil
rather than a hung batch run."
  (let* ((id (random 999999))
         (req (append (list :jsonrpc "2.0" :id id :method method)
                      (when params (list :params params))))
         (deadline (+ (float-time) (or timeout 5)))
         (result nil))
    (setq satan-mcp-test--last-request-id id)
    (set-process-filter
     proc
     (lambda (_p chunk)
       (setq result (concat (or result "") chunk))))
    (process-send-string proc (concat (json-serialize req
                                       :null-object :null
                                       :false-object :false)
                                      "\n"))
    ;; Wait for response (single-threaded Emacs: accept-process-output)
    (while (and (not (and result (string-match-p "\n" result)))
                (< (float-time) deadline))
      (accept-process-output proc 0.05))
    (when (and result (string-match-p "\n" result))
      (json-parse-string (string-trim (car (split-string result "\n")))
                         :object-type 'plist
                         :array-type 'list
                         :null-object nil
                         :false-object :false))))

(defun satan-mcp-test--request (proc method &optional params)
  "Send a JSON-RPC request to PROC and return the response plist.
Fails the test if no response arrives, so a server that silently drops a
request reddens the test instead of hanging the batch run."
  (or (satan-mcp-test--request-response proc method params)
      (ert-fail (format "no JSON-RPC response to %s within timeout" method))))

(defun satan-mcp-test--error-code (res)
  "Return the JSON-RPC error code in response RES, or nil."
  (plist-get (plist-get res :error) :code))

(defun satan-mcp-test--send-notification (proc method &optional params)
  "Send a JSON-RPC notification (no id) to PROC."
  (let ((msg (append (list :jsonrpc "2.0" :method method)
                     (when params (list :params params)))))
    (process-send-string proc (concat (json-serialize msg
                                       :null-object :null
                                       :false-object :false)
                                      "\n"))))

;; ── Identity helpers (SL-032 PHASE-04) ──────────────────────────────────────

(defun satan-mcp-test--identity (conversation &optional kind)
  "Return the identity plist an initialising client claims.
KIND defaults to \"interactive\", the wire rule for an absent kind."
  (list :conversation conversation :kind (or kind "interactive")))

(defun satan-mcp-test--initialize (proc &optional identity)
  "Send `initialize' to PROC claiming IDENTITY; return the response.
IDENTITY is the `capabilities.experimental.satan' object, e.g.
\='(:conversation \"7\" :kind \"interactive\").  A nil IDENTITY sends the
legacy capabilities with no `experimental' member at all."
  (satan-mcp-test--request
   proc "initialize"
   (list :protocolVersion "2025-06-18"
         :clientInfo (list :name "test" :version "0")
         :capabilities (if identity
                           (list :experimental (list :satan identity))
                         (make-hash-table)))))

(defun satan-mcp-test--identity-params (satan)
  "Return initialize params (server-parsed shape) claiming SATAN.
SATAN may be anything: `satan-mcp--parse-identity' must reject the
malformed shapes, so the helper must be able to build them."
  (list :protocolVersion "2025-06-18"
        :clientInfo (list :name "test" :version "0")
        :capabilities (list :experimental (list :satan satan))))

(defun satan-mcp-test--session-procs ()
  "Return every process that carries a server-side MCP session."
  (cl-loop for proc in (process-list)
           when (process-get proc 'satan-mcp-session) collect proc))

(defun satan-mcp-test--connect-session (socket-path)
  "Connect to SOCKET-PATH; return (CLIENT . SERVER-SESSION) for that pair.
Several sessions may be live at once, so the session is the one that
appeared across the connection rather than the first on `process-list'."
  (let* ((known (satan-mcp-test--session-procs))
         (client (satan-mcp-test--connect socket-path))
         (server nil)
         (deadline (+ (float-time) 5)))
    (while (and (not server) (< (float-time) deadline))
      (accept-process-output client 0.05)
      (setq server (cl-find-if (lambda (p) (not (memq p known)))
                               (satan-mcp-test--session-procs))))
    (cons client (and server (process-get server 'satan-mcp-session)))))

(defun satan-mcp-test--open-identified (socket-path identity)
  "Connect to SOCKET-PATH and initialize it with IDENTITY.
Return (CLIENT . SERVER-SESSION)."
  (let* ((pair (satan-mcp-test--connect-session socket-path))
         (res (satan-mcp-test--initialize (car pair) identity)))
    (should-not (plist-get res :error))
    pair))

(defun satan-mcp-test--register-memory-tools ()
  "Register the memory_* tools in the per-test tool registry.
`satan-tools' is bound to nil per test, so the load-time registration is
gone.  Re-running the file's own registration block is the only way to
get the real specifications rather than a copy of them."
  (dolist (name '("memory_mark" "memory_resonate" "memory_show_trace"))
    (satan-mcp-test--write-desc name (format "%s description." name)))
  (load "satan-tools-memory" nil t))

;; ── VT-mcp-jsonrpc ──────────────────────────────────────────────────────────

(ert-deftest satan-mcp/initialize-response-shape ()
  "initialize returns protocolVersion, capabilities, serverInfo."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "Stub A description.")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (res (satan-mcp-test--request proc "initialize"
                                           (list :protocolVersion "2025-06-18"
                                                 :capabilities (make-hash-table)
                                                 :clientInfo (list :name "test" :version "0")))))
     (should (equal (plist-get res :jsonrpc) "2.0"))
     (let ((result (plist-get res :result)))
       (should (stringp (plist-get result :protocolVersion)))
       (should (plist-get result :capabilities))
       (should (equal (plist-get (plist-get result :serverInfo) :name)
                      satan-mcp-server-name)))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/ping ()
  "ping returns an empty object."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request proc "ping")))
     (should (plist-get res :result))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/unknown-method-returns-32601 ()
  "Unknown method returns JSON-RPC error -32601 (method not found)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request proc "bogus/method")))
     (should (plist-get res :error))
     (should (= (plist-get (plist-get res :error) :code) -32601))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/notification-no-response ()
  "notifications/initialized produces no response (it's a notification)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Send notification (no id) — should not block or error
     (satan-mcp-test--send-notification proc "notifications/initialized")
     ;; Verify connection is still alive with a ping
     (let ((res (satan-mcp-test--request proc "ping")))
       (should (plist-get res :result)))
     (delete-process proc)
     (satan-mcp-test--stop))))

;; ── VT-mcp-tools-list ───────────────────────────────────────────────────────

(ert-deftest satan-mcp/tools-list-shape ()
  "tools/list returns MCP tool defs with name, description, inputSchema."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "Tool A does a thing.")
   (satan-mcp-test--register-stub "stub.a"
                                     '(msg (:type string :required t)))
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request proc "tools/list"))
          (tools (plist-get (plist-get res :result) :tools)))
     (should (= (length tools) 1))
     (let ((tool (elt tools 0)))
       (should (equal (plist-get tool :name) "stub.a"))
       (should (string-match-p "Tool A" (plist-get tool :description)))
       (let ((schema (plist-get tool :inputSchema)))
         (should (equal (plist-get schema :type) "object"))
         (should (plist-get schema :properties))
         (should (equal (append (plist-get schema :required) nil) '("msg")))))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/tools-list-multiple ()
  "tools/list returns all registered tools."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "First.")
   (satan-mcp-test--write-desc "stub.b" "Second.")
   (satan-mcp-test--register-stub "stub.a")
   (satan-mcp-test--register-stub "stub.b")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request proc "tools/list"))
          (tools (plist-get (plist-get res :result) :tools)))
     (should (>= (length tools) 2))
     (delete-process proc)
     (satan-mcp-test--stop))))

;; ── VT-mcp-tools-call ──────────────────────────────────────────────────────

(ert-deftest satan-mcp/tools-call-success ()
  "tools/call happy path: stub tool returns :ok → content with result text."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.echo" "Echo back.")
   (satan-mcp-test--register-stub "stub.echo"
                                     '(msg (:type string :required t)))
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request
                proc "tools/call"
                (list :name "stub.echo"
                      :arguments (list :msg "hello-world"))))
          (result (plist-get res :result)))
     (should (not (plist-get result :isError)))
     (let ((content (plist-get result :content)))
       (should content)
       (should (string-match-p "hello-world"
                               (plist-get (elt content 0) :text))))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/tools-call-unknown-tool ()
  "tools/call for unknown tool returns isError with error text."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request
                proc "tools/call"
                (list :name "no.such.tool" :arguments nil)))
          (result (plist-get res :result)))
     (should (eq (plist-get result :isError) t))
     (let ((text (plist-get (elt (plist-get result :content) 0) :text)))
       (should (string-match-p "unknown tool" text)))
     (delete-process proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/tools-call-arg-invalid ()
  "tools/call with wrong arg type returns isError."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.typed" "Needs an integer.")
   (satan-mcp-test--register-stub "stub.typed"
                                     '(count (:type integer :required t)))
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (satan-mcp-test--request
                proc "tools/call"
                (list :name "stub.typed"
                      :arguments (list :count "not-an-integer"))))
          (result (plist-get res :result)))
     (should (eq (plist-get result :isError) t))
     (delete-process proc)
     (satan-mcp-test--stop))))

;; ── VT-mcp-session-lifecycle ────────────────────────────────────────────────

(defvar satan-mcp-test--audit-writes 0
  "Number of `satan-audit--write-json' calls inside the current
`satan-mcp-test--with-audit-write-failure' body.")

(defmacro satan-mcp-test--with-audit-write-failure (fail-on &rest body)
  "Run BODY with `satan-audit--write-json' signalling on its FAIL-ON'th call.
Inside `satan-audit-open' the first call writes manifest.json and the
second bundle.json (satan-audit.el:60-62), so FAIL-ON 2 breaks the mint
after the run dir exists.  The counter is visible to BODY as
`satan-mcp-test--audit-writes'."
  (declare (indent 1))
  `(let ((satan-mcp-test--audit-writes 0)
         (original (symbol-function 'satan-audit--write-json)))
     (cl-letf (((symbol-function 'satan-audit--write-json)
                (lambda (path obj)
                  (setq satan-mcp-test--audit-writes
                        (1+ satan-mcp-test--audit-writes))
                  (when (= satan-mcp-test--audit-writes ,fail-on)
                    (error "simulated audit write failure: %s" path))
                  (funcall original path obj))))
       ,@body)))

(defun satan-mcp-test--run-dirs (runs-dir)
  "Return the run directories under RUNS-DIR (bucketed or flat layout).
Any directory counts, manifest or not, so a failed mint that leaves an
emptied run dir behind is still seen."
  (let (dirs)
    (when (file-directory-p runs-dir)
      (dolist (entry (directory-files runs-dir t directory-files-no-dot-files-regexp))
        (when (file-directory-p entry)
          (dolist (candidate
                   ;; A date bucket (YYYY-MM-DD) holds run dirs one level down.
                   (if (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
                                       (file-name-nondirectory entry))
                       (directory-files entry t directory-files-no-dot-files-regexp)
                     (list entry)))
            (when (file-directory-p candidate)
              (push candidate dirs))))))
    (nreverse dirs)))

(defun satan-mcp-test--run-dir-count (runs-dir)
  "Return the number of run directories under RUNS-DIR."
  (length (satan-mcp-test--run-dirs runs-dir)))

(defun satan-mcp-test--find-run-dir (runs-dir)
  "Return the first run directory under RUNS-DIR, or nil."
  (car (satan-mcp-test--run-dirs runs-dir)))

(defun satan-mcp-test--session ()
  "Return the server-side session of the live MCP connection, or nil.
The session is a process property on the server end of the socket pair,
not on the client process the test writes to."
  (cl-loop for proc in (process-list)
           for session = (process-get proc 'satan-mcp-session)
           when session return session))

(defun satan-mcp-test--session-has-no-run-p (session)
  "Return non-nil when SESSION has published no run slots (EX-1).
The run is minted lazily, so run-id, run-dir, audit, tool-ctx and
prepare are all nil until the first tools/call."
  (and session
       (cl-every #'null
                 (list (satan-mcp-session-run-id session)
                       (satan-mcp-session-run-dir session)
                       (satan-mcp-session-audit session)
                       (satan-mcp-session-tool-ctx session)
                       (satan-mcp-session-prepare session)))))

(defun satan-mcp-test--disconnect (proc)
  "Close the client end of PROC and let the server's sentinel run."
  (delete-process proc)
  (accept-process-output nil 0.2))

(defun satan-mcp-test--read-file (path)
  "Return the trimmed contents of PATH."
  (string-trim
   (with-temp-buffer
     (insert-file-contents path)
     (buffer-string))))

(defun satan-mcp-test--read-json (path)
  "Return PATH parsed as a JSON object plist."
  (json-parse-string (satan-mcp-test--read-file path)
                     :object-type 'plist
                     :array-type 'list
                     :null-object nil
                     :false-object :false))

(ert-deftest satan-mcp/lazy-mint-no-run-before-first-call ()
  "VT-1/EX-1: connect, initialize and tools/list leave no run dir.
`satan-mcp--ensure-run' mints at the top of the first tools/call, so
run-id, run-dir, audit, tool-ctx and prepare stay nil until then."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (let ((res (satan-mcp-test--request proc "tools/list")))
       (should (plist-get (plist-get res :result) :tools)))
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((session (satan-mcp-test--session)))
       (should session)
       (should (satan-mcp-test--session-has-no-run-p session)))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/lazy-mint-first-call-publishes-run ()
  "VT-1/EX-1: the first tools/call mints exactly one run and publishes
run-id, run-dir, audit, tool-ctx and prepare on the session; a second
call reuses that run."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((res (satan-mcp-test--request proc "tools/call"
                                         (list :name "stub.a" :arguments nil))))
       (should-not (plist-get res :error)))
     (should (= 1 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let* ((session (satan-mcp-test--session))
            (run-dir (and session (satan-mcp-session-run-dir session))))
       (should run-dir)
       (should (file-exists-p (expand-file-name "manifest.json" run-dir)))
       (should (equal run-dir (satan-mcp-test--find-run-dir satan-mcp-test--runs-dir)))
       (should (stringp (satan-mcp-session-run-id session)))
       (should (satan-mcp-session-audit session))
       (should (satan-mcp-session-tool-ctx session))
       (should (equal (plist-get (satan-mcp-session-prepare session) :run_id)
                      (satan-mcp-session-run-id session))))
     (let ((res (satan-mcp-test--request proc "tools/call"
                                         (list :name "stub.a" :arguments nil))))
       (should-not (plist-get res :error)))
     (should (= 1 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/lazy-mint-disconnect-without-call-leaves-no-run ()
  "EX-4/VT-1: a session with no run finalises nothing — connect,
initialize, tools/list, disconnect leaves no run dir at all."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (satan-mcp-test--request proc "tools/list")
     (satan-mcp-test--disconnect proc)
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (should-not (satan-mcp-test--session))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/lazy-mint-disconnect-finalises-done ()
  "EX-4/VT-1: after one tools/call, disconnect finalises the single run:
`satan-audit-verify-run' returns t, the status file reads \"done\" and
final.json carries :status \"done\" (the only status
`satan-audit-p/status-terminal' accepts for a clean finalise)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (satan-mcp-test--request proc "tools/call"
                              (list :name "stub.a" :arguments nil))
     (satan-mcp-test--disconnect proc)
     (should (= 1 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((run-dir (satan-mcp-test--find-run-dir satan-mcp-test--runs-dir)))
       (should (eq (satan-audit-verify-run run-dir) t))
       (should (equal (satan-mcp-test--read-file
                       (expand-file-name "status" run-dir))
                      "done"))
       (should (equal (plist-get (satan-mcp-test--read-json
                                  (expand-file-name "final.json" run-dir))
                                 :status)
                      "done")))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/lazy-mint-session-has-no-bufs-slot ()
  "EX-5: `bufs' is dropped from `satan-mcp-session'.
The line buffer is connection-scoped state and lives on the process now,
so the struct exposes no `satan-mcp-session-bufs' accessor."
  (should-not (fboundp 'satan-mcp-session-bufs)))

(ert-deftest satan-mcp/mint-failure-answers-32603-and-leaves-no-run ()
  "EX-2/VT-2: a mint that fails after the run dir exists answers -32603,
deletes the partly written dir, publishes no run slots, and the next call
mints exactly one dir.  `satan-audit--write-json' signals on its second
call — bundle.json inside `satan-audit-open'."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (let (res writes)
       (satan-mcp-test--with-audit-write-failure 2
         (setq res (satan-mcp-test--request-response
                    proc "tools/call" (list :name "stub.a" :arguments nil))
               writes satan-mcp-test--audit-writes))
       ;; Two writes = manifest.json then the failing bundle.json: the mint
       ;; broke after the run dir existed.  No answer at all is the current
       ;; failure; after the -32603 wrapper it is the error code that matters.
       (should res)
       (should (equal (satan-mcp-test--error-code res) -32603))
       (should (= 2 writes)))
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((session (satan-mcp-test--session)))
       (should session)
       (should (satan-mcp-test--session-has-no-run-p session)))
     ;; Retry: one successful call leaves exactly one run.
     (let ((res (satan-mcp-test--request proc "tools/call"
                                         (list :name "stub.a" :arguments nil))))
       (should-not (plist-get res :error)))
     (should (= 1 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/mint-failure-then-disconnect-leaves-no-run ()
  "EX-2/VT-2: a disconnect after a failed mint leaves no run dir and
finalises nothing."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (satan-mcp-test--with-audit-write-failure 2
       (satan-mcp-test--request-response proc "tools/call"
                                         (list :name "stub.a" :arguments nil)))
     (satan-mcp-test--disconnect proc)
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (should-not (satan-mcp-test--session))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/lazy-mint-boot-context-first-call ()
  "VT-2/EX-1: `satan_boot_context' as the FIRST tools/call mints the run
and answers with the capsule text.  `satan-context-interactive' is stubbed
so no backend is touched."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--register-boot-context)
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (should (= 0 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((res (cl-letf (((symbol-function 'satan-context-interactive)
                           (lambda (&rest _) (list :prompt "capsule"))))
                  (satan-mcp-test--request proc "tools/call"
                                           (list :name "satan_boot_context"
                                                 :arguments nil)))))
       (should-not (plist-get res :error))
       (should (string-match-p
                "capsule"
                (plist-get (elt (plist-get (plist-get res :result) :content) 0)
                           :text))))
     (should (= 1 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let ((session (satan-mcp-test--session)))
       (should (stringp (satan-mcp-session-run-id session))))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/request-error-non-tool-handler-answers-32603 ()
  "EX-3/VT-16: an uncaught error in a request that is not a tools/call is
answered -32603 with that request's id — the wrapper lives in
`satan-mcp--handle-message', so every request with an id is answered."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                          (list :protocolVersion "2025-06-18"
                                                :capabilities (make-hash-table)
                                                :clientInfo (list :name "test" :version "0")))))
     (let ((res (cl-letf (((symbol-function 'satan-mcp--interactive-tools)
                           (lambda () (error "simulated tools/list failure"))))
                  ;; Short timeout: today the filter only logs, so there is no
                  ;; response at all — fail fast instead of waiting 5s.
                  (satan-mcp-test--request-response proc "tools/list" nil 2))))
       (should res)
       (should (equal (satan-mcp-test--error-code res) -32603))
       (should (equal (plist-get res :id) satan-mcp-test--last-request-id)))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/session-transcript-has-calls ()
  "tools/call appends membrane records to transcript.jsonl."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (_call (satan-mcp-test--request
                  proc "tools/call"
                  (list :name "stub.a" :arguments nil))))
     (satan-mcp-test--stop)
     (let* ((run-dir (satan-mcp-test--find-run-dir satan-mcp-test--runs-dir))
            (tp (expand-file-name "transcript.jsonl" run-dir)))
       (should (file-exists-p tp))
       (let ((lines (split-string
                     (with-temp-buffer
                       (insert-file-contents tp)
                       (buffer-string))
                     "\n" t)))
         ;; Should have tool_call + tool_result records
         (should (cl-some (lambda (l) (string-match-p "tool-call" l)) lines))
         (should (cl-some (lambda (l) (string-match-p "tool-result" l)) lines))))
     (satan-mcp-test--stop))))

;; ── VT-mcp-startup ─────────────────────────────────────────────────────────

(ert-deftest satan-mcp/startup-refuses-without-xdg ()
  "Start refuses when XDG_RUNTIME_DIR is unset."
  (satan-mcp-test--with-tmp-env
   (setenv "XDG_RUNTIME_DIR" nil)
   (setq satan-mcp-runtime-dir "/dev/null")
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (setq satan-mcp-enabled t)
   (should-error (satan-mcp-start) :type 'error)
   (setq satan-mcp-enabled nil)))

(ert-deftest satan-mcp/startup-refuses-on-symlink-dir ()
  "Start refuses when runtime dir is a symlink (DEC-10)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((real-dir (expand-file-name "real" satan-mcp-test--tmp))
          (link-dir (expand-file-name "link" satan-mcp-test--tmp)))
     (make-directory real-dir t)
     (set-file-modes real-dir #o700)
     (make-symbolic-link real-dir link-dir)
     (setq satan-mcp-runtime-dir link-dir)
     (setq satan-mcp-enabled t)
     (should-error (satan-mcp-start) :type 'error)
     (setq satan-mcp-enabled nil))))

(ert-deftest satan-mcp/startup-refuses-missing-description ()
  "Start signals when a registered tool has no description file (R7 fail-fast)."
  (satan-mcp-test--with-tmp-env
   ;; Register a tool but DON'T write its description
   (satan-mcp-test--register-stub "orphan.tool")
   (setq satan-mcp-enabled t)
   ;; satan-mcp--check-tool-descriptions should find "orphan.tool"
   ;; missing its .md file and signal
   (should-error (satan-mcp-start) :type 'error)
   (setq satan-mcp-enabled nil)
   (satan-mcp-test--stop)))

(ert-deftest satan-mcp/start-is-idempotent ()
  "Starting a running server keeps the same listener and returns its socket."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (server satan-mcp--server-process))
     (should (equal (satan-mcp-start) sock))
     (should (eq satan-mcp--server-process server))
     (should (process-live-p server))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/session-prepare-is-the-canonical-run-ctx ()
  "SL-013 F5: the session's run_ctx comes from `satan-run-new-ctx'.

Was a hand-rolled 4-key clone.  The identity it carries — mode name,
run-id shape, and `:time_now' frozen off `:start_time' — must be
unchanged by the switch (C2); what changes is that the six v0
placeholders are now present, so later phases can `plist-put' onto a
session's run_ctx exactly as they do onto a scheduled run's."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-register-interactive-mode)
   (let ((session (make-satan-mcp-session)))
     ;; Mint lazily — `satan-mcp--ensure-run' is the only mint path.
     (satan-mcp--ensure-run session)
     (let ((prepare (satan-mcp-session-prepare session)))
       (should (equal (cl-loop for (k _v) on prepare by #'cddr collect k)
                      '(:run_id :mode_name :time_now :start_time
                        :evidence :percept :sensor_status :pre_spawn
                        :motive :observer)))
       (should (equal (plist-get prepare :mode_name) "interactive"))
       (should (string-match-p "\\`[0-9]\\{8\\}T[0-9]\\{6\\}-interactive-[0-9a-f]\\{6\\}\\'"
                               (plist-get prepare :run_id)))
       (should (equal (plist-get prepare :time_now)
                      (format-time-string satan-run--iso-time-format
                                          (plist-get prepare :start_time))))))))

(ert-deftest satan-mcp/dec124-connection-succeeds-while-spawn-running ()
  "V8 (DEC-124, retires DEC-8): an MCP connection mints its session and a
`tools/call' round-trips while `satan-run--spawn-running' is t.
DEC-8 refused the connection here; what a scheduled run and an MCP call
contend for is attribution, not exclusion (DEC-123)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let ((sock (satan-mcp-test--start)))
     (let ((satan-run--spawn-running t))
       (unwind-protect
           (let ((proc (satan-mcp-test--connect sock)))
             ;; Let the accept-filter callback fire in batch mode.
             (accept-process-output nil 0.5)
             ;; DEC-8's mint refusal deleted the client proc here.
             (should (process-live-p proc))
             ;; Guard: a refused connection would hang the response wait.
             (when (process-live-p proc)
               (should (satan-mcp-test--request
                        proc "initialize"
                        (list :protocolVersion "2025-06-18"
                              :capabilities (make-hash-table)
                              :clientInfo (list :name "test" :version "0"))))
               (let* ((res (satan-mcp-test--request
                            proc "tools/call"
                            (list :name "stub.a" :arguments nil)))
                      (text (plist-get
                             (car (plist-get (plist-get res :result) :content))
                             :text)))
                 (should-not (plist-get res :error))
                 (should (string-match-p "stub:stub.a" text)))
               (delete-process proc)))
         (satan-mcp-test--stop))))))

(ert-deftest satan-mcp/dec124-startup-succeeds-while-spawn-running ()
  "V8 (DEC-124, retires DEC-8): startup proceeds while
`satan-run--spawn-running' is t — the server no longer refuses."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let ((satan-run--spawn-running t))
     (should (stringp (satan-mcp-test--start)))
     (should (process-live-p satan-mcp--server-process)))
   (satan-mcp-test--stop)))

(ert-deftest satan-mcp/boot-context-caches-per-session ()
  "AUD-008 F-002/F-003: boot-context serves the per-session cache on a second
call and delegates capsule building to `satan-context-interactive'.
`:refresh' forces a rebuild."
  (let* ((calls 0)
         (session (make-satan-mcp-session
                   :run-id "rid" :run-dir "/tmp"
                   :prepare '(:run_id "rid") :boot-cache nil))
         (satan-mcp--current-session session))
    (cl-letf (((symbol-function 'satan-mode-resolve)
               (lambda (&rest _) '(:name "interactive")))
              ((symbol-function 'satan-context-interactive)
               (lambda (&rest _)
                 (setq calls (1+ calls))
                 (list :prompt (format "capsule-%d" calls)))))
      ;; First call builds.
      (should (equal (satan-mcp-tool/boot-context nil nil)
                     '(ok . "capsule-1")))
      (should (= calls 1))
      ;; Second call without :refresh → served from cache, no rebuild.
      (should (equal (satan-mcp-tool/boot-context nil nil)
                     '(ok . "capsule-1")))
      (should (= calls 1))
      ;; :refresh forces a rebuild.
      (should (equal (satan-mcp-tool/boot-context '(:refresh t) nil)
                     '(ok . "capsule-2")))
      (should (= calls 2)))))

;; ── VT-mcp-identity: pure parsing (SL-032 PHASE-04) ────────────────────────

(ert-deftest satan-mcp/identity-parse-identity-table ()
  "VT-1/EX-1: `satan-mcp--parse-identity' maps initialize params to
\(:conversation C :kind K) or (error . MSG), and is pure.

An absent satan capability is the legacy identity (conversation nil,
kind \"interactive\").  A conversation is 1-128 chars with no control
characters, opaque to SATAN.  Kind is \"interactive\" or \"scheduled\";
absent means \"interactive\".  Everything else is malformed: `satan'
that is not an object, wrong types, an unknown kind, an empty or
over-long conversation."
  (let* ((ok-max (make-string 128 ?a))
         (too-long (make-string 129 ?a))
         (cases
          (list
           ;; Legacy: no capabilities, no experimental, no satan.
           (list "no capabilities"
                 '(:protocolVersion "2025-06-18")
                 '(:conversation nil :kind "interactive"))
           (list "no experimental"
                 '(:capabilities (:tools ()))
                 '(:conversation nil :kind "interactive"))
           (list "no satan"
                 (satan-mcp-test--identity-params nil)
                 '(:conversation nil :kind "interactive"))
           ;; Well-formed identities.
           (list "scheduled identity"
                 (satan-mcp-test--identity-params
                  '(:conversation "7" :kind "scheduled"))
                 '(:conversation "7" :kind "scheduled"))
           (list "kind absent defaults to interactive"
                 (satan-mcp-test--identity-params '(:conversation "7"))
                 '(:conversation "7" :kind "interactive"))
           (list "128-char conversation"
                 (satan-mcp-test--identity-params (list :conversation ok-max))
                 (list :conversation ok-max :kind "interactive"))
           ;; Malformed identities.
           (list "satan is a string"
                 (satan-mcp-test--identity-params "7")
                 'error)
           (list "satan is an array"
                 (satan-mcp-test--identity-params '("7"))
                 'error)
           (list "conversation is a number"
                 (satan-mcp-test--identity-params '(:conversation 7))
                 'error)
           (list "kind is a number"
                 (satan-mcp-test--identity-params '(:conversation "7" :kind 7))
                 'error)
           (list "unknown kind"
                 (satan-mcp-test--identity-params
                  '(:conversation "7" :kind "batch"))
                 'error)
           (list "empty conversation"
                 (satan-mcp-test--identity-params '(:conversation ""))
                 'error)
           (list "129-char conversation"
                 (satan-mcp-test--identity-params (list :conversation too-long))
                 'error)
           (list "conversation with a newline"
                 (satan-mcp-test--identity-params '(:conversation "7\n8"))
                 'error)
           (list "conversation with DEL"
                 (satan-mcp-test--identity-params
                  (list :conversation (string ?7 127 ?8)))
                 'error)
           ;; Opaque: non-ASCII is not a control character.
           (list "non-ASCII conversation"
                 (satan-mcp-test--identity-params '(:conversation "über-7"))
                 '(:conversation "über-7" :kind "interactive")))))
    (dolist (case cases)
      (let* ((label (nth 0 case))
             (params (nth 1 case))
             (want (nth 2 case))
             (got (satan-mcp--parse-identity params)))
        (ert-info ((format "%s" label))
          (if (eq want 'error)
              (progn
                (should (eq (car-safe got) 'error))
                (should (stringp (cdr got))))
            (should (equal got want)))
          ;; Pure: the same params answer the same way.
          (should (equal (satan-mcp--parse-identity params) got)))))))

;; ── VT-mcp-identity: the initialize wire (SL-032 PHASE-04) ────────────────

(ert-deftest satan-mcp/identity-malformed-initialize-is-invalid-params ()
  "EX-2/VT-2: a malformed identity answers -32602 and leaves the session
uninitialised, so a following valid initialize succeeds.

-32602 is `invalid params'; the session's identity stays nil until an
initialize parses."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (pair (satan-mcp-test--connect-session sock))
          (proc (car pair))
          (session (cdr pair)))
     (should session)
     (dolist (bad (list (satan-mcp-test--identity "")
                        (satan-mcp-test--identity "7" "batch")
                        '(:conversation 7 :kind "interactive")))
       (should (equal (satan-mcp-test--error-code
                       (satan-mcp-test--initialize proc bad))
                      -32602))
       (should-not (satan-mcp-session-identity session)))
     (should-not (plist-get (satan-mcp-test--initialize
                             proc (satan-mcp-test--identity "7"))
                            :error))
     (should (equal (satan-mcp-session-identity session)
                    '(:conversation "7" :kind "interactive")))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-repeated-initialize-is-idempotent ()
  "EX-2/VT-2 (I1): the same identity again is answered as normal; a
different identity answers -32602 and the first identity stands."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (pair (satan-mcp-test--connect-session sock))
          (proc (car pair))
          (session (cdr pair)))
     (should session)
     (should-not (plist-get (satan-mcp-test--initialize
                             proc (satan-mcp-test--identity "7" "scheduled"))
                            :error))
     (let ((res (satan-mcp-test--initialize
                 proc (satan-mcp-test--identity "7" "scheduled"))))
       (should-not (plist-get res :error))
       (should (plist-get res :result)))
     (should (equal (satan-mcp-test--error-code
                     (satan-mcp-test--initialize
                      proc (satan-mcp-test--identity "8" "scheduled")))
                    -32602))
     (should (equal (satan-mcp-session-identity session)
                    '(:conversation "7" :kind "scheduled")))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-initialize-after-mint-is-invalid-request ()
  "EX-2/VT-2 (I1): once the run is minted the identity is fixed, so any
initialize answers -32600 `invalid request' — even the same identity."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (pair (satan-mcp-test--open-identified
                 sock (satan-mcp-test--identity "7")))
          (proc (car pair))
          (session (cdr pair)))
     (should-not (plist-get (satan-mcp-test--request
                             proc "tools/call"
                             (list :name "stub.a" :arguments nil))
                            :error))
     (should (satan-mcp-session-run-id session))
     (should (equal (satan-mcp-test--error-code
                     (satan-mcp-test--initialize
                      proc (satan-mcp-test--identity "7")))
                    -32600))
     (should (equal (satan-mcp-session-identity session)
                    '(:conversation "7" :kind "interactive")))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-initialize-result-is-unchanged ()
  "EX-3: accepting an identity adds no server capability — the result's
capabilities carries only `:tools'."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (res (satan-mcp-test--initialize proc (satan-mcp-test--identity "7")))
          (caps (plist-get (plist-get res :result) :capabilities)))
     (should (equal (cl-loop for (k _v) on caps by #'cddr collect k)
                    '(:tools)))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

;; ── VT-mcp-identity: identity on the artefacts (SL-032 PHASE-04) ──────────

(ert-deftest satan-mcp/identity-two-connections-write-distinct-runs ()
  "EX-3/VT-1: two live connections with different identities mint two
runs; each manifest and bundle carries that connection's
:conversation and :kind with :mode \"interactive\"; each session keeps
its own boot-cache; both runs verify after disconnect."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--register-boot-context)
   (let* ((sock (satan-mcp-test--start))
          (pair-a (satan-mcp-test--open-identified
                   sock (satan-mcp-test--identity "7")))
          (pair-b (satan-mcp-test--open-identified
                   sock (satan-mcp-test--identity "8" "scheduled")))
          (calls 0))
     ;; `satan_boot_context' mints the run and caches a per-session capsule.
     (cl-letf (((symbol-function 'satan-context-interactive)
                (lambda (&rest _)
                  (list :prompt (format "capsule-%d"
                                        (setq calls (1+ calls)))))))
       (dolist (pair (list pair-a pair-b))
         (should-not (plist-get (satan-mcp-test--request
                                 (car pair) "tools/call"
                                 (list :name "satan_boot_context"
                                       :arguments nil))
                                :error))))
     (should (= 2 (satan-mcp-test--run-dir-count satan-mcp-test--runs-dir)))
     (let* ((session-a (cdr pair-a))
            (session-b (cdr pair-b))
            (dir-a (satan-mcp-session-run-dir session-a))
            (dir-b (satan-mcp-session-run-dir session-b)))
       (should (and dir-a dir-b))
       (should-not (equal dir-a dir-b))
       (should (satan-mcp-session-boot-cache session-a))
       (should (satan-mcp-session-boot-cache session-b))
       (should-not (equal (satan-mcp-session-boot-cache session-a)
                          (satan-mcp-session-boot-cache session-b)))
       (dolist (want (list (list dir-a "7" "interactive")
                           (list dir-b "8" "scheduled")))
         (dolist (file '("manifest.json" "bundle.json"))
           (let ((obj (satan-mcp-test--read-json
                       (expand-file-name file (nth 0 want)))))
             (should (equal (plist-get obj :conversation) (nth 1 want)))
             (should (equal (plist-get obj :kind) (nth 2 want)))
             (should (equal (plist-get obj :mode) "interactive")))))
       (dolist (pair (list pair-a pair-b))
         (satan-mcp-test--disconnect (car pair)))
       (should (eq (satan-audit-verify-run dir-a) t))
       (should (eq (satan-audit-verify-run dir-b) t)))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-legacy-conversation-is-json-null ()
  "EX-3/A3: a client claiming no identity writes :conversation as JSON
null — the raw text says \"conversation\":null, not an empty string and
not an omitted key — with :kind \"interactive\"."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (pair (satan-mcp-test--connect-session sock))
          (proc (car pair))
          (session (cdr pair)))
     (should session)
     (should-not (plist-get (satan-mcp-test--initialize proc) :error))
     (should-not (plist-get (satan-mcp-test--request
                             proc "tools/call"
                             (list :name "stub.a" :arguments nil))
                            :error))
     (let ((dir (satan-mcp-session-run-dir session)))
       (should dir)
       (dolist (file '("manifest.json" "bundle.json"))
         (let ((path (expand-file-name file dir)))
           (should (string-match-p "\"conversation\":null"
                                   (satan-mcp-test--read-file path)))
           (should (equal (plist-get (satan-mcp-test--read-json path) :kind)
                          "interactive")))))
     (should (equal (satan-mcp-session-identity session)
                    '(:conversation nil :kind "interactive")))
     (satan-mcp-test--disconnect proc)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-trace-marked-carries-session-run-id ()
  "EX-3/VT-1 (A5): `memory_mark' through each connection emits one
`trace_marked' payload whose :run_id is that connection's session run
id.  Two connections, two run ids: attribution is not ambient."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--register-memory-tools)
   (let* ((sock (satan-mcp-test--start))
          (pair-a (satan-mcp-test--open-identified
                   sock (satan-mcp-test--identity "7")))
          (pair-b (satan-mcp-test--open-identified
                   sock (satan-mcp-test--identity "8" "scheduled")))
          (enqueued nil)
          (satan-attribute-updates-enabled t)
          (satan-tools-activity-dir
           (expand-file-name "activity" satan-mcp-test--tmp))
          (satan-goad-queue-file
           (expand-file-name "goad-queue.json" satan-mcp-test--tmp))
          (satan-goad-data-dir
           (expand-file-name "goad" satan-mcp-test--tmp)))
     ;; Only the DB-touching primitive and the enqueue are stubbed: the run
     ;; id has to travel the real handler path.
     (cl-letf (((symbol-function 'satan-db-query)
                (lambda (&rest _) (cons 'ok "tid-x")))
               ((symbol-function 'satan-attribute-enqueue)
                (lambda (payload &optional _db)
                  (push payload enqueued)
                  (cons 'ok 1))))
       (dolist (pair (list pair-a pair-b))
         (should-not (plist-get (satan-mcp-test--request
                                 (car pair) "tools/call"
                                 (list :name "memory_mark"
                                       :arguments
                                       (list :payload "identity attribution")))
                                :error))))
     (should (= 2 (length enqueued)))
     (let ((run-ids (mapcar (lambda (p) (plist-get p :run_id)) enqueued)))
       (should (= 2 (length (delete-dups run-ids))))
       (dolist (pair (list pair-a pair-b))
         (let* ((session (cdr pair))
                (run-id (satan-mcp-session-run-id session))
                (payload (cl-find-if
                          (lambda (p) (equal (plist-get p :run_id) run-id))
                          enqueued)))
           (should run-id)
           (should payload)
           (should (equal (plist-get payload :reason) "trace_marked")))))
     (dolist (pair (list pair-a pair-b))
       (satan-mcp-test--disconnect (car pair)))
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/identity-final-summary-names-conversation ()
  "EX-4: finalisation names the identity — \"interactive conversation 7\"
for an identified session, \"interactive session\" for a legacy one."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (pair-a (satan-mcp-test--open-identified
                   sock (satan-mcp-test--identity "7")))
          (pair-b (satan-mcp-test--connect-session sock))
          (_legacy-init (satan-mcp-test--initialize (car pair-b))))
     (should (cdr pair-b))
     (dolist (pair (list pair-a pair-b))
       (should-not (plist-get (satan-mcp-test--request
                               (car pair) "tools/call"
                               (list :name "stub.a" :arguments nil))
                              :error)))
     (let ((dir-a (satan-mcp-session-run-dir (cdr pair-a)))
           (dir-b (satan-mcp-session-run-dir (cdr pair-b))))
       (should (and dir-a dir-b))
       (should-not (equal dir-a dir-b))
       (dolist (pair (list pair-a pair-b))
         (satan-mcp-test--disconnect (car pair)))
       (should (equal (plist-get (satan-mcp-test--read-json
                                  (expand-file-name "final.json" dir-a))
                                 :summary)
                      "interactive conversation 7"))
       (should (equal (plist-get (satan-mcp-test--read-json
                                  (expand-file-name "final.json" dir-b))
                                 :summary)
                      "interactive session")))
     (satan-mcp-test--stop))))

(provide 'satan-mcp-test)
;;; satan-mcp-test.el ends here
