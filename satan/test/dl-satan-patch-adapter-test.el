;;; dl-satan-patch-adapter-test.el --- ert for adapter protocol -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'dl-satan-patch-adapter)

(defmacro dl-satan-patch-adapter-test--with-clean-registry (&rest body)
  "Run BODY with `dl-satan-patch-adapters' bound to a fresh empty list."
  `(let ((dl-satan-patch-adapters nil))
     ,@body))

(ert-deftest dl-satan-patch-adapter/register-and-lookup ()
  (dl-satan-patch-adapter-test--with-clean-registry
    (dl-satan-patch-adapter-register "fake" (lambda (&rest _) :sentinel))
    (should (functionp (dl-satan-patch-adapter-lookup "fake")))
    (should (null (dl-satan-patch-adapter-lookup "missing")))))

(ert-deftest dl-satan-patch-adapter/register-replaces ()
  (dl-satan-patch-adapter-test--with-clean-registry
    (dl-satan-patch-adapter-register "fake" (lambda (&rest _) :first))
    (dl-satan-patch-adapter-register "fake" (lambda (&rest _) :second))
    (should (eq :second
                (funcall (dl-satan-patch-adapter-lookup "fake"))))
    (should (= 1 (length dl-satan-patch-adapters)))))

(ert-deftest dl-satan-patch-adapter/invoke-dispatches ()
  (dl-satan-patch-adapter-test--with-clean-registry
    (let ((seen nil))
      (dl-satan-patch-adapter-register
       "fake"
       (cl-function
        (lambda (job-spec input &key on-finish on-log)
          (setq seen (list :job-id (plist-get job-spec :id)
                           :directive (plist-get input :directive)
                           :on-finish on-finish
                           :on-log on-log)))))
      (dl-satan-patch-adapter-invoke
       "fake"
       (list :id "patch_test")
       (list :directive "do the thing")
       :on-finish (lambda (_) t)
       :on-log (lambda (_) t))
      (should (equal "patch_test" (plist-get seen :job-id)))
      (should (equal "do the thing" (plist-get seen :directive)))
      (should (functionp (plist-get seen :on-finish)))
      (should (functionp (plist-get seen :on-log))))))

(ert-deftest dl-satan-patch-adapter/invoke-unknown-signals ()
  (dl-satan-patch-adapter-test--with-clean-registry
    (should-error
     (dl-satan-patch-adapter-invoke
      "missing" '(:id "x") '(:directive "y"))
     :type 'error)))

(ert-deftest dl-satan-patch-adapter/result-helpers-shape ()
  (let ((s (dl-satan-patch-adapter-result-success
            :summary "ok" :changed-files '("a"))))
    (should (eq 'success (plist-get s :status)))
    (should (equal "ok" (plist-get s :summary)))
    (should (equal '("a") (plist-get s :changed-files))))
  (let ((f (dl-satan-patch-adapter-result-failure "boom" :exit-code 1)))
    (should (eq 'failure (plist-get f :status)))
    (should (equal "boom" (plist-get f :error)))
    (should (= 1 (plist-get f :exit-code)))))

(provide 'dl-satan-patch-adapter-test)
;;; dl-satan-patch-adapter-test.el ends here
