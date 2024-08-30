// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGeniusMultiTokenPool
 * @author looter
 * 
 * @notice The GeniusMultiTokenPool contract facilitates cross-chain
 *         liquidity management and swaps, utilizing multiple sources of liquidity.
 */
interface IGeniusMultiTokenPool {

    /**
     * @notice Enum representing the possible statuses of an order.
     * @dev Used to track the lifecycle of an order in the system.
     */
    enum OrderStatus {
        Nonexistant,
        Created,
        Filled,
        Reverted
    }

    /**
     * @notice Struct representing an order in the system.
     * @param amountIn The amount of tokens to be swapped.
     * @param orderId Unique identifier for the order.
     * @param trader Address of the trader initiating the order.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline by which the order must be filled.
     * @param tokenIn The address of the token to be swapped.
     */
    struct Order {
        uint256 amountIn;
        uint32 orderId;
        address trader;
        uint16 srcChainId;
        uint16 destChainId;
        uint32 fillDeadline; 
        address tokenIn;
    }

    /**
     * @notice Struct representing the balance of a token in the pool.
     * @param token The address of the token.
     * @param balance The balance of the token.
     */
    struct TokenBalance {
        address token;
        uint256 balance;
    }

    /**
     * @notice Struct to store information about a token.
     * @param isSupported Boolean indicating if the token is supported.
     * @param balance The balance of the token.
     */
    struct TokenInfo {
        bool isSupported;
        uint256 balance;
    }

