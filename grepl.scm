(use tcp)

;; cpsl is a cps procedure, but we're mutating so that others can
;; access our latest cps.
(define (make-yielding-input-port port cpsl)
  (let ([reader (lambda ()
                  (let loop ()
                    (if (char-ready? port)
                        (read-char port)
                        (begin
                          (call/cc (lambda (return)
                                     ((car cpsl)
                                      (lambda (k) ;; cps
                                        (set! (car cpsl) k)
                                        (return (void))))))
                          (loop)))))] )
    (make-input-port reader
                     (lambda () (char-ready? port))
                     (lambda () (close-input-port port)))))

(define (repl-loop in-port out-port close!)

  (define (repl-prompt op)
    (display "@> " op)
    (flush-output op))

  ;; stolen from Chicken Core's eval.scm
  (define (write-results xs port)
    (cond ((null? xs)
           (##sys#print "; no values\n" #f port))
          ((not (eq? (##core#undefined) (car xs)))
           (for-each (cut ##sys#repl-print-hook <> port) xs)
           (when (pair? (cdr xs))
             (##sys#print
              (string-append "; " (##sys#number->string (length xs)) " values\n")
              #f port)))))

  (let loop ()
    (handle-exceptions root-exn
      (close!) ;; <-- close/remove repl connection on error (broken pipe)

      (repl-prompt out-port)
      (handle-exceptions exn
        (begin (print-error-message exn out-port)
               (print-call-chain out-port 4)
               (loop))
        ;; reading from in-port will probably yield:
        (let ([sexp (read in-port)])
          ;; eof, exit repl loop
          (if (eof-object? sexp)
              (close!) ;; I don't think this ever happens, actually
              (with-output-to-port out-port
                (lambda ()
                  (with-error-output-to-port
                   out-port
                   (lambda ()
                     (receive result (eval sexp)
                       (if (eq? (void) result)
                           (void) ;; don't print unspecified's
                           (write-results result out-port)))))))))
        (loop)))))

(define (make-grepl port)
  (define socket (tcp-listen port))
  (define connections '())

  (lambda (#!optional (command #:run))
    (cond
     ((eq? command #:connections) connections)
     ((eq? command #:socket)      socket)
     ((eq? command #:close)       "not yet implemented")
     ((eq? command #:run)
      (handle-exceptions exn
        ;; we might see things like "cannot compute remote address -
        ;; Transport endpoint is not connected" here:
        (begin (print-error-message exn)) ;; TODO: print to all repl outports too?
        (when (tcp-accept-ready? socket)
          (tcp-read-timeout #f)
          (let-values (((in out) (tcp-accept socket)))
            (let-values (((local-adr  remote-adr)  (tcp-addresses in))
                         ((local-port remote-port) (tcp-port-numbers in)))
              ;; con is our connection object. the car is always cps
              ;; procedure.
              (let* ((con (list #f remote-adr remote-port in out))
                     (close! (lambda ()
                               (set! connections
                                     (remove (lambda (con%)
                                               ;;(print con con% " equal? "  (equal? con con%))
                                               (equal? con con%)) connections)))))
                (set! (car con)
                      (lambda (k) ;; cps
                        (let ((kl (list k)))
                          (repl-loop (make-yielding-input-port in kl) out close!)
                          ((car kl) #f))))
                (set! connections (cons con connections)))))))
      ;; process all active connections:
      (for-each
       (lambda (con)
         (let ((proc (car con)))
           (call/cc
            (lambda (return)
              (proc (lambda (k) ;; cps
                      (set! (car con) k)
                      (return (void))))))))
       connections))
     (else (error "unknown command (try none #:connections #:socket #:close)" command)))))
