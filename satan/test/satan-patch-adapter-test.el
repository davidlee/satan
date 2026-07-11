;;; satan-patch-adapter-test.el --- ert for adapter protocol -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'satan-patch-adapter)

(defmacro satan-patch-adapter-test--with-clean-registry (&rest body)
  "Run BODY with `satan-patch-adapters' bound to a fresh empty list."
  `(let ((satan-patch-adapters nil))
     ,@body))

(ert-deftest satan-patch-adapter/register-and-lookup ()
  (satan-patch-adapter-test--with-clean-registry
    (satan-patch-adapter-register "fake" (lambda (&rest _) :sentinel))
    (should (functionp (satan-patch-adapter-lookup "fake")))
    (should (null (satan-patch-adapter-lookup "missing")))))

(ert-deftest satan-patch-adapter/register-replaces ()
  (satan-patch-adapter-test--with-clean-registry
    (satan-patch-adapter-register "fake" (lambda (&rest _) :first))
    (satan-patch-adapter-register "fake" (lambda (&rest _) :second))
    (should (eq :second
                (funcall (satan-patch-adapter-lookup "fake"))))
    (should (= 1 (length satan-patch-adapters)))))

(ert-deftest satan-patch-adapter/invoke-dispatches ()
  (satan-patch-adapter-test--with-clean-registry
    (let ((seen nil))
      (satan-patch-adapter-register
       "fake"
       (cl-function
        (lambda (job-spec input &key on-finish on-log)
          (setq seen (list :job-id (plist-get job-spec :id)
                           :directive (plist-get input :directive)
                           :on-finish on-finish
                           :on-log on-log)))))
      (satan-patch-adapter-invoke
       "fake"
       (list :id "patch_test")
       (list :directive "do the thing")
       :on-finish (lambda (_) t)
       :on-log (lambda (_) t))
      (should (equal "patch_test" (plist-get seen :job-id)))
      (should (equal "do the thing" (plist-get seen :directive)))
      (should (functionp (plist-get seen :on-finish)))
      (should (functionp (plist-get seen :on-log))))))

(ert-deftest satan-patch-adapter/invoke-unknown-signals ()
  (satan-patch-adapter-test--with-clean-registry
    (should-error
     (satan-patch-adapter-invoke
      "missing" '(:id "x") '(:directive "y"))
     :type 'error)))

(ert-deftest satan-patch-adapter/result-helpers-shape ()
  (let ((s (satan-patch-adapter-result-success
            :summary "ok" :changed-files '("a"))))
    (should (eq 'success (plist-get s :status)))
    (should (equal "ok" (plist-get s :summary)))
    (should (equal '("a") (plist-get s :changed-files))))
  (let ((f (satan-patch-adapter-result-failure "boom" :exit-code 1)))
    (should (eq 'failure (plist-get f :status)))
    (should (equal "boom" (plist-get f :error)))
    (should (= 1 (plist-get f :exit-code)))))

(provide 'satan-patch-adapter-test)
;;; satan-patch-adapter-test.el ends here
