;; Cross-Chain Liquidity Aggregator - Route Optimization & Admin
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

;; Token mappings across chains
(define-map token-mappings
  { source-chain: (string-ascii 20), source-token: (string-ascii 20), target-chain: (string-ascii 20) }
  { target-token: (string-ascii 20) }
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

;; Find optimal route for cross-chain swap
(define-public (find-optimal-route
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (source-amount uint)
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20)))
  
  (let (
    (route-id (var-get next-route-id))
    (best-path (get-optimal-path source-chain source-token target-chain target-token))
    (estimated-output (get-estimated-output source-chain source-token source-amount target-chain target-token))
  )
    (asserts! (is-ok best-path) err-invalid-route)
    (asserts! (is-ok estimated-output) err-invalid-route)
    
    (let (
      (path (unwrap-panic best-path))
      (output (unwrap-panic estimated-output))
      (protocol-fee (/ (* source-amount (var-get protocol-fee-bp)) u10000))
      (gas-estimate (estimate-gas-cost path))
    )
      ;; Cache the route
      (map-set route-cache
        { route-id: route-id }
        {
          source-chain: source-chain,
          source-token: source-token,
          target-chain: target-chain,
          target-token: target-token,
          path: path,
          estimated-output: output,
          estimated-fees: protocol-fee,
          timestamp: block-height,
          expiry: (+ block-height u72), ;; 12 hour route cache
          gas-estimate: gas-estimate
        }
      )
      
      ;; Increment route ID
      (var-set next-route-id (+ route-id u1))
      
      (ok { 
        route-id: route-id, 
        path: path,
        estimated-output: output,
        estimated-fees: protocol-fee,
        gas-estimate: gas-estimate
      })
    )
  )
)

;; Helper to get optimal path (simplified version)
(define-private (get-optimal-path
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20)))
  
  ;; In a real implementation, this would use a graph algorithm to find optimal paths
  ;; For demonstration, we'll create a simple direct path
  (let (
    (source-pool (map-get? liquidity-pools { chain-id: source-chain, token-id: source-token }))
    (target-pool (map-get? liquidity-pools { chain-id: target-chain, token-id: target-token }))
    (token-mapping (map-get? token-mappings { 
      source-chain: source-chain, 
      source-token: source-token, 
      target-chain: target-chain 
    }))
  )
    (if (and (is-some source-pool) (is-some target-pool) (is-some token-mapping))
      (ok (list 
        { chain: source-chain, token: source-token, pool: (get token-contract (unwrap-panic source-pool)) }
        { chain: target-chain, token: target-token, pool: (get token-contract (unwrap-panic target-pool)) }
      ))
      err-invalid-route
    )
  )
)

;; Helper to estimate output amount
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

;; Helper to estimate gas cost for a path
(define-private (estimate-gas-cost (path (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal })))
  ;; In a real implementation, this would calculate gas costs for each hop
  ;; For now, we'll provide a simple estimate based on number of hops
  (* (len path) u1000000) ;; 1 STX per hop
)

;; Emergency shutdown
(define-public (set-emergency-shutdown (shutdown bool))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set emergency-shutdown shutdown)
    (ok shutdown)
  )
)

;; Update protocol parameters
(define-public (set-protocol-fee (new-fee-bp uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-fee-bp u500) err-invalid-fee) ;; Max 5% fee
    
    (var-set protocol-fee-bp new-fee-bp)
    (ok new-fee-bp)
  )
)

;; Update max slippage
(define-public (set-max-slippage (new-slippage-bp uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-slippage-bp u1000) err-invalid-parameters) ;; Max 10% slippage
    
    (var-set max-slippage-bp new-slippage-bp)
    (ok new-slippage-bp)
  )
)

;; Update treasury address
(define-public (set-treasury-address (new-treasury principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (var-set treasury-address new-treasury)
    (ok new-treasury)
  )
)

;; Update chain status
(define-public (set-chain-status
  (chain-id (string-ascii 20))
  (enabled bool)
  (status uint))
  
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (< status u3) err-invalid-parameters) ;; Valid status
    
    (let (
      (chain (unwrap! (map-get? chains { chain-id: chain-id }) err-chain-not-found))
    )
      (map-set chains
        { chain-id: chain-id }
        (merge chain {
          status: status,
          enabled: enabled,
          last-updated: block-height
        })
      )
      
      (ok { chain: chain-id, status: status })
    )
  )
)

