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
(define-map user-milestones principal (list 5 uint))
(define-constant milestone-1 u1000)
(define-constant milestone-2 u5000)
(define-constant milestone-3 u10000)
(define-constant milestone-reward-1 u50)
(define-constant milestone-reward-2 u150)
(define-constant milestone-reward-3 u300)

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



;; Add these variables
(define-data-var contract-paused bool false)
(define-constant err-contract-paused (err u500))

;; Add admin function
(define-public (toggle-contract-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused (not (var-get contract-paused)))
    (ok true)))

;; Add to all public functions
(asserts! (not (var-get contract-paused)) err-contract-paused)


;; Add these variables
(define-data-var base-interest-rate uint u500) ;; 5% base rate
(define-data-var utilization-multiplier uint u100)
(define-map interest-rate-history uint uint)

(define-public (update-interest-rate)
  (let ((utilization-rate (/ (* (var-get total-deposits) u10000) u1000000)))
    (var-set base-interest-rate 
      (+ u500 (* utilization-rate (var-get utilization-multiplier))))
    (ok true)))


(define-map vote-locked-deposits
  principal
  {amount: uint, unlock-height: uint, voting-power: uint})

(define-public (vote-lock (amount uint) (lock-duration uint))
  (let ((voting-power (* amount (/ lock-duration u2592000))))
    (try! (deposit amount))
    (map-set vote-locked-deposits tx-sender
      {amount: amount,
       unlock-height: (+ block-height lock-duration),
       voting-power: voting-power})
    (ok voting-power)))



(define-map savings-goals
  principal
  {target: uint, deadline: uint, current: uint})

(define-public (set-savings-goal (target uint) (deadline uint))
  (begin
    (map-set savings-goals tx-sender
      {target: target,
       deadline: (+ block-height deadline),
       current: (get-deposit tx-sender)})
    (ok true)))

(define-read-only (get-goal-progress (user principal))
  (match (map-get? savings-goals user)
    goal {progress: (/ (* (get current goal) u100) (get target goal)),
          remaining: (- (get target goal) (get current goal))}
    {progress: u0, remaining: u0}))



(define-map loyalty-points principal uint)
(define-map loyalty-tiers
  uint 
  {min-points: uint, bonus-rate: uint})

(define-public (calculate-loyalty-points (user principal))
  (let ((deposit-amount (get-deposit user))
        (lock-duration (get-lock-duration user))
        (points (* deposit-amount (/ lock-duration u2592000))))
    (map-set loyalty-points user 
      (+ (default-to u0 (map-get? loyalty-points user)) points))
    (ok points)))


(define-read-only (get-lock-duration (user principal))
  (let ((lock-end (default-to u0 (map-get? lock-end-times user))))
    (if (> lock-end block-height)
        (- lock-end block-height)
        u0)))



(define-map referral-multiplier principal uint)
(define-constant base-multiplier u100)
(define-constant multiplier-increment u10)

(define-public (increase-referral-multiplier)
  (let ((current-multiplier (default-to base-multiplier (map-get? referral-multiplier tx-sender))))
    (map-set referral-multiplier tx-sender (+ current-multiplier multiplier-increment))
    (ok true)))


(define-map deposit-streak principal uint)
(define-constant streak-bonus u5) ;; 0.5% bonus per streak

(define-public (update-streak)
  (let ((current-streak (default-to u0 (map-get? deposit-streak tx-sender))))
    (map-set deposit-streak tx-sender (+ current-streak u1))
    (ok true)))


(define-map community-pool-share principal uint)
(define-data-var total-community-pool uint u0)

(define-public (join-community-pool (amount uint))
  (begin
    (try! (deposit amount))
    (map-set community-pool-share tx-sender amount)
    (var-set total-community-pool (+ (var-get total-community-pool) amount))
    (ok true)))



(define-map savings-challenge 
  principal 
  {target: uint, deadline: uint, completed: bool})

(define-public (start-challenge (target uint) (duration uint))
  (begin
    (map-set savings-challenge tx-sender
      {target: target,
       deadline: (+ block-height duration),
       completed: false})
    (ok true)))




(define-map interest-tiers principal uint)
(define-constant tier1-rate u500) ;; 5%
(define-constant tier2-rate u700) ;; 7%
(define-constant tier3-rate u1000) ;; 10%

(define-public (calculate-tier-interest)
  (let ((deposit-amount (get-deposit tx-sender)))
    (map-set interest-tiers tx-sender
      (if (>= deposit-amount u10000) 
          tier3-rate
          (if (>= deposit-amount u5000)
              tier2-rate
              tier1-rate)))
    (ok true)))



(define-map emergency-contacts principal principal)
(define-map contact-approval principal bool)

(define-public (set-emergency-contact (contact principal))
  (begin
    (map-set emergency-contacts tx-sender contact)
    (map-set contact-approval contact false)
    (ok true)))



(define-map withdrawal-schedule 
  principal 
  {amount: uint, date: uint, recurring: bool})

(define-public (schedule-withdrawal (amount uint) (future-block uint))
  (begin
    (map-set withdrawal-schedule tx-sender
      {amount: amount,
       date: future-block,
       recurring: false})
    (ok true)))



(define-map savings-goals-rewards
  principal
  {goal: uint, achieved: bool, reward: uint})

(define-public (set-savings-goal-with-reward (goal-amount uint))
  (begin
    (map-set savings-goals-rewards tx-sender
      {goal: goal-amount,
       achieved: false,
       reward: (/ goal-amount u20)}) ;; 5% reward
    (ok true)))



(define-map seasonal-bonus-periods 
  uint 
  {start-block: uint, end-block: uint, bonus-rate: uint})
(define-data-var current-season uint u1)

