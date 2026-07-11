;;; satan-mcp-test.el --- ert tests for satan-mcp MCP server -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-mcp-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-tools)
(require 'satan-mode)
(require 'satan-audit)
(require 'satan-mcp)

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

(defun satan-mcp-test--request (proc method &optional params)
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

(defun satan-mcp-test--send-notification (proc method &optional params)
  "Send a JSON-RPC notification (no id) to PROC."
  (let ((msg (append (list :jsonrpc "2.0" :method method)
                     (when params (list :params params)))))
    (process-send-string proc (concat (json-serialize msg
                                       :null-object :null
                                       :false-object :false)
                                      "\n"))))

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

(defun satan-mcp-test--find-run-dir (runs-dir)
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

(ert-deftest satan-mcp/session-creates-run-dir ()
  "Connecting mints a run directory under satan-runs-dir."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; A run directory should now exist
     (let ((dirs (directory-files satan-mcp-test--runs-dir t "\\`[^.]" t)))
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
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/session-disconnect-closes-audit ()
  "Disconnecting closes the audit with a completed final (not invalid)."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Disconnect — satan-mcp-stop in cleanup will close client sessions
     (satan-mcp-test--stop)
     ;; Find the run dir and verify final.json says completed
     (let* ((run-dir (satan-mcp-test--find-run-dir satan-mcp-test--runs-dir))
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

(ert-deftest satan-mcp/dec8-session-refuses-when-spawn-running ()
  "DEC-8: connection is rejected when satan-broker--spawn-running is t.
The accept-filter catches the error from mint-session and deletes the
client process."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   ;; Start server without the spawn flag first, then set flag
   (let ((sock (satan-mcp-test--start)))
     (setq satan-broker--spawn-running t)
     (let ((proc (satan-mcp-test--connect sock)))
       ;; Let the accept-filter callback fire in batch mode
       (accept-process-output nil 0.5)
       ;; accept-filter catches the error and deletes the client proc
       (should-not (process-live-p proc)))
     ;; Session-active flag should NOT be set (mint-session errored before reaching setq)
     (should-not satan-mcp--session-active)
     (setq satan-broker--spawn-running nil)
     (satan-mcp-test--stop))))

(ert-deftest satan-mcp/dec8-startup-refuses-when-spawn-running ()
  "DEC-8: startup refuses when satan-broker--spawn-running is t."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (setq satan-mcp-enabled t)
   (setq satan-broker--spawn-running t)
   (should-error (satan-mcp-start) :type 'user-error)
   (setq satan-broker--spawn-running nil)
   (setq satan-mcp-enabled nil)))

(ert-deftest satan-mcp/dec8-flag-cleared-on-disconnect ()
  "DEC-8: session-active flag is set on connect and cleared on disconnect."
  (satan-mcp-test--with-tmp-env
   (satan-mcp-test--write-desc "stub.a" "desc")
   (satan-mcp-test--register-stub "stub.a")
   (let* ((sock (satan-mcp-test--start))
          (proc (satan-mcp-test--connect sock))
          (_init (satan-mcp-test--request proc "initialize"
                                             (list :protocolVersion "2025-06-18"
                                                   :capabilities (make-hash-table)
                                                   :clientInfo (list :name "test" :version "0")))))
     ;; Flag should be set while session is active
     (should satan-mcp--session-active)
     ;; Close the connection — need to pump events for sentinel in batch mode
     (delete-process proc)
     (accept-process-output nil 0.5)
     ;; Flag should be cleared after close-session runs in sentinel
     (should-not satan-mcp--session-active)
     (satan-mcp-test--stop))))

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

(provide 'satan-mcp-test)
;;; satan-mcp-test.el ends here
