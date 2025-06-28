;; Cross-Chain Liquidity Aggregator - Swap Operations
;; A protocol that aggregates liquidity from multiple chains using Bitcoin and Stacks as a settlement layer

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-chain-exists (err u102))
(define-constant err-chain-not-found (err u103))
(define-constant err-pool-exists (err u104))
(define-constant err-pool-not-found (err u105))
(define-constant err-insufficient-funds (err u106))
(define-constant err-invalid-parameters (err u107))
(define-constant err-timeout-not-reached (err u108))
(define-constant err-timeout-expired (err u109))
(define-constant err-swap-already-claimed (err u110))
(define-constant err-swap-not-found (err u111))
(define-constant err-invalid-path (err u112))
(define-constant err-invalid-signature (err u113))
(define-constant err-slippage-too-high (err u114))
(define-constant err-oracle-not-found (err u115))
(define-constant err-price-deviation (err u116))
(define-constant err-insufficient-liquidity (err u117))
(define-constant err-invalid-fee (err u118))
(define-constant err-invalid-preimage (err u119))
(define-constant err-relayer-not-found (err u120))
(define-constant err-invalid-route (err u121))
(define-constant err-emergency-shutdown (err u122))
(define-constant err-already-executed (err u123))
(define-constant err-inactive-pool (err u124))

;; Protocol parameters
(define-data-var next-swap-id uint u1)
(define-data-var next-route-id uint u1)
(define-data-var protocol-fee-bp uint u25) ;; 0.25% fee in basis points
(define-data-var max-slippage-bp uint u100) ;; 1% maximum slippage allowed
(define-data-var min-liquidity uint u1000000) ;; 1 STX minimum liquidity
(define-data-var default-timeout-blocks uint u144) ;; ~24 hours (144 blocks/day)
(define-data-var max-route-hops uint u3) ;; maximum hops in a route
(define-data-var treasury-address principal contract-owner)
(define-data-var emergency-shutdown bool false)
(define-data-var price-deviation-threshold uint u200) ;; 2% threshold for price oracle deviation
(define-data-var relayer-reward-percentage uint u10) ;; 10% of protocol fee goes to relayers

;; Stacks token for protocol governance
(define-fungible-token xchain-token)

;; Chain status enumeration
;; 0 = Active, 1 = Paused, 2 = Deprecated
(define-data-var chain-statuses (list 3 (string-ascii 10)) (list "Active" "Paused" "Deprecated"))

;; Swap status enumeration
;; 0 = Pending, 1 = Completed, 2 = Refunded, 3 = Expired
(define-data-var swap-statuses (list 4 (string-ascii 10)) (list "Pending" "Completed" "Refunded" "Expired"))

;; Supported blockchains
(define-map chains
  { chain-id: (string-ascii 20) }
  {
    name: (string-ascii 40),
    adapter-contract: principal,
    status: uint,
    confirmation-blocks: uint,
    block-time: uint, ;; Average block time in seconds
    chain-token: (string-ascii 10), ;; Chain's native token symbol
    btc-connection-type: (string-ascii 20), ;; "native", "wrapped", "bridged"
    enabled: bool,
    base-fee: uint, ;; Base fee for transactions on this chain
    fee-multiplier: uint, ;; Dynamic fee multiplier
    last-updated: uint
  }
)

;; Liquidity pools
(define-map liquidity-pools
  { chain-id: (string-ascii 20), token-id: (string-ascii 20) }
  {
    token-contract: principal,
    total-liquidity: uint,
    available-liquidity: uint,
    committed-liquidity: uint,
    min-swap-amount: uint,
    max-swap-amount: uint,
    fee-bp: uint, ;; Fee in basis points
    active: bool,
    last-volume-24h: uint,
    cumulative-volume: uint,
    cumulative-fees: uint,
    last-price: uint, ;; Last price in STX
    creation-block: uint,
    last-updated: uint
  }
)

;; Cross-chain swaps
(define-map swaps
  { swap-id: uint }
  {
    initiator: principal,
    source-chain: (string-ascii 20),
    source-token: (string-ascii 20),
    source-amount: uint,
    target-chain: (string-ascii 20),
    target-token: (string-ascii 20),
    target-amount: uint,
    recipient: principal,
    timeout-block: uint,
    hash-lock: (buff 32),
    preimage: (optional (buff 32)),
    status: uint,
    execution-path: (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal }),
    max-slippage-bp: uint,
    protocol-fee: uint,
    relayer-fee: uint,
    relayer: (optional principal),
    creation-block: uint,
    completion-block: (optional uint),
    ref-hash: (string-ascii 64) ;; Reference hash for cross-chain tracking
  }
)

