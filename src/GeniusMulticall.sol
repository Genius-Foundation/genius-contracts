// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {MultiSendCallOnly} from "./libs/MultiSendCallOnly.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GeniusMulticall
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusMulticall contract that handles multicalls
 */
contract GeniusMulticall is MultiSendCallOnly {
    using SafeERC20 for IERC20;

    IAllowanceTransfer public immutable PERMIT2;

    constructor(address _permit2) {
        PERMIT2 = IAllowanceTransfer(_permit2);
    }

    function executeWithPermit2(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature
    ) external payable {
        if (target == address(0)) revert GeniusErrors.NonAddress0();

        address[] memory tokensIn = _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            msg.sender
        );
        uint256 tokensInLength = tokensIn.length;

        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target);

        for (uint256 i; i < tokensInLength; i++) {
            if (tokensIn[i] != address(0)) {
                uint256 balance = IERC20(tokensIn[i]).balanceOf(address(this));
                if (balance > 0) {
                    IERC20(tokensIn[i]).safeTransfer(msg.sender, balance);
                }
            }
        }
    }

    /**
     * @dev internal function to permit and batch transfer tokens
     *
     * @param permitBatch the permit batch details
     * @param permitSignature the signature for the Permit2 transfer
     * @param owner the owner of the tokens being transferred
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner
    ) private returns (address[] memory tokensIn) {
        if (permitBatch.spender != address(this))
            revert GeniusErrors.InvalidSpender();

        uint256 detailsLength = permitBatch.details.length;
        tokensIn = new address[](detailsLength);

        PERMIT2.permit(owner, permitBatch, permitSignature);

        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                detailsLength
            );
        for (uint i; i < detailsLength; ++i) {
            tokensIn[i] = permitBatch.details[i].token;

            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: address(this),
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });
        }

        PERMIT2.transferFrom(transferDetails);
    }

    function multiSend(bytes memory transactions) external payable {
        if (address(this) != msg.sender)
            revert GeniusErrors.InvalidCallerMulticall();
        _multiSend(transactions);
    }
}
