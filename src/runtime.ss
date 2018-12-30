(import (chezscheme)
        (tojoqk-aws-custom-runtime json)
        (tojoqk-aws-custom-runtime http))

(define (runtime filename function aws-lambda-rutnime-api)
  (let ([lambda-environment
         (copy-environment (scheme-environment))]
        [next (format #f "http://~a/2018-06-01/runtime/invocation/next"
                      aws-lambda-rutnime-api)])
    (load filename (lambda (sexp)
                     (eval sexp lambda-environment)))
    (let ([function (string->symbol function)])
      (let loop ()
        (let-values ([(code headers body/utf8)
                      (http/get next)])
          (let* ([event-data
                  (string->json (utf8->string body/utf8))]
                 [context '()]
                 [request-id
                  (cdr (assoc "Lambda-Runtime-Aws-Request-Id"
                              headers))]
                 [response (eval `(,function ',event-data ',context)
                                 lambda-environment)]
                 [response-url
                  (format
                   #f
                   "http://~a/2018-06-01/runtime/invocation/~a/response"
                   aws-lambda-rutnime-api
                   request-id)])
            (http/post response-url (json->string response))))
        (loop)))))

(apply runtime (cdr (command-line)))
