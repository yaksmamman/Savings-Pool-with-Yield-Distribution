;; smart-insurance-pool.clar
;; Community-driven insurance system for savings pool protection

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u200))
(define-constant err-insufficient-balance (err u201))
(define-constant err-policy-not-found (err u202))
(define-constant err-claim-not-eligible (err u203))
(define-constant err-invalid-coverage-amount (err u204))
(define-constant err-policy-expired (err u205))
(define-constant err-claim-already-processed (err u206))
(define-constant err-insufficient-insurance-fund (err u207))
(define-constant err-premium-payment-failed (err u208))
(define-constant err-invalid-policy-duration (err u209))
(define-constant err-coverage-limit-exceeded (err u210))

;; Data variables
(define-data-var total-insurance-fund uint u0)
(define-data-var total-premiums-collected uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var policy-counter uint u0)
(define-data-var claim-counter uint u0)
(define-data-var max-coverage-percentage uint u80) ;; 80% of deposit
(define-data-var base-premium-rate uint u3) ;; 3% annual premium rate
(define-data-var minimum-policy-duration uint u2592000) ;; 30 days
(define-data-var maximum-policy-duration uint u31104000) ;; 1 year
(define-data-var claims-processing-fee uint u50) ;; Fixed processing fee

;; Insurance policy structure
(define-map insurance-policies
  uint
  {policyholder: principal,
   coverage-amount: uint,
   premium-paid: uint,
   start-block: uint,
   end-block: uint,
   active: bool,
   deposit-snapshot: uint})

;; Claims tracking
(define-map insurance-claims
  uint
  {policy-id: uint,
   claimant: principal,
   claim-amount: uint,
   claim-reason: (string-ascii 50),
   submitted-block: uint,
   processed: bool,
   approved: bool,
   payout-amount: uint})

;; User policy tracking
(define-map user-policies
  principal
  (list 5 uint))

;; Premium payment history
(define-map premium-payments
  {policy-id: uint, payment-round: uint}
  {amount: uint, payment-block: uint})

;; Risk assessment factors
(define-map risk-factors
  principal
  {deposit-history-score: uint,
   claim-history-score: uint,
   total-risk-multiplier: uint})

;; Insurance fund contributions from yield farming
(define-data-var fund-contribution-rate uint u10) ;; 10% of farming yields
(define-data-var emergency-reserve-ratio uint u20) ;; 20% emergency reserve

;; Public functions

;; Purchase insurance policy
(define-public (purchase-insurance-policy (coverage-amount uint) (policy-duration uint))
  (let ((caller tx-sender)
        (policy-id (+ (var-get policy-counter) u1))
        (annual-premium (calculate-annual-premium coverage-amount caller))
        (duration-premium (/ (* annual-premium policy-duration) u31536000))
        (current-policies (default-to (list) (map-get? user-policies caller))))
    
    (asserts! (>= policy-duration (var-get minimum-policy-duration)) err-invalid-policy-duration)
    (asserts! (<= policy-duration (var-get maximum-policy-duration)) err-invalid-policy-duration)
    (asserts! (> coverage-amount u0) err-invalid-coverage-amount)
    (asserts! (< (len current-policies) u5) err-coverage-limit-exceeded)
    
    ;; Transfer premium payment
    (try! (stx-transfer? duration-premium caller (as-contract tx-sender)))
    
    ;; Create policy
    (map-set insurance-policies policy-id
      {policyholder: caller,
       coverage-amount: coverage-amount,
       premium-paid: duration-premium,
       start-block: block-height,
       end-block: (+ block-height policy-duration),
       active: true,
       deposit-snapshot: coverage-amount})
    
    ;; Update user policies list
    (map-set user-policies caller
      (unwrap! (as-max-len? (append current-policies policy-id) u5)
               err-coverage-limit-exceeded))
    
    ;; Update counters and fund
    (var-set policy-counter policy-id)
    (var-set total-premiums-collected (+ (var-get total-premiums-collected) duration-premium))
    (var-set total-insurance-fund (+ (var-get total-insurance-fund) duration-premium))
    
    ;; Record premium payment
    (map-set premium-payments {policy-id: policy-id, payment-round: u1}
      {amount: duration-premium, payment-block: block-height})
    
    (ok policy-id)))

