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
     * Fethches the balance of a token in the vault.
     * @param token The address of the token.
     */
    function tokenBalance(address token) external view returns (uint256);

    /**
     * @notice Manages (adds or removes) a token from the list of supported tokens.
     * @param token The address of the token to be managed.
     * @param isSupported True to add the token, false to remove it.
     */
    function setTokenSupported(address token, bool isSupported) external;

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
     * @notice Checks if a token is supported by the GeniusMultiTokenVault contract.
     * @param token The address of the token to check.
     * @return boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) external view returns (bool);

    event TokenSupported(address indexed token, bool indexed supported);

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
}