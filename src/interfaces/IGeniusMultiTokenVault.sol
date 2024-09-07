// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IGeniusVault} from "./IGeniusVault.sol";

/**
 * @title IGeniusMultiTokenVault
 * @author looter
 * 
 * @notice The GeniusMultiTokenVault contract facilitates cross-chain
 *         liquidity management and swaps, utilizing multiple sources of liquidity.
 */
interface IGeniusMultiTokenVault is IGeniusVault {
    
    /**
     * @notice Emitted when a swap is executed.
     * @param token The address of the token that was swapped.
     * @param amount The amount of tokens that were swapped.
     * @param stableDelta The amount of stablecoins that were swapped.
     */
    event SwapExecuted(
        address token,
        uint256 amount,
        uint256 stableDelta
    );

    /**
     * @notice Emitted when the balance of a token is updated due to token
     *         swaps or liquidity additions.
     * @param token The address of the token.
     * @param oldBalance The previous balance of the token.
     * @param newBalance The new balance of the token.
     */
    event BalanceUpdate(
        address token,
        uint256 oldBalance,
        uint256 newBalance
    );

    /**
     * @notice Emitted when there is an unexpected decrease in the balance of a token.
     * @param token The address of the token.
     * @param expectedBalance The expected balance of the token.
     * @param newBalance The actual new balance of the token.
     */
    event UnexpectedBalanceChange(
        address token,
        uint256 expectedBalance,
        uint256 newBalance
    );

    /**
     * Fethches the balance of a token in the vault.
     * @param token The address of the token.
     */
    function tokenBalance(address token) external view returns (uint256);

    /**
     * @notice Retrieves the balances of all supported tokens.
     * @return An array of balances for each supported token.
     */
    function supportedTokensBalances() external view returns (uint256[] memory);

    /**
     * @notice Manages (adds or removes) a token from the list of supported tokens.
     * @param token The address of the token to be managed.
     * @param isSupported True to add the token, false to remove it.
     */
    function manageToken(address token, bool isSupported) external;

    /**
     * @notice Swaps a specified amount of tokens or native currency to stablecoins.
     * @param token The address of the token to be swapped. Pass 0x0 for native currency.
     * @param amount The amount of tokens (or native) to be swapped.
     * @param target The address of the target contract to execute the swap.
     * @param data The calldata to be used when executing the swap on the target contract.
     */
    function swapToStables(
        address token,
        uint256 amount,
        address target,
        bytes calldata data
    ) external;

    /**
     * @notice Manages (adds or removes) a router.
     * @param router The address of the router to be managed.
     * @param authorize True to add the router, false to remove it.
     */
    function manageRouter(address router, bool authorize) external;

    /**
     * @notice Checks if a token is supported by the GeniusMultiTokenVault contract.
     * @param token The address of the token to check.
     * @return boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) external view returns (bool);

    /**
     * @notice Returns the number of supported tokens in the vault.
     * @return The count of supported tokens.
     */
    function supportedTokensCount() external view returns (uint256);

    /**
     * @notice Returns the address of a supported token at a specific index.
     * @param index The index of the supported token.
     * @return The address of the token at the given index.
     */
    function supportedTokensIndex(uint256 index) external view returns (address);
    
    /**
     * @notice Checks if a router is supported.
     * @param router The address of the router to check.
     * @return 1 if the router is supported, 0 otherwise.
     */
    function supportedRouters(address router) external view returns (uint256);
}