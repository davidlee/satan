;;; satan-db-test.el --- shared psql runner ert -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'satan-db)
(require 'satan-trace)

(defconst satan-db-test--db "satan_memory_test"
  "Test database (same as memory-store tests use).")

(defconst satan-db-test--host "/run/postgresql"
  "Production host default.  Overridden at call time by `satan-db-resolve-host'
via the `satan-db-host-override' carrier — the actual connection target is
the resolved host, not this literal.  Kept as a sentinel for test bodies.")

(defun satan-db-test--reachable-p ()
  "Return t if the test DB is reachable (delegates to shared predicate)."
  (satan-db-test-db-available-p satan-db-test--db))


;; ---------------------------------------------------------------------
;; satan-db-query — success paths
;; ---------------------------------------------------------------------

(ert-deftest satan-db/query-success ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "SELECT 42 AS n"
                            nil)
    (`(ok . ,out) (should (equal out "42")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/query-empty-result ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "SELECT 1 WHERE FALSE"
                            nil)
    (`(ok . ,out) (should (equal out "")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/query-variable-substitution ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "SELECT :'val' AS v"
                            '(("val" . "hello")))
    (`(ok . ,out) (should (equal out "hello")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/query-multi-variable ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "SELECT :'a' || :'b' AS v"
                            '(("a" . "foo") ("b" . "bar")))
    (`(ok . ,out) (should (equal out "foobar")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/query-multi-column-with-tab-separator ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "SELECT 'a' AS col1, 'b' AS col2"
                            nil)
    (`(ok . ,out) (should (equal out "a\tb")))
    (other (ert-fail (format "unexpected result: %S" other)))))


;; ---------------------------------------------------------------------
;; satan-db-query — error paths
;; ---------------------------------------------------------------------

(ert-deftest satan-db/query-syntax-error ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-query satan-db-test--db
                            satan-db-test--host
                            satan-db-default-program
                            "BOGUS SYNTAX"
                            nil)
    (`(error . ,msg)
     (should (string-match-p "psql exit" msg)))
    (other (ert-fail (format "expected error, got: %S" other)))))

(ert-deftest satan-db/query-connection-failure ()
  (let ((satan-db-host-override nil))
    (pcase (satan-db-query satan-db-test--db
                            "/nonexistent/path"
                            satan-db-default-program
                            "SELECT 1"
                            nil)
    (`(error . ,msg)
     (should (string-match-p "psql exit" msg)))
    (other (ert-fail (format "expected error, got: %S" other))))))


;; ---------------------------------------------------------------------
;; satan-db-psql — the thin wrapper
;; ---------------------------------------------------------------------

(ert-deftest satan-db/psql-success ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-psql satan-db-test--db
                           satan-db-test--host
                           satan-db-default-program
                           (list "-A" "-t" "-c" "SELECT 99 AS n"))
    (`(ok . ,out) (should (equal (string-trim out) "99")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/psql-single-transaction-passthrough ()
  (skip-unless (satan-db-test--reachable-p))
  "Verify --single-transaction is accepted (implied by psql not rejecting it)."
  (pcase (satan-db-psql satan-db-test--db
                           satan-db-test--host
                           satan-db-default-program
                           (list "-A" "-t" "--single-transaction" "-c" "SELECT 1"))
    (`(ok . ,out) (should (equal (string-trim out) "1")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/psql-with-input ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-psql satan-db-test--db
                           satan-db-test--host
                           satan-db-default-program
                           (list "-A" "-t" "-f" "-")
                           "SELECT 77 AS n")
    (`(ok . ,out) (should (equal (string-trim out) "77")))
    (other (ert-fail (format "unexpected result: %S" other)))))

(ert-deftest satan-db/psql-error ()
  (skip-unless (satan-db-test--reachable-p))
  (pcase (satan-db-psql satan-db-test--db
                           satan-db-test--host
                           satan-db-default-program
                           (list "-c" "INVALID SQL!!!!"))
    (`(error . ,msg)
     (should (string-match-p "psql exit" msg)))
    (other (ert-fail (format "expected error, got: %S" other)))))


