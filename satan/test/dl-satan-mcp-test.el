;;; dl-satan-mcp-test.el --- ert tests for dl-satan-mcp MCP server -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l dl-satan-mcp-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'dl-satan-tools)
(require 'dl-satan-mode)
(require 'dl-satan-audit)
(require 'dl-satan-mcp)

;; ── Test helpers ────────────────────────────────────────────────────────────

(defvar dl-satan-mcp-test--tmp nil
  "Temporary directory for the test run.")
(defvar dl-satan-mcp-test--runs-dir nil
  "Temporary runs directory.")
(defvar dl-satan-mcp-test--desc-dir nil
  "Temporary tool descriptions directory.")

(defmacro dl-satan-mcp-test--with-tmp-env (&rest body)
  "Run BODY with temporary XDG_RUNTIME_DIR, runs dir, and description dir.
Registers stub tools and the interactive mode."
  `(let* ((dl-satan-mcp-test--tmp (make-temp-file "satan-mcp-test-" t))
          (dl-satan-mcp-test--runs-dir
           (expand-file-name "runs" dl-satan-mcp-test--tmp))
          (dl-satan-mcp-test--desc-dir
           (expand-file-name "descs" dl-satan-mcp-test--tmp))
          (dl-satan-mcp-runtime-dir
           (expand-file-name "mcp" dl-satan-mcp-test--tmp))
          (dl-satan-runs-dir dl-satan-mcp-test--runs-dir)
          (dl-satan-tools-descriptions-dir dl-satan-mcp-test--desc-dir)
          ;; Reset tool registry per test
          (dl-satan-tools nil)
          (dl-satan-modes nil))
     (setenv "XDG_RUNTIME_DIR" dl-satan-mcp-runtime-dir)
     (make-directory dl-satan-mcp-runtime-dir t)
     (set-file-modes dl-satan-mcp-runtime-dir #o700)
     (make-directory dl-satan-mcp-test--desc-dir t)
     (unwind-protect
         (progn ,@body)
       (setenv "XDG_RUNTIME_DIR" nil)
       (dl-satan-mcp-test--stop)
       (when (file-directory-p dl-satan-mcp-test--tmp)
         (delete-directory dl-satan-mcp-test--tmp t)))))

(defun dl-satan-mcp-test--register-stub (name &optional args-schema capability)
  "Register a stub tool NAME with a handler that echoes its args.
ARGS-SCHEMA is an `:args-schema' plist; nil means no args.
CAPABILITY is an optional capability symbol."
  (let ((handler (lambda (args _ctx)
                   (cons 'ok (format "stub:%s args=%S" name args)))))
    (dl-satan-tool-register
     (list :name name
           :risk 'read
           :args-schema args-schema
           :handler handler
           :capability capability))))

(defun dl-satan-mcp-test--write-desc (name text)
  "Write a tool description file for NAME."
  (with-temp-file (expand-file-name (concat name ".md") dl-satan-mcp-test--desc-dir)
    (insert text)))

(defun dl-satan-mcp-test--start ()
  "Start the MCP server in the test env and return the socket path.
Enables the server, registers interactive mode, removes stub socket."
  (setq dl-satan-mcp-enabled t)
  (when (and dl-satan-mcp--server-process
             (process-live-p dl-satan-mcp--server-process))
    (delete-process dl-satan-mcp--server-process)
    (setq dl-satan-mcp--server-process nil))
  (dl-satan-mcp-register-interactive-mode)
  (my/satan-mcp-start))

(defun dl-satan-mcp-test--stop ()
  "Stop the MCP server."
  (my/satan-mcp-stop)
  (setq dl-satan-mcp-enabled nil))

(defun dl-satan-mcp-test--connect (socket-path)
  "Connect to the MCP server at SOCKET-PATH; return the client process."
  (make-network-process
   :name "mcp-test-client"
   :family 'local
   :service socket-path
   :coding 'utf-8
   :noquery t))

(defun dl-satan-mcp-test--request (proc method &optional params)
  "Send a JSON-RPC request to PROC and return the response plist.
Uses a unique id.  Blocks until one response line is received."
  (let* ((id (random 999999))
         (req (append (list :jsonrpc "2.0" :id id :method method)
                      (when params (list :params params))))
         (result nil))
    (set-process-filter
     proc
     (lambda (_p chunk)
       (setq result (concat (or result "") chunk))))
    (process-send-string proc (concat (json-serialize req
                                       :null-object :null
                                       :false-object :false)
                                      "\n"))
    ;; Wait for response (single-threaded Emacs: accept-process-output)
    (while (not (and result (string-match-p "\n" result)))
      (accept-process-output proc 1))
    ;; Parse the first complete line
    (let* ((lines (split-string result "\n"))
           (first (string-trim (car lines))))
      (json-parse-string first
                         :object-type 'plist
                         :array-type 'list
                         :null-object nil
                         :false-object :false))))

(defun dl-satan-mcp-test--send-notification (proc method &optional params)
  "Send a JSON-RPC notification (no id) to PROC."
  (let ((msg (append (list :jsonrpc "2.0" :method method)
                     (when params (list :params params)))))
    (process-send-string proc (concat (json-serialize msg
                                       :null-object :null
                                       :false-object :false)
                                      "\n"))))

;; ── VT-mcp-jsonrpc ──────────────────────────────────────────────────────────

(ert-deftest dl-satan-mcp/initialize-response-shape ()
  "initialize returns protocolVersion, capabilities, serverInfo."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "Stub A description.")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (res (dl-satan-mcp-test--request proc "initialize"
                                           (list :protocolVersion "2025-06-18"
                                                 :capabilities (make-hash-table)
                                                 :clientInfo (list :name "test" :version "0")))))
     (should (equal (plist-get res :jsonrpc) "2.0"))
     (let ((result (plist-get res :result)))
       (should (stringp (plist-get result :protocolVersion)))
       (should (plist-get result :capabilities))
       (should (equal (plist-get (plist-get result :serverInfo) :name)
                      dl-satan-mcp-server-name)))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/ping ()
  "ping returns an empty object."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request proc "ping")))
     (should (plist-get res :result))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/unknown-method-returns-32601 ()
  "Unknown method returns JSON-RPC error -32601 (method not found)."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request proc "bogus/method")))
     (should (plist-get res :error))
     (should (= (plist-get (plist-get res :error) :code) -32601))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/notification-no-response ()
  "notifications/initialized produces no response (it's a notification)."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Send notification (no id) — should not block or error
     (dl-satan-mcp-test--send-notification proc "notifications/initialized")
     ;; Verify connection is still alive with a ping
     (let ((res (dl-satan-mcp-test--request proc "ping")))
       (should (plist-get res :result)))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

