;;; satan-credential-test.el --- ert tests for satan-credential -*- lexical-binding: t; -*-

;; The credential seam (design.md sec-2, DEC-021) against the fake backend in
;; `satan-credential-fixture'.  ENV is always a literal list: the module never
;; reads `process-environment' itself.

(require 'ert)
(require 'cl-lib)
(require 'satan-credential)
(require 'satan-credential-fixture)

(defconst satan-credential-test--env
  '("PATH=/bin"
    "LIT_KEY=sk-literal"
    "HOT_KEY=op://v/hot/credential"
    "COLD_KEY=op://v/cold/credential")
  "LIT_KEY is a literal, HOT_KEY a cached ref, COLD_KEY an uncached ref.")

(defconst satan-credential-test--cache
  '(("op://v/hot/credential" . "hot-secret")))

(defconst satan-credential-test--read
  '(("op://v/hot/credential" . "hot-secret")
    ("op://v/cold/credential" . "cold-secret")))

;;; VT-1 — acquire: the strict path.

(ert-deftest satan-credential/acquire-literal-and-unset-need-no-backend ()
  (satan-credential-fixture-with (calls)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("LIT_KEY" "UNSET_KEY")
                    'defer "ctx")
                   '(:env nil :refs nil)))
    (should-not (funcall calls))))

(ert-deftest satan-credential/acquire-cached-ref-skips-session-probe ()
  (satan-credential-fixture-with (calls :cache satan-credential-test--cache)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("HOT_KEY") 'defer "ctx")
                   '(:env ("HOT_KEY=hot-secret")
                     :refs (("HOT_KEY" . "op://v/hot/credential")))))
    (should (equal (satan-credential-fixture-ops (funcall calls)) '(lookup)))))

(ert-deftest satan-credential/acquire-live-session-reads-silently ()
  (satan-credential-fixture-with (calls :session t
                                        :read satan-credential-test--read)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("COLD_KEY") 'defer "ctx")
                   '(:env ("COLD_KEY=cold-secret")
                     :refs (("COLD_KEY" . "op://v/cold/credential")))))
    (should (equal (funcall calls)
                   '((lookup "op://v/cold/credential")
                     (session-p)
                     (read "op://v/cold/credential" "ctx"))))))

(ert-deftest satan-credential/acquire-no-session-defer-never-reads ()
  (satan-credential-fixture-with (calls :read satan-credential-test--read)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("COLD_KEY") 'defer "ctx")
                   '(:deferred)))
    (should (equal (satan-credential-fixture-ops (funcall calls))
                   '(lookup session-p)))))

(ert-deftest satan-credential/acquire-no-session-prompt-reads-with-context ()
  (satan-credential-fixture-with (calls :read satan-credential-test--read)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("COLD_KEY") 'prompt
                    "satan broker/motd")
                   '(:env ("COLD_KEY=cold-secret")
                     :refs (("COLD_KEY" . "op://v/cold/credential")))))
    (should (member '(read "op://v/cold/credential" "satan broker/motd")
                    (funcall calls)))))

(ert-deftest satan-credential/acquire-mixed-keeps-every-ref ()
  (satan-credential-fixture-with (_calls :cache satan-credential-test--cache
                                         :session t
                                         :read satan-credential-test--read)
    (should (equal (satan-credential-acquire
                    satan-credential-test--env
                    '("LIT_KEY" "HOT_KEY" "COLD_KEY") 'defer "ctx")
                   '(:env ("HOT_KEY=hot-secret" "COLD_KEY=cold-secret")
                     :refs (("HOT_KEY" . "op://v/hot/credential")
                            ("COLD_KEY" . "op://v/cold/credential")))))))

(ert-deftest satan-credential/acquire-failed-prompt-read-is-unavailable ()
  "Strict: a read that signals (e.g. a dismissed dialog) → :unavailable ERR."
  (satan-credential-fixture-with (_calls)
    (let ((verdict (satan-credential-acquire
                    satan-credential-test--env '("COLD_KEY") 'prompt "ctx")))
      (should (eq (car verdict) :unavailable))
      (should (string-match-p "cannot read"
                              (error-message-string (cadr verdict)))))))

;;; VT-11 — no backend: fail closed.

