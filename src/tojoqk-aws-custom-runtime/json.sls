(library (tojoqk-aws-custom-runtime json)
  (export string->json json->string)
  (import (rnrs))

  (define (string->json str)
    (let ([in (open-string-input-port str)])
      (call/cc
       (lambda (fail)
         (parse-json in (lambda () (fail #f)))))))

  (define (char-degit? c)
    (case c
      [(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9) #t]
      [else #f]))

  (define (numeric-char->number c)
    (- (char->integer c) 48))

  (define (whitespace? c)
    (case c
      [(#\space #\tab #\newline #\return) #t]
      [else #f]))

  (define (skip-whitespace in)
    (cond
     [(whitespace? (peek-char in))
      (get-char in)
      (skip-whitespace in)]
     [else 'done]))

  (define (parse-json in fail)
    (skip-whitespace in)
    (let ([c (peek-char in)])
      (cond
       [(eof-object? c) (fail)]
       [(char=? c #\{)
        (parse-object in fail)]
       [(char=? c #\[)
        (parse-array in fail)]
       [(char-degit? c)
        (parse-number in fail)]
       [(char=? c #\")
        (parse-string in fail)]
       [else (fail)])))

  (define (parse-object in fail)
    (get-char in)                       ; drop #\{
    (skip-whitespace in)
    (let ([c (peek-char in)])
      (cond
       [(eof-object? c) (fail)]
       [(char=? c #\})
        (get-char in)
        '()]
       [else
        (%parse-object in fail)])))

  (define (%parse-object in fail)
    (let ([key (parse-string in fail)])
      (skip-whitespace in)
      (let ([value
             (let ([c (get-char in)])
               (cond
                [(eof-object? c) (fail)]
                [(char=? c #\:)
                 (parse-json in fail)]
                [else (fail)]))])
        (skip-whitespace in)
        (cons (cons key value)
              (let ([c (get-char in)])
                (cond
                 [(eof-object? c) (fail)]
                 [(char=? c #\,)
                  (parse-object in fail)]
                 [(char=? c #\})
                  '()]
                 [else (fail)]))))))

  (define (parse-array in fail)
    (get-char in)                       ; drop #\[
    (list->vector
     (let ([c (peek-char in)])
       (cond
        [(eof-object? c) (fail)]
        [(char=? c #\]) '()]
        [else
         (%parse-array in fail)]))))

  (define (%parse-array in fail)
    (let ([first (parse-json in fail)])
      (skip-whitespace in)
      (let ([c (get-char in)])
        (cons first
              (cond
               [(eof-object? c) (fail)]
               [(char=? c #\,)
                (%parse-array in fail)]
               [(char=? c #\])
                '()]
               [else (fail)])))))

  (define (parse-string in fail)
    (get-char in)
    (call-with-string-output-port
      (lambda (out)
        (let loop ()
          (let ([c (get-char in)])
            (case c
              [(#\") 'done]
              [(#\\)
               (let ([c (get-char in)])
                 (case c
                   [(#\\ #\/) (put-char out c)]
                   [(#\n) (put-char out #\newline)]
                   [(#\t) (put-char out #\tab)]
                   [(#\r) (put-char out #\return)]
                   [(#\b) (put-char out #\backspace)]
                   [(#\f) (put-char out #\x000c)]
                   [(#\u)
                    (let* ([s (get-string-n in 4)])
                      (cond
                       [(string->number s 16)
                        => (lambda (n)
                             (put-char out (integer->char s)))]
                       [else (fail)]))]
                   [else
                    (put-char out #\\)
                    (put-char out c)]))
               (loop)]
              [else
               (put-char out c)
               (loop)]))))))

  (define (parse-number in fail)
    (cond
     [(string->number
       (call-with-string-output-port
         (lambda (out)
           (let loop ([decimal? #f])
             (let ([c (peek-char in)])
               (cond
                [(char-degit? c)
                 (get-char in)
                 (put-char out c)
                 (loop decimal?)]
                [(and (not decimal?) (char=? c #\.))
                 (get-char in)
                 (put-char out c)
                 (loop #t)]
                [else 'done]))))))
      => (lambda (n) n)]
     [else (fail)]))

  (define (json->string sexp)
    (call/cc
     (lambda (fail)
       (call-with-string-output-port
         (lambda (out)
           (%json->string out sexp (lambda () (fail #f))))))))

  (define (%json->string out sexp fail)
    (cond
     [(list? sexp)
      (cond
       [(null? sexp)
        (put-string out "{}")]
       [else
        (put-char out #\{)
        (let loop ([sexp sexp])
          (define (put-pair)
            (let ([pair (car sexp)])
              (cond
               [(and (pair? pair)
                     (or (symbol? (car pair))
                         (string? (car pair))))
                (put-char out #\")
                (display (car pair) out)
                (put-char out #\")
                (put-char out #\:)
                (%json->string out (cdr pair) fail)]
               [else (fail)])))
          (cond
           [(null? (cdr sexp))
            (put-pair)
            (put-char out #\})]
           [else
            (put-pair)
            (put-char out #\,)
            (loop (cdr sexp))]))])]
     [(vector? sexp)
      (let ([n (vector-length sexp)])
        (cond
         [(= n 0)
          (put-string out "[]")]
         [else
          (put-char out #\[)
          (let loop ([i 0])
            (cond
             [(= i (- n 1))
              (%json->string out (vector-ref sexp i) fail)
              (put-char out #\])]
             [else
              (%json->string out (vector-ref sexp i) fail)
              (put-char out #\,)
              (loop (+ i 1))]))]))]
     [(string? sexp)
      (put-char out #\")
      (string-for-each
       (lambda (c)
         (case c
           [(#\newline) (put-string out "\\n")]
           [(#\tab) (put-string out "\\t")]
           [(#\return) (put-string out "\\r")]
           [(#\backspace) (put-string out "\\b")]
           [(#\x000c) (put-string out "\\f")]
           [else
            (put-char out c)]))
       sexp)
      (put-char out #\")]
     [(integer? sexp) (display sexp out)]
     [(real? sexp)
      (display (if (exact? sexp)
                   (inexact sexp)
                   sexp)
               out)]
     [else
      (fail)]))
  )
