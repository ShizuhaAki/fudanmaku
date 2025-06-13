#lang racket
;; scheduler.rkt  –  Schedule bullets into discrete frames
(provide   (all-defined-out))


(struct scheduler (current-frame table)
  #:mutable
  #:transparent)

-
(define (make-scheduler)
  (scheduler 0 (make-hash)))


(define (schedule-bullet sched b)
  (define f (scheduler-current-frame sched))
  (hash-update! (scheduler-table sched)
                f
                (lambda (lst) (cons b lst))
                '()))

(define (schedule-bullet-at sched frame b)
  (hash-update! (scheduler-table sched)
                frame
                (lambda (lst) (cons b lst))
                '()))


(define (advance-frame sched)
  (set-scheduler-current-frame! sched
                                (add1 (scheduler-current-frame sched))))


(define (get-scheduled-bullets sched frame)
  (hash-ref (scheduler-table sched) frame '()))


(define (all-scheduled-frames sched)
  (hash-keys (scheduler-table sched)))
