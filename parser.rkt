#lang racket
;; parser.rkt  –  Translate raw DSL S-expressions into ast.rkt nodes

(require racket/match
         "ast.rkt")

(provide parse-program)

;; Entry point
(define (parse-program forms)
  (for/list ([f forms])
    (parse-top f)))

;; Top-level declarations
(define (parse-top sexp)
  (match sexp
    [(list 'define-pattern (and name (not (? keyword?))) (list params ...) body)
     (pattern-def name params (parse-expr body))]

    [(list 'define-transform (and tname (not (? keyword?))) (list params ...) tbody)
     (transform-def tname params (parse-expr tbody))]

    [_ (error 'parse-top "unknown top-level form: ~s" sexp)]))

;; Pattern-level expressions
(define (parse-expr e)
  (match e

    ;; (let ((x 12) (y 34)) body)
    [`(let ,binds ,body)
     (let-expr
      (map (lambda (b)
             (match b
               [(list nm v) (cons nm (parse-val v))]
               [_ (error 'parse-expr "bad let binding: ~a" b)]))
           binds)
      (parse-expr body))]

    ;; (set! x (+ x 1))
    [`(set! ,name ,v)
     (set-expr name (parse-val v))]
    [(cons 'update-bullet! (cons b args))
     ;; b    is the bullet expression
     ;; args is a proper list of keyword/value pairs
     (define kvs
       (let loop ([xs args] [acc '()])
         (cond
           [(null? xs)
            (reverse acc)]

           [(and (keyword? (first xs))
                 (pair?   (rest xs)))
            (let ([key   (first xs)]
                  [val-expr (second xs)])
              (loop (cddr xs)
                    (cons (cons (string->symbol
                                 (keyword->string key))
                                (parse-val val-expr))
                          acc)))]

           [else
            (error 'parse-expr
                   "bad update-bullet! syntax (expected #:key val ...), got: ~s"
                   xs)])))
     (update-node (parse-val b) kvs)]


    [(cons 'bullet attrs)
     (bullet-node (parse-attrs attrs))]





    [`(sequential ,iter ,start ,'-> ,end ,bodys ...)
     (seq-node iter
               (parse-val start)
               (parse-val end)
               (map parse-expr bodys))]   ; 保存列表


    [`(parallel ,iter ,start ,'-> ,end ,bodys ...)
     (par-node iter
               (parse-val start)
               (parse-val end)
               (map parse-expr bodys))]

    [`(transform ,xform ,mod ,sub)
     (trans-node xform (parse-mod mod) (parse-expr sub))]

    [`(wait ,n)         (wait-node   (parse-val n))]
    [`(repeat ,k ,sub)  (repeat-node (parse-val k) (parse-expr sub))]
    [`(loop ,sub)       (loop-node   (parse-expr sub))]

    ;; pattern calls (e.g., (ring 1 2 3))
    [(list* (and sym (not (? keyword?))) args)
     (call-node sym (map parse-val args))]


    [_ (error 'parse-expr "bad pattern expression: ~s" e)]))

;; Bullet attributes
(define (parse-attrs xs)
  (cond
    [(null? xs) '()]

    [(and (keyword? (first xs))
          (pair? (rest xs)))
     (let ([key (string->symbol (keyword->string (first xs)))]
           [val (second xs)])
       (cons (bullet-attr key (parse-val val))
             (parse-attrs (cddr xs))))]

    [else
     (error 'parse-attrs "attribute syntax error: ~s" xs)]))


;; Transform modifiers
(define (parse-mod mod-sexp)
  (match mod-sexp
    [`(after-frame ,n)  (modifier-after (parse-val n))]
    [`(every-frame ,n)  (modifier-every (parse-val n))]
    [_                  (modifier-none)]))

;; Value expressions
(define (parse-val v)
  (match v
    [(? number?)   (num-lit v)]
    [(? symbol?)   (id-ref  v)]

    [`(+ ,a ,b)    (add-expr (parse-val a) (parse-val b))]
    [`(* ,a ,b)    (mul-expr (parse-val a) (parse-val b))]

    [`(random ,n)              (random-int   (parse-val n))]
    [`(random-float ,lo ,hi)   (random-float (parse-val lo) (parse-val hi))]


    ;; in parser.rkt, inside parse-val:
    [(list 'if cond then else)
     (if-expr (parse-val cond)
              (parse-val then)
              (parse-val else))]

    [(list 'quote (? symbol? s)) (sym-lit s)]
    ;; allow lists as data (e.g. (list x y))
    [(list* fun args)
     (callv-expr fun (map parse-val args))]


    [_ (error 'parse-val "cannot parse value expr: ~s" v)]))
