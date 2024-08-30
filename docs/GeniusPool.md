# GeniusPool Contract Documentation

## Overview

The GeniusPool contract is a critical component of a cross-chain liquidity management system. It allows for the management of stablecoin assets across multiple blockchain networks, facilitating cross-chain swaps, liquidity provision, and rebalancing operations.

## Key Features

1. Cross-chain liquidity management
2. Order creation and execution for cross-chain swaps
3. Staking and unstaking of liquidity
4. Rebalancing threshold management
5. Emergency pause functionality

## Contract Details

- License: MIT
- Solidity Version: ^0.8.20
- Inherits from: `IGeniusPool`, `AccessControl`, `Pausable`

## Important State Variables

- `STABLECOIN`: The ERC20 token used as the stablecoin in the system
- `VAULT`: Address of the Vault contract where users stake their stablecoins
- `EXECUTOR`: Address of the Executor contract (controlled by orchestrators)
- `totalStakedAssets`: Total amount of stablecoin assets available to the pool
- `rebalanceThreshold`: Maximum percentage deviation from `totalStakedAssets` before blocking trades
- `totalOrders`: Total number of orders processed
- `orderStatus`: Mapping of order hashes to their current status

## Key Roles

- `DEFAULT_ADMIN_ROLE`: Can perform administrative actions
- `PAUSER_ROLE`: Can pause and unpause the contract
- `ORCHESTRATOR_ROLE`: Can perform orchestrator actions (including executor actions)

## Main Functions

### Liquidity Management

1. `stakeLiquidity(address trader, uint256 amount)`: Allows the Vault to stake liquidity on behalf of a trader
2. `removeStakedLiquidity(address trader, uint256 amount)`: Allows the Vault to remove staked liquidity on behalf of a trader
3. `removeBridgeLiquidity(uint256 amountIn, uint16 dstChainId, address[] memory targets, uint256[] calldata values, bytes[] memory data)`: Removes liquidity for bridging to another chain
4. `removeRewardLiquidity(uint256 amount)`: Removes reward liquidity from the pool

### Cross-Chain Swap Operations

1. `addLiquiditySwap(address trader, address tokenIn, uint256 amountIn, uint16 destChainId, uint32 fillDeadline)`: Initiates a cross-chain swap on the source chain
2. `removeLiquiditySwap(Order memory order)`: Completes a cross-chain swap on the destination chain
3. `setOrderAsFilled(Order memory order)`: Marks an order as filled on the source chain
4. `revertOrder(Order calldata order, address[] calldata targets, bytes[] calldata data, uint256[] calldata values)`: Reverts an unfilled order on the source chain

### Pool Management

1. `setRebalanceThreshold(uint256 threshold)`: Sets the rebalance threshold
2. `pause()`: Pauses all contract functions
3. `unpause()`: Unpauses the contract

## View Functions

1. `totalAssets()`: Returns the total assets in the pool
2. `minAssetBalance()`: Returns the minimum required asset balance
3. `availableAssets()`: Returns the available assets for operations
4. `assets()`: Returns total assets, available assets, and total staked assets
5. `orderHash(Order memory order)`: Calculates the hash of an order

## Events

- `Stake`: Emitted when liquidity is staked
- `Unstake`: Emitted when staked liquidity is removed
- `SwapDeposit`: Emitted when a cross-chain swap is initiated
- `SwapWithdrawal`: Emitted when a cross-chain swap is completed
- `OrderFilled`: Emitted when an order is filled
- `OrderReverted`: Emitted when an order is reverted
- `RemovedLiquidity`: Emitted when liquidity is removed for bridging

## Security Considerations

1. The contract uses OpenZeppelin's `AccessControl` for role-based access control
2. `Pausable` functionality is implemented for emergency situations
3. Rebalance threshold ensures a minimum liquidity is maintained
4. Order status tracking prevents double-spending and ensures proper order flow
5. Deadline checks on orders prevent execution of stale orders

## Cross-Chain Functionality

The GeniusPool contract is designed to work across multiple chains:

- It's deployed on each L1 and L2 chain in the system
- Some functions are specific to the source chain (e.g., `addLiquiditySwap`, `setOrderAsFilled`)
- Other functions are specific to the destination chain (e.g., `removeLiquiditySwap`)
- The contract facilitates bridging of assets between these chains

## Integration with Other Components

1. **Vault**: Users stake their stablecoins in the Vault to receive gUSD (geniusUSD). The Vault interacts with GeniusPool to manage staked liquidity.
2. **Executor**: Controlled by orchestrators, it has special permissions to execute certain functions in GeniusPool.
3. **Orchestrators**: Secure keys owned by a decentralized compute network. They can execute Lit Actions (JavaScript smart contracts) to interact with GeniusPool.

## Conclusion

The GeniusPool contract is a sophisticated liquidity management system designed for cross-chain operations. It provides a secure and efficient way to manage stablecoin assets across multiple blockchain networks, facilitating cross-chain swaps and maintaining liquidity balance. The contract's design emphasizes security, flexibility, and decentralized control through its integration with orchestrators and the Lit Protocol.