;; Submit insurance claim
(define-public (submit-insurance-claim (policy-id uint) (claim-amount uint) (claim-reason (string-ascii 50)))
  (let ((caller tx-sender)
        (policy (unwrap! (map-get? insurance-policies policy-id) err-policy-not-found))
        (claim-id (+ (var-get claim-counter) u1)))
    
    (asserts! (is-eq (get policyholder policy) caller) err-claim-not-eligible)
    (asserts! (get active policy) err-policy-expired)
    (asserts! (<= block-height (get end-block policy)) err-policy-expired)
    (asserts! (<= claim-amount (get coverage-amount policy)) err-invalid-coverage-amount)
    (asserts! (>= (var-get total-insurance-fund) claim-amount) err-insufficient-insurance-fund)
    
    ;; Create claim record
    (map-set insurance-claims claim-id
      {policy-id: policy-id,
       claimant: caller,
       claim-amount: claim-amount,
       claim-reason: claim-reason,
       submitted-block: block-height,
       processed: false,
       approved: false,
       payout-amount: u0})
    
    (var-set claim-counter claim-id)
    (ok claim-id)))

;; Process insurance claim (owner only)
(define-public (process-insurance-claim (claim-id uint) (approved bool))
  (let ((claim (unwrap! (map-get? insurance-claims claim-id) err-claim-not-eligible))
        (policy (unwrap! (map-get? insurance-policies (get policy-id claim)) err-policy-not-found))
        (processing-fee (var-get claims-processing-fee))
        (net-payout (if approved
                       (- (get claim-amount claim) processing-fee)
                       u0)))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (get processed claim)) err-claim-already-processed)
    
    (if approved
      (begin
        ;; Process approved claim
        (try! (as-contract (stx-transfer? net-payout tx-sender (get claimant claim))))
        (var-set total-claims-paid (+ (var-get total-claims-paid) net-payout))
        (var-set total-insurance-fund (- (var-get total-insurance-fund) (get claim-amount claim))))
      true)
    
    ;; Update claim record
    (map-set insurance-claims claim-id
      (merge claim 
        {processed: true,
         approved: approved,
         payout-amount: net-payout}))
    
    (ok net-payout)))

;; Renew insurance policy
(define-public (renew-insurance-policy (policy-id uint) (additional-duration uint))
  (let ((caller tx-sender)
        (policy (unwrap! (map-get? insurance-policies policy-id) err-policy-not-found))
        (renewal-premium (calculate-renewal-premium policy-id additional-duration)))
    
    (asserts! (is-eq (get policyholder policy) caller) err-claim-not-eligible)
    (asserts! (get active policy) err-policy-expired)
    (asserts! (>= additional-duration (var-get minimum-policy-duration)) err-invalid-policy-duration)
    
    ;; Pay renewal premium
    (try! (stx-transfer? renewal-premium caller (as-contract tx-sender)))
    
    ;; Update policy
    (map-set insurance-policies policy-id
      (merge policy 
        {end-block: (+ (get end-block policy) additional-duration),
         premium-paid: (+ (get premium-paid policy) renewal-premium)}))
    
    ;; Update fund
    (var-set total-premiums-collected (+ (var-get total-premiums-collected) renewal-premium))
    (var-set total-insurance-fund (+ (var-get total-insurance-fund) renewal-premium))
    
    (ok true)))

;; Add funds to insurance pool from yield farming
(define-public (contribute-farming-yield (yield-amount uint))
  (let ((contribution-amount (/ (* yield-amount (var-get fund-contribution-rate)) u100)))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> yield-amount u0) err-insufficient-balance)
    
    (try! (stx-transfer? contribution-amount tx-sender (as-contract tx-sender)))
    (var-set total-insurance-fund (+ (var-get total-insurance-fund) contribution-amount))
    
    (ok contribution-amount)))

;; Emergency fund withdrawal (owner only)
(define-public (emergency-fund-withdrawal (amount uint))
  (let ((emergency-limit (/ (* (var-get total-insurance-fund) (var-get emergency-reserve-ratio)) u100)))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= amount emergency-limit) err-insufficient-insurance-fund)
    
    (try! (as-contract (stx-transfer? amount tx-sender contract-owner)))
    (var-set total-insurance-fund (- (var-get total-insurance-fund) amount))
    
    (ok amount)))

