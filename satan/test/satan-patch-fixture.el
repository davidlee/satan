;;; satan-patch-fixture.el --- a fake patch runner for tests -*- lexical-binding: t; -*-

;; A fake malebolge runner: an in-process NDJSON server on a temp unix
;; socket, bound to `satan-patch-rpc-socket' for the body.  Tests never
;; touch the live socket.  Not a suite file (no -test suffix): suites
;; `require' it.
;;
;; HANDLER maps one request plist to what the server does:
;;
;;   PLIST           answer {requestId, ok:true, ...PLIST}; a PLIST that
;;                   sets :ok or :requestId overrides the default
;;                   (`satan-patch-fixture-refusal' builds an ok:false)
;;   (:frames F ...) answer ok, then send each frame F (a watch)
;;   :hang           read the request, never answer
;;   :close          close the connection without a line
;;
;; Every request is recorded, in arrival order, for assertions.

;;; Code:

(require 'cl-lib)
(require 'satan-jsonl)
(require 'satan-patch-rpc)

(defvar satan-patch-fixture--requests nil
  "Requests the fake runner received, newest first.  Bound per fixture.")

(defun satan-patch-fixture-requests ()
  "The requests the fake runner received, in arrival order."
  (reverse satan-patch-fixture--requests))

(defun satan-patch-fixture-refusal (code message)
  "A handler answer refusing the request with CODE and MESSAGE."
  (list :ok :false :error (list :code code :message message)))

(defun satan-patch-fixture--answer (client request answer)
  "Act on ANSWER (a handler result) to REQUEST over CLIENT."
  (pcase answer
    (:hang nil)
    (:close (delete-process client))
    (_
     (let ((frames (plist-get answer :frames))
           (body (if (plist-member answer :frames) nil answer)))
       (satan-jsonl-send
        client (append body
                       (unless (plist-member body :requestId)
                         (list :requestId (plist-get request :requestId)))
                       (unless (plist-member body :ok) (list :ok t))))
       (dolist (frame frames)
         (satan-jsonl-send client frame))))))

(defun satan-patch-fixture--accept (handler clients)
  "A server `:log' function: serve each accepted client with HANDLER.
CLIENTS is a cons whose car collects the accepted connections."
  (lambda (_server client _message)
    (push client (car clients))
    (set-process-filter
     client
     (satan-jsonl-make-filter
      (lambda (request)
        (push request satan-patch-fixture--requests)
        (satan-patch-fixture--answer client request (funcall handler request)))
      #'ignore))))

(defun satan-patch-fixture-call-with-runner (handler thunk)
  "Call THUNK with a fake runner serving HANDLER on `satan-patch-rpc-socket'."
  (let* ((dir (make-temp-file "satan-fake-runner-" t))
         (socket (expand-file-name "control.sock" dir))
         (clients (list nil))
         (satan-patch-fixture--requests nil)
         (server (make-network-process
                  :name "satan-fake-runner" :server t :family 'local
                  :service socket :coding 'utf-8 :noquery t
                  :log (satan-patch-fixture--accept handler clients))))
    (unwind-protect
        (let ((satan-patch-rpc-socket socket))
          (funcall thunk))
      (mapc #'delete-process (car clients))
      (delete-process server)
      (delete-directory dir t))))

(defmacro satan-patch-fixture-with-runner (handler &rest body)
  "Run BODY against a fake runner answering requests with HANDLER."
  (declare (indent 1))
  `(satan-patch-fixture-call-with-runner ,handler (lambda () ,@body)))

(defun satan-patch-fixture-answering (answers)
  "A handler answering each op by ANSWERS, an alist (OP . ANSWER).
An op absent from ANSWERS is refused `invalid_request'."
  (lambda (request)
    (let ((op (plist-get request :op)))
      (or (cdr (assoc op answers))
          (satan-patch-fixture-refusal "invalid_request"
                                       (format "unexpected op %s" op))))))

(provide 'satan-patch-fixture)
;;; satan-patch-fixture.el ends here
