;;; satan-tools-test.el --- ert tests for satan-tools registry/validator/dispatcher -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-notify)

(ert-deftest satan-tools/schema-required-missing ()
  (let ((spec (list :args-schema '(scope (:type string :required t
                                          :enum ("today" "week"))))))
    (should (stringp (satan-tool-validate-args spec '())))))

(ert-deftest satan-tools/schema-enum-violation ()
  (let ((spec (list :args-schema '(scope (:type string :required t
                                          :enum ("today" "week"))))))
    (should (stringp (satan-tool-validate-args spec '(:scope "year"))))))

(ert-deftest satan-tools/schema-ok ()
  (let ((spec (list :args-schema '(scope (:type string :required t
                                          :enum ("today" "week"))))))
    (should (null (satan-tool-validate-args spec '(:scope "today"))))))

(ert-deftest satan-tools/schema-array-non-array-rejected ()
  (let ((spec (list :args-schema '(tags (:type array :items string)))))
    (should (string-match-p
             "tags must be array"
             (satan-tool-validate-args spec '(:tags "foo"))))))

(ert-deftest satan-tools/schema-array-of-scalars-ok ()
  (let ((spec (list :args-schema '(tags (:type array :items string)))))
    (should (null (satan-tool-validate-args spec '(:tags ("a" "b")))))))

(ert-deftest satan-tools/schema-array-element-type-mismatch ()
  (let ((spec (list :args-schema '(tags (:type array :items string)))))
    (should (string-match-p
             "tags\\[1\\]"
             (satan-tool-validate-args spec '(:tags ("a" 2)))))))

(ert-deftest satan-tools/schema-array-of-objects-shape-ok ()
  (let ((spec (list :args-schema
                    '(rows (:type array
                            :items (:type object
                                    :shape (id (:type string :required t))))))))
    (should (null (satan-tool-validate-args
                   spec '(:rows ((:id "x") (:id "y"))))))))

(ert-deftest satan-tools/schema-array-of-objects-shape-missing-required ()
  (let ((spec (list :args-schema
                    '(rows (:type array
                            :items (:type object
                                    :shape (id (:type string :required t))))))))
    (should (string-match-p
             "id"
             (satan-tool-validate-args spec '(:rows ((:other "x"))))))))

(ert-deftest satan-tools/jsonschema-items-scalar ()
  (let* ((params (satan-tool--args-schema-to-jsonschema
                  '(tags (:type array :items string))))
         (tags (plist-get (plist-get params :properties) :tags)))
    (should (equal (plist-get tags :type) "array"))
    (should (equal (plist-get tags :items) (list :type "string")))))

(ert-deftest satan-tools/jsonschema-items-object-shape ()
  (let* ((params (satan-tool--args-schema-to-jsonschema
                  '(rows (:type array
                          :items (:type object
                                  :shape (id (:type string :required t)))))))
         (rows (plist-get (plist-get params :properties) :rows))
         (items (plist-get rows :items)))
    (should (equal (plist-get items :type) "object"))
    (should (equal (plist-get (plist-get items :properties) :id)
                   (list :type "string")))
    (should (equal (plist-get items :required) ["id"]))))

(ert-deftest satan-tools/dispatch-unknown ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "x" :name "no.such" :args nil)
              '("no.such")
              nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "unknown tool" (plist-get res :error)))))

(ert-deftest satan-tools/dispatch-not-allowed ()
  (satan-tool-register
   (list :name "test.allowed-check"
         :args-schema nil
         :handler (lambda (_a _c) (cons 'ok '(:done t)))))
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "x" :name "test.allowed-check" :args nil)
              '()
              nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "not allowed" (plist-get res :error)))))

;; ---------- dispatch capability guard (Phase 0.2) ----------

(ert-deftest satan-tools/dispatch-capability-denied-by-dispatcher ()
  "When a tool declares `:capability' and the mode's tool-ctx lacks it,
the dispatcher denies the call *before* invoking the handler.  The
handler stub must observe zero calls; the result error must name the
capability."
  (let ((called 0))
    (satan-tool-register
     (list :name "test.cap-required"
           :capability 'foo-write
           :args-schema nil
           :handler (lambda (_a _c) (cl-incf called) (cons 'ok '(:done t)))))
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "c1" :name "test.cap-required" :args nil)
                '("test.cap-required")
                '(:capabilities (other-write)))))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "capability" (plist-get res :error)))
      (should (string-match-p "foo-write" (plist-get res :error)))
      (should (= 0 called)))))

(ert-deftest satan-tools/dispatch-capability-allowed ()
  "When the mode carries the required capability the handler runs."
  (let ((called 0))
    (satan-tool-register
     (list :name "test.cap-ok"
           :capability 'foo-write
           :args-schema nil
           :handler (lambda (_a _c) (cl-incf called) (cons 'ok '(:done t)))))
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "c2" :name "test.cap-ok" :args nil)
                '("test.cap-ok")
                '(:capabilities (foo-write)))))
      (should (eq (plist-get res :ok) t))
      (should (= 1 called)))))

(ert-deftest satan-tools/dispatch-no-capability-required ()
  "Tools without `:capability' dispatch unchanged regardless of ctx caps."
  (let ((called 0))
    (satan-tool-register
     (list :name "test.no-cap"
           :args-schema nil
           :handler (lambda (_a _c) (cl-incf called) (cons 'ok '()))))
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "c3" :name "test.no-cap" :args nil)
                '("test.no-cap")
                '(:capabilities ()))))
      (should (eq (plist-get res :ok) t))
      (should (= 1 called)))))

(ert-deftest satan-tools/notify-send-carries-notify-capability ()
  "`notify_send' tool-spec declares the `notify' capability so the
dispatcher can enforce it without each mode having to opt in."
  (should (eq (plist-get (satan-tool-lookup "notify_send") :capability)
              'notify)))

(ert-deftest satan-tools/dispatch-rejects-notify-without-capability ()
  "Remove `notify' from a mode's tool-ctx; `notify_send' is rejected by
the dispatcher, the handler stub records zero calls."
  (let ((handler-called 0))
    (cl-letf (((symbol-function 'notifications-notify)
               (lambda (&rest _args) (cl-incf handler-called) 42)))
      (let ((res (satan-tool-dispatch
                  '(:type "tool_call" :id "n0" :name "notify_send"
                    :args (:title "t" :body "b"))
                  '("notify_send")
                  '(:capabilities (inbox-write memory-write)))))
        (should (equal (plist-get res :ok) :false))
        (should (string-match-p "capability" (plist-get res :error)))
        (should (string-match-p "notify" (plist-get res :error)))
        (should (= 0 handler-called))))))

;; ---------- JSON Schema builder ----------

(defun satan-tools-test--with-tool-descriptions (alist body-fn)
  "Run BODY-FN with `satan-tools-descriptions-dir' bound to a tmp dir
populated from ALIST `((NAME . CONTENT) …)'."
  (let ((tmp (make-temp-file "satan-tools-" t)))
    (unwind-protect
        (let ((satan-tools-descriptions-dir tmp))
          (dolist (pair alist)
            (with-temp-file (expand-file-name (concat (car pair) ".md") tmp)
              (insert (cdr pair))))
          (funcall body-fn))
      (delete-directory tmp t))))

(ert-deftest satan-tools/json-schema-from-notes ()
  "json-schema dict pulls description from notes and shape from elisp."
  (satan-tools-test--with-tool-descriptions
   '(("fake.tool" . "Stage a fake test thing.\n\nParams:\n- title: a string."))
   (lambda ()
     (let* ((spec (list :name "fake.tool"
                        :risk 'low
                        :args-schema '(title (:type string :required t)
                                       count (:type integer :required nil))
                        :modes '("morning")
                        :handler (lambda (_a _c) (cons 'ok '()))))
            (js (satan-tool-json-schema spec))
            (fn (plist-get js :function))
            (params (plist-get fn :parameters))
            (props (plist-get params :properties)))
       (should (equal (plist-get js :type) "function"))
       (should (equal (plist-get fn :name) "fake.tool"))
       (should (string-match-p "Stage a fake" (plist-get fn :description)))
       (should (equal (plist-get params :type) "object"))
       (should (equal (plist-get (plist-get props :title) :type) "string"))
       (should (equal (plist-get (plist-get props :count) :type) "integer"))
       (should (equal (append (plist-get params :required) nil) '("title")))))))

(ert-deftest satan-tools/json-schema-includes-enum ()
  (satan-tools-test--with-tool-descriptions
   '(("fake.enum" . "desc"))
   (lambda ()
     (let* ((spec (list :name "fake.enum"
                        :args-schema '(scope (:type string :required t
                                              :enum ("a" "b")))
                        :handler #'ignore))
            (js (satan-tool-json-schema spec))
            (scope (plist-get (plist-get
                               (plist-get (plist-get js :function) :parameters)
                               :properties)
                              :scope)))
       (should (equal (append (plist-get scope :enum) nil) '("a" "b")))))))

(ert-deftest satan-tools/missing-description-errors ()
  "Missing tool description file signals; manifest build cannot proceed."
  (let ((satan-tools-descriptions-dir
         (make-temp-file "satan-tools-empty-" t)))
    (unwind-protect
        (let ((spec (list :name "fake.absent"
                          :args-schema nil
                          :handler #'ignore)))
          (should-error (satan-tool-json-schema spec) :type 'error))
      (delete-directory satan-tools-descriptions-dir t))))

(ert-deftest satan-tools/final-schema-uses-notes-description ()
  (satan-tools-test--with-tool-descriptions
   '(("satan_final" . "Terminate the run; describe what you did."))
   (lambda ()
     (let* ((js (satan-tool-final-schema))
            (fn (plist-get js :function))
            (params (plist-get fn :parameters)))
       (should (equal (plist-get fn :name) "satan_final"))
       (should (string-match-p "Terminate" (plist-get fn :description)))
       (should (equal (append (plist-get params :required) nil) '("summary")))))))

(provide 'satan-tools-test)
;;; satan-tools-test.el ends here
