;; savings-pool.clar

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-pool-locked (err u103))
(define-constant err-pool-not-locked (err u104))
(define-constant err-no-yield (err u105))

;; Data vars
(define-data-var pool-locked bool false)
(define-data-var lock-period uint u2592000) ;; 30 days in seconds
(define-data-var lock-start-time uint u0)
(define-data-var total-deposits uint u0)
(define-data-var total-yield uint u0)

;; Maps
(define-map deposits principal uint)
(define-map withdrawals principal uint)

;; Public functions
(define-public (deposit (amount uint))
  (let ((caller tx-sender))
    (asserts! (not (var-get pool-locked)) err-pool-locked)
    (asserts! (> amount u0) err-insufficient-balance)
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (map-set deposits caller (+ (default-to u0 (map-get? deposits caller)) amount))
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (ok true)))
(define-public (lock-pool)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get pool-locked)) err-pool-locked)
    (var-set pool-locked true)
    (var-set lock-start-time block-height)
    (ok true)))

(define-public (unlock-pool)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (var-get pool-locked) err-pool-not-locked)
    (asserts! (>= block-height (+ (var-get lock-start-time) (var-get lock-period))) err-pool-locked)
    (var-set pool-locked false)
    (ok true)))

(define-public (add-yield (amount uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> amount u0) err-no-yield)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (var-set total-yield (+ (var-get total-yield) amount))
    (ok true)))
(define-public (withdraw)
  (let ((caller tx-sender)
        (user-deposit (default-to u0 (map-get? deposits caller)))
        (previous-withdrawal (default-to u0 (map-get? withdrawals caller)))
        (yield-share (/ (* user-deposit (var-get total-yield)) (var-get total-deposits)))
        (total-amount (+ user-deposit yield-share)))
    (asserts! (not (var-get pool-locked)) err-pool-locked)
    (asserts! (> user-deposit u0) err-insufficient-balance)
    (try! (as-contract (stx-transfer? total-amount tx-sender caller)))
    (map-delete deposits caller)
    (map-set withdrawals caller (+ previous-withdrawal total-amount))
    (var-set total-deposits (- (var-get total-deposits) user-deposit))
    (ok total-amount)))
;; Read-only functions
(define-read-only (get-deposit (user principal))
  (default-to u0 (map-get? deposits user)))

(define-read-only (get-pool-status)
  {locked: (var-get pool-locked),
   total-deposits: (var-get total-deposits),
   total-yield: (var-get total-yield),
   lock-start-time: (var-get lock-start-time)})

(define-read-only (get-user-yield-estimate (user principal))
  (let ((user-deposit (default-to u0 (map-get? deposits user))))
    (if (is-eq user-deposit u0)
        u0
        (/ (* user-deposit (var-get total-yield)) (var-get total-deposits)))))

        