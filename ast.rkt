#lang racket
;  Top–level declarations
(struct pattern-def   (name params body)        #:transparent)
(struct transform-def (name params body)        #:transparent)

;  Pattern-level expression nodes
;  (Everything that can appear *inside* a pattern definition.)
(struct bullet-node  (attrs)                                #:transparent)

(struct seq-node     (iter-id start-expr end-expr body)    #:transparent)
(struct par-node     (iter-id start-expr end-expr body)    #:transparent)

(struct trans-node   (xform-name modifier subexpr)         #:transparent)

(struct wait-node    (frames-expr)                         #:transparent)
(struct repeat-node  (count-expr subexpr)                  #:transparent)
(struct loop-node    (subexpr)                             #:transparent)

(struct call-node    (pattern-name arg-exprs)              #:transparent)

;  Bullet attributes
;  (Each attribute key/value is captured *before* evaluation.)
(struct bullet-attr  (key value-expr)                      #:transparent)

;  Transform modifiers
(struct modifier-after  (n-expr)   #:transparent)
(struct modifier-every  (n-expr)   #:transparent)
(struct modifier-none   ()         #:transparent) ; default

;  Value-level expressions
;  (Arithmetic, identifiers, and helper calls that reduce to numbers.)
(struct num-lit      (n)                     #:transparent) ; 42
(struct id-ref       (sym)                   #:transparent) ; x  /  iter
(struct add-expr     (lhs rhs)               #:transparent) ; (+ … …)
(struct mul-expr     (lhs rhs)               #:transparent) ; (* … …)
(struct random-int   (upper)                 #:transparent) ; (random n)
(struct random-float (min max)               #:transparent) ; (random-float a b)
(struct callv-expr   (fn args)               #:transparent) ; user helpers
(struct sym-lit (sym) #:transparent)     ; e.g. 'position
(struct let-expr (bindings body) #:transparent) ; bindings: listof (cons sym val-expr)
(struct set-expr (name val-expr)  #:transparent)
(struct update-node (bullet-expr kv-pairs) #:transparent)
(struct if-expr (cond-expr then-expr else-expr) #:transparent)

;; Export every struct so other modules can `require "ast.rkt"`
(provide (all-defined-out))
