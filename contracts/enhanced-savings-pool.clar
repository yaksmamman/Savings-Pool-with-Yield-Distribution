;; enhanced-savings-pool.clar

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-token-owner (err u101))
(define-constant err-insufficient-balance (err u102))
(define-constant err-pool-locked (err u103))
(define-constant err-pool-not-locked (err u104))
(define-constant err-no-yield (err u105))
(define-constant err-emergency-withdrawal (err u106))
(define-constant err-max-deposit-exceeded (err u107))
(define-constant err-early-withdrawal (err u108))
(define-constant err-not-eligible-for-reward (err u109))

;; Data vars
(define-data-var pool-locked bool false)
(define-data-var lock-period uint u2592000) ;; 30 days in seconds
(define-data-var lock-start-time uint u0)
(define-data-var total-deposits uint u0)
(define-data-var total-yield uint u0)
(define-data-var interest-calculation-interval uint u86400) ;; 1 day in seconds
(define-data-var last-interest-distribution uint u0)

;; Maps
(define-map deposits principal uint)
(define-map withdrawals principal uint)
(define-map rewards principal uint) ;; Optional rewards for early users
(define-map transaction-history (tuple (user principal) (tx-type uint)) uint) ;; Record of transactions
;; (define-map transactions-history principal (list 100 {user: principal, tx-type: (string-ascii 20), amount: uint}))

;; Transaction types
(define-constant tx-deposit u1)
(define-constant tx-withdraw u2)
(define-constant tx-reward u3)

;; Public functions
(define-public (deposit (amount uint))
  (let ((caller tx-sender))
    (asserts! (not (var-get pool-locked)) err-pool-locked)
    (asserts! (> amount u0) err-insufficient-balance)
    (asserts! (<= amount u10000) err-max-deposit-exceeded) ;; Example max deposit limit
    (try! (stx-transfer? amount caller (as-contract tx-sender)))
    (map-set deposits caller (+ (default-to u0 (map-get? deposits caller)) amount))
    (var-set total-deposits (+ (var-get total-deposits) amount))
    (map-set transaction-history (tuple (user caller) (tx-type tx-deposit)) amount)
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

(define-public (withdraw (amount uint))
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
    (map-set transaction-history (tuple (user caller) (tx-type tx-withdraw)) total-amount)
    (ok total-amount)))


;; Emergency Withdraw Function
(define-public (emergency-withdraw (amount uint))
  (let ((caller tx-sender)
        (user-deposit (default-to u0 (map-get? deposits caller)))
        (penalty-rate u10)) ;; Define penalty rate as 10%
    (asserts! (>= user-deposit amount) err-insufficient-balance)
    (let ((penalty (/ (* amount penalty-rate) u100)))
      (var-set total-deposits (- (var-get total-deposits) amount))
      (try! (as-contract (stx-transfer? (- amount penalty) tx-sender caller))) ;; Transfer minus penalty
      (map-set deposits caller (- user-deposit amount)) ;; Update user deposit
      (ok (- amount penalty))))) ;; Return amount after penalty
(define-public (distribute-interest)
  (let ((current-time block-height))
    (if (>= (- current-time (var-get last-interest-distribution)) (var-get interest-calculation-interval))
      (begin
        ;; Interest distribution logic here
        (var-set last-interest-distribution current-time)
        (ok true))
      (ok false))))

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


;; Helper function to check if the entry belongs to the user
(define-private (entry-belongs-to-user (entry {user: principal, tx-type: (string-ascii 20)}) (user principal))
  (is-eq (get user entry) user))

    
(define-read-only (get-rewards (user principal))
  (default-to u0 (map-get? rewards user)))