;; ── VT-mcp-tools-list ───────────────────────────────────────────────────────

(ert-deftest dl-satan-mcp/tools-list-shape ()
  "tools/list returns MCP tool defs with name, description, inputSchema."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "Tool A does a thing.")
   (dl-satan-mcp-test--register-stub "stub.a"
                                     '(msg (:type string :required t)))
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request proc "tools/list"))
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
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/tools-list-multiple ()
  "tools/list returns all registered tools."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "First.")
   (dl-satan-mcp-test--write-desc "stub.b" "Second.")
   (dl-satan-mcp-test--register-stub "stub.a")
   (dl-satan-mcp-test--register-stub "stub.b")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request proc "tools/list"))
          (tools (plist-get (plist-get res :result) :tools)))
     (should (>= (length tools) 2))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

;; ── VT-mcp-tools-call ──────────────────────────────────────────────────────

(ert-deftest dl-satan-mcp/tools-call-success ()
  "tools/call happy path: stub tool returns :ok → content with result text."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.echo" "Echo back.")
   (dl-satan-mcp-test--register-stub "stub.echo"
                                     '(msg (:type string :required t)))
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request
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
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/tools-call-unknown-tool ()
  "tools/call for unknown tool returns isError with error text."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request
                proc "tools/call"
                (list :name "no.such.tool" :arguments nil)))
          (result (plist-get res :result)))
     (should (eq (plist-get result :isError) t))
     (let ((text (plist-get (elt (plist-get result :content) 0) :text)))
       (should (string-match-p "unknown tool" text)))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/tools-call-arg-invalid ()
  "tools/call with wrong arg type returns isError."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.typed" "Needs an integer.")
   (dl-satan-mcp-test--register-stub "stub.typed"
                                     '(count (:type integer :required t)))
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (res (dl-satan-mcp-test--request
                proc "tools/call"
                (list :name "stub.typed"
                      :arguments (list :count "not-an-integer"))))
          (result (plist-get res :result)))
     (should (eq (plist-get result :isError) t))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

