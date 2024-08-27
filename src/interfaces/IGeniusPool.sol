// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGeniusPool
 * @author looter
 * 
 * @notice Interface for the GeniusPool contract that allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps,
 *         and other Genius related activities.
 */
interface IGeniusPool {
    // =============================================================
    //                          EVENTS
    // =============================================================

    /**
     * @dev Emitted when a trader stakes their funds in the GeniusPool contract.
     * @param trader The address of the trader who is staking their funds.
     * @param amountDeposited The amount of funds being deposited by the trader.
     * @param newTotalDeposits The new total amount of funds deposited in the GeniusPool contract after the stake.
     */
    event Stake(
        address indexed trader,
        uint256 amountDeposited,
        uint256 newTotalDeposits
    );

    /**
     * @dev Emitted when a trader unstakes their funds from the GeniusPool contract.
     * @param trader The address of the trader who unstaked their funds.
     * @param amountWithdrawn The amount of funds that were withdrawn by the trader.
     * @param newTotalDeposits The new total amount of deposits in the GeniusPool contract after the withdrawal.
     */
    event Unstake(
        address indexed trader,
        uint256 amountWithdrawn,
        uint256 newTotalDeposits
    );

    /**
     * @dev Emitted when a swap deposit is made.
     * @param trader The address of the trader who made the deposit.
     * @param amountDeposited The amount of tokens deposited.
     */
    event SwapDeposit(
        address indexed trader,
        address token,
        uint256 amountDeposited
    );

    /**
     * @dev Emitted when a swap withdrawal occurs.
     * @param trader The address of the trader who made the withdrawal.
     * @param amountWithdrawn The amount that was withdrawn.
     */
    event SwapWithdrawal(
        address indexed trader,
        uint256 amountWithdrawn
    );

    /**
     * @dev Emitted when funds are bridged to another chain.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event BridgeFunds(
        uint256 amount,
        uint16 chainId
    );

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Initializes the GeniusVault contract.
     * @param vaultAddress The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address vaultAddress, address executor) external;

    function totalAssets() external view returns (uint256);

    function minAssetBalance() external view returns (uint256);

    function availableAssets() external view returns (uint256);

    /**
     * @dev Removes liquidity from a bridge pool and swaps it to the destination chain.
     * @param amountIn The amount of tokens to remove from the bridge pool.
     * @param dstChainId The chain ID of the destination chain.
     * @param targets The array of target addresses to call.
     * @param values The array of values to send along with the function calls.
     * @param data The array of function call data.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint16 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external payable;

    /**
     * @notice Deposits tokens into the vault
     * @param trader The address of the trader that tokens are being deposited for
     * @param amount The amount of tokens to deposit
     * @notice Emits a SwapDeposit event with the trader's address, the token address, and the amount of tokens swapped.
     */
    function addLiquiditySwap(
        address trader,
        address token,
        uint256 amount
    ) external;

    /**
     * @dev Removes liquidity from the GeniusPool contract by swapping stablecoins for the specified amount.
     *      Only the orchestrator can call this function.
     * @param trader The address of the trader to use for 
     * @param amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external;

    /**
     * @dev Removes reward liquidity from the GeniusPool contract.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external;

    /**
     * @dev Allows a user to stake liquidity tokens.
     * @param trader The address of the trader who is staking the liquidity tokens.
     * @param amount The amount of liquidity tokens to stake.
     */
    function stakeLiquidity(address trader, uint256 amount) external;

    /**
     * @dev Removes staked liquidity from the GeniusPool contract.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of liquidity to be removed.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external;

    /**
     * @dev Sets the rebalance threshold for the GeniusPool contract.
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external;

    /**
     * @dev Pauses the contract and locks all functionality in case of an emergency.
     * This function sets the `Paused` state to true, preventing all contract operations.
     */
    function emergencyLock() external;

    /**
     * @dev Allows the owner to emergency unlock the contract.
     * This function sets the `Paused` state to true, allowing normal contract operations to resume.
     */
    function emergencyUnlock() external;

    /**
     * @dev Returns the current state of the assets in the GeniusPool contract.
     * @return totalAssets The total number of assets in the pool.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the pool.
     */
    function assets() external view returns (uint256, uint256, uint256);

    // =============================================================
    //                          VARIABLES
    // =============================================================

    function STABLECOIN() external view returns (IERC20);
    function VAULT() external view returns (address);
    function initialized() external view returns (uint256);
    function totalStakedAssets() external view returns (uint256);
    function rebalanceThreshold() external view returns (uint256);
}