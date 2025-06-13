#lang racket
;; This is the runtime def, not the parse time def in ast.rkt
(struct bullet (attrs) #:transparent)

(define next-id 0)                       ; ★ NEW
(define (make-bullet h)                  ; ★ NEW
  (unless (hash-has-key? h 'uid)
    ;(print (list "Warning: Bullet without uid, assigning " (add1 next-id)))
    (set! next-id (add1 next-id))
    (hash-set! h 'uid next-id))
  (bullet h))

(provide make-bullet)                    ; ★ NEW


(provide (all-defined-out))
