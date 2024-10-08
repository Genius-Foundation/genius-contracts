// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusRouter} from "./interfaces/IGeniusRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

/**
 * @title GeniusRouter
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusRouter contract allows for the aggregation of multiple calls
 *         in a single transaction, as well as facilitating interactions with the GeniusVault contract.
 */
contract GeniusRouter is IGeniusRouter {
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    IERC20 public immutable override STABLECOIN;
    IGeniusVault public immutable VAULT;
    IAllowanceTransfer public immutable PERMIT2;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        CONSTRUCTOR                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    constructor(address permit2, address vault) {
        PERMIT2 = IAllowanceTransfer(permit2);
        VAULT = IGeniusVault(vault);

        STABLECOIN = VAULT.STABLECOIN();
        STABLECOIN.approve(address(VAULT), type(uint256).max);
    }

    /**
     * @dev See {IGeniusRouter-swapAndCreateOrder}.
     */
    function swapAndCreateOrder(
        bytes32 seed,
        address[] calldata tokensIn,
        uint256[] calldata amountsIn,
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        address owner,
        uint256 destChainId,
        uint256 fillDeadline,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable override {
        if (targets.length != data.length || data.length != values.length)
            revert GeniusErrors.ArrayLengthsMismatch();
        if (tokensIn.length != amountsIn.length)
            revert GeniusErrors.ArrayLengthsMismatch();
        if (msg.value != _sum(values))
            revert GeniusErrors.InvalidNativeAmount();

        for (uint256 i = 0; i < tokensIn.length; i++)
            IERC20(tokensIn[i]).safeTransferFrom(
                msg.sender,
                address(this),
                amountsIn[i]
            );

        _batchExecution(targets, data, values);

        uint256 delta = STABLECOIN.balanceOf(address(this));

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: seed,
            trader: VAULT.addressToBytes32(owner),
            receiver: receiver,
            tokenIn: VAULT.addressToBytes32(address(STABLECOIN)),
            tokenOut: tokenOut,
            amountIn: delta,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            srcChainId: block.chainid,
            fee: fee
        });

        VAULT.createOrder(order);
    }

    /**
     * @dev See {IGeniusRouter-swapAndCreateOrderPermit2}.
     */
    function swapAndCreateOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        address owner,
        uint256 destChainId,
        uint256 fillDeadline,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable override {
        if (targets.length != data.length || data.length != values.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        if (msg.value != _sum(values))
            revert GeniusErrors.InvalidNativeAmount();

        _permitAndBatchTransfer(permitBatch, permitSignature, owner);

        _batchExecution(targets, data, values);

        uint256 delta = STABLECOIN.balanceOf(address(this));

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: seed,
            trader: VAULT.addressToBytes32(owner),
            receiver: receiver,
            tokenIn: VAULT.addressToBytes32(address(STABLECOIN)),
            tokenOut: tokenOut,
            amountIn: delta,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            srcChainId: block.chainid,
            fee: fee
        });

        VAULT.createOrder(order);
    }

    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner
    ) private {
        if (permitBatch.spender != address(this)) {
            revert GeniusErrors.InvalidSpender();
        }
        PERMIT2.permit(owner, permitBatch, permitSignature);

        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                permitBatch.details.length
            );
        for (uint i; i < permitBatch.details.length; i++) {
            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: address(this),
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });
        }

        PERMIT2.transferFrom(transferDetails);
    }

    function _batchExecution(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) private {
        for (uint i; i < targets.length; i++) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success)
                revert GeniusErrors.ExternalCallFailed(targets[i], i);
        }
    }

    /**
     * @dev Sums the amounts in an array.
     * @param amounts The array of amounts to be summed.
     */
    function _sum(
        uint256[] calldata amounts
    ) internal pure returns (uint256 total) {
        for (uint i; i < amounts.length; i++) {
            total += amounts[i];
        }
    }

    /**
     * @dev Fallback function to prevent native tokens from being sent directly.
     */
    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}
