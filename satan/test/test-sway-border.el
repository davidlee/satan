;;; test-sway-border.el --- ert tests for sway-border tools -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l test-sway-border.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-sway)
(require 'satan-intervention)

(defconst satan-sway-test--ctx
  '(:id "20260523T120000-pulse-deadbe"
    :mode-name "pulse"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities ()
    :audit satan-sway-test--stub-audit)
  "Synthetic tool-ctx for sway_border_set dispatch tests.")

(defvar satan-sway-test--captured nil
  "Per-test capture of `satan-intervention-create' kwarg plists.")

;; ---------- nested-object validator extension ----------

(ert-deftest satan-sway/validator-rejects-non-object ()
  (let ((spec (list :args-schema
                    '(classes (:type object :required t
                               :shape (focused (:type object :required nil
                                                :shape (border (:type string :required t)))))))))
    (should (stringp (satan-tool-validate-args spec '(:classes "nope"))))))

(ert-deftest satan-sway/validator-recurses-into-shape ()
  (let ((spec (list :args-schema
                    '(classes (:type object :required t
                               :shape (focused (:type object :required nil
                                                :shape (border (:type string :required t)))))))))
    (should (string-match-p
             "border"
             (satan-tool-validate-args spec '(:classes (:focused (:background "#ffffff"))))))))

(ert-deftest satan-sway/validator-skips-absent-class ()
  "Absent class keys do not trigger shape recursion."
  (let ((spec (list :args-schema
                    '(classes (:type object :required t
                               :shape (focused (:type object :required nil
                                                :shape (border (:type string :required t)))
                                       unfocused (:type object :required nil
                                                  :shape (border (:type string :required t)))))))))
    (should (null (satan-tool-validate-args
                   spec '(:classes (:focused (:border "#ff0000"))))))))

(ert-deftest satan-sway/validator-pattern-enforces-hex ()
  (let ((spec (list :args-schema
                    '(classes (:type object :required t
                               :shape (focused (:type object :required nil
                                                :shape (border (:type string :required t
                                                                :pattern "\\`#[0-9a-fA-F]\\{6\\}\\'")))))))))
    (should (string-match-p
             "match"
             (satan-tool-validate-args
              spec '(:classes (:focused (:border "red"))))))))

;; ---------- JSON Schema mapper extension ----------

(ert-deftest satan-sway/jsonschema-nests-properties ()
  (let* ((schema '(classes (:type object :required t
                            :shape (focused (:type object :required nil
                                             :shape (border (:type string :required t
                                                             :pattern "\\`#[0-9a-fA-F]\\{6\\}\\'")))))))
         (js (satan-tool--args-schema-to-jsonschema schema))
         (classes-prop (plist-get (plist-get js :properties) :classes))
         (focused-prop (plist-get (plist-get classes-prop :properties) :focused))
         (border-prop  (plist-get (plist-get focused-prop :properties) :border)))
    (should (equal (plist-get js :type) "object"))
    (should (equal (append (plist-get js :required) nil) '("classes")))
    (should (equal (plist-get classes-prop :type) "object"))
    (should (equal (plist-get focused-prop :type) "object"))
    (should (equal (plist-get border-prop :type) "string"))
    (should (equal (plist-get border-prop :pattern)
                   "^#[0-9a-fA-F]{6}$"))))

;; ---------- sway_border_set handler ----------

(defvar satan-sway-test--swaymsg-calls nil)

(defmacro satan-sway-test--with-stub (&rest body)
  "Run BODY with `satan-trace-call' + `satan-intervention-create' stubbed.
swaymsg is now routed through `satan-trace-call' (ledgered + bounded),
so the seam is that call, not raw `call-process'.  Captures the LOGICAL
swaymsg argv (trace-call's ARGS, wrapper-free) into `…--swaymsg-calls'
and intervention kwargs into `…--captured'."
  (declare (indent 0))
  `(let ((satan-sway-test--swaymsg-calls nil)
         (satan-sway-test--captured '()))
     (cl-letf (((symbol-function 'satan-trace-call)
                (lambda (_program args &rest _)
                  (push args satan-sway-test--swaymsg-calls)
                  (list :exit 0 :stdout "" :timed-out nil)))
               ((symbol-function 'satan-intervention-create)
                (lambda (&rest args)
                  (push args satan-sway-test--captured)
                  "iv-sway-stub-01")))
       ,@body)))

(ert-deftest satan-sway/set-emits-three-required-colours ()
  (satan-sway-test--with-stub
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "s1" :name "sway_border_set"
                  :args (:classes
                         (:focused (:border "#ff0000"
                                    :background "#ff0000"
                                    :text "#ffffff"))))
                '("sway_border_set")
                satan-sway-test--ctx)))
      (should (eq (plist-get res :ok) t))
      (should (equal (car satan-sway-test--swaymsg-calls)
                     '("client.focused" "#ff0000" "#ff0000" "#ffffff")))
      (should (equal (plist-get (plist-get res :result) :applied)
                     '("focused"))))))

(ert-deftest satan-sway/set-surfaces-intervention-id ()
  "tool_result carries the intervention_id minted on full success."
  (satan-sway-test--with-stub
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "si" :name "sway_border_set"
                  :args (:classes
                         (:focused (:border "#ff0000"
                                    :background "#ff0000"
                                    :text "#ffffff"))))
                '("sway_border_set")
                satan-sway-test--ctx)))
      (should (eq (plist-get res :ok) t))
      (should (equal "iv-sway-stub-01"
                     (plist-get (plist-get res :result) :intervention_id))))))

(ert-deftest satan-sway/set-intervention-args-shape ()
  "Handler passes §3.3 defaults into `satan-intervention-create'."
  (satan-sway-test--with-stub
    (satan-tool-dispatch
     '(:type "tool_call" :id "sa" :name "sway_border_set"
       :args (:classes
              (:focused   (:border "#000000"
                           :background "#000000"
                           :text "#ffffff")
               :unfocused (:border "#111111"
                           :background "#111111"
                           :text "#aaaaaa"))))
     '("sway_border_set")
     satan-sway-test--ctx)
    (let ((args (car satan-sway-test--captured)))
      (should args)
      (should (equal "visible_sign" (plist-get args :kind)))
      (should (equal "sway-mainbar" (plist-get args :target-surface)))
      (should (equal "low"          (plist-get args :severity)))
      (should (equal 30             (plist-get args :outcome-window-minutes)))
      (should (string-match-p "focused"
                              (plist-get args :message)))
      (should (string-match-p "border-colour change"
                              (plist-get args :expected-outcome))))))

(ert-deftest satan-sway/set-no-intervention-on-swaymsg-error ()
  "Failed swaymsg short-circuits before intervention-create."
  (let ((satan-sway-test--swaymsg-calls nil)
        (satan-sway-test--captured '()))
    (cl-letf (((symbol-function 'call-process)
               (lambda (_prog _infile _dest _display &rest _args) 1))
              ((symbol-function 'satan-intervention-create)
               (lambda (&rest args)
                 (push args satan-sway-test--captured)
                 "iv-unused")))
      (let ((res (satan-tool-dispatch
                  '(:type "tool_call" :id "se" :name "sway_border_set"
                    :args (:classes
                           (:focused (:border "#ff0000"
                                      :background "#ff0000"
                                      :text "#ffffff"))))
                  '("sway_border_set")
                  satan-sway-test--ctx)))
        (should (equal (plist-get res :ok) :false))
        (should (null satan-sway-test--captured))))))

(ert-deftest satan-sway/set-emits-optional-colours-when-given ()
  (satan-sway-test--with-stub
    (satan-tool-dispatch
     '(:type "tool_call" :id "s2" :name "sway_border_set"
       :args (:classes
              (:focused (:border "#000000"
                         :background "#111111"
                         :text "#ffffff"
                         :indicator "#aaaaaa"
                         :child_border "#222222"))))
     '("sway_border_set")
     satan-sway-test--ctx)
    (should (equal (car satan-sway-test--swaymsg-calls)
                   '("client.focused" "#000000" "#111111" "#ffffff"
                     "#aaaaaa" "#222222")))))

(ert-deftest satan-sway/set-rejects-bad-hex ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "s3" :name "sway_border_set"
                :args (:classes (:focused (:border "red"
                                           :background "#ffffff"
                                           :text "#ffffff"))))
              '("sway_border_set")
              nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "match" (plist-get res :error)))))

(ert-deftest satan-sway/set-rejects-unknown-class ()
  (satan-sway-test--with-stub
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "s4" :name "sway_border_set"
                  :args (:classes (:bindsym (:border "#ff0000"
                                             :background "#ff0000"
                                             :text "#ff0000"))))
                '("sway_border_set")
                nil)))
      (should (equal (plist-get res :ok) :false))
      (should (string-match-p "unknown class" (plist-get res :error)))
      (should (null satan-sway-test--swaymsg-calls)))))

(ert-deftest satan-sway/set-requires-border-background-text ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "s5" :name "sway_border_set"
                :args (:classes (:focused (:border "#ff0000"))))
              '("sway_border_set")
              nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p
             "\\(background\\|text\\|requires\\)"
             (plist-get res :error)))))

(ert-deftest satan-sway/set-rejects-empty-classes ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "s6" :name "sway_border_set"
                :args (:classes nil))
              '("sway_border_set")
              nil)))
    (should (equal (plist-get res :ok) :false))))