;; Update risk factors for user
(define-public (update-user-risk-factors (user principal) (deposit-score uint) (claim-score uint))
  (let ((risk-multiplier (calculate-risk-multiplier deposit-score claim-score)))
    
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (map-set risk-factors user
      {deposit-history-score: deposit-score,
       claim-history-score: claim-score,
       total-risk-multiplier: risk-multiplier})
    
    (ok risk-multiplier)))

;; Private helper functions

;; Calculate annual premium based on coverage and risk
(define-private (calculate-annual-premium (coverage-amount uint) (user principal))
  (let ((base-premium (/ (* coverage-amount (var-get base-premium-rate)) u100))
        (risk-data (default-to 
          {deposit-history-score: u100, claim-history-score: u100, total-risk-multiplier: u100}
          (map-get? risk-factors user)))
        (risk-multiplier (get total-risk-multiplier risk-data)))
    
    (/ (* base-premium risk-multiplier) u100)))

;; Calculate renewal premium with potential discounts
(define-private (calculate-renewal-premium (policy-id uint) (duration uint))
  (let ((policy (unwrap-panic (map-get? insurance-policies policy-id)))
        (base-annual (calculate-annual-premium (get coverage-amount policy) (get policyholder policy)))
        (loyalty-discount (calculate-loyalty-discount policy-id)))
    
    (- (/ (* base-annual duration) u31536000) loyalty-discount)))

;; Calculate loyalty discount based on policy history
(define-private (calculate-loyalty-discount (policy-id uint))
  (let ((policy (unwrap-panic (map-get? insurance-policies policy-id)))
        (policy-age (- block-height (get start-block policy))))
    
    (if (>= policy-age u7776000) ;; 90 days
        (/ (get premium-paid policy) u20) ;; 5% discount
        u0)))

;; Calculate risk multiplier from scores
(define-private (calculate-risk-multiplier (deposit-score uint) (claim-score uint))
  (let ((combined-score (/ (+ deposit-score claim-score) u2)))
    
    (if (>= combined-score u80)
        u90  ;; 10% discount for low risk
        (if (>= combined-score u60)
            u100 ;; Standard rate
            u120)))) ;; 20% premium increase for high risk

;; Read-only functions

(define-read-only (get-insurance-policy (policy-id uint))
  (map-get? insurance-policies policy-id))

(define-read-only (get-user-policies (user principal))
  (default-to (list) (map-get? user-policies user)))

(define-read-only (get-insurance-claim (claim-id uint))
  (map-get? insurance-claims claim-id))

(define-read-only (get-fund-status)
  {total-fund: (var-get total-insurance-fund),
   total-premiums: (var-get total-premiums-collected),
   total-claims: (var-get total-claims-paid),
   active-policies: (var-get policy-counter),
   processed-claims: (var-get claim-counter),
   fund-utilization: (if (> (var-get total-insurance-fund) u0)
                        (/ (* (var-get total-claims-paid) u100) (var-get total-insurance-fund))
                        u0)})

(define-read-only (get-premium-quote (coverage-amount uint) (duration uint) (user principal))
  (let ((annual-premium (calculate-annual-premium coverage-amount user))
        (duration-premium (/ (* annual-premium duration) u31536000)))
    
    {annual-premium: annual-premium,
     duration-premium: duration-premium,
     coverage-amount: coverage-amount,
     policy-duration: duration}))

(define-read-only (get-user-risk-profile (user principal))
  (default-to 
    {deposit-history-score: u100, claim-history-score: u100, total-risk-multiplier: u100}
    (map-get? risk-factors user)))

(define-read-only (get-policy-coverage-status (policy-id uint))
  (let ((policy (map-get? insurance-policies policy-id)))
    (match policy
      p {active: (get active p),
         expires-at: (get end-block p),
         blocks-remaining: (if (> (get end-block p) block-height)
                             (- (get end-block p) block-height)
                             u0),
         coverage-remaining: (get coverage-amount p)}
      {active: false, expires-at: u0, blocks-remaining: u0, coverage-remaining: u0})))


