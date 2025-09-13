;; dca-savings-pool.clar
;; Automated Dollar-Cost Averaging system for the savings pool
;; Allows users to set up recurring deposits with flexible scheduling

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u300))
(define-constant err-insufficient-balance (err u301))
(define-constant err-invalid-amount (err u302))
(define-constant err-invalid-frequency (err u303))
(define-constant err-dca-not-found (err u304))
(define-constant err-dca-paused (err u305))
(define-constant err-execution-failed (err u306))
(define-constant err-insufficient-allowance (err u307))
(define-constant err-frequency-too-low (err u308))

;; Data variables
(define-data-var dca-counter uint u0)
(define-data-var min-dca-amount uint u100)
(define-data-var max-active-dca uint u10)
(define-data-var execution-fee uint u5)
(define-data-var total-dca-volume uint u0)
(define-data-var system-paused bool false)

;; DCA plan structure
(define-map dca-plans
  uint
  {user: principal,
   amount: uint,
   frequency: uint,
   next-execution: uint,
   total-executions: uint,
   max-executions: uint,
   total-invested: uint,
   active: bool,
   created-at: uint,
   last-execution: uint})

;; User DCA tracking
(define-map user-dca-list
  principal
  (list 10 uint))

;; Execution history
(define-map execution-history
  {dca-id: uint, execution-count: uint}
  {executed-at: uint,
   amount: uint,
   pool-price: uint,
   success: bool})

;; User allowances for automated execution
(define-map user-allowances
  principal
  {total-allowance: uint,
   used-allowance: uint,
   expires-at: uint})

;; Statistics tracking
(define-map dca-statistics
  principal
  {total-plans: uint,
   successful-executions: uint,
   total-volume: uint,
   average-execution-amount: uint})

;; Public functions

;; Create new DCA plan
(define-public (create-dca-plan (amount uint) (frequency uint) (max-executions uint))
  (let ((caller tx-sender)
        (dca-id (+ (var-get dca-counter) u1))
        (current-user-plans (default-to (list) (map-get? user-dca-list caller))))
    
    (asserts! (not (var-get system-paused)) err-dca-paused)
    (asserts! (>= amount (var-get min-dca-amount)) err-invalid-amount)
    (asserts! (>= frequency u1440) err-frequency-too-low) ;; Minimum 1 day
    (asserts! (> max-executions u0) err-invalid-amount)
    (asserts! (< (len current-user-plans) (var-get max-active-dca)) (err u309))
    
    ;; Create DCA plan
    (map-set dca-plans dca-id
      {user: caller,
       amount: amount,
       frequency: frequency,
       next-execution: (+ block-height frequency),
       total-executions: u0,
       max-executions: max-executions,
       total-invested: u0,
       active: true,
       created-at: block-height,
       last-execution: u0})
    
    ;; Update user plan list
    (map-set user-dca-list caller
      (unwrap! (as-max-len? (append current-user-plans dca-id) u10)
               (err u310)))
    
    ;; Update statistics
    (let ((stats (default-to 
            {total-plans: u0, successful-executions: u0, total-volume: u0, average-execution-amount: u0}
            (map-get? dca-statistics caller))))
      (map-set dca-statistics caller
        (merge stats {total-plans: (+ (get total-plans stats) u1)})))
    
    (var-set dca-counter dca-id)
    (ok dca-id)))

;; Set user allowance for automated executions
(define-public (set-dca-allowance (total-allowance uint) (duration uint))
  (let ((caller tx-sender))
    (asserts! (> total-allowance u0) err-invalid-amount)
    (asserts! (> duration u0) err-invalid-frequency)
    
    (map-set user-allowances caller
      {total-allowance: total-allowance,
       used-allowance: u0,
       expires-at: (+ block-height duration)})
    
    (ok true)))

;; Execute DCA plan
(define-public (execute-dca-plan (dca-id uint))
  (let ((plan (unwrap! (map-get? dca-plans dca-id) err-dca-not-found))
        (user (get user plan))
        (allowance (unwrap! (map-get? user-allowances user) err-insufficient-allowance))
        (execution-amount (get amount plan))
        (fee-amount (var-get execution-fee)))
    
    (asserts! (not (var-get system-paused)) err-dca-paused)
    (asserts! (get active plan) err-dca-not-found)
    (asserts! (>= block-height (get next-execution plan)) err-execution-failed)
    (asserts! (< (get total-executions plan) (get max-executions plan)) err-execution-failed)
    (asserts! (> (get expires-at allowance) block-height) err-insufficient-allowance)
    (asserts! (>= (- (get total-allowance allowance) (get used-allowance allowance)) 
                  (+ execution-amount fee-amount)) err-insufficient-allowance)
    
    ;; Execute the deposit to savings pool
    (try! (contract-call? .savings-pool deposit execution-amount))
    
    ;; Update plan
    (map-set dca-plans dca-id
      (merge plan 
        {next-execution: (+ block-height (get frequency plan)),
         total-executions: (+ (get total-executions plan) u1),
         total-invested: (+ (get total-invested plan) execution-amount),
         last-execution: block-height}))
    
    ;; Update allowance
    (map-set user-allowances user
      (merge allowance 
        {used-allowance: (+ (get used-allowance allowance) (+ execution-amount fee-amount))}))
    
    ;; Record execution history
    (map-set execution-history 
      {dca-id: dca-id, execution-count: (get total-executions plan)}
      {executed-at: block-height,
       amount: execution-amount,
       pool-price: u1000000, ;; Simplified price tracking
       success: true})
    
    ;; Update statistics
    (let ((stats (default-to 
            {total-plans: u0, successful-executions: u0, total-volume: u0, average-execution-amount: u0}
            (map-get? dca-statistics user)))
          (new-volume (+ (get total-volume stats) execution-amount))
          (new-executions (+ (get successful-executions stats) u1)))
      (map-set dca-statistics user
        (merge stats 
          {successful-executions: new-executions,
           total-volume: new-volume,
           average-execution-amount: (/ new-volume new-executions)})))
    
    ;; Update global volume
    (var-set total-dca-volume (+ (var-get total-dca-volume) execution-amount))
    
    ;; Deactivate plan if max executions reached
    (if (>= (+ (get total-executions plan) u1) (get max-executions plan))
      (map-set dca-plans dca-id (merge plan {active: false}))
      true)
    
    (ok execution-amount)))

