# GeniusGasTank Contract Documentation

## Overview
The GeniusGasTank contract enables sponsored transactions using Permit2, allowing for gas-less transactions and meta-transactions on the EVM. It integrates with OpenZeppelin's AccessControl and Pausable patterns for secure administration.

## Key Features
- Permit2 integration for gasless approvals
- Support for both ordered and unordered transactions
- Fee management system
- Role-based access control
- Emergency pause functionality
- Batch transaction support

## Core Functions

### sponsorOrderedTransactions
Executes sponsored transactions in an ordered sequence.

```solidity
function sponsorOrderedTransactions(
    address target,
    bytes calldata data,
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    address owner,
    address feeToken,
    uint256 feeAmount,
    uint256 deadline,
    bytes calldata signature
) external payable
```

**Parameters:**
- `target`: Contract to interact with
- `data`: Encoded function call data
- `permitBatch`: Permit2 batch details
- `permitSignature`: Permit2 signature
- `owner`: Token owner
- `feeToken`: Token used for fee payment
- `feeAmount`: Fee amount
- `deadline`: Transaction deadline
- `signature`: Owner's signature

### sponsorUnorderedTransactions
Executes sponsored transactions without order dependency.
This was created to make limit orders possible.

```solidity
function sponsorUnorderedTransactions(
    address target,
    bytes calldata data,
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    address owner,
    address feeToken,
    uint256 feeAmount,
    uint256 deadline,
    bytes32 seed,
    bytes calldata signature
) external payable
```

Additional parameter:
- `seed`: Unique identifier to prevent replay attacks

### aggregateWithPermit2
Executes direct transactions with Permit2 integration.

```solidity
function aggregateWithPermit2(
    address target,
    bytes calldata data,
    IAllowanceTransfer.PermitBatch calldata permitBatch,
    bytes calldata permitSignature,
    address feeToken,
    uint256 feeAmount
) external payable
```

## Administrative Functions

### Access Control
- `setFeeRecipient(address payable _feeRecipient)`: Updates fee recipient address
- `setProxyCall(address _proxyCall)`: Updates proxy call contract address
- `pause()`: Pauses contract operations (PAUSER_ROLE)
- `unpause()`: Resumes contract operations (DEFAULT_ADMIN_ROLE)

## Security Features

### Roles
- `DEFAULT_ADMIN_ROLE`: Full administrative access
- `PAUSER_ROLE`: Can pause contract operations

### Safety Checks
1. Deadline validation
2. Signature verification
3. Balance checks
4. Address validation
5. Spender validation
6. Replay protection via nonces and seeds

### Error Handling
Custom errors defined in GeniusErrors:
- `IsNotAdmin()`
- `IsNotPauser()`
- `DeadlinePassed(uint256)`
- `InvalidSeed()`
- `NonAddress0()`
- `InvalidSpender()`
- `InsufficientBalance(address, uint256, uint256)`
- `InvalidSignature()`

## Events
- `OrderedTransactionsSponsored`
- `UnorderedTransactionsSponsored`
- `FeeRecipientUpdated`
- `ProxyCallChanged`

## Dependencies
- OpenZeppelin:
  - AccessControl
  - Pausable
  - IERC20
  - SafeERC20
  - ECDSA
  - MessageHashUtils
- Permit2: IAllowanceTransfer
- Custom: IGeniusGasTank, IGeniusProxyCall