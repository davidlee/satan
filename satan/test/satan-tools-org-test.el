;;; satan-tools-org-test.el --- ert tests for satan-tools-org -*- lexical-binding: t; -*-

;; Run from CLI:
;;   emacs --batch \
;;     -L ~/.emacs.d/core -L ~/.emacs.d/satan -L ~/.emacs.d/satan/test \
;;     -l satan-tools-org-test.el -f ert-run-tests-batch-and-exit

(require 'ert)
(require 'cl-lib)
(require 'satan-tools)
(require 'satan-tools-org)
(require 'satan-mode)
(require 'satan-intervention)

(defconst satan-org-test--ctx
  '(:id "20260523T120000-morning-deadbe"
    :mode-name "morning"
    :time-now "2026-05-23T12:00:00+1000"
    :run-started-at "2026-05-23T12:00:00+1000"
    :capabilities (write-daily)
    :audit satan-org-test--stub-audit)
  "Synthetic tool-ctx used by proposal_stage dispatch tests.")

(defmacro satan-org-test--with-stubs (&rest body)
  "Capture intervention-create kwarg plists into `…--captured'."
  (declare (indent 0))
  `(let ((satan-org-test--captured '()))
     (cl-letf (((symbol-function 'satan-intervention-create)
                (lambda (&rest args)
                  (push args satan-org-test--captured)
                  "iv-proposal-stub-01")))
       ,@body)))

(ert-deftest satan-org/update-owned-block-rejects-motd-target ()
  "motd is no longer a writable target; satan_final.summary owns motd."
  (let ((res (satan-tool-dispatch
              '(:type "tool_call" :id "u1" :name "org_update_owned_block"
                :args (:target "motd" :block "satan" :content "x"))
              '("org_update_owned_block")
              '(:capabilities (write-daily)))))
    (should (equal (plist-get res :ok) :false))
    (should (string-match-p "target" (plist-get res :error)))))

(ert-deftest satan-org/update-owned-block-tool-not-in-motd-mode ()
  "motd mode's :tools list must not include org_update_owned_block."
  (let* ((mode (satan-mode-resolve "motd"))
         (tools (plist-get mode :tools)))
    (should-not (member "org_update_owned_block" tools))))

(ert-deftest satan-org/update-owned-block-only-listed-by-morning ()
  "Mode `:tools' allowlist gates org_update_owned_block: morning yes, motd no.
T4 dropped the documentary `:modes' field from tool specs; the
mode-spec is now the single source of truth, enforced at load by
`satan-mode-check-tool-references'."
  (let ((morning-tools (plist-get (satan-mode-resolve "morning") :tools))
        (motd-tools    (plist-get (satan-mode-resolve "motd") :tools)))
    (should     (member "org_update_owned_block" morning-tools))
    (should-not (member "org_update_owned_block" motd-tools))))

(ert-deftest satan-org/proposal-stage-surfaces-intervention-id ()
  "proposal_stage result carries the intervention_id minted by the write API."
  (let* ((tmp (make-temp-file "satan-proposals-" t))
         (satan-proposals-dir tmp))
    (unwind-protect
        (satan-org-test--with-stubs
          (let ((res (satan-tool/proposal-stage
                      '(:title "Refactor X" :body "consider Y")
                      satan-org-test--ctx)))
            (should (eq (car res) 'ok))
            (should (equal "iv-proposal-stub-01"
                           (plist-get (cdr res) :intervention_id)))
            (should (file-readable-p (plist-get (cdr res) :path)))))
      (when (file-directory-p tmp) (delete-directory tmp t)))))

(ert-deftest satan-org/proposal-stage-intervention-args-shape ()
  "Handler passes §3.3 defaults into `satan-intervention-create'."
  (let* ((tmp (make-temp-file "satan-proposals-" t))
         (satan-proposals-dir tmp))
    (unwind-protect
        (satan-org-test--with-stubs
          (satan-tool/proposal-stage
           '(:title "Refactor X" :body "consider Y")
           satan-org-test--ctx)
          (let ((args (car satan-org-test--captured)))
            (should args)
            (should (equal "proposal" (plist-get args :kind)))
            (should (string-prefix-p tmp (plist-get args :target-surface)))
            (should (equal "medium"   (plist-get args :severity)))
            (should (equal 120        (plist-get args :outcome-window-minutes)))
            (should (equal "Refactor X" (plist-get args :message)))
            (should (string-match-p "accepts or rejects"
                                    (plist-get args :expected-outcome)))))
      (when (file-directory-p tmp) (delete-directory tmp t)))))

(provide 'satan-tools-org-test)
;;; satan-tools-org-test.el ends here
