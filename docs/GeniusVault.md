# GeniusVault Documentation

## Overview

GeniusVault is a sophisticated cross-chain stablecoin bridge implementing an intent-based architecture with EVM and Solana compatibility. The system utilizes Chainlink price feeds to protect against stablecoin depegs and implements a secure stake-and-bridge mechanism.

## Key Features

- Cross-chain stablecoin bridging
- Price-based deposit protection using Chainlink oracles
- Stake-based liquidity provision
- Intent-based order system
- Fee collection and distribution
- Upgradeable architecture (UUPS pattern)
- Emergency pause functionality
- Role-based access control

## Notes

- All addresses are stored as left-padded bytes32 for Solana compatibility

## Core Components

### State Variables

- `STABLECOIN`: The ERC20 stablecoin token used in the vault
- `feesCollected`: Total fees collected from operations
- `feesClaimed`: Total fees claimed by administrators
- `totalStakedAssets`: Total amount of staked assets in the vault
- `rebalanceThreshold`: Threshold for rebalancing operations (basis points)
- `stablecoinPriceFeed`: Chainlink price feed for stablecoin
- `orderStatus`: Mapping tracking the status of orders

### Price Bounds

- `PRICE_LOWER_BOUND`: 0.98 (98_000_000 with 8 decimals)
- `PRICE_UPPER_BOUND`: 1.02 (102_000_000 with 8 decimals)

### Access Control Roles

- `DEFAULT_ADMIN_ROLE`: Full administrative access
- `PAUSER_ROLE`: Can pause the contract
- `ORCHESTRATOR_ROLE`: Handles cross-chain operations

## Key Functions

### Initialization

```solidity
function initialize(
    address _stablecoin,
    address _admin,
    address _multicall,
    uint256 _rebalanceThreshold,
    address _priceFeed
) external initializer
```

Initializes the vault with required parameters including stablecoin address, admin address, and price feed configuration.

### Order Management

```solidity
function createOrder(Order memory order) external payable
```
Creates a new cross-chain bridge order with the following validations:
- Verifies stablecoin price is within bounds
- Validates order parameters (amounts, addresses, chain IDs)
- Ensures minimum fee requirements are met
- Transfers tokens to the vault

### Liquidity Management

```solidity
function stakeDeposit(uint256 amount, address receiver) external
```
Allows users to stake stablecoins and receive gUSD tokens in return.

```solidity
function stakeWithdraw(uint256 amount, address receiver, address owner) external
```
Enables withdrawal of staked assets, burning gUSD tokens in the process.

```solidity
function rebalanceLiquidity(
    uint256 amountIn,
    uint256 dstChainId,
    address target,
    bytes calldata data
) external payable
```
Allows orchestrators to rebalance liquidity across chains.

### Fee Management

```solidity
function claimableFees() public view returns (uint256)
```
Returns the amount of fees that can be claimed.

```solidity
function claimFees(uint256 amount, address token) external
```
Allows orchestrators or admins to claim accumulated fees.

## Security Features

### Price Protection
The contract implements price-based protection through Chainlink price feeds:
- Verifies price feed staleness
- Ensures price remains within 0.98-1.02 range
- Prevents operations during price deviations

### Access Controls
- Role-based access control for administrative functions
- Separate roles for pausing, orchestration, and administration
- Non-reentrant function guards where necessary

### Emergency Controls
```solidity
function pause() external onlyPauser
function unpause() external onlyAdmin
```
Emergency pause functionality to stop operations in case of detected issues.

## Events

- `OrderCreated`: Emitted when a new order is created
- `OrderFilled`: Emitted when an order is filled
- `StakeDeposit`: Emitted on successful stake deposits
- `StakeWithdraw`: Emitted on successful stake withdrawals
- `FeesClaimed`: Emitted when fees are claimed
- `RebalancedLiquidity`: Emitted during liquidity rebalancing

## Technical Considerations

### Upgradability
- Implements UUPS upgradeable pattern
- Uses storage gaps for future upgrades
- Initializer pattern for proper initialization

### Fee Structure
- Minimum fee requirements per target chain
- Fee collection and distribution system
- Claimable fee tracking

### Liquidity Management
- Maintains minimum liquidity requirements
- Rebalancing threshold system
- Available assets calculation

## Integration Guidelines

### Order Creation
1. Approve STABLECOIN transfer to vault
2. Create order with required parameters
3. Handle emitted events for order tracking

### Staking Process
1. Approve STABLECOIN transfer
2. Call stakeDeposit
3. Receive gUSD tokens
4. Track StakeDeposit event

### Chain Integration
- Implement corresponding contracts on target chains
- Configure minimum fees per chain
- Set up proper orchestrator infrastructure

## Security Recommendations

1. Always verify price feed status before operations
2. Implement proper monitoring for pause events
3. Monitor rebalancing operations
4. Track fee accumulation and claims
5. Maintain proper access control management
6. Regular audits of upgrades and changes

## Limitations and Constraints

1. Only supports single stablecoin configuration
2. Requires active Chainlink price feeds
3. Dependent on orchestrator availability
4. Subject to minimum liquidity requirements
5. Cross-chain operations limited by gas costs

## Error Handling

The contract uses custom errors defined in GeniusErrors for clear error reporting:
- `NonAddress0`: Zero address validation
- `InvalidAmount`: Amount validation
- `InvalidTokenIn`: Token validation
- `InsufficientFees`: Fee requirement validation
- `PriceOutOfBounds`: Price protection errors
- `StalePrice`: Price feed staleness checks

## Future Considerations

1. Multi-token support
2. Dynamic fee adjustment
3. Enhanced price feed redundancy
4. Governance implementation
5. Advanced rebalancing strategies