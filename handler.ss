(import (rnrs))

(define (hello in out)
  (put-string out "{")
  (put-string out "\"hello\": \"world\"")
  (put-string out ",")
  (put-string out "\"event-data\": ")
  (put-string out (get-string-all in))
  (put-string out "}"))

(define (fail-test in out)
  (error 'fail "failure" 'oops!))

(define (assertion-test in out)
  (assertion-violation 'assertion "failure" 'oops!))

(define (raise-test in out)
  (raise "raised-string"))
