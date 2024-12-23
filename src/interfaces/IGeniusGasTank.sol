// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

/**
 * @title IGeniusGasTank
 * @notice Interface for the GeniusGasTank contract that handles sponsored transactions using Permit2
 */
interface IGeniusGasTank {
    event OrderedTransactionsSponsored(
        address indexed sender,
        address indexed owner,
        address indexed target,
        address feeToken,
        uint256 feeAmount,
        uint256 nonce
    );

    event UnorderedTransactionsSponsored(
        address indexed sender,
        address indexed owner,
        address indexed target,
        address feeToken,
        uint256 feeAmount,
        bytes32 seed
    );

    event FeeRecipientUpdated(address newFeeRecipient);

    /**
     * @notice Emitted when the proxy call address is changed.
     * @param newProxyCall The new proxy call address.
     */
    event ProxyCallChanged(address newProxyCall);

    /**
     * @notice Returns the current nonce for a given owner address
     * @param owner The address to check the nonce for
     * @return The current nonce value
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @notice Executes a sponsored transaction with ordered nonce checking
     * @param target The contract to execute the call on
     * @param data The calldata to execute
     * @param permitBatch The Permit2 batch transfer details
     * @param permitSignature The signature for the Permit2 transfer
     * @param owner The owner of the tokens being transferred
     * @param feeToken The token used to pay the fee
     * @param feeAmount The amount of fee to be paid
     * @param deadline The deadline for execution
     * @param signature The owner's signature authorizing the transaction
     */
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
    ) external payable;

    /**
     * @notice Executes a sponsored transaction with seed-based replay protection
     * @param target The contract to execute the call on
     * @param data The calldata to execute
     * @param permitBatch The Permit2 batch transfer details
     * @param permitSignature The signature for the Permit2 transfer
     * @param owner The owner of the tokens being transferred
     * @param feeToken The token used to pay the fee
     * @param feeAmount The amount of fee to be paid
     * @param deadline The deadline for execution
     * @param seed Unique identifier to prevent replay attacks
     * @param signature The owner's signature authorizing the transaction
     */
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
    ) external payable;

    /**
     * @notice Executes a direct transaction using Permit2 without sponsorship
     * @param target The contract to execute the call on
     * @param data The calldata to execute
     * @param permitBatch The Permit2 batch transfer details
     * @param permitSignature The signature for the Permit2 transfer
     * @param feeToken The token used to pay the fee
     * @param feeAmount The amount of fee to be paid
     * @param toApprove The address that will approve the transaction
     */
    function aggregateWithPermit2(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address feeToken,
        uint256 feeAmount,
        address toApprove
    ) external payable;

    /**
     * @notice Updates the address that receives transaction fees
     * @param _feeRecipient The new fee recipient address
     */
    function setFeeRecipient(address payable _feeRecipient) external;

    /**
     * @notice Set the proxy call contract address
     * @param _proxyCall The new proxy call contract address
     */
    function setProxyCall(address _proxyCall) external;

    /**
     * @notice Pauses the contract and locks all functionality in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;
}