;; Update pool status
(define-public (set-pool-status
  (chain-id (string-ascii 20))
  (token-id (string-ascii 20))
  (active bool))
  
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    
    (let (
      (pool (unwrap! (map-get? liquidity-pools { chain-id: chain-id, token-id: token-id }) err-pool-not-found))
    )
      (map-set liquidity-pools
        { chain-id: chain-id, token-id: token-id }
        (merge pool {
          active: active,
          last-updated: block-height
        })
      )
      
      (ok { chain: chain-id, token: token-id, active: active })
    )
  )
)

;; Update price from oracle
(define-public (update-price
  (chain-id (string-ascii 20))
  (token-id (string-ascii 20))
  (price uint))
  
  (let (
    (caller tx-sender)
    (oracle (unwrap! (map-get? price-oracles { chain-id: chain-id, token-id: token-id }) err-oracle-not-found))
  )
    ;; Ensure caller is the oracle contract
    (asserts! (is-eq caller (get oracle-contract oracle)) err-not-authorized)
    
    ;; Check for price deviation
    (let (
      (last-price (get last-price oracle))
      (deviation-threshold (get deviation-threshold oracle))
    )
      (if (> last-price u0)
        (let (
          (price-change (if (> price last-price)
                           (- price last-price)
                           (- last-price price)))
          (percentage-change (/ (* price-change u10000) last-price))
        )
          ;; Check if price change exceeds deviation threshold
          (asserts! (<= percentage-change deviation-threshold) err-price-deviation)
        )
        true
      )
      
      ;; Update price
      (map-set price-oracles
        { chain-id: chain-id, token-id: token-id }
        (merge oracle {
          last-price: price,
          last-updated: block-height
        })
      )
      
      ;; Update pool last price
      (match (map-get? liquidity-pools { chain-id: chain-id, token-id: token-id })
        pool (map-set liquidity-pools
               { chain-id: chain-id, token-id: token-id }
               (merge pool { last-price: price })
             )
        true
      )
      
      (ok price)
    )
  )
)

;; Read-only functions

;; Get chain info
(define-read-only (get-chain (chain-id (string-ascii 20)))
  (map-get? chains { chain-id: chain-id })
)

;; Get pool info
(define-read-only (get-pool (chain-id (string-ascii 20)) (token-id (string-ascii 20)))
  (map-get? liquidity-pools { chain-id: chain-id, token-id: token-id })
)

;; Get oracle info
(define-read-only (get-oracle (chain-id (string-ascii 20)) (token-id (string-ascii 20)))
  (map-get? price-oracles { chain-id: chain-id, token-id: token-id })
)

;; Get token mapping
(define-read-only (get-token-mapping (source-chain (string-ascii 20)) (source-token (string-ascii 20)) (target-chain (string-ascii 20)))
  (map-get? token-mappings { source-chain: source-chain, source-token: source-token, target-chain: target-chain })
)

;; Get cached route
(define-read-only (get-cached-route (route-id uint))
  (map-get? route-cache { route-id: route-id })
)

;; Get chain status as string
(define-read-only (get-chain-status-string (chain-id (string-ascii 20)))
  (let (
    (chain (map-get? chains { chain-id: chain-id }))
  )
    (if (is-some chain)
      (let (
        (status (get status (unwrap-panic chain)))
        (status-list (var-get chain-statuses))
      )
        (default-to "Unknown" (element-at status-list status))
      )
      "Not Found"
    )
  )
)

;; Get protocol parameters
(define-read-only (get-protocol-parameters)
  {
    protocol-fee-bp: (var-get protocol-fee-bp),
    max-slippage-bp: (var-get max-slippage-bp),
    min-liquidity: (var-get min-liquidity),
    default-timeout-blocks: (var-get default-timeout-blocks),
    max-route-hops: (var-get max-route-hops),
    treasury-address: (var-get treasury-address),
    emergency-shutdown: (var-get emergency-shutdown),
    price-deviation-threshold: (var-get price-deviation-threshold),
    relayer-reward-percentage: (var-get relayer-reward-percentage)
  }
)
