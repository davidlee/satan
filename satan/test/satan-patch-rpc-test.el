;;; satan-patch-rpc-test.el --- the patch runner's control-socket client -*- lexical-binding: t; -*-

;; Against the fake runner in satan-patch-fixture.el; never the live socket.

(require 'ert)
(require 'cl-lib)
(require 'satan-patch-rpc)
(require 'satan-patch-fixture)

(defmacro satan-patch-rpc-test--within (seconds &rest body)
  "Run BODY; fail unless it returns within SECONDS of wall time."
  (declare (indent 1))
  `(let ((start (float-time)))
     (prog1 (progn ,@body)
       (should (< (- (float-time) start) ,seconds)))))

(ert-deftest satan-patch-rpc/round-trip ()
  "One request per call, with the op's fields and a fresh requestId."
  (satan-patch-fixture-with-runner
      (lambda (_request) (list :job (list :jobId "pj-1" :state "queued")))
    (should (equal (satan-patch-rpc-call "status" (list :jobId "pj-1"))
                   '(ok :job (:jobId "pj-1" :state "queued"))))
    (satan-patch-rpc-call "status" (list :jobId "pj-1"))
    (let ((requests (satan-patch-fixture-requests)))
      (should (= 2 (length requests)))
      (should (equal (plist-get (car requests) :op) "status"))
      (should (equal (plist-get (car requests) :jobId) "pj-1"))
      (should (stringp (plist-get (car requests) :requestId)))
      (should-not (equal (plist-get (car requests) :requestId)
                         (plist-get (cadr requests) :requestId))))))

(ert-deftest satan-patch-rpc/sends-arrays-as-arrays ()
  "A list field reaches the runner as a JSON array, non-ASCII intact."
  (satan-patch-fixture-with-runner (lambda (_request) nil)
    (should (eq 'ok (car (satan-patch-rpc-call
                          "ack" (list :jobIds '("pj-1" "pj-ü"))))))
    (should (equal (plist-get (car (satan-patch-fixture-requests)) :jobIds)
                   '("pj-1" "pj-ü")))))

(ert-deftest satan-patch-rpc/refusal-carries-code-and-message ()
  (satan-patch-fixture-with-runner
      (lambda (_request) (satan-patch-fixture-refusal "unknown_job" "no job pj-9"))
    (should (equal (satan-patch-rpc-call "status" (list :jobId "pj-9"))
                   '(error . "unknown_job: no job pj-9")))))

(ert-deftest satan-patch-rpc/missing-socket-is-unreachable ()
  (let ((satan-patch-rpc-socket
         (expand-file-name "absent.sock" (make-temp-file "satan-rpc-" t))))
    (pcase (satan-patch-rpc-call "status" (list :jobId "pj-1"))
      (`(error . ,msg)
       (should (string-prefix-p "patch runner unreachable" msg))
       ;; Names the socket, not the connection's arguments.
       (should (string-search satan-patch-rpc-socket msg))
       (should-not (string-search ":filter" msg)))
      (other (ert-fail (format "expected error, got %S" other))))))

(ert-deftest satan-patch-rpc/silent-runner-times-out ()
  "A runner that never answers is an error within the deadline."
  (satan-patch-fixture-with-runner (lambda (_request) :hang)
    (let ((satan-patch-rpc-timeout 0.2))
      (satan-patch-rpc-test--within 2
        (pcase (satan-patch-rpc-call "status" (list :jobId "pj-1"))
          (`(error . ,msg)
           (should (string-prefix-p "patch runner unreachable" msg))
           (should (string-match-p "no response" msg)))
          (other (ert-fail (format "expected error, got %S" other))))))))

(ert-deftest satan-patch-rpc/close-without-a-line-is-an-error ()
  "A runner fault drops the connection unanswered: an error, not a hang."
  (satan-patch-fixture-with-runner (lambda (_request) :close)
    (satan-patch-rpc-test--within 2
      (pcase (satan-patch-rpc-call "status" (list :jobId "pj-1"))
        (`(error . ,msg)
         (should (string-prefix-p "patch runner unreachable" msg))
         (should (string-match-p "closed" msg)))
        (other (ert-fail (format "expected error, got %S" other)))))))

(ert-deftest satan-patch-rpc/answer-for-another-request-is-refused ()
  (satan-patch-fixture-with-runner (lambda (_request) (list :requestId "other"))
    (pcase (satan-patch-rpc-call "status" (list :jobId "pj-1"))
      (`(error . ,msg) (should (string-match-p "requestId" msg)))
      (other (ert-fail (format "expected error, got %S" other))))))

(ert-deftest satan-patch-rpc/watch-delivers-frames-after-its-answer ()
  "The watch's answer opens it; every later line is a frame."
  (let ((frame (list :event "job_changed" :job (list :jobId "pj-1")))
        opened frames reason)
    (satan-patch-fixture-with-runner
        (lambda (_request) (list :frames (list frame frame)))
      (pcase (satan-patch-rpc-watch-open
              (lambda (f) (push f frames))
              (lambda (why) (setq reason why))
              (lambda () (setq opened t)))
        (`(ok . ,proc)
         (let ((deadline (+ (float-time) 2)))
           (while (and (< (length frames) 2) (< (float-time) deadline))
             (accept-process-output nil 0.05)))
         (should opened)
         (should (equal frames (list frame frame)))
         (should-not reason)
         (should (equal (plist-get (car (satan-patch-fixture-requests)) :op)
                        "watch"))
         (delete-process proc)
         (should (equal reason "deleted")))
        (other (ert-fail (format "watch: %S" other)))))))

(ert-deftest satan-patch-rpc/watch-refusal-closes-with-its-code ()
  (let (reason)
    (satan-patch-fixture-with-runner
        (lambda (_request) (satan-patch-fixture-refusal "invalid_request" "no"))
      (pcase (satan-patch-rpc-watch-open #'ignore (lambda (why) (setq reason why)))
        (`(ok . ,_proc)
         (let ((deadline (+ (float-time) 2)))
           (while (and (null reason) (< (float-time) deadline))
             (accept-process-output nil 0.05)))
         (should (equal reason "invalid_request: no")))
        (other (ert-fail (format "watch: %S" other)))))))

(ert-deftest satan-patch-rpc/watch-on-missing-socket-is-unreachable ()
  (let ((satan-patch-rpc-socket
         (expand-file-name "absent.sock" (make-temp-file "satan-rpc-" t))))
    (pcase (satan-patch-rpc-watch-open #'ignore #'ignore)
      (`(error . ,msg) (should (string-prefix-p "patch runner unreachable" msg)))
      (other (ert-fail (format "expected error, got %S" other))))))

(provide 'satan-patch-rpc-test)
;;; satan-patch-rpc-test.el ends here
