// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";
import {MultiSendCallOnly} from "./libs/MultiSendCallOnly.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title GeniusProxyCall
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusProxyCall contract allows for the aggregation of multiple calls
 *         in a single transaction.
 */
contract GeniusProxyCall is IGeniusProxyCall, MultiSendCallOnly {
    using SafeERC20 for IERC20;

    /**
     * @dev See {IGeniusProxyCall-aggregate}.
     */
    function execute(
        address target,
        bytes calldata data
    ) external payable override {
        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);
    }

    function call(
        address receiver,
        address swapTarget,
        address callTarget,
        address stablecoin,
        address tokenOut,
        uint256 minAmountOut,
        bytes calldata swapData,
        bytes calldata callData
    ) external override returns (bool) {
        bool _success = true;

        bool isSwap = swapTarget != address(0);
        bool isCall = callTarget != address(0);
        if (isSwap) {
            bytes memory wrappedSwapData = abi.encodeWithSelector(
                IGeniusProxyCall.approveTokenExecuteAndVerify.selector,
                stablecoin,
                swapTarget,
                swapData,
                tokenOut,
                minAmountOut,
                isCall ? callTarget : receiver
            );
            (_success, ) = address(this).call(wrappedSwapData);
            if (!_success) {
                IERC20(stablecoin).safeTransfer(
                    receiver,
                    IERC20(stablecoin).balanceOf(address(this))
                );
                return _success;
            }
        }

        if (isCall) {
            bytes memory wrappedCallData;

            if (isSwap) {
                wrappedCallData = abi.encodeWithSelector(
                    IGeniusProxyCall.transferTokenAndExecute.selector,
                    tokenOut,
                    callTarget,
                    callData
                );
            } else {
                wrappedCallData = abi.encodeWithSelector(
                    IGeniusProxyCall.approveTokenExecute.selector,
                    tokenOut,
                    callTarget,
                    callData
                );
            }
            (_success, ) = address(this).call(wrappedCallData);
        }

        uint256 balance = IERC20(tokenOut).balanceOf(receiver);

        if (balance > 0) {
            IERC20(tokenOut).safeTransfer(receiver, balance);
        }
        return _success;
    }

    function approveTokenExecuteAndVerify(
        address token,
        address target,
        bytes calldata data,
        address tokenOut,
        uint256 minAmountOut,
        address expectedTokenReceiver
    ) external payable override {
        approveTokenExecute(token, target, data);

        uint256 balance = IERC20(tokenOut).balanceOf(expectedTokenReceiver);
        if (balance < minAmountOut)
            revert GeniusErrors.InvalidAmountOut(balance, minAmountOut);
    }

    function approveTokenExecute(
        address token,
        address target,
        bytes calldata data
    ) public payable override {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (target == address(this)) {
            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);
        } else {
            IERC20(token).approve(target, type(uint256).max);

            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

            IERC20(token).approve(target, 0);
        }
    }

    function approveTokensAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data
    ) external payable override {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (target == address(this)) {
            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);
        } else {
            uint256 tokensLength = tokens.length;
            for (uint i; i < tokensLength; i++) {
                IERC20(tokens[i]).approve(target, type(uint256).max);
            }

            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

            for (uint i; i < tokensLength; i++) {
                IERC20(tokens[i]).approve(target, 0);
            }
        }
    }

    function transferTokenAndExecute(
        address token,
        address target,
        bytes calldata data
    ) external payable {
        IERC20(token).safeTransfer(
            target,
            IERC20(token).balanceOf(address(this))
        );
        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);
    }

    function transferTokensAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data
    ) external payable {
        uint256 tokensLength = tokens.length;
        for (uint i; i < tokensLength; i++) {
            IERC20(tokens[i]).safeTransfer(
                target,
                IERC20(tokens[i]).balanceOf(address(this))
            );
        }
        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);
    }

    function multiSend(bytes memory transactions) external payable {
        if (address(this) != msg.sender)
            revert GeniusErrors.InvalidCallerMulticall();
        _multiSend(transactions);
    }

    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}
