// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

/**
 * @title IGeniusGenericBundler
 * @notice Interface for the GeniusGenericBundler contract that handles sponsored transactions using Permit2
 */
interface IGeniusGenericBundler {
    event FeeRecipientUpdated(address newFeeRecipient);

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
     * @notice Pauses the contract and locks all functionality in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;
}
