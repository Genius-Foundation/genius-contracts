// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IGeniusProxyCall
 * @author @altloot, @samuel_vdu
 *
 * @notice Interface for the GeniusProxyCall contract which allows for the aggregation of multiple calls
 *         in a single transaction.
 * @dev This interface defines the core functionality for executing batched transactions, managing token
 *      approvals, and handling token transfers within the GeniusProxyCall system.
 */
interface IGeniusProxyCall {
    /**
     * @notice Executes a single call to a target contract
     * @dev This function is restricted to approved callers and the contract itself
     * @param target The address of the contract to call
     * @param data The calldata to pass to the target contract
     */
    function execute(address target, bytes calldata data) external payable;

    /**
     * @notice Performs a sequence of operations: optional token swap 
     * followed by an optional contract call.
     * The swap is executed from an function of the contract called as an external function, 
     * so if the call revert because the amountOut is too low, the contract will revert the swap.
     * 
     * @param receiver The address that will receive any remaining tokens after the operations
     * @param swapTarget The target contract for the swap operation (address(0) if no swap needed)
     * @param callTarget The target contract for the subsequent call (address(0) if no call needed)
     * @param stablecoin The address of the input stablecoin token
     * @param tokenOut The desired output token address for the swap
     * @param minAmountOut The minimum amount of output tokens to receive from the swap
     * @param swapData The calldata for the swap operation
     * @param callData The calldata for the subsequent contract call
     * @return effectiveTokenOut The actual token that was output from the operations
     * @return effectiveAmountOut The actual amount of tokens that were output
     * @return success Whether the operations completed successfully
     */
    function call(
        address receiver,
        address swapTarget,
        address callTarget,
        address stablecoin,
        address tokenOut,
        uint256 minAmountOut,
        bytes calldata swapData,
        bytes calldata callData
    )
        external
        returns (
            address effectiveTokenOut,
            uint256 effectiveAmountOut,
            bool success
        );

    /**
     * @notice Approves a token for spending, executes a call, and verifies the output amount
     * @dev This function handles token approvals and verifies the received amount meets minimum requirements
     * @param token The token to approve for spending
     * @param target The target contract to call
     * @param data The calldata to pass to the target contract
     * @param tokenOut The expected output token address
     * @param minAmountOut The minimum amount of output tokens to receive
     * @param expectedTokenReceiver The address expected to receive the output tokens
     * @return amountOut The actual amount of tokens received
     */
    function approveTokenExecuteAndVerify(
        address token,
        address target,
        bytes calldata data,
        address tokenOut,
        uint256 minAmountOut,
        address expectedTokenReceiver
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Approves a token for spending and executes a call
     * @dev This function handles token approvals without verifying the output amount
     * @param token The token to approve for spending
     * @param target The target contract to call
     * @param data The calldata to pass to the target contract
     */
    function approveTokenExecute(
        address token,
        address target,
        bytes calldata data
    ) external payable;

    /**
     * @notice Approves multiple tokens for spending and executes a call
     * @dev This function handles multiple token approvals in a single transaction
     * @param tokens Array of token addresses to approve
     * @param to The target contract to approve tokens for and call
     * @param data The calldata to pass to the target contract
     */
    function approveTokensAndExecute(
        address[] memory tokens,
        address to,
        bytes calldata data
    ) external payable;

    /**
     * @notice Transfers a token to a target contract and executes a call
     * @dev This function transfers tokens before executing the call
     * @param token The token to transfer
     * @param to The target contract to receive tokens and execute call
     * @param data The calldata to pass to the target contract
     */
    function transferTokenAndExecute(
        address token,
        address to,
        bytes calldata data
    ) external payable;

    /**
     * @notice Transfers multiple tokens to a target contract and executes a call
     * @dev This function transfers multiple tokens before executing the call
     * @param tokens Array of token addresses to transfer
     * @param to The target contract to receive tokens and execute call
     * @param data The calldata to pass to the target contract
     */
    function transferTokensAndExecute(
        address[] memory tokens,
        address to,
        bytes calldata data
    ) external payable;

    /**
     * @notice Executes multiple transactions in a single call
     * @dev This function is restricted to internal calls only
     * @param transactions Encoded batch of transactions to execute
     */
    function multiSend(bytes memory transactions) external payable;
}
