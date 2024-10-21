// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGeniusProxyCall
 * @author @altloot, @samuel_vdu
 *
 * @notice Interface for the GeniusProxyCall contract which allows for the aggregation of multiple calls
 *         in a single transaction.
 */
interface IGeniusProxyCall {
    function execute(address target, bytes calldata data) external payable;

    function call(
        address receiver,
        address swapTarget,
        address callTarget,
        address stablecoin,
        address tokenOut,
        uint256 minAmountOut,
        bytes calldata swapData,
        bytes calldata callData
    ) external;

    function approveTokenExecuteAndVerify(
        address token,
        address target,
        bytes calldata data,
        address tokenOut,
        uint256 minAmountOut,
        address expectedTokenReceiver
    ) external payable;

    function approveTokenExecute(
        address token,
        address target,
        bytes calldata data
    ) external payable;

    function approveTokensAndExecute(
        address[] memory tokens,
        address to,
        bytes calldata data
    ) external payable;

    function transferTokenAndExecute(
        address token,
        address to,
        bytes calldata data
    ) external payable;

    function transferTokensAndExecute(
        address[] memory tokens,
        address to,
        bytes calldata data
    ) external payable;

    function multiSend(bytes memory transactions) external payable;
}
