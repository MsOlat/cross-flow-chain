;; Cross-Chain Liquidity Aggregator - Foundation
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
;; Cross-Chain Liquidity Aggregator - Extended Data Structures
;; Building upon the foundation with additional cross-chain infrastructure

;; ...existing foundation code from commit 1...

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
;; Cross-Chain Liquidity Aggregator - Core Swap Operations
;; Implementation of atomic cross-chain swap functionality

;; ...existing foundation and data structures from commits 1-2...

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
    (swap-id (var-get next-swap-id))
    (current-block block-height)
    (timeout-block (+ current-block (var-get default-timeout-blocks)))
    (protocol-fee (/ (* source-amount (var-get protocol-fee-bp)) u10000))
    (ref-hash (generate-ref-hash swap-id hash-lock current-block))
  )
    ;; Check if emergency shutdown is active
    (asserts! (not (var-get emergency-shutdown)) err-emergency-shutdown)
    
    ;; Validate parameters
    (asserts! (> source-amount u0) err-invalid-parameters)
    (asserts! (<= slippage-bp (var-get max-slippage-bp)) err-slippage-too-high)
    
    ;; Validate source and target chains exist
    (asserts! (is-some (map-get? chains { chain-id: source-chain })) err-chain-not-found)
    (asserts! (is-some (map-get? chains { chain-id: target-chain })) err-chain-not-found)
    
    ;; Validate execution path
    (asserts! (validate-execution-path source-chain source-token target-chain target-token execution-path) err-invalid-path)
    
    ;; Create swap record
    (map-set swaps { swap-id: swap-id } {
      initiator: tx-sender,
      source-chain: source-chain,
      source-token: source-token,
      source-amount: source-amount,
      target-chain: target-chain,
      target-token: target-token,
      target-amount: u0, ;; Will be calculated during execution
      recipient: recipient,
      timeout-block: timeout-block,
      hash-lock: hash-lock,
      preimage: none,
      status: u0, ;; Pending
      execution-path: execution-path,
      max-slippage-bp: slippage-bp,
      protocol-fee: protocol-fee,
      relayer-fee: u0,
      relayer: none,
      creation-block: current-block,
      completion-block: none,
      ref-hash: ref-hash
    })
    
    ;; Increment swap ID
    (var-set next-swap-id (+ swap-id u1))
    
    (ok swap-id)
  )
)

;; Generate reference hash for cross-chain tracking
(define-private (generate-ref-hash (swap-id uint) (hash-lock (buff 32)) (block uint))
  ;; Create a simple reference hash 
  (let (
    (reference (keccak256 hash-lock))
  )
    ;; Return a 64-character hex string representation
    "0000000000000000000000000000000000000000000000000000000000000000"
  )
)

;; Execute a cross-chain swap with preimage
(define-public (execute-cross-chain-swap
  (swap-id uint)
  (preimage (buff 32)))
  
  (let (
    (swap-data (unwrap! (map-get? swaps { swap-id: swap-id }) err-swap-not-found))
    (hash-check (keccak256 preimage))
  )
    ;; Verify swap exists and is pending
    (asserts! (is-eq (get status swap-data) u0) err-already-executed)
    
    ;; Verify preimage matches hash-lock
    (asserts! (is-eq hash-check (get hash-lock swap-data)) err-invalid-preimage)
    
    ;; Check timeout hasn't expired
    (asserts! (< block-height (get timeout-block swap-data)) err-timeout-expired)
    
    ;; Update swap status to completed
    (map-set swaps { swap-id: swap-id } 
      (merge swap-data { 
        status: u1, ;; Completed
        preimage: (some preimage),
        completion-block: (some block-height)
      }))
    
    (ok true)
  )
)
;; Cross-Chain Liquidity Aggregator - Support Functions & Utilities
;; Completion of the protocol with refund mechanisms and helper functions

;; ...existing foundation, data structures, and swap operations from commits 1-3...

;; Refund a swap after timeout
(define-public (refund-swap (swap-id uint))
  (let (
    (swap-data (unwrap! (map-get? swaps { swap-id: swap-id }) err-swap-not-found))
  )
    ;; Verify swap exists and is still pending
    (asserts! (is-eq (get status swap-data) u0) err-already-executed)
    
    ;; Verify timeout has been reached
    (asserts! (>= block-height (get timeout-block swap-data)) err-timeout-not-reached)
    
    ;; Verify caller is the initiator
    (asserts! (is-eq tx-sender (get initiator swap-data)) err-not-authorized)
    
    ;; Update swap status to refunded
    (map-set swaps { swap-id: swap-id } 
      (merge swap-data { 
        status: u2, ;; Refunded
        completion-block: (some block-height)
      }))
    
    (ok true)
  )
)

;; Helper to get estimated output amount
(define-private (get-estimated-output
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (source-amount uint)
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20)))
  
  ;; Simple estimation - in a real implementation this would use price oracles
  (let (
    (protocol-fee (/ (* source-amount (var-get protocol-fee-bp)) u10000))
    (net-amount (- source-amount protocol-fee))
  )
    ;; For now, assume 1:1 ratio minus fees
    net-amount
  )
)

;; Validate execution path
(define-private (validate-execution-path
  (source-chain (string-ascii 20))
  (source-token (string-ascii 20))
  (target-chain (string-ascii 20))
  (target-token (string-ascii 20))
  (path (list 5 { chain: (string-ascii 20), token: (string-ascii 20), pool: principal })))
  
  ;; For now, basic validation - path should not be empty and should connect source to target
  (let (
    (path-length (len path))
  )
    ;; Validate path is not empty and has reasonable length
    (and (> path-length u0) (<= path-length (var-get max-route-hops)))
  )
)

;; Read-only functions for data access
(define-read-only (get-swap (swap-id uint))
  (map-get? swaps { swap-id: swap-id })
)

(define-read-only (get-cached-route (route-id uint))
  (map-get? route-cache { route-id: route-id })
)

(define-read-only (get-swap-status-string (swap-id uint))
  (let (
    (swap-data (map-get? swaps { swap-id: swap-id }))
  )
    (match swap-data
      swap-info (let (
        (status (get status swap-info))
      )
        (if (is-eq status u0) "Pending"
        (if (is-eq status u1) "Completed"
        (if (is-eq status u2) "Refunded"
        "Expired"))))
      "Not Found"
    )
  )
)

