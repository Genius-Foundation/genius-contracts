# Genius Protocol Overview

## Introduction

Genius Protocol is a sophisticated cross-chain liquidity management and transaction system built on EVM-compatible blockchains and Solana. The protocol enables secure cross-chain stablecoin transfers with price-based deposit protection, gas-efficient sponsored transactions, and advanced liquidity management capabilities.

## Core Components

### 1. GeniusVault
The central component of the protocol that manages cross-chain liquidity and stablecoin operations.

Key features:
- Cross-chain stablecoin bridging with price protection
- Staking mechanism with gUSD (Genius USD) tokens
- Chainlink price feed integration for stablecoin depeg protection
- Configurable rebalancing thresholds
- Fee collection and management
- Emergency pause functionality

### 2. GeniusMultiTokenVault
An advanced version of GeniusVault that supports multiple token types for cross-chain liquidity management.

Key features:
- Multi-token support including native tokens
- Token-specific fee management
- Separate fee collection and claiming per token
- Enhanced swap functionality
- Native token handling

### 3. GeniusGasTank
Handles sponsored transactions using the Permit2 standard.

Key features:
- Ordered and unordered transaction sponsorship
- Permit2 integration for gasless approvals
- Fee management system
- Batch transaction processing
- Access control with admin and pauser roles

### 4. GeniusRouter
Facilitates transaction aggregation and vault interactions.

Key features:
- Aggregates multiple calls in single transactions
- Integrates with GeniusVault for cross-chain operations
- Permit2-based token approvals
- Swap and order creation capabilities

### 5. GeniusProxyCall
Manages the execution of aggregated transactions.

Key features:
- Multi-call transaction execution
- Token approval management
- Secure external contract interactions
- Access control system

### 6. GeniusActions
Manages the protocol's action registry and authorization system.

Key features:
- Action registration and management
- IPFS integration for action metadata
- Orchestrator authorization system
- Emergency controls
- Action status management
- Commit hash authorization

## Security Features

1. **Price Protection**
   - Chainlink price feeds integration
   - Configurable price bounds (0.98 - 1.02)
   - Stale price checks

2. **Access Control**
   - Role-based access control (Admin, Pauser, Orchestrator, Sentinel)
   - Upgradeable contracts with UUPS pattern
   - Emergency pause functionality
   - Action-level authorization controls

3. **Transaction Safety**
   - Reentrancy protection
   - Safe ERC20 operations
   - Signature verification
   - Contract existence checks
   - Action verification system

4. **Liquidity Management**
   - Minimum liquidity thresholds
   - Rebalancing controls
   - Token-specific fee management
   - Multi-token support safeguards

## Key Workflows

### Cross-Chain Transfer
1. User creates order through GeniusRouter
2. Order is validated and processed by appropriate vault (GeniusVault or GeniusMultiTokenVault)
3. Fees are collected and managed per token
4. Target chain receives and processes the order
5. Funds are released to receiver

### Sponsored Cross-Chain Transfer
1. User signs Permit2 approval and transfer order
2. Relayer submits order through GeniusGasTank's sponsorOrderedTransactions
3. Token transfers and approvals are processed via Permit2
4. Order is created in source chain GeniusVault with relayer covering gas
5. Orchestrator monitors and executes order on destination chain
6. Receiver gets funds while relayer receives fee compensation

### Limit-Order using Non-Ordered Sponsored Txns
1. User signs limit order with price conditions and Permit2 approvals
2. Order includes unique seed to prevent replay attacks
3. Relayer monitors for market conditions matching limit price
4. When conditions met, relayer calls sponsorUnorderedTransactions
5. GeniusGasTank verifies seed uniqueness and signatures
6. Order executes on target DEX via ProxyCall with relayer paying gas
7. User receives swapped tokens, relayer gets fee compensation

### Sponsored Transactions
1. User signs transaction with Permit2
2. GeniusGasTank validates signature and permissions
3. Transaction is executed through ProxyCall
4. Fees are collected and distributed
5. Events are emitted for tracking

### Action Execution
1. Action is registered in GeniusActions
2. Action metadata is stored on IPFS
3. Orchestrators are authorized
4. Action execution is validated
5. Emergency controls available through Sentinel role

### Liquidity Management
1. Support for multiple token types
2. Token-specific fee collection
3. Separate liquidity pools
4. Configurable minimum thresholds
5. Native token handling

## Technical Specifications

### Upgradability
- UUPS (Universal Upgradeable Proxy Standard)
- Storage gaps for future upgrades
- Admin-controlled upgrade process

### Integration Points
1. **External**
   - Chainlink Price Feeds
   - Permit2 Contract
   - ERC20 Tokens
   - IPFS System

2. **Internal**
   - Multi-vault architecture
   - Cross-contract communication
   - Action registry system

### Error Handling
Comprehensive error system with custom errors:
- Price-related errors
- Access control errors
- Transaction validation errors
- Liquidity management errors
- Action execution errors

## Events

Important events emitted by the protocol:
- OrderCreated
- OrderFilled
- StakeDeposit
- StakeWithdraw
- RebalancedLiquidity
- FeesClaimed
- ActionAdded
- ActionStatusUpdated
- OrchestratorAuthorized
- SwapExecuted

## Protocol Parameters

1. **Price Bounds**
   - Lower: 0.98 (98_000_000)
   - Upper: 1.02 (102_000_000)

2. **Fees**
   - Chain-specific minimum fees
   - Token-specific fee tracking
   - Configurable fee recipient
   - Claimable fee tracking per token

3. **Rebalancing**
   - Configurable threshold (basis points)
   - Minimum liquidity requirements
   - Cross-chain balance management
   - Token-specific thresholds

## Action Registry

1. **Action Management**
   - IPFS-based metadata storage
   - Unique action identifiers
   - Status tracking
   - Version control

2. **Authorization**
   - Orchestrator permissions
   - Commit hash validation
   - Emergency controls
   - Admin oversight

## Security Considerations

### Risk Factors
1. Price feed manipulation
2. Cross-chain communication failures
3. Smart contract upgrade risks
4. Liquidity management risks
5. Action execution risks
6. Multi-token complexity

### Mitigations
1. Chainlink price feed integration
2. Multiple validation layers
3. Access control systems
4. Emergency pause functionality
5. Minimum liquidity requirements
6. Action registry controls
7. Sentinel role for emergency actions