;; Price oracles for tokens
(define-map price-oracles
  { chain-id: (string-ascii 20), token-id: (string-ascii 20) }
  {
    oracle-contract: principal,
    last-price: uint, ;; In STX with 8 decimal precision
    last-updated: uint,
    heartbeat: uint, ;; Maximum time between updates in blocks
    deviation-threshold: uint, ;; Max allowed deviation in basis points
    trusted: bool
  }
)

;; Optimal routes cache
(define-map route-cache
  { route-id: uint }
  {
    source-chain: (string-ascii 20),
    source-token: (string-ascii 20),
    target-chain: (string-ascii 20),
    target-token: (string-ascii 20),
    path: (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal }),
    estimated-output: uint,
    estimated-fees: uint,
    timestamp: uint,
    expiry: uint,
    gas-estimate: uint
  }
)

;; Token mappings across chains
(define-map token-mappings
  { source-chain: (string-ascii 20), source-token: (string-ascii 20), target-chain: (string-ascii 20) }
  { target-token: (string-ascii 20) }
)

;; Initiate a cross-chain swap
(define-public (initiate-cross-chain-swap
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (source-amount uint)
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20))
  (recipient principal)
  (hash-lock (buff 32))
  (execution-path (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal }))
  (slippage-bp uint))
  
  (let (
    (initiator tx-sender)
    (swap-id (var-get next-swap-id))
    (timeout-block (+ block-height (var-get default-timeout-blocks)))
    (routing-valid (validate-execution-path source-chain source-token target-chain target-token execution-path))
  )
    ;; Check for emergency shutdown
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    
    ;; Validate parameters
    (asserts! (is-ok routing-valid) err-invalid-path)
    (asserts! (<= slippage-bp (var-get max-slippage-bp)) err-invalid-parameters)
    (asserts! (not (is-eq source-chain target-chain)) err-invalid-parameters) ;; Must be cross-chain
    
    ;; Check source chain and token exist
    (let (
      (source-pool (unwrap! (map-get? liquidity-pools { chain-id: source-chain, token-id: source-token }) err-pool-not-found))
      (source-chain-info (unwrap! (map-get? chains { chain-id: source-chain }) err-chain-not-found))
      (estimated-output (unwrap! (get-estimated-output source-chain source-token source-amount target-chain target-token) err-invalid-route))
    )
      ;; Validate swap amount
      (asserts! (>= source-amount (get min-swap-amount source-pool)) err-invalid-parameters)
      (asserts! (<= source-amount (get max-swap-amount source-pool)) err-invalid-parameters)
      (asserts! (<= source-amount (get available-liquidity source-pool)) err-insufficient-liquidity)
      
      ;; Calculate fees
      (let (
        (protocol-fee (/ (* source-amount (var-get protocol-fee-bp)) u10000))
        (pool-fee (/ (* source-amount (get fee-bp source-pool)) u10000))
        (relayer-fee (/ (* protocol-fee (var-get relayer-reward-percentage)) u100))
        (total-fee (+ protocol-fee pool-fee))
        (net-amount (- source-amount total-fee))
        (ref-hash (generate-ref-hash swap-id hash-lock block-height))
      )
        ;; Lock source tokens in contract
        (if (is-eq source-chain "stacks")
          ;; For STX tokens
          (if (is-eq source-token "stx")
            (try! (stx-transfer? source-amount initiator (as-contract tx-sender)))
            ;; For other tokens on Stacks
            (try! (contract-call? (get token-contract source-pool) transfer source-amount initiator (as-contract tx-sender) none))
          )
          ;; For tokens on other chains, call adapter contract
          (try! (contract-call? (get adapter-contract source-chain-info) lock-funds source-token source-amount initiator (as-contract tx-sender)))
        )
        
        ;; Update available liquidity
        (map-set liquidity-pools
          { chain-id: source-chain, token-id: source-token }
          (merge source-pool {
            available-liquidity: (- (get available-liquidity source-pool) net-amount),
            committed-liquidity: (+ (get committed-liquidity source-pool) net-amount),
            cumulative-volume: (+ (get cumulative-volume source-pool) source-amount),
            cumulative-fees: (+ (get cumulative-fees source-pool) pool-fee),
            last-updated: block-height
          })
        )
        
        ;; Create swap record
        (map-set swaps
          { swap-id: swap-id }
          {
            initiator: initiator,
            source-chain: source-chain,
            source-token: source-token,
            source-amount: source-amount,
            target-chain: target-chain,
            target-token: target-token,
            target-amount: estimated-output,
            recipient: recipient,
            timeout-block: timeout-block,
            hash-lock: hash-lock,
            preimage: none,
            status: u0, ;; Pending
            execution-path: execution-path,
            max-slippage-bp: slippage-bp,
            protocol-fee: protocol-fee,
            relayer-fee: relayer-fee,
            relayer: none,
            creation-block: block-height,
            completion-block: none,
            ref-hash: ref-hash
          }
        )
        
        ;; Increment swap ID
        (var-set next-swap-id (+ swap-id u1))
        
        (ok { 
          swap-id: swap-id, 
          timeout-block: timeout-block, 
          estimated-output: estimated-output,
          ref-hash: ref-hash
        })
      )
    )
  )
)