(define-public (activate-seasonal-bonus (duration uint) (bonus uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set seasonal-bonus-periods (var-get current-season)
      {start-block: block-height,
       end-block: (+ block-height duration),
       bonus-rate: bonus})
    (var-set current-season (+ (var-get current-season) u1))
    (ok true)))



(define-map vip-status principal bool)
(define-map vip-benefits principal 
  {bonus-rate: uint, 
   priority-withdrawal: bool,
   custom-lock-periods: bool})

(define-public (activate-vip-status)
  (let ((user-deposit (get-deposit tx-sender)))
    (asserts! (>= user-deposit u50000) (err u401))
    (map-set vip-status tx-sender true)
    (map-set vip-benefits tx-sender
      {bonus-rate: u200,
       priority-withdrawal: true,
       custom-lock-periods: true})
    (ok true)))



(define-map deposit-strategy
  principal
  {target-yield: uint,
   auto-rebalance: bool,
   risk-level: uint})

(define-public (set-deposit-strategy (target-yield uint) (risk-level uint))
  (begin
    (map-set deposit-strategy tx-sender
      {target-yield: target-yield,
       auto-rebalance: true,
       risk-level: risk-level})
    (ok true)))



(define-map user-badges
  principal
  (list 10 {badge-id: uint, earned-at: uint, bonus-points: uint}))
(define-constant savings-master-badge u1)
(define-constant quick-starter-badge u2)
(define-constant loyal-saver-badge u3)

(define-public (award-badge (badge-id uint))
  (let ((current-badges (default-to (list) (map-get? user-badges tx-sender))))
    (map-set user-badges tx-sender
      (unwrap! (as-max-len? 
        (append current-badges 
          {badge-id: badge-id,
           earned-at: block-height,
           bonus-points: u100}) u10)
        (err u403)))
    (ok true)))





(define-private (award-milestone-reward (amount uint))
  (begin
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (ok amount)))

(define-public (check-milestones)
  (let ((deposit-amount (get-deposit tx-sender)))
    (if (>= deposit-amount milestone-3)
        (try! (award-milestone-reward milestone-reward-3))
        (if (>= deposit-amount milestone-2)
            (try! (award-milestone-reward milestone-reward-2))
            (if (>= deposit-amount milestone-1)
                (try! (award-milestone-reward milestone-reward-1))
                (try! (award-milestone-reward u0)))))
    (ok true)))



(define-map savings-groups 
  uint 
  {members: (list 10 principal),
   group-target: uint,
   group-balance: uint})
(define-data-var group-counter uint u0)

(define-public (create-savings-group (target uint))
  (let ((group-id (+ (var-get group-counter) u1)))
    (var-set group-counter group-id)
    (map-set savings-groups group-id
      {members: (list tx-sender),
       group-target: target,
       group-balance: u0})
    (ok group-id)))


(define-map user-notifications 
  principal 
  (list 50 {type: uint, message: (string-ascii 50), timestamp: uint}))
(define-constant notification-deposit u1)
(define-constant notification-goal u2)
(define-constant notification-reward u3)

(define-public (add-notification (type uint) (message (string-ascii 50)))
  (let ((current-notifications (default-to (list) (map-get? user-notifications tx-sender))))
    (map-set user-notifications tx-sender
      (unwrap! (as-max-len? 
        (append current-notifications 
          {type: type,
           message: message,
           timestamp: block-height}) u50)
        (err u404)))
    (ok true)))

(define-map challenge-participants principal uint)
(define-data-var challenge-start-time uint u0)
(define-data-var challenge-duration uint u2592000) ;; 30 days
(define-data-var challenge-prize-pool uint u0)

(define-public (join-savings-challenge (stake uint))
  (begin
    (try! (deposit stake))
    (map-set challenge-participants tx-sender stake)
    (var-set challenge-prize-pool (+ (var-get challenge-prize-pool) stake))
    (ok true)))

(define-map savings-achievements 
  principal 
  {goals-completed: uint,
   nft-earned: (list 10 uint)})
(define-constant achievement-nft-1 u1)
(define-constant achievement-nft-2 u2)
(define-constant achievement-nft-3 u3)

(define-public (mint-achievement-nft (achievement-id uint))
  (let ((current-achievements (default-to 
         {goals-completed: u0, nft-earned: (list)} 
         (map-get? savings-achievements tx-sender))))
    (map-set savings-achievements tx-sender
      {goals-completed: (+ (get goals-completed current-achievements) u1),
       nft-earned: (unwrap! (as-max-len? 
                    (append (get nft-earned current-achievements) achievement-id)
                    u10)
                    (err u405))})
    (ok true)))




(define-map withdrawal-preferences
  principal
  {schedule: uint,
   split-amount: uint,
   auto-reinvest: bool})

(define-public (set-withdrawal-preferences 
    (schedule uint) 
    (split-amount uint) 
    (auto-reinvest bool))
  (begin
    (map-set withdrawal-preferences tx-sender
      {schedule: schedule,
       split-amount: split-amount,
       auto-reinvest: auto-reinvest})
    (ok true)))


(define-map risk-profiles
  principal
  {risk-score: uint,
   max-deposit: uint,
   withdrawal-limit: uint})
(define-constant low-risk u1)
(define-constant medium-risk u2)
(define-constant high-risk u3)

(define-public (set-risk-profile (risk-level uint))
  (begin
    (map-set risk-profiles tx-sender
      {risk-score: risk-level,
       max-deposit: (if (is-eq risk-level low-risk)
                       u5000
                       (if (is-eq risk-level medium-risk)
                           u20000
                           u50000)),
       withdrawal-limit: (if (is-eq risk-level low-risk)
                           u1000
                           (if (is-eq risk-level medium-risk)
                               u5000
                               u10000))})
    (ok true)))
