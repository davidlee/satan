;;; satan-jsonl-test.el --- ert tests for satan-jsonl -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-jsonl-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'satan-jsonl)

(ert-deftest satan-jsonl/parses-complete-line ()
  (let* ((seen nil)
         (filter (satan-jsonl-make-filter
                  (lambda (obj) (push obj seen))
                  (lambda (_err) (error "should not error")))))
    (funcall filter nil "{\"type\":\"ready\",\"run_id\":\"r1\"}\n")
    (should (equal (length seen) 1))
    (should (equal (plist-get (car seen) :type) "ready"))
    (should (equal (plist-get (car seen) :run_id) "r1"))))

(ert-deftest satan-jsonl/joins-chunked-line ()
  (let* ((seen nil)
         (filter (satan-jsonl-make-filter
                  (lambda (obj) (push obj seen))
                  (lambda (_err) (error "should not error")))))
    (funcall filter nil "{\"type\":\"log\",")
    (funcall filter nil "\"message\":\"x\"}\n")
    (should (equal (length seen) 1))
    (should (equal (plist-get (car seen) :type) "log"))))

(ert-deftest satan-jsonl/holds-partial-trailing-line ()
  (let* ((seen nil)
         (filter (satan-jsonl-make-filter
                  (lambda (obj) (push obj seen))
                  (lambda (_err) (error "should not error")))))
    (funcall filter nil "{\"type\":\"log\",\"message\":\"a\"}\n{\"type\":")
    (should (equal (length seen) 1))
    (funcall filter nil "\"log\",\"message\":\"b\"}\n")
    (should (equal (length seen) 2))))

(ert-deftest satan-jsonl/reports-parse-error ()
  (let* ((errs nil)
         (filter (satan-jsonl-make-filter
                  (lambda (_obj) (error "should not call on-object"))
                  (lambda (e) (push e errs)))))
    (funcall filter nil "not-json\n")
    (should (equal (length errs) 1))
    (should (equal (car (car errs)) "not-json"))))