;; Pause/resume DCA plan
(define-public (toggle-dca-plan (dca-id uint))
  (let ((plan (unwrap! (map-get? dca-plans dca-id) err-dca-not-found)))
    (asserts! (is-eq tx-sender (get user plan)) err-owner-only)
    
    (map-set dca-plans dca-id
      (merge plan {active: (not (get active plan))}))
    
    (ok (not (get active plan)))))

;; Update DCA plan parameters
(define-public (update-dca-plan (dca-id uint) (new-amount uint) (new-frequency uint))
  (let ((plan (unwrap! (map-get? dca-plans dca-id) err-dca-not-found)))
    (asserts! (is-eq tx-sender (get user plan)) err-owner-only)
    (asserts! (>= new-amount (var-get min-dca-amount)) err-invalid-amount)
    (asserts! (>= new-frequency u1440) err-frequency-too-low)
    
    (map-set dca-plans dca-id
      (merge plan 
        {amount: new-amount,
         frequency: new-frequency,
         next-execution: (+ block-height new-frequency)}))
    
    (ok true)))

;; Cancel DCA plan
(define-public (cancel-dca-plan (dca-id uint))
  (let ((plan (unwrap! (map-get? dca-plans dca-id) err-dca-not-found)))
    (asserts! (is-eq tx-sender (get user plan)) err-owner-only)
    
    (map-set dca-plans dca-id
      (merge plan {active: false}))
    
    (ok true)))

;; Batch execute multiple ready DCA plans for a user
(define-public (batch-execute-user-plans (user principal))
  (let ((user-plans (default-to (list) (map-get? user-dca-list user))))
    (ok (fold execute-plan-if-ready user-plans u0))))

;; Admin functions

;; Toggle system pause
(define-public (toggle-system-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set system-paused (not (var-get system-paused)))
    (ok (var-get system-paused))))

;; Update system parameters
(define-public (update-dca-parameters (min-amount uint) (max-plans uint) (fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> min-amount u0) err-invalid-amount)
    (asserts! (> max-plans u0) err-invalid-amount)
    
    (var-set min-dca-amount min-amount)
    (var-set max-active-dca max-plans)
    (var-set execution-fee fee)
    (ok true)))

;; Private helper functions

(define-private (execute-plan-if-ready (dca-id uint) (count uint))
  (let ((plan (map-get? dca-plans dca-id)))
    (match plan
      p (if (and (get active p) (>= block-height (get next-execution p)))
          (begin
            (unwrap! (execute-dca-plan dca-id) (+ count u1))
            (+ count u1))
          count)
      count)))

;; Read-only functions

(define-read-only (get-dca-plan (dca-id uint))
  (map-get? dca-plans dca-id))

(define-read-only (get-user-dca-plans (user principal))
  (default-to (list) (map-get? user-dca-list user)))

(define-read-only (get-user-allowance (user principal))
  (default-to 
    {total-allowance: u0, used-allowance: u0, expires-at: u0}
    (map-get? user-allowances user)))

(define-read-only (get-dca-statistics (user principal))
  (default-to 
    {total-plans: u0, successful-executions: u0, total-volume: u0, average-execution-amount: u0}
    (map-get? dca-statistics user)))

(define-read-only (get-execution-history (dca-id uint) (execution-count uint))
  (map-get? execution-history {dca-id: dca-id, execution-count: execution-count}))

(define-read-only (get-ready-plans (user principal))
  (let ((user-plans (get-user-dca-plans user)))
    (filter is-plan-ready user-plans)))

(define-read-only (get-system-status)
  {paused: (var-get system-paused),
   total-volume: (var-get total-dca-volume),
   active-plans: (var-get dca-counter),
   min-amount: (var-get min-dca-amount),
   execution-fee: (var-get execution-fee)})

;; Helper function to check if plan is ready for execution
(define-private (is-plan-ready (dca-id uint))
  (let ((plan (map-get? dca-plans dca-id)))
    (match plan
      p (and (get active p) 
             (>= block-height (get next-execution p))
             (< (get total-executions p) (get max-executions p)))
      false)))
