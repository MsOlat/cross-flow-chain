# Cross-Chain Liquidity Aggregator

A decentralized cross-chain liquidity aggregation protocol built on Stacks that enables seamless asset swaps across multiple blockchain networks using Bitcoin as the settlement layer.

## 🚀 Overview

The Cross-Chain Liquidity Aggregator is a sophisticated DeFi protocol that aggregates liquidity from multiple blockchain networks, providing users with:

- **Unified Liquidity Access**: Aggregate liquidity from multiple chains in a single interface
- **Atomic Cross-Chain Swaps**: Secure, trustless swaps using Hash Time-Locked Contracts (HTLCs)
- **Optimal Route Discovery**: Intelligent routing for best prices and lowest fees
- **Multi-Chain Asset Support**: Support for major blockchain networks and their native/wrapped tokens
- **Decentralized Price Oracles**: Real-time price feeds for accurate swap calculations
- **Liquidity Provider Rewards**: Earn fees by providing liquidity to cross-chain pools

## 🏗️ Architecture

### Core Components

1. **Foundation Layer** (`commit-1-foundation.clar`)
   - Error constants and protocol parameters
   - Chain registry and liquidity pool definitions
   - Governance token and status enumerations

2. **Data Structures** (`commit-2-data-structures.clar`)
   - Cross-chain swap structures with HTLC support
   - Price oracle infrastructure
   - Route caching system
   - Token mapping for cross-chain assets

3. **Swap Operations** (`commit-3-swap-operations.clar`)
   - Atomic swap initiation and execution
   - HTLC preimage verification
   - Reference hash generation for tracking

4. **Utilities & Support** (`commit-4-utilities.clar`)
   - Timeout-based refund mechanisms
   - Price estimation and validation
   - Read-only data access functions

### Key Features

#### 🔗 Multi-Chain Support
- **Ethereum**: Native ETH and ERC-20 tokens
- **Bitcoin**: Native BTC and wrapped variants
- **Polygon**: MATIC and bridged assets
- **Arbitrum**: ARB and L2 tokens
- **Extensible**: Easy addition of new blockchain networks

#### 🔒 Security Features
- **Hash Time-Locked Contracts (HTLCs)**: Ensures atomic swaps
- **Timeout Protection**: Automatic refunds for expired swaps
- **Oracle Price Validation**: Guards against price manipulation
- **Slippage Protection**: Configurable maximum slippage limits
- **Emergency Shutdown**: Protocol-level pause mechanism

#### 💰 Economic Model
- **Protocol Fee**: 0.25% (25 basis points) on all swaps
- **Dynamic Pricing**: Fees adjust based on network congestion
- **Liquidity Rewards**: LPs earn proportional share of protocol fees
- **Relayer Incentives**: 10% of protocol fees reward transaction relayers

## 🛠️ Development Setup

### Prerequisites