;; ── VT-mcp-session-lifecycle ────────────────────────────────────────────────

(defun dl-satan-mcp-test--find-run-dir (runs-dir)
  "Find the first run directory under RUNS-DIR (bucketed or flat layout)."
  (catch 'found
    (when (file-directory-p runs-dir)
      (dolist (entry (directory-files runs-dir t directory-files-no-dot-files-regexp))
        (when (file-directory-p entry)
          ;; Check if it looks like a date bucket (YYYY-MM-DD)
          (if (string-match-p "^[0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}$"
                              (file-name-nondirectory entry))
              (dolist (child (directory-files entry t directory-files-no-dot-files-regexp))
                (when (and (file-directory-p child)
                           (file-exists-p
                            (expand-file-name "manifest.json" child)))
                  (throw 'found child)))
            (when (file-exists-p (expand-file-name "manifest.json" entry))
              (throw 'found entry))))))
    nil))

(ert-deftest dl-satan-mcp/session-creates-run-dir ()
  "Connecting mints a run directory under dl-satan-runs-dir."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; A run directory should now exist
     (let ((dirs (directory-files dl-satan-mcp-test--runs-dir t "\\`[^.]" t)))
       (should dirs)
       ;; At least one subdirectory (the date bucket) with a run dir inside
       (let ((found nil))
         (dolist (d dirs)
           (when (file-directory-p d)
             (let ((children (directory-files d t "\\`[^.]" t)))
               (dolist (c children)
                 (when (and (file-directory-p c)
                            (file-exists-p (expand-file-name "manifest.json" c)))
                   (setq found t))))))
         (should found)))
     (delete-process proc)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/session-disconnect-closes-audit ()
  "Disconnecting closes the audit with a completed final (not invalid)."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Disconnect — my/satan-mcp-stop in cleanup will close client sessions
     (dl-satan-mcp-test--stop)
     ;; Find the run dir and verify final.json says completed
     (let* ((run-dir (dl-satan-mcp-test--find-run-dir dl-satan-mcp-test--runs-dir))
            (final-path (expand-file-name "final.json" run-dir)))
       (should (file-exists-p final-path))
       (let ((final (json-parse-string
                     (with-temp-buffer
                       (insert-file-contents final-path)
                       (buffer-string))
                     :object-type 'plist
                     :null-object nil
                     :false-object :false)))
         (should (equal (plist-get final :status) "completed"))))
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/session-transcript-has-calls ()
  "tools/call appends membrane records to transcript.jsonl."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0"))))
          (_call (dl-satan-mcp-test--request
                  proc "tools/call"
                  (list :name "stub.a" :arguments nil))))
     (dl-satan-mcp-test--stop)
     (let* ((run-dir (dl-satan-mcp-test--find-run-dir dl-satan-mcp-test--runs-dir))
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
     (dl-satan-mcp-test--stop))))

;; ── VT-mcp-startup ─────────────────────────────────────────────────────────

(ert-deftest dl-satan-mcp/startup-refuses-without-xdg ()
  "Start refuses when XDG_RUNTIME_DIR is unset."
  (dl-satan-mcp-test--with-tmp-env
   (setenv "XDG_RUNTIME_DIR" nil)
   (setq dl-satan-mcp-runtime-dir "/dev/null")
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (setq dl-satan-mcp-enabled t)
   (should-error (my/satan-mcp-start) :type 'error)
   (setq dl-satan-mcp-enabled nil)))

(ert-deftest dl-satan-mcp/startup-refuses-on-symlink-dir ()
  "Start refuses when runtime dir is a symlink (DEC-10)."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((real-dir (expand-file-name "real" dl-satan-mcp-test--tmp))
          (link-dir (expand-file-name "link" dl-satan-mcp-test--tmp)))
     (make-directory real-dir t)
     (set-file-modes real-dir #o700)
     (make-symbolic-link real-dir link-dir)
     (setq dl-satan-mcp-runtime-dir link-dir)
     (setq dl-satan-mcp-enabled t)
     (should-error (my/satan-mcp-start) :type 'error)
     (setq dl-satan-mcp-enabled nil))))

(ert-deftest dl-satan-mcp/startup-refuses-missing-description ()
  "Start signals when a registered tool has no description file (R7 fail-fast)."
  (dl-satan-mcp-test--with-tmp-env
   ;; Register a tool but DON'T write its description
   (dl-satan-mcp-test--register-stub "orphan.tool")
   (setq dl-satan-mcp-enabled t)
   ;; dl-satan-mcp--check-tool-descriptions should find "orphan.tool"
   ;; missing its .md file and signal
   (should-error (my/satan-mcp-start) :type 'error)
   (setq dl-satan-mcp-enabled nil)
   (dl-satan-mcp-test--stop)))

(ert-deftest dl-satan-mcp/dec8-session-refuses-when-spawn-running ()
  "DEC-8: connection is rejected when dl-satan-broker--spawn-running is t.
The accept-filter catches the error from mint-session and deletes the
client process."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   ;; Start server without the spawn flag first, then set flag
   (let ((sock (dl-satan-mcp-test--start)))
     (setq dl-satan-broker--spawn-running t)
     (let ((proc (dl-satan-mcp-test--connect sock)))
       ;; Let the accept-filter callback fire in batch mode
       (accept-process-output nil 0.5)
       ;; accept-filter catches the error and deletes the client proc
       (should-not (process-live-p proc)))
     ;; Session-active flag should NOT be set (mint-session errored before reaching setq)
     (should-not dl-satan-mcp--session-active)
     (setq dl-satan-broker--spawn-running nil)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/dec8-startup-refuses-when-spawn-running ()
  "DEC-8: startup refuses when dl-satan-broker--spawn-running is t."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (setq dl-satan-mcp-enabled t)
   (setq dl-satan-broker--spawn-running t)
   (should-error (my/satan-mcp-start) :type 'user-error)
   (setq dl-satan-broker--spawn-running nil)
   (setq dl-satan-mcp-enabled nil)))

(ert-deftest dl-satan-mcp/dec8-flag-cleared-on-disconnect ()
  "DEC-8: session-active flag is set on connect and cleared on disconnect."
  (dl-satan-mcp-test--with-tmp-env
   (dl-satan-mcp-test--write-desc "stub.a" "desc")
   (dl-satan-mcp-test--register-stub "stub.a")
   (let* ((sock (dl-satan-mcp-test--start))
          (proc (dl-satan-mcp-test--connect sock))
          (_init (dl-satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Flag should be set while session is active
     (should dl-satan-mcp--session-active)
     ;; Close the connection — need to pump events for sentinel in batch mode
     (delete-process proc)
     (accept-process-output nil 0.5)
     ;; Flag should be cleared after close-session runs in sentinel
     (should-not dl-satan-mcp--session-active)
     (dl-satan-mcp-test--stop))))

(ert-deftest dl-satan-mcp/boot-context-caches-per-session ()
  "AUD-008 F-002/F-003: boot-context serves the per-session cache on a second
call and delegates capsule building to `dl-satan-context-interactive'.
`:refresh' forces a rebuild."
  (let* ((calls 0)
         (session (make-dl-satan-mcp-session
                   :run-id "rid" :run-dir "/tmp"
                   :prepare '(:run_id "rid") :boot-cache nil))
         (dl-satan-mcp--current-session session))
    (cl-letf (((symbol-function 'dl-satan-mode-resolve)
               (lambda (&rest _) '(:name "interactive")))
              ((symbol-function 'dl-satan-context-interactive)
               (lambda (&rest _)
                 (setq calls (1+ calls))
                 (list :prompt (format "capsule-%d" calls)))))
      ;; First call builds.
      (should (equal (dl-satan-mcp-tool/boot-context nil nil)
                     '(ok . "capsule-1")))
      (should (= calls 1))
      ;; Second call without :refresh → served from cache, no rebuild.
      (should (equal (dl-satan-mcp-tool/boot-context nil nil)
                     '(ok . "capsule-1")))
      (should (= calls 1))
      ;; :refresh forces a rebuild.
      (should (equal (dl-satan-mcp-tool/boot-context '(:refresh t) nil)
                     '(ok . "capsule-2")))
      (should (= calls 2)))))

(provide 'dl-satan-mcp-test)
;;; dl-satan-mcp-test.el ends here