(ert-deftest satan-jsonl/prepare-stringifies-symbols ()
  "`json-serialize' rejects elisp symbols other than t / nil / :null
/ :false.  `satan-jsonl-prepare' is the single wire-encoding
chokepoint and must coerce them so `bundle.json' / tool results /
transcript records survive any in-memory symbol leak (resonance
:status, motive :dormant_reason, etc.)."
  ;; Regular symbol → bare name.
  (should (equal "ok" (satan-jsonl-prepare 'ok)))
  ;; Keyword → bare name, colon dropped.
  (should (equal "missing-cue" (satan-jsonl-prepare :missing-cue)))
  ;; JSON special sentinels preserved.
  (should (eq t (satan-jsonl-prepare t)))
  (should (null  (satan-jsonl-prepare nil)))
  (should (eq :null  (satan-jsonl-prepare :null)))
  (should (eq :false (satan-jsonl-prepare :false)))
  ;; Nested: plist values get coerced; keyword keys stay keywords for
  ;; downstream `json-serialize' which handles those itself.
  (let* ((v (satan-jsonl-prepare
             (list :status 'ok :reason :no-match))))
    (should (equal "ok" (plist-get v :status)))
    (should (equal "no-match" (plist-get v :reason))))
  ;; Round-trips through `json-serialize' without error.
  (should (stringp (json-serialize
                    (satan-jsonl-prepare
                     (list :status 'ok
                           :motives (list (list :id "m1"
                                                :dormant_reason :missing-cue))))
                    :null-object :null :false-object :false))))

(ert-deftest satan-jsonl/prepare-flattens-alists-to-plists ()
  "Alists of `(KEY . VAL)' dotted pairs must encode as JSON objects.
A live tick crashed `json-serialize' with `wrong-type-argument consp 1'
because `satan-context--tally-tool-calls' embeds an alist
`((\"activity_read\" . 1) (\"notes_recent\" . 2))' under `:tools' inside
each `:recent_runs' entry and `satan-jsonl-prepare' used to coerce
it to a vector of dotted-pair conses — a JSON-illegal shape."
  ;; Direct alist coercion: keys become keywords, values are walked.
  (let ((v (satan-jsonl-prepare
            '(("activity_read" . 1) ("notes_recent" . 2)))))
    (should (equal 1 (plist-get v :activity_read)))
    (should (equal 2 (plist-get v :notes_recent))))
  ;; Nested under a plist: `:tools' is the production carrier.
  (let* ((entry (list :when "2026-05-23 10:33"
                      :tools '(("activity_read" . 3))))
         (out (satan-jsonl-prepare entry)))
    (should (equal 3 (plist-get (plist-get out :tools) :activity_read))))
  ;; Regression: the exact production failure round-trips through
  ;; `json-serialize' without signalling.
  (let* ((bundle (list :recent_runs
                       (list (list :when "2026-05-23 10:33"
                                   :mode "tick-pulse"
                                   :status "ok"
                                   :summary "x"
                                   :tools '(("activity_read" . 1)
                                            ("notes_recent" . 2))))))
         (encoded (json-serialize (satan-jsonl-prepare bundle)
                                  :null-object :null :false-object :false)))
    (should (stringp encoded))
    (should (string-match-p "\"activity_read\":1" encoded))
    (should (string-match-p "\"notes_recent\":2" encoded)))
  ;; Lists of plists must still encode as JSON arrays, not get folded
  ;; into a plist by the alist branch.
  (let ((v (satan-jsonl-prepare
            (list (list :name "a") (list :name "b")))))
    (should (vectorp v))
    (should (equal "a" (plist-get (aref v 0) :name))))
  ;; Lists of proper 2-lists must still encode as JSON arrays of arrays.
  (let ((v (satan-jsonl-prepare '(("a" 1) ("b" 2)))))
    (should (vectorp v))
    (should (vectorp (aref v 0)))))

(ert-deftest satan-jsonl/prepare-decodes-unibyte-strings ()
  "`json-serialize' rejects unibyte strings with `wrong-type-argument
json-value-p'.  Raw UTF-8 bytes leak into the subprocess ledger via
psql argv / child output (e.g. a `payload=…—…' element carrying an
em-dash).  `satan-jsonl-prepare' must decode unibyte strings to
multibyte so the row survives the wire layer instead of being silently
dropped."
  ;; A bare unibyte UTF-8 string decodes to a multibyte string that
  ;; `json-serialize' accepts and round-trips to the original text.
  (let* ((raw (encode-coding-string "payload=x—y" 'utf-8))
         (out (satan-jsonl-prepare raw)))
    (should (not (multibyte-string-p raw)))
    (should (multibyte-string-p out))
    (should (equal "[\"payload=x—y\"]"
                   (decode-coding-string (json-serialize (vector out))
                                         'utf-8)))))

(ert-deftest satan-jsonl/prepare-unibyte-in-ledger-row ()
  "The realistic subprocess ledger row: a plist whose `:argv' vector
holds a unibyte argv element serialises without error after prepare."
  (let* ((raw (encode-coding-string "payload=x—y" 'utf-8))
         (row (list :kind "subprocess"
                    :argv (vector "psql" "-c" raw)))
         (encoded (json-serialize (satan-jsonl-prepare row)
                                  :null-object :null :false-object :false)))
    (should (stringp encoded))
    (should (string-match-p "payload=x—y"
                            (decode-coding-string encoded 'utf-8)))))

(ert-deftest satan-jsonl/prepare-leaves-multibyte-strings-unchanged ()
  "Ordinary multibyte strings pass through untouched — not re-decoded."
  (let ((s "payload=x—y"))
    (should (multibyte-string-p s))
    (should (equal s (satan-jsonl-prepare s)))))

(provide 'satan-jsonl-test)
;;; satan-jsonl-test.el ends here
