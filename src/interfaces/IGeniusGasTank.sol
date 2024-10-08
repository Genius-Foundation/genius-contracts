// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

interface IGeniusGasTank {
    event TransactionsSponsored(
        address indexed sender,
        address indexed owner,
        address indexed feeToken,
        uint256 feeAmount,
        uint256 nonce,
        uint256 txnsCount
    );

    event FeeRecipientUpdated(address newFeeRecipient);

    event AllowedTarget(address indexed target, bool indexed isAllowed);

    function nonces(address owner) external view returns (uint256);

    function sponsorTransactions(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address feeToken,
        uint256 feeAmount,
        bytes calldata signature
    ) external payable;

    function setFeeRecipient(address payable _feeRecipient) external;

    function setAllowedTarget(address target, bool isAllowed) external;
}
