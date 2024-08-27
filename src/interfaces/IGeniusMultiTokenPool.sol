// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGeniusMultiTokenPool
 * @author looter
 * 
 * @notice The GeniusMultiTokenPool contract helps to facilitate cross-chain
 *         liquidity management and swaps and can utilize multiple sources of liquidity.
 */
interface IGeniusMultiTokenPool {
    // Structs
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    struct TokenInfo {
        bool isSupported;
        uint256 balance;
    }

    // Events
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
     * @dev Emitted when a swap is executed.
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
     * @dev Emitted when a swap deposit is made.
     * @param trader The address of the trader who made the deposit.
     * @param token The address of the token deposited.
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

    /**
     * @dev Emitted when the contract receives funds from a bridge.
     * @param amount The amount of funds received.
     * @param chainId The chain ID that funds are received from.
     */
    event ReceiveBridgeFunds(
        uint256 amount,
        uint16 chainId
    );

    /**
     * @dev Emitted when the balance of a token is updated due to token
     *      swaps or liquidity additions.
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
     * @dev Emitted when there is an excess balance of a token.
     * @param token The address of the token.
     * @param excess The amount of excess tokens.
     */
    event ExcessBalance(
        address token,
        uint256 excess
    );

    /**
     * @dev Emitted when there is an unexpected decrease in the balance of a token.
     * @param token The address of the token.
     * @param expectedBalance The new balance of the token.
     * @param newBalance The previous balance of the token.
     */
    event UnexpectedBalanceChange(
        address token,
        uint256 expectedBalance,
        uint256 newBalance
    );

    // Functions
    /**
     * @dev Initializes the GeniusMultiTokenPool contract.
     * @param executor The address of the executor.
     * @param vaultAddress The address of the GeniusVault contract.
     * @param tokens The array of token addresses to be supported by the contract.
     * @param bridges The array of bridge addresses to be supported.
     * @param routers The array of router addresses to be supported.
     * @notice This function can only be called once by the contract owner.
     * @notice Once initialized, the `VAULT` address cannot be changed.
     */
    function initialize(
        address executor,
        address vaultAddress,
        address[] memory tokens,
        address[] memory bridges,
        address[] memory routers
    ) external;

    /**
     * @dev Manages (adds or removes) a token from the list of supported tokens.
     * @param token The address of the token to be managed.
     * @param isSupported True to add the token, false to remove it.
     */
    function manageToken(address token, bool isSupported) external;

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
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external payable;

    /**
     * @dev Returns the total assets in the pool.
     * @return The total amount of assets in the pool.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @dev Returns the minimum asset balance required in the pool.
     * @return The minimum asset balance.
     */
    function minAssetBalance() external view returns (uint256);

    /**
     * @dev Returns the available assets in the pool.
     * @return The amount of available assets.
     */
    function availableAssets() external view returns (uint256);

    /**
     * @dev Adds liquidity to the GeniusMultiTokenPool contract by swapping tokens.
     * @param trader The address of the trader who is adding liquidity.
     * @param token The address of the token being swapped.
     * @param amount The amount of tokens being swapped.
     */
    function addLiquiditySwap(
        address trader,
        address token,
        uint256 amount
    ) external payable;

    /**
     * @dev Removes liquidity from the GeniusMultiTokenPool contract by swapping stablecoins for the specified amount.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of stablecoins to be swapped and transferred to the caller.
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external;

    /**
     * @dev Removes reward liquidity from the GeniusMultiTokenPool contract.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external;

    /**
     * @dev Swaps a specified amount of tokens or native currency to stablecoins.
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
     * @dev Stakes liquidity into the GeniusMultiTokenPool.
     * @param trader The address of the trader staking the liquidity.
     * @param amount The amount of liquidity to be staked.
     */
    function stakeLiquidity(address trader, uint256 amount) external;

    /**
     * @dev Removes staked liquidity from the GeniusMultiTokenPool contract.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of liquidity to be removed.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external;

    /**
     * @dev Sets the rebalance threshold for the GeniusMultiTokenPool contract.
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external;

    /**
     * @dev Authorizes or unauthorizes a bridge target.
     * @param bridge The address of the bridge target to be managed.
     * @param authorize True to authorize the bridge, false to unauthorize it.
     */
    function manageBridge(address bridge, bool authorize) external;

    /**
     * @dev Manages (adds or removes) a router.
     * @param router The address of the router to be managed.
     * @param authorize True to add the router, false to remove it.
     */
    function manageRouter(address router, bool authorize) external;

    /**
     * @dev Pauses the contract and locks all functionality in case of an emergency.
     */
    function emergencyLock() external;

    /**
     * @dev Allows the owner to emergency unlock the contract.
     */
    function emergencyUnlock() external;

    /**
     * @dev Checks if a token is supported by the GeniusMultiTokenPool contract.
     * @param token The address of the token to check.
     * @return boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) external view returns (bool);

    /**
     * @dev Returns the balances of the stablecoins in the GeniusMultiTokenPool contract.
     * @return currentStables The current total balance of stablecoins in the pool.
     * @return availStables The available balance of stablecoins in the pool.
     * @return stakedStables The total balance of staked stablecoins in the pool.
     */
    function stablecoinBalances() external view returns (
        uint256 currentStables,
        uint256 availStables,
        uint256 stakedStables
    );

    /**
     * @dev Retrieves the balances of supported tokens.
     * @return array of TokenBalance structs containing the token address and balance.
     */
    function supportedTokenBalances() external view returns (TokenBalance[] memory);

    // Additional view functions
    function STABLECOIN() external view returns (IERC20);
    function NATIVE() external view returns (address);
    function VAULT() external view returns (address);
    function initialized() external view returns (uint256);
    function totalStakedAssets() external view returns (uint256);
    function rebalanceThreshold() external view returns (uint256);
    function supportedTokensCount() external view returns (uint256);
    function tokenInfo(address) external view returns (bool isSupported, uint256 balance);
    function supportedTokensIndex(uint256) external view returns (address);
    function tokenBalances(address) external view returns (uint256);
    function supportedBridges(address) external view returns (uint256);
    function supportedRouters(address) external view returns (uint256);
}