    /**
     * @notice Emitted when a trader stakes their funds in the GeniusPool contract.
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
     * @notice Emitted when a trader unstakes their funds from the GeniusPool contract.
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
     * @notice Emitted on the source chain when a swap deposit is made.
     * @param orderId The unique identifier of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event SwapDeposit(
        uint32 indexed orderId,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint16 indexed destChainId,
        uint32 fillDeadline
    );

    /**
     * @notice Emitted on the destination chain when a swap withdrawal occurs.
     * @param orderId The unique identifier of the order.
     * @param trader The address of the trader.
     * @param tokenOut The address of the output token.
     * @param amountOut The amount of output tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event SwapWithdrawal(
        uint32 indexed orderId,
        address indexed trader,
        address tokenOut,
        uint256 amountOut,
        uint16 indexed srcChainId,
        uint16 destChainId,
        uint32 fillDeadline
    );

    /**
     * @notice Emitted on the source chain when an order is filled.
     * @param orderId The unique identifier of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event OrderFilled(
        uint32 indexed orderId,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint16 indexed destChainId,
        uint32 fillDeadline
    );

    /**
     * @notice Emitted on the source chain when an order is reverted.
     * @param orderId The unique identifier of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event OrderReverted(
        uint32 indexed orderId,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint16 indexed destChainId,
        uint32 fillDeadline
    );

    /**
     * @notice Emitted when liquidity are being rebalanced out.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event RemovedLiquidity(
        uint256 amount,
        uint16 chainId
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
     * @notice Emitted when there is an excess balance of a token.
     * @param token The address of the token.
     * @param excess The amount of excess tokens.
     */
    event ExcessBalance(
        address token,
        uint256 excess
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
     * @notice Manages (adds or removes) a token from the list of supported tokens.
     * @param token The address of the token to be managed.
     * @param isSupported True to add the token, false to remove it.
     */
    function manageToken(address token, bool isSupported) external;

    /**
     * @notice Removes liquidity from the bridge pool and swaps it to the destination chain for rebalancing.
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
     * @notice Returns the total assets in the pool.
     * @return The total amount of assets in the pool.
     */
    function totalAssets() external view returns (uint256);

    /**
     * @notice Returns the minimum asset balance required in the pool.
     * @return The minimum asset balance.
     */
    function minAssetBalance() external view returns (uint256);

    /**
     * @notice Returns the available assets in the pool.
     * @return The amount of available assets.
     */
    function availableAssets() external view returns (uint256);

    /**
     * @notice Adds liquidity to a source chain on the GeniusMultiTokenPool contract within a cross-chain swap flow.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    function addLiquiditySwap(
        address trader,
        address tokenIn,
        uint256 amountIn,
        uint16 destChainId,
        uint32 fillDeadline
    ) external payable;

    /**
     * @notice Removes liquidity on the destination chain from the GeniusMultiTokenPool contract within a cross-chain swap flow.
     * @param order The Order struct containing the order details.
     */
    function removeLiquiditySwap(
        Order memory order
    ) external;

    /**
     * @notice Sets the status of an order as filled on the source chain.
     * @param order The Order struct containing the order details.
     */
    function setOrderAsFilled(Order memory order) external;

    /**
     * @notice Reverts an order on the source and executes revert actions.
     * @param order The Order struct containing the order details.
     * @param targets The array of target addresses to call.
     * @param data The array of function call data.
     * @param values The array of values to send along with the function calls.
     * @dev Can only be called by an orchestrator, 
     * when the fill deadline has passed and the order was not filled.
     */
    function revertOrder(
        Order memory order, 
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external;

    /**
     * @notice Removes reward liquidity from the GeniusMultiTokenPool contract.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external;

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
     * @notice Stakes liquidity into the GeniusMultiTokenPool.
     * @param trader The address of the trader staking the liquidity.
     * @param amount The amount of liquidity to be staked.
     */
    function stakeLiquidity(address trader, uint256 amount) external;

    /**
     * @notice Removes staked liquidity from the GeniusMultiTokenPool contract.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of liquidity to be removed.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external;

    /**
     * @notice Sets the rebalance threshold for the GeniusMultiTokenPool contract.
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external;

    /**
     * @notice Authorizes or unauthorizes a bridge target.
     * @param bridge The address of the bridge target to be managed.
     * @param authorize True to authorize the bridge, false to unauthorize it.
     */
    function manageBridge(address bridge, bool authorize) external;

    /**
     * @notice Manages (adds or removes) a router.
     * @param router The address of the router to be managed.
     * @param authorize True to add the router, false to remove it.
     */
    function manageRouter(address router, bool authorize) external;

    /**
     * @notice Pauses the contract and locks all features in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;

    /**
     * @notice Checks if a token is supported by the GeniusMultiTokenPool contract.
     * @param token The address of the token to check.
     * @return boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) external view returns (bool);

    /**
     * @notice Returns the balances of the stablecoins in the GeniusMultiTokenPool contract.
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
     * @notice Retrieves the balances of supported tokens.
     * @return An array of TokenBalance structs containing the token address and balance.
     */
    function supportedTokenBalances() external view returns (TokenBalance[] memory);

    /**
     * @notice Calculates the hash of an order.
     * @param order The Order struct to hash.
     * @return The bytes32 hash of the order.
     */
    function orderHash(Order memory order) external pure returns (bytes32);

    /**
     * @notice Returns the address of the stablecoin used in the pool.
     * @return The IERC20 interface of the stablecoin.
     */
    function STABLECOIN() external view returns (IERC20);

    /**
     * @notice Returns the total amount of staked assets in the pool.
     * @return The total amount of staked assets.
     */
    function totalStakedAssets() external view returns (uint256);

    /**
     * @notice Returns the current rebalance threshold.
     * @return The rebalance threshold as a percentage.
     */
    function rebalanceThreshold() external view returns (uint256);

    /**
     * @notice Returns the number of supported tokens in the pool.
     * @return The count of supported tokens.
     */
    function supportedTokensCount() external view returns (uint256);

    /**
     * @notice Retrieves information about a specific token.
     * @param token The address of the token to query.
     * @return isSupported Boolean indicating if the token is supported.
     * @return balance The balance of the token in the pool.
     */
    function tokenInfo(address token) external view returns (bool isSupported, uint256 balance);

    /**
     * @notice Returns the address of a supported token at a specific index.
     * @param index The index of the supported token.
     * @return The address of the token at the given index.
     */
    function supportedTokensIndex(uint256 index) external view returns (address);

    /**
     * @notice Returns the balance of a specific token in the pool.
     * @param token The address of the token to query.
     * @return The balance of the token.
     */
    function tokenBalances(address token) external view returns (uint256);

    /**
     * @notice Checks if a bridge is supported.
     * @param bridge The address of the bridge to check.
     * @return 1 if the bridge is supported, 0 otherwise.
     */
    function supportedBridges(address bridge) external view returns (uint256);

    /**
     * @notice Checks if a router is supported.
     * @param router The address of the router to check.
     * @return 1 if the router is supported, 0 otherwise.
     */
    function supportedRouters(address router) external view returns (uint256);
}