(ert-deftest satan-credential/no-backend-defer-defers ()
  (let ((satan-credential-function nil))
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("COLD_KEY") 'defer "ctx")
                   '(:deferred)))))

(ert-deftest satan-credential/no-backend-prompt-is-unavailable ()
  (let* ((satan-credential-function nil)
         (verdict (satan-credential-acquire
                   satan-credential-test--env '("COLD_KEY") 'prompt "ctx")))
    (should (eq (car verdict) :unavailable))
    (should (eq (car (cadr verdict)) 'satan-credential-no-backend))))

(ert-deftest satan-credential/no-backend-literal-passes ()
  (let ((satan-credential-function nil))
    (should (equal (satan-credential-acquire
                    satan-credential-test--env '("LIT_KEY") 'defer "ctx")
                   '(:env nil :refs nil)))
    (should (satan-credential-ready-p satan-credential-test--env '("LIT_KEY")))
    (should-not (satan-credential-ready-p satan-credential-test--env
                                          '("COLD_KEY")))))

(ert-deftest satan-credential/scrub-drops-refs-only ()
  (should (equal (satan-credential-scrub
                  (append satan-credential-test--env '(bogus "NOEQUALS")))
                 '("PATH=/bin" "LIT_KEY=sk-literal" bogus "NOEQUALS"))))

(ert-deftest satan-credential/scrub-follows-the-ref-regexp ()
  (let ((satan-credential-ref-regexp "\\`vault:"))
    (should (equal (satan-credential-scrub '("A=vault:x" "B=op://v/i/f"))
                   '("B=op://v/i/f")))))

;;; ready-p and resolve.

(ert-deftest satan-credential/ready-p-probes-only-when-pending ()
  (satan-credential-fixture-with (calls :cache satan-credential-test--cache)
    (should (satan-credential-ready-p satan-credential-test--env '("HOT_KEY")))
    (should (equal (satan-credential-fixture-ops (funcall calls)) '(lookup))))
  (satan-credential-fixture-with (calls :session t)
    (should (satan-credential-ready-p satan-credential-test--env '("COLD_KEY")))
    (should-not (memq 'read (satan-credential-fixture-ops (funcall calls))))))

(ert-deftest satan-credential/resolve-collects-per-var-failures ()
  "Lenient: one failing var does not stop the others."
  (satan-credential-fixture-with (_calls
                                  :read '(("op://v/cold/credential" . "cold")))
    (let ((out (satan-credential-resolve
                '("A_KEY=op://v/missing/credential"
                  "COLD_KEY=op://v/cold/credential")
                '("A_KEY" "COLD_KEY") "satan patch-adapter/pi")))
      (should (equal (plist-get out :env) '("COLD_KEY=cold")))
      (should (equal (mapcar #'car (plist-get out :failed)) '("A_KEY"))))))

;;; VT-12 — no backend signal escapes.

(ert-deftest satan-credential/backend-signals-never-escape ()
  (dolist (op '(lookup session-p read))
    (satan-credential-fixture-with (_calls :signal (list op)
                                           :read satan-credential-test--read)
      (let ((verdict (satan-credential-acquire
                      satan-credential-test--env '("COLD_KEY") 'prompt "ctx")))
        (should (eq (car verdict) :unavailable)))
      (unless (eq op 'read)
        (should-not (satan-credential-ready-p satan-credential-test--env
                                              '("COLD_KEY"))))
      (let ((out (satan-credential-resolve satan-credential-test--env
                                           '("COLD_KEY") "ctx")))
        (unless (eq op 'session-p)      ; resolve never probes the session
          (should (equal (mapcar #'car (plist-get out :failed))
                         '("COLD_KEY"))))))))

(ert-deftest satan-credential/forget-returns-err-never-signals ()
  (satan-credential-fixture-with (calls)
    (should-not (satan-credential-forget "op://v/hot/credential"))
    (should (equal (funcall calls) '((forget "op://v/hot/credential")))))
  (satan-credential-fixture-with (_calls :signal '(forget))
    (should (consp (satan-credential-forget "op://v/hot/credential"))))
  (let ((satan-credential-function nil))
    (should-not (satan-credential-forget "op://v/hot/credential"))))

(provide 'satan-credential-test)
;;; satan-credential-test.el ends here
