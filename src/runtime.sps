(import (chezscheme))

(define runtime-dir "/tmp/runtime")
(define header-file (string-append runtime-dir "/" "header"))
(define input-file (string-append runtime-dir "/" "input.json"))
(define output-file (string-append runtime-dir "/" "output.json"))
(define error-file (string-append runtime-dir "/" "error.json"))

(define (http-transcoder)
  (make-transcoder (latin-1-codec)
                   (eol-style crlf)))

(define (unix-transcoder)
  (make-transcoder (utf-8-codec)
                   (eol-style lf)))

(define (runtime filename function/string aws-lambda-rutnime-api)
  (let ([lambda-environment
         (copy-environment (scheme-environment))])
    (load filename (lambda (sexp)
                     (eval sexp lambda-environment)))
    (let ([function (eval (string->symbol function/string)
                          lambda-environment)])
      (mkdir runtime-dir)
      (let loop ()
        (get-next (next-url aws-lambda-rutnime-api) input-file header-file)
        (let* ([headers
                (let ([in (open-file-input-port header-file
                                                (file-options)
                                                (buffer-mode block)
                                                (http-transcoder))])
                  (dynamic-wind
                    void
                    (lambda () (parse-header in))
                    (lambda () (close-input-port in))))]
               [request-id (cdr (assoc "Lambda-Runtime-Aws-Request-Id" headers))])
          (let ([in (open-file-input-port input-file
                                          (file-options)
                                          (buffer-mode block)
                                          (unix-transcoder))]
                [out (open-file-output-port output-file
                                            (file-options no-fail)
                                            (buffer-mode block)
                                            (unix-transcoder))]
                [err (open-file-output-port error-file
                                            (file-options no-fail)
                                            (buffer-mode block)
                                            (unix-transcoder))])
            (dynamic-wind
              void
              (lambda ()
                (guard (con
                        [else
                         (put-string
                          err
                          (cond
                           [(error? con)
                            "{\"errorType\":\"Error\",\"errorMessage\":\"An error has occured.\"}"]
                           [(violation? con)
                            "{\"errorType\":\"Violation\",\"errorMessage\":\"a bug has found.\"}"]
                           [else
                            "{\"errorType\":\"Raise\",\"errorMessage\":\"a object has raised.\"}"]))
                         (close-output-port err)
                         (post-error (error-url aws-lambda-rutnime-api request-id)
                                     error-file)
                         (raise con)])
                  (function in out)))
              (lambda ()
                (close-input-port in)
                (close-output-port out)
                (close-output-port err)))
            (post-response (response-url aws-lambda-rutnime-api request-id)
                           output-file)))
        (loop)))))

(define (get-next url input-file header-file)
  (system (format #f
                  "curl -so ~a -D ~a ~a"
                  input-file
                  header-file
                  url)))

(define (post-response url output-file)
  (system (format #f
                  "curl -so /dev/null -X POST -H 'Content-Type: application/json' ~a -d @~a"
                  url
                  output-file)))

(define (post-error url error-file)
  (system (format #f
                  "curl -so /dev/null -X POST -H 'Content-Type: application/json' ~a -d @~a"
                  url
                  error-file)))

(define (next-url aws-lambda-rutnime-api)
  (format #f
          "http://~a/2018-06-01/runtime/invocation/next"
          aws-lambda-rutnime-api))

(define (response-url aws-lambda-rutnime-api request-id)
  (format #f
          "http://~a/2018-06-01/runtime/invocation/~a/response"
          aws-lambda-rutnime-api
          request-id))

(define (error-url aws-lambda-rutnime-api request-id)
  (format #f
          "http://~a/2018-06-01/runtime/invocation/~a/error"
          aws-lambda-rutnime-api
          request-id))

(define (string-index str c)
  (let ([n (string-length str)])
    (call/cc
     (lambda (return)
       (do ([i 0 (+ i 1)])
           [(= n i) #f]
         (when (char=? c (string-ref str i))
           (return i)))))))

(define (parse-header in)
  (let loop ([alist '()])
    (let ([line (get-line in)])
      (if (eof-object? line)
          alist
          (cond
           [(string-index line #\:)
            => (lambda (i)
                 (loop (cons (cons (substring line 0 i)
                                   (substring line
                                              (+ i 2) ; skip a whitespace
                                              (string-length line)))
                             alist)))]
           [else
            (loop alist)])))))

(apply runtime (cdr (command-line)))
