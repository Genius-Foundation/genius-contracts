// SPDX-License-Identifier: MIT 

pragma solidity ^0.8.20;

library GeniusErrors {
    /**
     * @dev Error thrown when an invalid spender address is encountered.
     */
    error InvalidSpender();

    /**
     * @dev Error thrown when an invalid trader address is encountered.
     */
    error InvalidTrader();

    /**
     * @dev Error thrown when msg.sender is not the vault.
     */
    error IsNotVault();

    /**
     * @dev This library contains custom error definitions for the Genius contract.
     */
    error Paused();

    /**
     * @dev Error thrown when the contract is already initialized.
     */
    error Initialized();

    /**
     * @dev Error thrown when the contract is not initialized.
     */
    error NotInitialized();

    /**
     * @dev Error thrown when an invalid amount is encountered.
     */
    error InvalidAmount();

    /**
    * @dev Error thrown when the array lengths do not match.
    */
    error ArrayLengthsMismatch();

    /**
    * @dev Error thrown when the permit batch length is invalid.
    */
    error InvalidPermitBatchLength();

    /**
    * @dev Error thrown thrown when the msg.value is not sufficient.
    */
    error InvalidNativeAmount(uint256 amount);

    /**
     * @dev Error thrown when the target of a generic call is invalid.
     */
    error InvalidTarget(address invalidTarget);

    /**
     * @dev Error thrown when the target of a generic call is invalid.
     */
    error UnexpectedBalanceChange(address effectedToken);

    /**
     * @dev Error thrown when there is an insufficient amount of STABLECOIN available for rebalance
            or swaps in the contract.
     */
    error InsufficientLiquidity(uint256 availableLiquidity, uint256 requiredLiquidity);

    /**
     * @dev Error thrown when an invalid amount is passed to a function.
     * @param assets The amount that was passed.
     * @param shares The amount that was expected.
     */
    error InvalidAssetAmount(uint256 assets, uint256 shares);

    /**
     * @dev Error thrown when an approval fails.
     * @param token The address of the token that is required.
     * @param amount The amount that is required.
     */
    error ApprovalFailure(address token, uint256 amount);

    /**
     * @dev Error thrown when an approval fails.
     * @param token The address of the token that is required.
     * @param amount The amount that is required.
     */
    error TransferFailed(address token, uint256 amount);

    /**
     * @dev Error thrown when an external call fails.
     * @param target The address of the target contract.
     * @param index The index of the function that was called.
     */
    error ExternalCallFailed(address target, uint256 index);

    /**
     * @dev Error thrown when there is insufficient native balance.
     * @param expectedAmount The amount that is required.
     * @param actualAmount The amount that is available.
     */
    error InsufficientNativeBalance(uint256 expectedAmount, uint256 actualAmount);

    /**
     * @dev Error thrown when there is a residual STABLECOIN balance after an external call.
     * @param amount The amount that of STABLECOIN that would be left in the contract.
     */
    error ResidualBalance(uint256 amount);

    /**
     * @dev Error thrown when there is insufficient token balance.
     * @param token The address of the token.
     * @param amount The amount that is required.
     * @param balance The balance that is available.
     */
    error InsufficientBalance(address token, uint256 amount, uint256 balance);

    /**
     * @dev Thrown when a token address is invalid.
     * @param token The adddress of the invalid token.
     */
    error InvalidToken(address token);

    /**
     * @dev Thrown when attempting to set a threshold balance that would exceed the minimum STABLECOIN balance needed.
     * @param threshBal The threshold balance being attempted to set.
     * @param attemptedThreshBal The balance that would be exceeded if the threshold is set.
     */
    error ThresholdWouldExceed(uint256 threshBal, uint256 attemptedThreshBal);

}