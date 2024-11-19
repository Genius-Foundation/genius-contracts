# GeniusRouter Documentation

## Overview

GeniusRouter is a sophisticated contract that aggregates multiple calls and facilitates interactions with the GeniusVault contract. It provides advanced features for token swapping, order creation, and permit2 integration for gasless approvals.

## Key Features

- Multicall aggregation
- Permit2 integration for gasless approvals
- Token swap and order creation in single transaction
- Safe ERC20 token handling
- Direct vault interaction capabilities

## Core Components

### Immutable State Variables

- `STABLECOIN`: The ERC20 stablecoin token used in the system
- `VAULT`: Reference to the GeniusVault contract
- `PERMIT2`: Reference to Uniswap's Permit2 contract
- `PROXYCALL`: Reference to the proxy call contract for multicall functionality

## Key Functions

### Constructor
```solidity
constructor(address permit2, address vault, address proxycall)
```
Initializes the router with:
- Permit2 contract address
- Vault contract address
- Proxy call contract address
- Maximum approval for vault interactions

### Core Functions

#### Swap and Order Creation
```solidity
function swapAndCreateOrder(
    bytes32 seed,
    address[] calldata tokensIn,
    uint256[] calldata amountsIn,
    address target,
    bytes calldata data,
    address owner,
    uint256 destChainId,
    uint256 fee,
    bytes32 receiver,
    uint256 minAmountOut,
    bytes32 tokenOut
) public payable
```
Performs a token swap and creates a bridge order in one transaction:
- Accepts multiple input tokens
- Executes swap through target contract
- Creates order in the vault
- Handles token transfers and approvals

#### Permit2 Integration

```solidity
function swapAndCreateOrderPermit2(
    bytes32 seed,
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    address target,
    bytes calldata data,
    uint256 destChainId,
    uint256 fee,
    bytes32 receiver,
    uint256 minAmountOut,
    bytes32 tokenOut
) public payable
```
Gasless version of swapAndCreateOrder using Permit2:
- Batch permits for multiple tokens
- Signature-based approvals
- Integrated swap and order creation

```solidity
function createOrderPermit2(
    bytes32 seed,
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    uint256 destChainId,
    uint256 fee,
    bytes32 receiver,
    uint256 minAmountOut,
    bytes32 tokenOut
) external payable
```
Creates an order using Permit2 without swapping:
- Direct stablecoin transfer
- Signature-based approval
- Order creation in vault

## Internal Functions

### Permit and Transfer
```solidity
function _permitAndBatchTransfer(
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    address owner
) private returns (address[] memory tokensIn)
```
Handles permit2 operations:
- Validates permit details
- Processes signatures
- Executes batch transfers

## Security Features

### Transfer Safety
- Uses OpenZeppelin's SafeERC20 for token transfers
- Validates array lengths and parameters
- Checks for valid spender addresses

### Error Handling
Custom errors through GeniusErrors:
- `EmptyArray`: Empty input validation
- `ArrayLengthsMismatch`: Array length validation
- `InvalidSpender`: Spender address validation
- `InvalidTokenIn`: Token validation

### Native Token Protection
- Prevents direct ETH transfers
- Includes receive function with revert

## Integration Guidelines

### Direct Swap and Order
1. Approve tokens for router
2. Prepare swap data
3. Call swapAndCreateOrder with parameters
4. Handle transaction result

### Gasless Integration (Permit2)
1. Generate permit signature
2. Prepare permit batch
3. Call swapAndCreateOrderPermit2
4. Monitor order creation event

## Technical Considerations

### Gas Optimization
- Batch processing for multiple tokens
- Single transaction for swap and order
- Efficient approval management

### Permit2 Requirements
- Valid signatures
- Proper permit formatting
- Signature expiry management

### Proxy Call Integration
- Proper target contract validation
- Correct calldata formatting
- Value handling for ETH transactions

## Limitations and Constraints

1. Only supports permit2 compatible tokens
2. Requires valid permit signatures
3. Limited to supported swap targets
4. Must handle native token separately

## Best Practices

1. Validate all input parameters
2. Check permit signature validity
3. Verify token approvals
4. Monitor transaction success
5. Handle failed swaps appropriately

## Error Scenarios

1. Invalid permit signature
2. Insufficient token allowance
3. Failed swap execution
4. Invalid target contract
5. Incorrect token arrays

## Integration Examples

### Basic Swap and Order
```solidity
router.swapAndCreateOrder(
    seed,
    [tokenA, tokenB],
    [amount1, amount2],
    swapTarget,
    swapData,
    owner,
    destChainId,
    fee,
    receiver,
    minAmountOut,
    tokenOut
);
```

### Permit2 Integration
```solidity
router.swapAndCreateOrderPermit2(
    seed,
    permitBatch,
    signature,
    swapTarget,
    swapData,
    destChainId,
    fee,
    receiver,
    minAmountOut,
    tokenOut
);
```

## Future Considerations

1. Enhanced batch processing
2. Additional permit types support
3. Advanced swap routing
4. Gas optimization improvements
5. Cross-chain permit compatibility