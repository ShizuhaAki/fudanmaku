#lang racket
;; evaluator.rkt  –– Turn AST into an FTL schedule: frame → list of bullets

(require racket/match
         racket/list
         "ast.rkt"
         "env.rkt"
         "scheduler.rkt"
         "bullet.rkt")

(provide evaluate-program)

;; ---------------------------------------------------------------------
;;  Global timeline
;; ---------------------------------------------------------------------
(define MAX-FRAMES 3600)
(define (valid-frame? f) (< f MAX-FRAMES))

;; ---------------------------------------------------------------------
;;  Entry point
;; ---------------------------------------------------------------------
(define (evaluate-program decls)
  (define env   (build-env decls))
  (define sched (make-scheduler))
  (define top   (lookup-pattern env 'top))
  (eval-pattern top '() env sched)
  (scheduler-table sched))

;; Build the env
(define (build-env decls)
  (foldl (lambda (d e)
           (match d
             [(pattern-def . _)    (extend-pattern   e d)]
             [(transform-def . _)  (extend-transform e d)]
             [_ e]))
         (make-env)
         decls))
;; ensure-uid : bullet produced-by-transform × bullet original → bullet'
;;
;; If the transform product already has a uid → leave it.
;; Otherwise copy the uid from the original bullet.
;;
(define (ensure-uid product src)
  (define h (hash-copy (bullet-attrs product)))
  (unless (hash-has-key? h 'uid)
    (hash-set! h 'uid (hash-ref (bullet-attrs src) 'uid)))
  (make-bullet h))            ; funnel through make-bullet once

;; ---------------------------------------------------------------------
;;  Pattern evaluation
;; ---------------------------------------------------------------------
(define (eval-pattern pd args env sched)
  (define loc (make-hash))
  (for ([n (pattern-def-params pd)]
        [v args])
    (hash-set! loc n v))
  (eval-expr (pattern-def-body pd) loc env sched))

;; ---------------------------------------------------------------------
;;  Core expression evaluator
;; ---------------------------------------------------------------------
(define (eval-expr expr loc env sched)
  (match expr
    ;; bullet ------------------------------------------------------------------
    [(bullet-node attrs)
     (schedule-bullet sched
                      (make-bullet (attrs->hash attrs loc env)))]

    ;; sequential --------------------------------------------------------------
    [(seq-node i lo hi bodies)
     (for ([v (in-range (eval-val lo loc env)
                        (add1 (eval-val hi loc env)))])
       (hash-set! loc i v)
       (for ([b bodies]) (eval-expr b loc env sched))
       (advance-frame sched))]

    ;; parallel ----------------------------------------------------------------
    [(par-node i lo hi bodies)
     (define base  (scheduler-current-frame sched))
     (define last# base)
     (for ([v (in-range (eval-val lo loc env)
                        (add1 (eval-val hi loc env)))])
       (hash-set! loc i v)
       (define tmp (make-scheduler))
       (set-scheduler-current-frame! tmp base)
       (for ([b bodies]) (eval-expr b loc env tmp))
       (for ([f (all-scheduled-frames tmp)])
         (for ([blt (get-scheduled-bullets tmp f)])
           (schedule-bullet-at sched f blt)))
       (define branch-max (if (null? (all-scheduled-frames tmp))
                              base
                              (apply max (all-scheduled-frames tmp))))
       (set! last# (max last# branch-max)))
     (set-scheduler-current-frame! sched (+ last# 1))]

    ;; wait --------------------------------------------------------------------
    [(wait-node n)
     (set-scheduler-current-frame! sched
                                   (+ (scheduler-current-frame sched)
                                      (eval-val n loc env)))]

    ;; repeat / loop -----------------------------------------------------------
    [(repeat-node k body)
     (for ([j (in-range (eval-val k loc env))])
       (eval-expr body loc env sched))]

    [(loop-node body)
     (for ([j (in-range 1000)]) (eval-expr body loc env sched))]

    ;; pattern call ------------------------------------------------------------
    [(call-node name args)
     (define pd (lookup-pattern env name))
     (eval-pattern pd (map (λ (x) (eval-val x loc env)) args) env sched)]

    ;; transform ---------------------------------------------------------------
    [(trans-node xform mod sub)
     (eval-transform xform mod sub loc env sched)]

    ;; let / set ---------------------------------------------------------------
    [(let-expr binds body)
     (define loc2 (hash-copy loc))
     (for ([b binds])
       (hash-set! loc2 (car b) (eval-val (cdr b) loc env)))
     (eval-expr body loc2 env sched)]

    [(set-expr nm ve)
     (hash-set! loc nm (eval-val ve loc env))]

    ;; ─────────────────────────────────────────────────────────────────────
    ;; In your eval-expr, replace the old update-node clause with this:
    ;; (update-node bullet-expr kv-pairs)
    ;; ─────────────────────────────────────────────────────────────────────
    [(update-node b-expr kvs)
     ;; 1) Evaluate the bullet expression to get the source bullet
     (define src (eval-val b-expr loc env))
     (unless (bullet? src)
       (error 'eval-expr "update-bullet! expect a bullet, got ~a" src))

     ;; 2) Build a fresh mutable hash and copy all existing attrs
     (define old-h (bullet-attrs src))
     (define new-h (make-hash))
     (for ([k (hash-keys old-h)])
       (hash-set! new-h k (hash-ref old-h k)))

     ;; 3) Apply each key/value update
     (for ([kv kvs])
       (define key   (car kv))
       (define vexpr (cdr kv))
       (hash-set! new-h
                  key
                  (eval-val vexpr loc env)))

     ;; 4) Ensure uid survives (just in case)
     (unless (hash-has-key? new-h 'uid)
       (hash-set! new-h 'uid (hash-ref old-h 'uid)))

     ;; 5) Wrap in a bullet (will not reassign uid)
     (make-bullet new-h)]


    [else (error 'eval-expr "Unhandled AST node: ~a" expr)]))

;; ---------------------------------------------------------------------
;;  Value evaluator
;; ---------------------------------------------------------------------
(define (eval-val ve loc env)
  (match ve
    [(num-lit n)            n]
    [(id-ref s)             (hash-ref loc s
                                      (λ () (error 'eval-val "unbound ~a" s)))]
    [(add-expr l r)         (+ (eval-val l loc env) (eval-val r loc env))]
    [(mul-expr l r)         (* (eval-val l loc env) (eval-val r loc env))]
    [(random-int u)         (random (max 0 (eval-val u loc env)))]
    [(random-float lo hi)   (define a (eval-val lo loc env))
                            (define b (eval-val hi loc env))
                            (+ a (* (random) (- b a)))]
    [(sym-lit s)            s]
    ;; in evaluator.rkt, inside eval-val:
    [(if-expr cond-e then-e else-e)
     (if (eval-val cond-e loc env)
         (eval-val then-e loc env)
         (eval-val else-e loc env))]

    [(callv-expr fn args)   (apply (resolve-fn fn)
                                   (map (λ (x) (eval-val x loc env)) args))]
    [else (error 'eval-val "Bad value expr: ~a" ve)]))

;; primitive functions
(define known-fns
  (hash '+ + '- - '* * '/ /
        'cos  cos          'sin  sin
        'cosd (λ (d) (cos (* pi (/ d 180.0))))
        'sind (λ (d) (sin (* pi (/ d 180.0))))
        'even? even? 'odd? odd?
        'add1 add1 'sub1 sub1
        'floor floor       'ceiling ceiling
        'modulo modulo     'list list
        'quote  (λ (x) x)
        'get-attr
        (λ (b k)
          (hash-ref (bullet-attrs b) k
                    (λ () (error 'get-attr "attribute ~a missing" k))))))

(define (resolve-fn s)
  (hash-ref known-fns s
            (λ () (error 'resolve-fn "No such function: ~a" s))))
;; apply-kvs : hash → (listof (cons sym val)) → hash'
(define (apply-kvs h kvs)
  (for/fold ([newh (hash-copy h)]) ([kv kvs])
    (hash-set newh (car kv) (cdr kv))))

;; ---------------------------------------------------------------------
;;  Bullet helpers
;; ---------------------------------------------------------------------
(define (attrs->hash attrs loc env)
  (define h (make-hash))
  (for ([a attrs])
    (hash-set! h
               (bullet-attr-key a)
               (eval-val (bullet-attr-value-expr a) loc env)))
  h)

;; ---------------------------------------------------------------------
;;  Transform evaluation (corrected)
;; ---------------------------------------------------------------------
;; ─────────────────────────────────────────────────────────────────────
;; eval-transform : Symbol × Modifier × Expr × Loc × Env × Scheduler → void
;;
;; For every bullet B emitted by SUB at frame F₀:
;;   • Let D be the delay determined by the modifier.
;;   • Advance B forward by D frames (using its current speed/dir) → Bₜ
;;   • Apply the transform definition to Bₜ  →  zero/one/many products
;;   • Schedule each product **unchanged** at frame F₀ + D
;;
;; The *original* bullet is NOT rescheduled here—it was already scheduled
;; by the sub-pattern and continues moving until the transform frame.
;; ─────────────────────────────────────────────────────────────────────
(define (eval-transform name mod sub loc env sched)
  (define now (scheduler-current-frame sched))

  ;; Step 1 – run the sub-pattern in a temp scheduler to capture bullets
  (define tmp (make-scheduler))
  (set-scheduler-current-frame! tmp now)
  (eval-expr sub loc env tmp)

  ;; Step 2 – transform definition
  (define xdef (lookup-transform env name))

  ;; For each bullet B at frame F₀ …
  (for* ([f  (in-list (sort (all-scheduled-frames tmp) <))]
         [b  (in-list (get-scheduled-bullets tmp f))])
    (schedule-bullet-at sched f b)
    (define rel (- f now))   ; delay of original emission relative to NOW

    (define (apply-and-schedule delay)
      (define tgt (+ now delay))               ; absolute target frame
      (when (< tgt MAX-FRAMES)                 ; clamp to run length
        ;; snapshot bullet state at transform time
        (define bt  (advance-bullet b delay))
        ;; run the transform body
        (define products (let ([lst (apply-transform xdef bt env)])
                           (if (null? lst) (list bt) lst)))
        ;; schedule each product *as-is* at frame tgt
        (for ([p products])
          (schedule-bullet-at sched tgt p))))

    ;; ─── Modifier dispatch ───────────────────────────────────────────
    (match mod
      ;; (after-frame n)
      [(modifier-after n-expr)
       (define d (+ rel (eval-val n-expr loc env)))
       (apply-and-schedule d)]

      ;; (every-frame n)
      [(modifier-every n-expr)
       (define period (eval-val n-expr loc env))
       ;; `prev` starts as the original bullet `b`
       (let loop ([time (+ now rel)]  ; first target frame
                  [prev b])            ; bullet state at last transform
         (when (< time MAX-FRAMES)
           ;; 1) Advance the bullet forward by `period`
           (define bt (advance-bullet prev period))
           ;; 2) Apply the transform to that advanced bullet
           (define prods (apply-transform xdef bt env))
           ;; 3) Pick the first produced bullet (or fall back to bt)
           (define next (if (null? prods) bt (first prods)))
           ;; 4) Schedule it at the target frame
           (schedule-bullet-at sched time next)
           ;; 5) Recurse for the next period
           (loop (+ time period) next)))]

      ;; no modifier → transform happens immediately (delay = rel)
      [(modifier-none)
       (apply-and-schedule rel)])))


;; apply-transform → listof bullet
;; return list of bullets produced by the transform body
(define (apply-transform xdef src env)
  (define param (first (transform-def-params xdef)))
  (define loc   (make-hash (list (cons param src))))
  (define result (eval-expr (transform-def-body xdef) loc env (make-scheduler)))
  ;; normalize to list
  (cond [(bullet? result)      (list result)]
        [(and (list? result)
              (andmap bullet? result)) result]
        [else '()]))  ; nothing produced


;; ---------------------------------------------------------------------
;;  Bullet physics helpers
;; ---------------------------------------------------------------------
(define (deg->rad d) (* pi (/ d 180.0)))

(define (advance-bullet b n)
  (define h   (hash-copy (bullet-attrs b)))
  (define dir (hash-ref h 'direction 0))
  (define spd (hash-ref h 'speed     0))
  (define pos (hash-ref h 'position  '(0 0)))
  (define dx  (* spd n (cos (deg->rad dir))))
  (define dy  (* spd n (sin (deg->rad dir))))
  (hash-set! h 'position
             (list (+ (first pos) dx) (+ (second pos) dy)))
  (make-bullet h))
