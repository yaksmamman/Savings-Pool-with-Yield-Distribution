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

;; Referral System
(define-map referrers principal (list 10 principal))
(define-map referral-rewards principal uint)
(define-constant referral-bonus u5) ;; 5% bonus

(define-public (add-referral (referrer principal))
  (let ((caller tx-sender))
    (asserts! (not (is-eq caller referrer)) (err u401))
    (try! (append-referral referrer caller))
    (ok true)))

(define-private (append-referral (referrer principal) (referred principal))
  (match (map-get? referrers referrer) 
    referred-list (ok (map-set referrers referrer (unwrap! (as-max-len? (append referred-list referred) u10) (err u402))))
    (ok (map-set referrers referrer (list referred)))))

(define-read-only (get-referrals (user principal))
  (default-to (list) (map-get? referrers user)))


  ;; Staking Tiers System
(define-constant bronze-tier u1000)
(define-constant silver-tier u5000) 
(define-constant gold-tier u10000)

(define-map user-tiers principal uint)

(define-read-only (get-user-tier (user principal))
(let ((deposit-amount (get-deposit user)))
  (if (>= deposit-amount gold-tier)
      u3
      (if (>= deposit-amount silver-tier)
          u2
          (if (>= deposit-amount bronze-tier)
              u1
              u0)))))
              
(define-read-only (get-tier-bonus (tier-level uint))
(if (is-eq tier-level u3)
    u10  ;; 10% bonus
    (if (is-eq tier-level u2)
        u7   ;; 7% bonus
        (if (is-eq tier-level u1)
            u5   ;; 5% bonus
            u0))))    ;; 0% bonus


;; Auto-compound Settings
(define-map auto-compound-enabled principal bool)
(define-data-var compound-interval uint u86400) ;; 24 hours in seconds

(define-public (toggle-auto-compound)
  (let ((caller tx-sender))
    (map-set auto-compound-enabled 
             caller 
             (not (default-to false (map-get? auto-compound-enabled caller))))
    (ok true)))

(define-public (execute-auto-compound)
  (let ((current-time block-height)
        (user tx-sender)
        (yield-amount (get-user-yield-estimate user)))
    (asserts! (default-to false (map-get? auto-compound-enabled user)) (err u301))
    (try! (as-contract (stx-transfer? yield-amount tx-sender user)))
    (try! (deposit yield-amount))
    (ok true)))


;; Time-Lock Bonus System
(define-map lock-end-times principal uint)
(define-constant lock-bonus-rate u15) ;; 15% bonus for time lock

(define-public (enable-time-lock (lock-duration uint))
  (let ((caller tx-sender))
    (asserts! (>= lock-duration u2592000) (err u201)) ;; Minimum 30 days
    (map-set lock-end-times caller (+ block-height lock-duration))
    (ok true)))

(define-read-only (get-lock-status (user principal))
  (let ((lock-end (default-to u0 (map-get? lock-end-times user))))
    {locked: (> lock-end block-height),
     end-time: lock-end}))


;; Add these maps
(define-map referral-chain 
  principal 
  {referrer: (optional principal), 
   rewards: uint})

(define-public (refer-user (new-user principal))
  (let ((referrer tx-sender))
    (asserts! (not (is-eq new-user referrer)) (err u401))
    (map-set referral-chain 
             new-user 
             {referrer: (some referrer), 
              rewards: u0})
    (ok true)))



;; Add achievement tracking
(define-map user-achievements 
  principal 
  {deposit-streak: uint,
   total-deposited: uint,
   referrals-made: uint})

(define-read-only (get-user-achievements (user principal))
  (default-to 
    {deposit-streak: u0,
     total-deposited: u0,
     referrals-made: u0}
    (map-get? user-achievements user)))


