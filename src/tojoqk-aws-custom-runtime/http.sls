(library (tojoqk-aws-custom-runtime http)
  (export http/get http/post)
  (import (chezscheme))

  (define init
    (begin (load-shared-object "libcurl.so")))

  (define CURLOPT_URL 10002)
  (define CURLOPT_PORT 3)
  (define CURLOPT_POST 47)
  (define CURLOPT_USE_SSL 119)
  (define CURLOPT_HTTPHEADER 10023)
  (define CURLOPT_READDATA 10009)
  (define CURLOPT_READFUNCTION 20012)
  (define CURLOPT_WRITEDATA 10001)
  (define CURLOPT_WRITEFUNCTION 20011)
  (define CURLOPT_HEADERDATA 10029)
  (define CURLOPT_HEADERFUNCTION 20079)
  (define CURLINFO_RESPONSE_CODE 2097154)

  (define curl-easy-init
    (foreign-procedure "curl_easy_init" () void*))
  (define curl-easy-perform
    (foreign-procedure "curl_easy_perform" (void*) int))
  (define curl-easy-cleanup
    (foreign-procedure "curl_easy_cleanup" (void*) void*))
  (define curl-easy-setopt/long
    (foreign-procedure "curl_easy_setopt" (void* int long) int))
  (define curl-easy-setopt/string
    (foreign-procedure "curl_easy_setopt" (void* int string) int))
  (define curl-easy-setopt/void*
    (foreign-procedure "curl_easy_setopt" (void* int void*) void))
  (define curl-easy-setopt/scheme-object
    (foreign-procedure "curl_easy_setopt" (void* int scheme-object) void))

  (define curl-easy-getinfo/int
    (foreign-procedure "curl_easy_getinfo"
                       (void* int void*) int))

  (define curl-slist-append
    (foreign-procedure "curl_slist_append"
                       (void* string)
                       void*))

  (define curl-slist-free-all
    (foreign-procedure "curl_slist_free_all"
                       (void*)
                       void))
  (define http/get
    (case-lambda
     [(url)
      (http/get url #f)]
     [(url headers)
      (http/get url headers #f)]
     [(url headers port)
      (http/get url headers port #f)]
     [(url headers port ssl?)
      (http 'GET url headers port ssl? #f)]))

  (define http/post
    (case-lambda
     [(url data)
      (http/post url data #f)]
     [(url data headers)
      (http/post url data headers #f)]
     [(url data headers port)
      (http/post url data headers port #f)]
     [(url data headers port ssl?)
      (http 'POST url headers port ssl? data)]))

  (define (http method url headers port ssl? data)
    (let* ([url
            (cond
             [(string? url) url]
             [else (assertion-violation 'http (format #f "'url' must be sring (~a)" url))])]
           [ssl?
            (cond
             [(boolean? ssl?) ssl?]
             [else (assertion-violation 'http
                                        (format #f "'ssl?' must be boolean (~a)" ssl?))])]
           [port
            (cond
             [(or (eq? port #f)
                  (and (integer? port)
                       (< 0 port)))
              port]
             [else (assertion-violation 'http
                                        (format #f "port must be positive integer (~a)" port))])]
           [method
            (case method
              [(get GET) 'GET]
              [(post POST) 'POST]
              [else
               (assertion-violation 'http
                                    (format #f "yet implemented method ~a" method))])]
           [data
            (cond
             [(string? data) (string->utf8 data)]
             [(bytevector? data) data]
             [(not data) #f]
             [else (assertion-violation 'http
                                        (format #f "can't write data (~a)" data))])]
           [headers
            (cond
             [(eq? headers #f) '()]
             [(and (list? headers)
                   (andmap pair? headers))
              headers]
             [else
              (assertion-violation 'http "headers must be alist")])]
           [headers
            (cond
             [data (cons (cons "Content-Length" (bytevector-length data)) headers)]
             [else headers])])
      (define (getinfo/status curl)
        (define l (make-ftype-pointer long (foreign-alloc (ftype-sizeof long))))
        (unless (= (curl-easy-getinfo/int curl CURLINFO_RESPONSE_CODE
                                          (ftype-pointer-address l)) 0)
          (error 'curl_easy_getinfo "can't get status code"))
        (let ([result (ftype-ref long () l)])
          (unlock-object l)
          result))
      (define (get curl)
        #f)
      (define (post curl)
        (curl-easy-setopt/long curl CURLOPT_POST 1))
      (define (use-ssl curl)
        (curl-easy-setopt/long curl CURLOPT_USE_SSL 119))
      (define (read-data curl)
        (let* ([in (open-bytevector-input-port data)]
               [read-function
                (foreign-callable
                 (lambda (buf size nmemb obj)
                   (let* ([segsize (* size nmemb)])
                     (let loop ([i 0])
                       (cond
                        [(= segsize i) segsize]
                        [else
                         (let ([b (get-u8 in)])
                           (cond
                            [(eof-object? b) i]
                            [else
                             (foreign-set! 'unsigned-8 buf i b)
                             (loop (+ i 1))]))]))))
                 (void* size_t size_t scheme-object)
                 size_t)])
          (lock-object read-function)
          (curl-easy-setopt/scheme-object curl CURLOPT_READDATA #f)
          (curl-easy-setopt/void*
           curl
           CURLOPT_READFUNCTION
           (foreign-callable-entry-point read-function))
          read-function))
      (define (write-data curl)
        (let-values ([(output get-output)
                      (open-bytevector-output-port)])
          (let ([write-function
                 (foreign-callable
                  (lambda (buf size nmemb obj)
                    (let* ([segsize (* size nmemb)])
                      (put-bytevector output buf 0 segsize)
                      segsize))
                  (u8* size_t size_t scheme-object)
                  size_t)])
            (lock-object write-function)
            (curl-easy-setopt/scheme-object curl CURLOPT_WRITEDATA output)
            (curl-easy-setopt/void*
             curl
             CURLOPT_WRITEFUNCTION
             (foreign-callable-entry-point write-function))
            (values
             get-output
             write-function))))
      (define (header-data curl)
        (let-values ([(output get-output)
                      (open-bytevector-output-port)])
          (let ([header-function
                 (foreign-callable
                  (lambda (buf size nmemb obj)
                    (let* ([segsize (* size nmemb)])
                      (put-bytevector output buf 0 segsize)
                      segsize))
                  (u8* size_t size_t scheme-object)
                  size_t)])
            (lock-object header-function)
            (curl-easy-setopt/scheme-object curl CURLOPT_HEADERDATA output)
            (curl-easy-setopt/void*
             curl
             CURLOPT_HEADERFUNCTION
             (foreign-callable-entry-point header-function))
            (values
             (lambda ()
               (let ([str (utf8->string (get-output))])
                 (filter values
                         (map split-header
                              (split-headers str)))))
             header-function))))
      (cond
       [(curl-easy-init)
        => (lambda (curl)
             (curl-easy-setopt/string curl CURLOPT_URL url)
             (when ssl? (use-ssl curl))
             (when port (curl-easy-setopt/long curl CURLOPT_PORT port))
             (case method
               [(GET) (get curl)]
               [(POST) (post curl)])
             (let-values
                 ([(get-body write-function) (write-data curl)]
                  [(get-headers header-function) (header-data curl)]
                  [(read-function) (if data (read-data curl) #f)]
                  [(slist)
                   (fold-left curl-slist-append 0
                              (map (lambda (header)
                                     (format #f "~a: ~a" (car header) (cdr header)))
                                   headers))])
               (curl-easy-setopt/void* curl
                                       CURLOPT_HTTPHEADER
                                       slist)
               (unless (= (curl-easy-perform curl) 0)
                 (error 'http "can't perform curl"))
               (let ([body (get-body)]
                     [headers (get-headers)]
                     [status (getinfo/status curl)])
                 (when data
                   (unlock-object read-function))
                 (unlock-object write-function)
                 (unlock-object header-function)
                 (curl-easy-cleanup curl)
                 (curl-slist-free-all slist)
                 (values status headers body))))]
       [else
        (error 'http "can't init curl")])))

  ;; for minimize librariy dependencies
  (define (string-index str sep start)
    (let ([len (string-length str)]
          [p?
           (cond
            [(char? sep) (lambda (c)
                           (char=? c sep))]
            [(procedure? sep) sep]
            [else (assertion-violation 'string-index
                                       "must be char or predicate"
                                       sep)])])
      (let loop ([i start])
        (cond
         [(>= i len) #f]
         [(p? (string-ref str i)) i]
         [else (loop (+ i 1))]))))

  (define (string-split str sep start count)
    (define (make-last i)
      (list (substring str i (string-length str))))
    (let rec ([i 0]
              [c 0])
      (cond
       [(and count (= count c)) (make-last i)]
       [(string-index str sep i)
        => (lambda (idx)
             (cons (substring str i idx)
                   (rec (+ idx 1) (+ c 1))))]
       [else (make-last i)])))

  (define (string-trim-left str c)
    (let ([n (string-length str)])
      (let loop ([i 0])
        (cond
         [(= i n) ""]
         [(char=? c (string-ref str i))
          (loop (+ i 1))]
         [else
          (substring str i (string-length str))]))))

  (define (split-headers str)
    (map (lambda (s)
           (string-trim-left s #\newline))
         (string-split str #\return 0 #f)))

  (define (split-header str)
    (let ([ss (string-split str #\: 0 1)])
      (if (= 2 (length ss))
          (cons (car ss)
                (string-trim-left (cadr ss) #\space))
          #f))))