;; Generate reference hash for cross-chain tracking
(define-private (generate-ref-hash (swap-id uint) (hash-lock (buff 32)) (block uint))
  (to-ascii (keccak256 (concat (to-consensus-buff swap-id) 
                              (concat hash-lock (to-consensus-buff block)))))
)

;; Execute a cross-chain swap with preimage
(define-public (execute-cross-chain-swap
  (swap-id uint)
  (preimage (buff 32)))
  
  (let (
    (executor tx-sender)
    (swap (unwrap! (map-get? swaps { swap-id: swap-id }) err-swap-not-found))
    (hash-lock (get hash-lock swap))
  )
    ;; Check for emergency shutdown
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    
    ;; Validate swap state
    (asserts! (is-eq (get status swap) u0) err-already-executed) ;; Must be pending
    (asserts! (< block-height (get timeout-block swap)) err-timeout-expired) ;; Must not be expired
    
    ;; Verify preimage
    (asserts! (is-eq (sha256 preimage) hash-lock) err-invalid-preimage)
    
    ;; Check target chain and token
    (let (
      (target-chain (get target-chain swap))
      (target-token (get target-token swap))
      (target-amount (get target-amount swap))
      (recipient (get recipient swap))
      (target-pool (unwrap! (map-get? liquidity-pools { chain-id: target-chain, token-id: target-token }) err-pool-not-found))
      (target-chain-info (unwrap! (map-get? chains { chain-id: target-chain }) err-chain-not-found))
      (slippage-bp (get max-slippage-bp swap))
    )
      ;; Check sufficient liquidity
      (asserts! (>= (get available-liquidity target-pool) target-amount) err-insufficient-liquidity)
      
      ;; Calculate minimum acceptable amount with slippage
      (let (
        (min-acceptable-amount (- target-amount (/ (* target-amount slippage-bp) u10000)))
      )
        ;; Release target tokens to recipient
        (if (is-eq target-chain "stacks")
          ;; For STX tokens
          (if (is-eq target-token "stx")
            (as-contract (try! (stx-transfer? target-amount (as-contract tx-sender) recipient)))
            ;; For other tokens on Stacks
            (as-contract (try! (contract-call? (get token-contract target-pool) transfer target-amount (as-contract tx-sender) recipient none)))
          )
          ;; For tokens on other chains, call adapter contract
          (as-contract (try! (contract-call? (get adapter-contract target-chain-info) release-funds target-token target-amount (as-contract tx-sender) recipient)))
        )
        
        ;; Update available liquidity
        (map-set liquidity-pools
          { chain-id: target-chain, token-id: target-token }
          (merge target-pool {
            available-liquidity: (- (get available-liquidity target-pool) target-amount),
            committed-liquidity: (+ (get committed-liquidity target-pool) target-amount),
            last-volume-24h: (+ (get last-volume-24h target-pool) target-amount),
            cumulative-volume: (+ (get cumulative-volume target-pool) target-amount),
            last-updated: block-height
          })
        )
        
        ;; Mark swap as completed
        (map-set swaps
          { swap-id: swap-id }
          (merge swap {
            status: u1, ;; Completed
            preimage: (some preimage),
            completion-block: (some block-height),
            relayer: (some executor)
          })
        )
        
        ;; Transfer protocol fee to treasury
        (let (
          (protocol-fee (get protocol-fee swap))
        )
          (as-contract (try! (stx-transfer? protocol-fee (as-contract tx-sender) (var-get treasury-address))))
        )
        
        (ok { 
          swap-id: swap-id, 
          recipient: recipient, 
          amount: target-amount,
          preimage: preimage
        })
      )
    )
  )
)

