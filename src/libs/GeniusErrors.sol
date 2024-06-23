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
     * @dev Error thrown when an invalid amount is passed to a function.
     */
    error InvalidAssetAmount(uint256 assets, uint256 shares);

    /**
    * @dev Error thrown when the contract needs to be rebalanced.
    */
     error NeedsRebalance(uint256 totalStakedAssets, uint256 availableAssets);

    /**
     * @dev Error thrown when an approval fails.
     */
    error ApprovalFailure(address token, uint256 amount);

    /**
     * @dev Error thrown when an external call fails.
     */
    error ExternalCallFailed(address target, uint256 index);

    /**
     * @dev Error thrown when there is insufficient native balance.
     */
    error InsufficientNativeBalance(uint256 expectedAmount, uint256 actualAmount);

    /**
     * @dev Error thrown when there is a residual STABLECOIN balance after a transfer.
     */
    error ResidualBalance(uint256 amount);

    /**
     * @dev Error thrown when there is insufficient STABLECOIN balance.
     */
    error InsufficentBalance(uint256 amount, uint256 balance);

    /**
     * @dev Error thrown when there is insufficient LP token balance.
     */
    error InvalidToken(address token);
}