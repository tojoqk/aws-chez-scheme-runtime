(import (rnrs))

(define (hello event-data context)
  `((hello . "world!!!")
    (event-data . ,event-data)))

(define (fail-test event-data context)
  (error 'fail "failure" 'oops!))

(define (assertion-test event-data context)
  (assertion-violation 'assertion "failure" 'oops!))

(define (raise-test event-data context)
  (raise "raised-string"))