;; Refund a swap after timeout
(define-public (refund-swap (swap-id uint))
  (let (
    (initiator tx-sender)
    (swap (unwrap! (map-get? swaps { swap-id: swap-id }) err-swap-not-found))
  )
    ;; Validate swap state
    (asserts! (is-eq (get status swap) u0) err-already-executed) ;; Must be pending
    (asserts! (>= block-height (get timeout-block swap)) err-timeout-not-reached) ;; Timeout must be reached
    (asserts! (is-eq initiator (get initiator swap)) err-not-authorized) ;; Only initiator can refund
    
    ;; Get source info
    (let (
      (source-chain (get source-chain swap))
      (source-token (get source-token swap))
      (source-amount (get source-amount swap))
      (protocol-fee (get protocol-fee swap))
      (source-pool (unwrap! (map-get? liquidity-pools { chain-id: source-chain, token-id: source-token }) err-pool-not-found))
      (source-chain-info (unwrap! (map-get? chains { chain-id: source-chain }) err-chain-not-found))
      (net-amount (- source-amount protocol-fee))
    )
      ;; Return tokens to initiator (minus protocol fee)
      (if (is-eq source-chain "stacks")
        ;; For STX tokens
        (if (is-eq source-token "stx")
          (as-contract (try! (stx-transfer? net-amount (as-contract tx-sender) initiator)))
          ;; For other tokens on Stacks
          (as-contract (try! (contract-call? (get token-contract source-pool) transfer net-amount (as-contract tx-sender) initiator none)))
        )
        ;; For tokens on other chains, call adapter contract
        (as-contract (try! (contract-call? (get adapter-contract source-chain-info) release-funds source-token net-amount (as-contract tx-sender) initiator)))
      )
      
      ;; Update available liquidity
      (map-set liquidity-pools
        { chain-id: source-chain, token-id: source-token }
        (merge source-pool {
          committed-liquidity: (- (get committed-liquidity source-pool) net-amount),
          available-liquidity: (+ (get available-liquidity source-pool) net-amount),
          last-updated: block-height
        })
      )
      
      ;; Mark swap as refunded
      (map-set swaps
        { swap-id: swap-id }
        (merge swap {
          status: u2, ;; Refunded
          completion-block: (some block-height)
        })
      )
      
      ;; Transfer protocol fee to treasury
      (as-contract (try! (stx-transfer? protocol-fee (as-contract tx-sender) (var-get treasury-address))))
      
      (ok { 
        swap-id: swap-id, 
        refunded-amount: net-amount,
        fee-kept: protocol-fee
      })
    )
  )
)

;; Helper to get estimated output amount
(define-private (get-estimated-output
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (source-amount uint)
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20)))
  
  (let (
    (source-pool (map-get? liquidity-pools { chain-id: source-chain, token-id: source-token }))
    (target-pool (map-get? liquidity-pools { chain-id: target-chain, token-id: target-token }))
    (source-oracle (map-get? price-oracles { chain-id: source-chain, token-id: source-token }))
    (target-oracle (map-get? price-oracles { chain-id: target-chain, token-id: target-token }))
  )
    (if (and (is-some source-pool) (is-some target-pool) (is-some source-oracle) (is-some target-oracle))
      (let (
        (source-price (get last-price (unwrap-panic source-oracle)))
        (target-price (get last-price (unwrap-panic target-oracle)))
        (protocol-fee (/ (* source-amount (var-get protocol-fee-bp)) u10000))
        (pool-fee (/ (* source-amount (get fee-bp (unwrap-panic source-pool))) u10000))
        (total-fee (+ protocol-fee pool-fee))
        (net-amount (- source-amount total-fee))
        (source-value (* net-amount source-price))
        (target-amount (/ source-value target-price))
      )
        (ok target-amount)
      )
      err-invalid-route
    )
  )
)

;; Validate execution path
(define-private (validate-execution-path
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20))
  (path (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal })))
  
  (let (
    (path-length (len path))
    (first-hop (unwrap! (element-at path u0) err-invalid-path))
    (last-hop (unwrap! (element-at path (- path-length u1)) err-invalid-path))
  )
    ;; Check that path starts and ends at correct chains/tokens
    (if (and 
          (is-eq (get chain first-hop) source-chain)
          (is-eq (get token first-hop) source-token)
          (is-eq (get chain last-hop) target-chain)
          (is-eq (get token last-hop) target-token)
        )
      (ok true)
      err-invalid-path
    )
  )
)

;; Read-only functions

;; Get swap details
(define-read-only (get-swap (swap-id uint))
  (map-get? swaps { swap-id: swap-id })
)

;; Get cached route
(define-read-only (get-cached-route (route-id uint))
  (map-get? route-cache { route-id: route-id })
)

;; Get swap status as string
(define-read-only (get-swap-status-string (swap-id uint))
  (let (
    (swap (map-get? swaps { swap-id: swap-id }))
  )
    (if (is-some swap)
      (let (
        (status (get status (unwrap-panic swap)))
        (status-list (var-get swap-statuses))
      )
        (default-to "Unknown" (element-at status-list status))
      )
      "Not Found"
    )
  )
)
