// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

interface IGeniusGasTank {
    event OrderedTransactionsSponsored(
        address indexed sender,
        address indexed owner,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 nonce,
        uint256 txnsCount
    );

    event UnorderedTransactionsSponsored(
        address indexed sender,
        address indexed owner,
        address indexed feeToken,
        uint256 feeAmount,
        bytes32 seed,
        uint256 txnsCount
    );

    event FeeRecipientUpdated(address newFeeRecipient);

    event AllowedTarget(address indexed target, bool indexed isAllowed);

    function nonces(address owner) external view returns (uint256);

    function sponsorOrderedTransactions(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        bytes calldata signature
    ) external payable;

    function sponsorUnorderedTransactions(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        bytes32 seed,
        bytes calldata signature
    ) external payable;

    function setFeeRecipient(address payable _feeRecipient) external;

    function setAllowedTarget(address target, bool isAllowed) external;

    /**
     * @notice Pauses the contract and locks all functionality in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;
}
