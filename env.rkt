#lang racket
;; env.rkt  –  Environment for storing user‐defined patterns and transforms

(require "ast.rkt")

(provide Env
         make-env
         extend-pattern
         extend-transform
         lookup-pattern
         lookup-transform)

(struct Env (patterns transforms) #:transparent)

(define (make-env)
  (Env (make-hash)        ; initially: no patterns
       (make-hash)))      ; initially: no transforms

(define (extend-pattern env pat-def)
  (hash-set! (Env-patterns env)
             (pattern-def-name pat-def)
             pat-def)
  env)


(define (extend-transform env xform-def)
  (hash-set! (Env-transforms env)
             (transform-def-name xform-def)
             xform-def)
  env)


(define (lookup-pattern env pat-name)
    (hash-ref (Env-patterns env) pat-name
                        (lambda ()
                            (error 'lookup-pattern
                                         (format "Pattern not found: ~a. Available patterns: ~a"
                                                         pat-name
                                                         (hash-keys (Env-patterns env)))))))


(define (lookup-transform env xform-name)
  (hash-ref (Env-transforms env) xform-name
            (lambda ()
              (error 'lookup-transform
                     (format "Transform not found: ~a" xform-name)))))
