(use test prepl srfi-18)

(define port 9797)
(define REPL (make-prepl port))

(test "returns without clients" (void) (REPL))
(test "connections: none before connecting" 0 (length (REPL #:connections)))

;; We keep track of how many times we've run our tests. call/cc is
;; tricky and we wanna make sure (REPL) doesn't return same place
;; twice and run our tests multiple times. There's probably a better
;; way to test this, though...
(define counter (let ((c 0)) (lambda () (set! c (+ 1 c)) c)))

(let-values (((in out) (tcp-connect "127.0.0.1" port)))

  (set! *TEST* 1)
  (test "returns without data" (void) (REPL))
  (test "counter 1" 1 (counter))

  (display "(set! *TEST* " out) ;; <-- send start

  (test "*TEST* before eval" 1 *TEST*)
  (test "returns with incomplete sexp" (void) (REPL))
  (test "counter 2" 2 (counter))

  (display "2)" out) ;; <-- send rest
  (test "returns with complete sexp (runs eval)" (void) (REPL))
  (test "counter 3" 3 (counter))

  (test "*TEST* after eval" 2 *TEST*)

  (let-values (((in2 out2) (tcp-connect "127.0.0.1" port)))
    (display "(set! *TEST* 3)" out2)
    (test "returns with 2 clients" (void) (REPL))
    (test "counter 4" 4 (counter))
    (test "*TEST* from client 2" 3 *TEST*)
    (test "connections: two before closing anything" 2 (length (REPL #:connections)))
    (close-output-port out2)
    (close-input-port in2)
    (test "returns with a clients disconnect" (void) (REPL))
    (test "counter 5" 5 (counter))
    (test "connections: two before closing anything" 1 (length (REPL #:connections))))

  (test "returns again with one client disconnect" (void) (REPL))
  (test "connections: one before closing" 1 (length (REPL #:connections)))
  (close-output-port out)
  (close-input-port  in)
  (test "returns with two clients down" (void) (REPL))
  (test "counter 6" 6 (counter))

  (test "connections: none after closing" 0 (length (REPL #:connections))))

(test "counter 7" 7 (counter))
(test-exit)