(ert-deftest satan-sway/set-applies-multiple-classes-in-order ()
  (satan-sway-test--with-stub
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "s7" :name "sway_border_set"
                  :args (:classes
                         (:focused   (:border "#000000"
                                      :background "#000000"
                                      :text "#ffffff")
                          :unfocused (:border "#111111"
                                      :background "#111111"
                                      :text "#aaaaaa"))))
                '("sway_border_set")
                satan-sway-test--ctx)))
      (should (eq (plist-get res :ok) t))
      ;; calls accumulated in reverse push order
      (let ((reversed (reverse satan-sway-test--swaymsg-calls)))
        (should (equal (car (car reversed)) "client.focused"))
        (should (equal (car (cadr reversed)) "client.unfocused"))))))

;; ---------- sway_border_reset handler ----------

(ert-deftest satan-sway/reset-emits-reload ()
  (satan-sway-test--with-stub
    (let ((res (satan-tool-dispatch
                '(:type "tool_call" :id "r1" :name "sway_border_reset"
                  :args nil)
                '("sway_border_reset")
                nil)))
      (should (eq (plist-get res :ok) t))
      (should (equal (car satan-sway-test--swaymsg-calls)
                     '("reload"))))))

;; ---------- mode allowlist ----------

(ert-deftest satan-sway/not-allowed-in-mode-without-tool ()
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "x" :name "sway_border_reset"
                :args nil)
              '()
              nil)))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "not allowed" (plist-get res :error)))))

(provide 'test-sway-border)
;;; test-sway-border.el ends here