- [Clarinet](https://github.com/hirosystems/clarinet) - Stacks smart contract development toolkit
- [Node.js](https://nodejs.org/) (v16+) - For testing and tooling
- [Deno](https://deno.land/) - For running Clarinet tests

### Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd cross-chain-flow
```

2. Install Clarinet (if not already installed):
```bash
# Using Homebrew (macOS)
brew install clarinet

# Using npm
npm install -g @stacks/clarinet
```

3. Verify installation:
```bash
clarinet --version
```

### Project Structure

```
cross-chain-flow/
├── contracts/
│   ├── cross-chain-contract.clar        # Main contract
│   ├── commit-1-foundation.clar          # Foundation layer
│   ├── commit-2-data-structures.clar     # Extended data structures
│   ├── commit-3-swap-operations.clar     # Core swap logic
│   └── commit-4-utilities.clar           # Support functions
├── tests/
│   └── cross-chain-contract_test.ts      # Contract tests
├── settings/
│   ├── Devnet.toml                       # Development network config
│   ├── Testnet.toml                      # Testnet configuration
│   └── Mainnet.toml                      # Mainnet configuration
├── Clarinet.toml                         # Project configuration
├── COMMIT_BREAKDOWN.md                   # Development commits breakdown
└── README.md                             # This file
```

## 🧪 Testing

### Run Contract Checks
```bash
clarinet check
```

### Run Test Suite
```bash
clarinet test
```

### Available VS Code Tasks
- **Check Contracts**: Validates contract syntax and logic
- **Test Contracts**: Runs the complete test suite

## 🚀 Usage

### For Developers

#### Adding a New Chain
```clarity
;; Register a new blockchain
(contract-call? .cross-chain-contract add-chain 
  "polygon" 
  "Polygon Network" 
  adapter-contract-principal
  u12  ;; confirmation blocks
  u2   ;; block time in seconds
  "MATIC"
  "wrapped"
  u100000 ;; base fee
  u150)   ;; fee multiplier
```

#### Creating a Liquidity Pool
```clarity
;; Add liquidity pool for a token
(contract-call? .cross-chain-contract add-pool
  "ethereum"
  "USDC"
  usdc-contract-principal
  u1000000  ;; min swap amount
  u100000000 ;; max swap amount
  u30)      ;; 0.3% fee
```

#### Initiating a Cross-Chain Swap
```clarity
;; Start an atomic cross-chain swap
(contract-call? .cross-chain-contract initiate-swap
  "ethereum"     ;; source chain
  "USDC"         ;; source token
  u1000000       ;; amount (1 USDC)
  "polygon"      ;; target chain
  "USDC"         ;; target token
  recipient-principal
  hash-lock
  u144)          ;; timeout in blocks
```

### For Liquidity Providers

1. **Provide Liquidity**: Deposit tokens to earn fees from swaps
2. **Monitor Performance**: Track rewards and pool utilization
3. **Withdraw Anytime**: Remove liquidity with accrued rewards

### For End Users

1. **Connect Wallet**: Use any Stacks-compatible wallet
2. **Select Assets**: Choose source and destination tokens/chains
3. **Review Route**: Check estimated fees and execution path
4. **Execute Swap**: Confirm transaction and wait for completion

## 📊 Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Protocol Fee | 0.25% | Fee charged on all swaps |
| Max Slippage | 1% | Maximum allowed price slippage |
| Min Liquidity | 1,000,000 μSTX | Minimum pool liquidity requirement |
| Default Timeout | 144 blocks | ~24 hours for swap completion |
| Max Route Hops | 3 | Maximum intermediate swaps in a route |
| Price Deviation | 2% | Maximum oracle price deviation allowed |
| Relayer Reward | 10% | Percentage of protocol fee for relayers |

## 🔐 Security Considerations

### Audits
- [ ] Smart contract security audit (planned)
- [ ] Economic model analysis (planned)
- [ ] Oracle manipulation testing (planned)

### Risk Factors
- **Smart Contract Risk**: Bugs in contract logic
- **Oracle Risk**: Price feed manipulation or failure
- **Liquidity Risk**: Insufficient liquidity for large swaps
- **Network Risk**: Blockchain congestion or downtime
- **Regulatory Risk**: Changes in cryptocurrency regulations

### Best Practices
- Start with small amounts for testing
- Verify token addresses and chain IDs
- Monitor transaction status and timeouts
- Keep private keys secure and use hardware wallets

## 🤝 Contributing

We welcome contributions from the community! Please see our contribution guidelines:

### Development Process
1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Test** your changes thoroughly
4. **Commit** with clear messages (`git commit -m 'Add amazing feature'`)
5. **Push** to your branch (`git push origin feature/amazing-feature`)
6. **Open** a Pull Request

### Code Standards
- Follow Clarity best practices
- Include comprehensive tests
- Document complex logic
- Use meaningful variable names
- Maintain consistent formatting

## 📈 Roadmap

### Phase 1: Core Protocol (Current)
- [x] Basic cross-chain swap functionality
- [x] HTLC implementation
- [x] Multi-chain support framework
- [ ] Price oracle integration
- [ ] Route optimization

### Phase 2: Enhanced Features
- [ ] Flash loan integration
- [ ] Governance token distribution
- [ ] Advanced routing algorithms
- [ ] Mobile-friendly interface
- [ ] Additional chain integrations

### Phase 3: Ecosystem Growth
- [ ] Third-party integrations
- [ ] Institutional features
- [ ] Cross-chain yield farming
- [ ] NFT bridging support
- [ ] Decentralized governance

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📧 Contact & Support

- **Documentation**: [Link to docs]
- **Discord**: [Community server]
- **Twitter**: [@CrossChainFlow]
- **Email**: support@crosschainflow.com

## ⚠️ Disclaimer

This software is experimental and under active development. Use at your own risk. The protocol has not been audited and may contain bugs or vulnerabilities. Never invest more than you can afford to lose.

---

**Built with ❤️ on Stacks | Powered by Bitcoin**
