;;; dl-satan-db.el --- shared psql subprocess runner -*- lexical-binding: t; -*-

;; Single entry point for psql subprocess calls within the SATAN broker.
;; Two surfaces:
;;
;;   dl-satan-db-query(db host program sql variables) → (ok . stdout) | (error . msg)
;;     For the common pattern: SQL + variable substitution → trimmed result.
;;     Always passes -q (quiet mode) so psql welcome-banner never leaks
;;     into stdout.
;;
;;   dl-satan-db-psql(db host program extra-flags &optional input) → (ok . stdout) | (error . msg)
;;     Thin wrapper for callers that need custom flags (--single-transaction,
;;     -c inline SQL, etc.).  Returns untrimmed stdout to match
;;     dl-satan-memory-migrate--psql semantics.

(require 'cl-lib)
(require 'subr-x)
(require 'dl-satan-trace)

(defgroup dl-satan-db nil
  "Shared psql subprocess runner for the SATAN broker."
  :group 'dl-satan)

(defcustom dl-satan-db-timeout-seconds 5
  "Per-call wall-clock deadline (seconds) for psql subprocesses.
Applied via `dl-satan-trace-call' at both chokepoints.  A breach maps
to the existing (error . MSG) contract.  Callers that must never be
killed (schema migrations, bulk renormalize writes) pass an explicit
`:timeout-secs nil' to run UNBOUNDED."
  :type 'integer :group 'dl-satan-db)

(defcustom dl-satan-db-default-host "/run/postgresql"
  "Default Postgres host or socket directory.
Used as a sentinel fallback in `dl-satan-db-database-url'; overridden
at call time by `dl-satan-db-resolve-host' via the carrier."
  :type 'string :group 'dl-satan-db)

(defcustom dl-satan-db-default-program
  (or (executable-find "psql") "psql")
  "Default path to the `psql' binary."
  :type 'string :group 'dl-satan-db)

(defvar dl-satan-db-host-override (getenv "SATAN_DB_HOST")
  "When non-nil, overrides the HOST arg in every psql call at the chokepoint.
Batch: seeded from SATAN_DB_HOST at process start so `just check' picks it up.
Interactive: `let'-bind this around a test suite to redirect DB tests to a
test DB for that dynamic extent only — the live broker keeps using its
production host outside the binding.  Never `setq' globally — that would
redirect the live broker's production traffic.")

;; ---------------------------------------------------------------------
;; host resolution — the single routing point for every psql/connection spawn
;; ---------------------------------------------------------------------

(defun dl-satan-db-resolve-host (host)
  "Effective psql host: the override carrier wins over HOST.
Refuses the production socket in batch unless SATAN_FAILOVER_TO_SYSTEM_DB
is set.  Every psql/connection spawn — chokepoint or not — routes its
host through this so the test redirect is universal."
  (let ((h (or dl-satan-db-host-override host)))
    (when (and noninteractive
            (equal h "/run/postgresql")
            (not (getenv "SATAN_FAILOVER_TO_SYSTEM_DB")))
      (error "dl-satan-db: refusing production socket \"/run/postgresql\" in batch; set SATAN_DB_HOST or SATAN_FAILOVER_TO_SYSTEM_DB"))
    h))

(defun dl-satan-db-database-url (db &optional host)
  "libpq DATABASE_URL for DB on the resolved host (port via PGPORT env).
For external binaries (bough, satan-patcher, attribute daemon) that
connect via libpq env vars rather than through dl-satan-db-psql."
  (format "postgres:///%s?host=%s"
    db (dl-satan-db-resolve-host (or host dl-satan-db-default-host))))

;; ---------------------------------------------------------------------
;; dl-satan-db-query — the common case (SQL + variables → trimmed result)
;; ---------------------------------------------------------------------

(cl-defun dl-satan-db-query (db host program sql variables
                                &key label
                                (timeout-secs dl-satan-db-timeout-seconds))
  "Run SQL against DB with VARIABLES (alist of NAME . VALUE) bound via -v.
Returns (ok . STDOUT-TRIMMED) or (error . MSG).

HOST and PROGRAM are explicit params so each module passes its own
defcustoms independently.  SQL is fed to psql on stdin via -f -
because -c does not perform variable substitution.  Field separator is
tab so multi-column SELECTs are unambiguous to parse.  Always passes
-q (quiet mode) so psql welcome-banner never leaks into stdout.

The call is routed through `dl-satan-trace-call' so it is ledgered and
bounded.  LABEL is an optional per-caller ledger tag.  TIMEOUT-SECS
defaults to `dl-satan-db-timeout-seconds'; an explicit nil runs the
call UNBOUNDED (no `timeout' wrapper).  A deadline breach maps to
\(error . \"psql timed out …\")."
  (let* ((host (dl-satan-db-resolve-host host))
         (var-args (cl-loop for (k . v) in variables
                            append (list "-v"
                                         (format "%s=%s" k v))))
         (full-args (append (list "-h" host
                                  "-d" db
                                  "--no-psqlrc"
                                  "-X" "-A" "-t" "-q"
                                  "-F" "\t"
                                  "-v" "ON_ERROR_STOP=1")
                            var-args
                            (list "-f" "-")))
         (result (dl-satan-trace-call program full-args
                                      :stdin sql
                                      :timeout-secs timeout-secs
                                      :label label))
         (exit (plist-get result :exit))
         (out (plist-get result :stdout)))
    (cond
     ((plist-get result :timed-out)
      (cons 'error (format "psql timed out after %ss on %s" timeout-secs db)))
     ((and (integerp exit) (zerop exit))
      (cons 'ok (string-trim out)))
     (t
      (cons 'error (format "psql exit %s on %s: %s"
                           exit db (string-trim out)))))))

;; ---------------------------------------------------------------------
;; dl-satan-db-psql — thin wrapper for callers with custom flags
;; ---------------------------------------------------------------------

(cl-defun dl-satan-db-psql (db host program extra-flags &optional input
                               &key label
                               (timeout-secs dl-satan-db-timeout-seconds))
  "Run psql against DB with EXTRA-FLAGS appended after base args.
Optional INPUT string is fed to psql on stdin.  Returns untrimmed
(ok . STDOUT) or (error . MSG).

Base args are -h HOST -d DB --no-psqlrc -v ON_ERROR_STOP=1.
EXTRA-FLAGS is a list of strings (e.g. --single-transaction, -f -,
-c \"SELECT ...\").  When INPUT is non-nil, EXTRA-FLAGS should
include -f - so psql reads from stdin; otherwise include -c SQL.

The call is routed through `dl-satan-trace-call' so it is ledgered and
bounded.  LABEL is an optional per-caller ledger tag.  TIMEOUT-SECS
defaults to `dl-satan-db-timeout-seconds'; an explicit nil runs the
call UNBOUNDED — migrations and bulk renormalize writes pass nil so
they are never killed.  A deadline breach maps to (error . \"psql
timed out …\")."
  (let* ((host (dl-satan-db-resolve-host host))
         (full-args (append (list "-h" host
                                  "-d" db
                                  "--no-psqlrc"
                                  "-v" "ON_ERROR_STOP=1")
                            extra-flags))
         (result (dl-satan-trace-call program full-args
                                      :stdin input
                                      :timeout-secs timeout-secs
                                      :label label))
         (exit (plist-get result :exit))
         (out (plist-get result :stdout)))
    (cond
     ((plist-get result :timed-out)
      (cons 'error (format "psql timed out after %ss on %s" timeout-secs db)))
     ((and (integerp exit) (zerop exit))
      (cons 'ok out))
     (t
      (cons 'error (format "psql exit %s on %s: %s"
                           exit db (string-trim out)))))))

;; ---------------------------------------------------------------------
;; pg-array parser (from dl-satan-intervention, better double-quote handling)
;; ---------------------------------------------------------------------

(defun dl-satan-db-parse-pg-array (text)
  "Parse a PostgreSQL text[] literal like \"{a,b,c}\" into a list of strings.
Handles double-quoted entries.  Returns nil for empty input or \"{}\"."
  (cond
    ((or (null text) (string-empty-p text)) nil)
    ((not (and (string-prefix-p "{" text) (string-suffix-p "}" text))) nil)
    (t (let ((inner (substring text 1 -1)))
         (cond
           ((string-empty-p inner) nil)
           (t (mapcar (lambda (e)
                        (if (and (string-prefix-p "\"" e)
                              (string-suffix-p "\"" e))
                          (substring e 1 -1)
                          e))
                (split-string inner ","))))))))

;; ---------------------------------------------------------------------
;; test-db availability predicate
;; ---------------------------------------------------------------------

(defun dl-satan-db-test-db-available-p (db)
  "Non-nil when DB tests may run against DB.  Never probes the prod socket.
DB is the database name (e.g. \"satan_memory_test\").
In batch without SATAN_DB_HOST, the guard inside dl-satan-db-resolve-host
errors before we ever reach psql."
  (let ((host (dl-satan-db-resolve-host "/run/postgresql")))
    (cond
     ((equal host "/run/postgresql")
      nil)               ; skip — never touch prod (interactive path)
     (t
      (eq 'ok (car (dl-satan-db-psql
                     db host dl-satan-db-default-program
                     (list "-A" "-t" "-c" "SELECT 1"))))))))

(provide 'dl-satan-db)
;;; dl-satan-db.el ends here
