;;; satan-goad-integration-test.el --- the goad loop end to end -*- lexical-binding: t; -*-

;; SL-016 PHASE-08 (A) — one integration test drives the whole loop with
;; no goad host: `goad_ask' writes the queue, the *real* corpus
;; `backend.py' (a subprocess over a temp copy of itself, D1) evaluates
;; and renders the ask first, a scripted `respond' answers it, and the
;; observer classifies the record `backend.py' wrote.  A form ask is
;; answered with field values, which reach the observation trace intact.
;; The committed goldens are re-derived from the same `backend.py' so
;; they cannot drift (VT-43).
;;
;; Isolation (SL-016 PHASE-08 A1/D1): `backend.py''s `DATA' is anchored to
;; its own directory and `main()' offers no override, so the test copies
;; the corpus backend into a temp goad dir beside its data.  The copy's
;; records land under `satan-goad-data-dir' and never in the keeper's live
;; record; each test asserts the corpus `goad/data/' is unchanged (R1).
;; The backend reads the real clock, so an ask's `:time-now' is the real
;; now and the observer runs at emit + 61 minutes (A2).
;;
;; The goad/session fixtures are the tool and observer suites' own
;; (`satan-tools-goad-test--with-goad', `satan-intervention-test--with-db'
;; / `--with-ctx', `satan-observer-test--*'), required here with the
;; suite's usual guard: no fixture is cloned (R3).

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'json)
(require 'subr-x)
(require 'satan-custom)
(require 'satan-jsonl)
(require 'satan-goad)
(require 'satan-goad-fixture)
(require 'satan-intervention-test)
(require 'satan-observer-test)
(require 'satan-tools-goad-test)

;; ── the corpus, and the temp copy of backend.py (A1, D1) ────────────────────

(defconst satan-goad-integration-test--corpus-goad-dir
  (satan-corpus-path "goad")
  "The corpus `goad/' directory: `backend.py', `goldens.py' and the goldens'
source.  Bound through `satan-corpus-root', so a missing corpus skips (A3).")

(defconst satan-goad-integration-test--backend "backend.py")

(defconst satan-goad-integration-test--goldens "goldens.py")

(defconst satan-goad-integration-test--golden-day "2026-09-23"
  "The only day file `goldens.py' writes (fixtures README's scenario).")

(defun satan-goad-integration-test--corpus-p ()
  "Non-nil when the corpus `goad/backend.py' is readable: the skip gate (A3)."
  (file-readable-p (expand-file-name satan-goad-integration-test--backend
                                     satan-goad-integration-test--corpus-goad-dir)))

(defun satan-goad-integration-test--now ()
  "The current instant, ISO 8601 with the local offset.
`backend.py' uses the real clock, so the ask's `:time-now' must be near
it for the ask to render (A2)."
  (format-time-string "%FT%T%:z" (current-time)))

(defun satan-goad-integration-test--plus-minutes (ts minutes)
  "TS plus MINUTES, ISO 8601 with the offset TS carried."
  (format-time-string "%FT%T%:z"
                      (time-add (date-to-time ts)
                                (seconds-to-time (* 60 minutes)))))

;; ── T2: the harness ─────────────────────────────────────────────────────────

(defun satan-goad-integration-test--install-backend ()
  "Copy the corpus backend into the suite's temp goad dir, beside its data.
`backend.py''s `DATA' resolves to `Path(__file__).parent / \"data\"' and
`main()' offers no override (A1), so this copy records under
`satan-goad-data-dir', never in the keeper's live record (D1)."
  (let ((goad-dir (file-name-directory satan-goad-queue-file)))
    (make-directory satan-goad-data-dir t)
    (copy-file (expand-file-name satan-goad-integration-test--backend
                                 satan-goad-integration-test--corpus-goad-dir)
               (expand-file-name satan-goad-integration-test--backend goad-dir)
               t)))

(defun satan-goad-integration-test--exchange (request)
  "Run one goad exchange through the temp copy of `backend.py'.
REQUEST is a plist: `(:type \"evaluate\")' or a `respond'.  The queue is
the suite's `satan-goad-queue-file', handed to the process as
`GOAD_SATAN_QUEUE' (`backend.py''s `queue_path').  One process per
exchange, read to completion — no sleeps, no polling (R4).  Returns the
parsed reply."
  (let* ((goad-dir (file-name-directory satan-goad-queue-file))
         (request-file (expand-file-name "integration-request.json" goad-dir))
         (process-environment
          (cons (concat "GOAD_SATAN_QUEUE=" satan-goad-queue-file)
                process-environment))
         (program (expand-file-name satan-goad-integration-test--backend
                                    goad-dir)))
    (satan-goad-fixture-write
     request-file
     (json-serialize (satan-jsonl-prepare request)
                     :null-object :null :false-object :false))
    (with-temp-buffer
      (let ((status (call-process "python3" request-file t nil program)))
        (unless (and (integerp status) (zerop status))
          (error "satan-goad-integration: %s exited %s: %s"
                 program status (buffer-string)))
        (goto-char (point-min))
        (json-parse-buffer :object-type 'plist :array-type 'list
                           :null-object nil :false-object :false)))))

(defun satan-goad-integration-test--present ()
  "Evaluate once through the backend and return the rendered view.
Asserts the ask is the view's title and its section header the body's
(VT-1: the ask is pending ahead of every checklist item)."
  (let* ((reply (satan-goad-integration-test--exchange (list :type "evaluate")))
         (view (plist-get reply :view)))
    (should view)
    (should (equal satan-tools-goad-test--question (plist-get view :title)))
    (should (string-prefix-p "SATAN asks ·" (plist-get view :body)))
    view))

(defun satan-goad-integration-test--answer (option &optional values)
  "Respond with OPTION (`opt:<choice>:ask:<iid>') and VALUES.
VALUES is the host's field-value object; omitted (or nil) means the
untouched default form, whose `values' are `{}' (R-8)."
  (satan-goad-integration-test--exchange
   (list :type "respond"
         :response (append (list :option option)
                           (and values (list :values values))))))

(defun satan-goad-integration-test--emit (ctx now &rest args)
  "Emit an ask through `goad_ask' in CTX at NOW; the tool result.
ARGS (a plist) forwards to the handler, e.g. `:form'.  The quiet window
is a one-hour band starting after NOW's local hour, so the ask is never
refused for quiet hours whatever hour the suite runs."
  (let ((satan-goad-quiet-hours (satan-tools-goad-test--hour-window now 1)))
    (apply #'satan-tools-goad-test--ask
           (satan-tools-goad-test--ctx ctx :time-now now) args)))

(defun satan-goad-integration-test--emitted-id (ctx now &rest args)
  "Emit an ask in CTX at NOW (ARGS forward to the handler); its id.
Asserts the tool asked: a refused or suppressed ask has no route to
test."
  (let ((result (apply #'satan-goad-integration-test--emit ctx now args)))
    (should (eq 'ok (car result)))
    (should (eq t (plist-get (cdr result) :asked)))
    (plist-get (cdr result) :intervention_id)))

(defun satan-goad-integration-test--classify (root run-id now minutes
                                                   &optional mark-fn)
  "Run the observer MINUTES past NOW over RUN-ID's run; its summary.
ROOT is the runs root; RUN-ID the run the ask was recorded in.  Writes
the run's `bundle.json' first so the classifier has a baseline, and
binds the after-state to the real `:goad' slice — the queue and the
backing day records `backend.py' wrote.  MARK-FN, when given, replaces
`satan-memory-store-mark' (the trace capture VT-61 reads)."
  (satan-observer-test--write-bundle-with-handles
   (satan-observer-test--make-run-dir root run-id)
   (list satan-tools-goad-test--subject "app:goad"))
  (satan-observer-test--with-stubbed-after-state
      (list :goad (satan-goad-slice))
    (satan-observer-process
     (satan-observer-test--process-ctx
      root "20260523T235959-morning-observe"
      (satan-goad-integration-test--plus-minutes now minutes))
     (append (list :runs-dir root
                   :touch-footer-fn (lambda (&rest _) t))
             (and mark-fn (list :memory-mark-fn mark-fn))))))

(defun satan-goad-integration-test--observations (summary iid)
  "SUMMARY's verdict plist for IID, or nil."
  (car (cl-remove-if-not (lambda (v) (equal iid (plist-get v :intervention_id)))
                         (plist-get summary :verdicts))))

(defun satan-goad-integration-test--should-worked (summary iid)
  "Assert SUMMARY classified the ask IID `:worked' by `:goad_answer' alone;
its verdict plist."
  (should (= 1 (plist-get summary :processed)))
  (let ((verdict (satan-goad-integration-test--observations summary iid)))
    (should (eq :worked (plist-get verdict :classification)))
    (should (equal '(:goad_answer) (plist-get verdict :predicates)))
    verdict))

;; ── R1: the keeper's record is never written ────────────────────────────────

(defun satan-goad-integration-test--corpus-data-state ()
  "An alist of (NAME . MTIME) for every file in the corpus goad data dir.
nil when the directory is absent (the corpus is not then installed)."
  (let ((dir (satan-corpus-path "goad/data")))
    (when (file-directory-p dir)
      (sort (cl-loop for f in (directory-files dir nil "\\`[^.]" t)
                     collect (cons (file-name-nondirectory f)
                                   (file-attribute-modification-time
                                    (file-attributes f))))
            (lambda (a b) (string< (car a) (car b)))))))

(defmacro satan-goad-integration-test--with-untouched-record (&rest body)
  "Run BODY, then assert the corpus goad data dir is unchanged (R1).
The exchange tests write only the temp copy's own data dir (D1)."
  (declare (indent 0))
  (let ((before (make-symbol "before")))
    `(let ((,before (satan-goad-integration-test--corpus-data-state)))
       (let ((result (progn ,@body)))
         (should (equal ,before (satan-goad-integration-test--corpus-data-state)))
         result))))

(defmacro satan-goad-integration-test--with-loop (ctx root &rest body)
  "Run BODY with the end-to-end fixtures up (R3: none is cloned).
Binds CTX to a run-bound tool-ctx under runs root ROOT, a freshly
migrated test DB, the tool suite's goad fixtures (goad enabled, doorbell
and attribute enqueue stubbed, a vacated quiet window), and a copy of
the corpus `backend.py' in the temp goad dir; asserts the corpus record
is untouched afterwards (R1).  Callers bind `now' from
`satan-goad-integration-test--now'."
  (declare (indent 2))
  `(satan-goad-integration-test--with-untouched-record
     (satan-intervention-test--with-db
       (satan-intervention-test--with-ctx (,ctx ,root)
         (satan-tools-goad-test--with-goad satan-tools-goad-test--thesis-motive
           (satan-goad-integration-test--install-backend)
           ,@body)))))

;; ── T1: VT-43, the goldens cannot drift ─────────────────────────────────────

(defun satan-goad-integration-test--read-literal (path)
  "The bytes of PATH as a string, no coding conversion."
  (with-temp-buffer
    (insert-file-contents-literally path)
    (buffer-string)))

(defun satan-goad-integration-test--golden-bytes (relative)
  "The committed golden file RELATIVE to `satan-goad-fixture-dir', literally."
  (satan-goad-integration-test--read-literal
   (expand-file-name relative satan-goad-fixture-dir)))

(defun satan-goad-integration-test--run-goldens (dir)
  "Run the corpus `goldens.py' with DIR as its output directory.
It drives `backend.run' with fixed instants (the fixtures README's
scenario), so DIR/queue.json and DIR/data/*.json are the producer's own
bytes for that script.  DIR is never the live record."
  (let ((default-directory satan-goad-integration-test--corpus-goad-dir))
    (with-temp-buffer
      (let ((status (call-process "python3" nil t nil
                                  satan-goad-integration-test--goldens dir)))
        (unless (and (integerp status) (zerop status))
          (error "satan-goad-integration: goldens.py exited %s: %s"
                 status (buffer-string)))))))

(ert-deftest satan-goad-integration/goldens-match-backend ()
  "VT-43 — every committed golden fixture equals what the real
`backend.py' produces for the same script, re-derived here so the
fixtures cannot drift from the producer.  Round-trip through disk: the
bytes `goldens.py' writes are compared literally."
  (skip-unless (satan-goad-integration-test--corpus-p))
  (let ((out (make-temp-file "satan-goad-goldens-" t)))
    (unwind-protect
        (progn
          (satan-goad-integration-test--run-goldens out)
          (should (equal (satan-goad-integration-test--golden-bytes "queue.json")
                         (satan-goad-integration-test--read-literal
                          (expand-file-name "queue.json" out))))
          (let ((day (format "data/%s.json" satan-goad-integration-test--golden-day)))
            (should (equal (satan-goad-integration-test--golden-bytes day)
                           (satan-goad-integration-test--read-literal
                            (expand-file-name day out))))
            (should (equal (list (format "%s.json"
                                         satan-goad-integration-test--golden-day))
                           (sort (mapcar #'file-name-nondirectory
                                         (directory-files
                                          (expand-file-name "data" out)
                                          nil "\\`[^.]" t))
                                 #'string<)))))
      (delete-directory out t))))

;; ── T3: VT-1 and VT-42, the default ask round trip ──────────────────────────

(ert-deftest satan-goad-integration/ask-renders-first ()
  "VT-1 — an ask emitted by `goad_ask' takes priority in the real
`backend.py''s `pending()' and is the rendered view: with all fourteen
checklist items unanswered, the view's title is the ask's question and
its section header is `SATAN asks', not a checklist item."
  (skip-unless (satan-goad-integration-test--corpus-p))
  (satan-goad-integration-test--with-loop ctx root
    (let* ((now (satan-goad-integration-test--now))
           (iid (satan-goad-integration-test--emitted-id ctx now))
           (view (satan-goad-integration-test--present)))
      ;; the queue the backend renders from carries exactly this ask
      (should (equal (list iid)
                     (satan-goad-fixture-iids (satan-goad-read-queue))))
      ;; the ask's own default form is what the backend renders
      (should (equal (format "opt:yes:ask:%s" iid)
                     (plist-get (car (plist-get view :options)) :id))))))

(ert-deftest satan-goad-integration/answer-round-trip ()
  "VT-42 — the answer round trip through the real backend: `goad_ask'
emits, `backend.py' renders and the scripted `respond' writes
`opt:<option>:ask:<iid>' into the ask's own record; the observer at
emit + 61 minutes reads that record and classifies the intervention
`:worked' by `:goad_answer' alone (no ambient predicate applies to an
ask)."
  (skip-unless (satan-goad-integration-test--corpus-p))
  (satan-goad-integration-test--with-loop ctx root
    (let* ((now (satan-goad-integration-test--now))
           (iid (satan-goad-integration-test--emitted-id ctx now)))
      (satan-goad-integration-test--present)
      (satan-goad-integration-test--answer (format "opt:yes:ask:%s" iid))
      ;; the record `backend.py' wrote holds the answer, in window
      (let ((record (satan-goad-read-record iid now)))
        (should (plist-get record :presented_at))
        (should (equal "yes" (plist-get (plist-get record :value) :option))))
      (satan-observer-test--capture-mark captured
        (satan-goad-integration-test--should-worked
         (satan-goad-integration-test--classify
          root (plist-get ctx :id) now 61 mark-fn)
         iid)
        (should captured))
      ;; the verdict reaches the projection row
      (should (equal "worked"
                     (plist-get (plist-get (satan-intervention-lookup iid)
                                           :outcome)
                                :classification))))))

;; ── T4: VT-61, the form round trip ──────────────────────────────────────────

(defconst satan-goad-integration-test--form
  (vector (list :id "rate" :label "Rate it"
                :fields (vector
                         (list :id "energy" :kind "number" :label "Energy"
                               :min 0 :max 10)
                         (list :id "blocker" :kind "choice" :label "Blocker"
                               :options (vector (list :id "none" :label "None")
                                                (list :id "unclear"
                                                      :label "Unclear")))
                         (list :id "note" :kind "text" :label "Note")
                         (list :id "walked" :kind "boolean" :label "Walked")
                         (list :id "back_at" :kind "datetime" :label "Back at")))
          (list :id "skip" :label "Not now"))
  "A valid answer form: one option with one field of every kind, and a
fieldless option.  Mirrors the golden `form' ask's shape.")

(defconst satan-goad-integration-test--form-values
  '(:energy 6 :blocker "unclear" :note "steady after lunch" :walked t
    :back_at "2026-09-23T13:20:00+10:00")
  "One value of every field kind, as the host sends them (DEC-025).")

(ert-deftest satan-goad-integration/form-round-trip ()
  "VT-61 — the form round trip through the real backend: a form ask
renders its options and fields, a scripted `respond' with field values
is stored as `{option, values}' in the day file, and the observation
trace's metadata carries that value intact (the PHASE-09 D3 seam)."
  (skip-unless (satan-goad-integration-test--corpus-p))
  (satan-goad-integration-test--with-loop ctx root
    (let* ((now (satan-goad-integration-test--now))
           (iid (satan-goad-integration-test--emitted-id
                 ctx now :form satan-goad-integration-test--form))
           (option (format "opt:rate:ask:%s" iid)))
      (let ((view (satan-goad-integration-test--present)))
        ;; the form's own options and fields render through the backend
        (should (equal option
                       (plist-get (car (plist-get view :options)) :id)))
        (should (equal 5 (length (plist-get (car (plist-get view :options))
                                            :fields))))
        (should (equal (format "opt:skip:ask:%s" iid)
                       (plist-get (cadr (plist-get view :options)) :id))))
      (satan-goad-integration-test--answer
       option satan-goad-integration-test--form-values)
      ;; the day file stores {option, values} verbatim
      (should (equal (list :option "rate"
                           :values satan-goad-integration-test--form-values)
                     (plist-get (satan-goad-read-record iid now) :value)))
      (satan-observer-test--capture-mark captured
        (satan-goad-integration-test--should-worked
         (satan-goad-integration-test--classify
          root (plist-get ctx :id) now 61 mark-fn)
         iid)
        ;; the trace's metadata carries the question and the value
        (should captured)
        (let ((md (plist-get (car captured) :metadata-json)))
          (should (equal satan-tools-goad-test--question (plist-get md :question)))
          (should (equal (list :option "rate"
                               :values satan-goad-integration-test--form-values)
                         (plist-get md :value))))))))

(provide 'satan-goad-integration-test)
;;; satan-goad-integration-test.el ends here