;; ---------------------------------------------------------------------
;; VT-db-chokepoint-guard — resolver, guard, predicate, database-url
;; ---------------------------------------------------------------------

;; --- satan-db-resolve-host ---

(ert-deftest satan-db/resolve-host-passthrough-when-no-override ()
  "Without override, the host arg passes through unchanged."
  (skip-unless noninteractive)
  (let ((satan-db-host-override nil)
        (process-environment
         (cons "SATAN_FAILOVER_TO_SYSTEM_DB=1" process-environment)))
    (should (equal (satan-db-resolve-host "/run/postgresql")
                   "/run/postgresql"))
    (should (equal (satan-db-resolve-host "/custom/host")
                   "/custom/host"))))

(ert-deftest satan-db/resolve-host-override-wins ()
  "When the override carrier is set, it wins over the host arg."
  (let ((satan-db-host-override "192.168.1.1"))
    (should (equal (satan-db-resolve-host "/run/postgresql")
                   "192.168.1.1"))
    (should (equal (satan-db-resolve-host "/other/host")
                   "192.168.1.1"))))

(ert-deftest satan-db/resolve-host-guard-fires-in-batch ()
  "In noninteractive batch, resolving /run/postgresql errors loudly."
  (skip-unless noninteractive)
  (let ((satan-db-host-override nil))
    (should-error
     (satan-db-resolve-host "/run/postgresql")
     :type 'error)))

(ert-deftest satan-db/resolve-host-guard-passes-with-override ()
  "In batch with override set, the guard does not fire."
  (skip-unless noninteractive)
  (let ((satan-db-host-override "127.0.0.1"))
    (should (equal (satan-db-resolve-host "/run/postgresql")
                   "127.0.0.1"))))

(ert-deftest satan-db/resolve-host-guard-escape-hatch ()
  "SATAN_FAILOVER_TO_SYSTEM_DB suppresses the batch guard."
  (skip-unless noninteractive)
  (let ((satan-db-host-override nil)
        (process-environment
         (cons "SATAN_FAILOVER_TO_SYSTEM_DB=1" process-environment)))
    (should (equal (satan-db-resolve-host "/run/postgresql")
                   "/run/postgresql"))))

;; --- satan-db-test-db-available-p ---

(ert-deftest satan-db/test-db-available-p-returns-nil-for-prod ()
  "Predicate returns nil when host is the production socket."
  (skip-unless noninteractive)
  (let ((satan-db-host-override nil)
        (process-environment
         (cons "SATAN_FAILOVER_TO_SYSTEM_DB=1" process-environment)))
    (should-not (satan-db-test-db-available-p "satan_memory_test"))))

(ert-deftest satan-db/test-db-available-p-probes-test-host ()
  "Predicate probes the test host and returns t when reachable."
  (let ((satan-db-host-override "127.0.0.1"))
    (should (satan-db-test-db-available-p "satan_memory_test"))))

(ert-deftest satan-db/test-db-available-p-returns-nil-for-bad-host ()
  "Predicate returns nil for an unreachable host."
  (let ((satan-db-host-override "255.255.255.255"))
    (should-not (satan-db-test-db-available-p "satan_memory_test"))))

;; --- satan-db-database-url ---

(ert-deftest satan-db/database-url-format ()
  (skip-unless noninteractive)
  (let ((satan-db-host-override nil)
        (process-environment
         (cons "SATAN_FAILOVER_TO_SYSTEM_DB=1" process-environment)))
    (should (equal (satan-db-database-url "mydb" "/run/postgresql")
                   "postgres:///mydb?host=/run/postgresql"))))

(ert-deftest satan-db/database-url-uses-resolver ()
  "database-url routes its host through the resolver (override wins)."
  (let ((satan-db-host-override "10.0.0.1"))
    (should (equal (satan-db-database-url "mydb" "/run/postgresql")
                   "postgres:///mydb?host=10.0.0.1"))))

;; ---------------------------------------------------------------------
;; VT-1 — routing through `satan-trace-call': timeout, unbounded
;; opt-out, and per-caller ledger labelling.  These stub
;; `satan-trace-call' so no real DB (and no real `timeout') is
;; needed to force the timed-out branch deterministically.
;; ---------------------------------------------------------------------

(ert-deftest satan-db/query-timeout-maps-to-error ()
  "A timed-out psql (`satan-trace-call' :timed-out t) → (error . …)."
  (let ((satan-db-host-override "127.0.0.1"))
    (cl-letf (((symbol-function 'satan-trace-call)
               (lambda (&rest _)
                 (list :exit 124 :stdout "" :timed-out t))))
      (pcase (satan-db-query "d" "h" "psql" "SELECT 1" nil)
        (`(error . ,msg) (should (string-match-p "timed out" msg)))
        (other (ert-fail (format "expected timeout error, got %S" other)))))))

(ert-deftest satan-db/psql-timeout-maps-to-error ()
  "A timed-out psql via `satan-db-psql' → (error . …)."
  (let ((satan-db-host-override "127.0.0.1"))
    (cl-letf (((symbol-function 'satan-trace-call)
               (lambda (&rest _)
                 (list :exit 124 :stdout "" :timed-out t))))
      (pcase (satan-db-psql "d" "h" "psql" (list "-c" "SELECT 1"))
        (`(error . ,msg) (should (string-match-p "timed out" msg)))
        (other (ert-fail (format "expected timeout error, got %S" other)))))))

(ert-deftest satan-db/psql-timeout-secs-nil-runs-unbounded ()
  "Migrate-style `:timeout-secs nil' forwards nil to `satan-trace-call'
so the call runs UNBOUNDED (no `timeout' wrapper)."
  (let ((satan-db-host-override "127.0.0.1")
        captured)
    (cl-letf (((symbol-function 'satan-trace-call)
               (lambda (_program _args &rest kw)
                 (setq captured (plist-member kw :timeout-secs))
                 (list :exit 0 :stdout "ok" :timed-out nil))))
      (satan-db-psql "d" "h" "psql" (list "-f" "-") "SELECT 1"
                        :timeout-secs nil)
      ;; Forwarded, and forwarded as nil (unbounded).
      (should captured)
      (should (eq (cadr captured) nil)))))

(ert-deftest satan-db/psql-default-timeout-is-bounded ()
  "Omitting `:timeout-secs' forwards the defcustom default (bounded)."
  (let ((satan-db-host-override "127.0.0.1")
        captured)
    (cl-letf (((symbol-function 'satan-trace-call)
               (lambda (_program _args &rest kw)
                 (setq captured (plist-get kw :timeout-secs))
                 (list :exit 0 :stdout "ok" :timed-out nil))))
      (satan-db-psql "d" "h" "psql" (list "-c" "SELECT 1"))
      (should (equal captured satan-db-timeout-seconds)))))

(ert-deftest satan-db/query-forwards-label-for-ledger-attribution ()
  "Per-caller `:label' reaches `satan-trace-call' so ledger rows carry
per-caller attribution."
  (let ((satan-db-host-override "127.0.0.1")
        captured)
    (cl-letf (((symbol-function 'satan-trace-call)
               (lambda (_program _args &rest kw)
                 (setq captured (plist-get kw :label))
                 (list :exit 0 :stdout "42" :timed-out nil))))
      (satan-db-query "d" "h" "psql" "SELECT 42" nil
                         :label "memory.fetch")
      (should (equal captured "memory.fetch")))))

(provide 'satan-db-test)
;;; satan-db-test.el ends here
