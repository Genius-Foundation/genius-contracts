// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IGeniusVault
 * @author looter
 * 
 * @notice Interface for the GeniusVault contract that allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps,
 *         and other Genius related activities.
 */
interface IGeniusVault {

    /**
     * @notice Emitted when assets are staked in the GeniusVault contract.
     * @param caller The address of the caller.
     * @param owner The address of the owner of the staked assets.
     * @param amount The amount of assets staked.
     */
    event StakeDeposit(address indexed caller, address indexed owner, uint256 amount);

    /**
     * @notice Emitted when assets are withdrawn from the GeniusVault contract.
     * @param caller The address of the caller.
     * @param receiver The address of the receiver of the withdrawn assets.
     * @param owner The address of the owner of the staked assets.
     * @param amount The amount of assets withdrawn.
     */
    event StakeWithdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 amount
    );

    /**
     * @notice Enum representing the possible statuses of an order.
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
     * @param seed Seed used for the order, to avoid 2 same orders having the same hash.
     * @param trader Address of the trader initiating the order.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline by which the order must be filled.
     * @param tokenIn The address of the token to be swapped.
     */
    struct Order {
        bytes32 seed;
        uint256 amountIn;
        address trader;
        uint16 srcChainId;
        uint32 destChainId;
        uint32 fillDeadline; 
        address tokenIn;
        uint256 fee;
    }

    /**
     * @notice Emitted on the source chain when a swap deposit is made.
     * @param seed The unique seed of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event SwapDeposit(
        bytes32 indexed seed,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint32 indexed destChainId,
        uint32 fillDeadline,
        uint256 fee
    );

    /**
     * @notice Emitted on the destination chain when a swap withdrawal occurs.
     * @param seed The unique seed of the order.
     * @param trader The address of the trader.
     * @param tokenOut The address of the output token.
     * @param amountOut The amount of output tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event SwapWithdrawal(
        bytes32 indexed seed,
        address indexed trader,
        address tokenOut,
        uint256 amountOut,
        uint16 indexed srcChainId,
        uint32 destChainId,
        uint32 fillDeadline
    );

    /**
     * @notice Emitted on the source chain when an order is filled.
     * @param seed The unique seed of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event OrderFilled(
        bytes32 indexed seed,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint32 indexed destChainId,
        uint32 fillDeadline,
        uint256 fee
    );

    /**
     * @notice Emitted on the source chain when an order is reverted.
     * @param seed The unique seed of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event OrderReverted(
        bytes32 indexed seed,
        address indexed trader,
        address tokenIn,
        uint256 amountIn,
        uint16 srcChainId,
        uint32 indexed destChainId,
        uint32 fillDeadline,
        uint256 fee
    );

    /**
     * @notice Emitted when liquidity is removed for rebalancing.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event RemovedLiquidity(
        uint256 amount,
        uint32 chainId
    );

    /**
     * @notice Emitted when fees are claimed from the Vault contract.
     * @param token The address of the token the fees were claimed in.
     * @param amount The amount of fees claimed.
     */
    event FeesClaimed(
        address token,
        uint256 amount
    );

    /**
     * @notice Returns the total balance of the vault excluding fees.
     * @return The total balance of the vault excluding fees.
     */
    function balanceMinusFees(address token) external view returns (uint256);

    /**
     * @notice Returns the total balance of the vault.
     * @return The total balance of the vault.
     */
    function stablecoinBalance() external view returns (uint256);

    /**
     * @notice Returns the minimum asset balance required in the vault.
     * @return The minimum asset balance.
     */
    function minAssetBalance() external view returns (uint256);

    /**
     * @notice Returns the available assets in the vault.
     * @return The amount of available assets.
     */
    function availableAssets() external view returns (uint256);

    /**
     * @notice Stake assets in the GeniusVault contract.
     * @param amount The amount of assets to stake.
     * @param receiver The address of the receiver of the staked assets.
     * @dev The receiver is the address that will receive gUSD tokens 
     * in exchange for the staked assets with a 1:1 ratio.
     */
    function stakeDeposit(uint256 amount, address receiver) external;

    /**
     * @notice Withdraws staked assets from the GeniusVault contract.
     * @param amount The amount of assets to withdraw.
     * @param receiver The address of the receiver of the withdrawn assets.
     * @param owner The address of the owner of the staked assets.
     */
    function stakeWithdraw(
        uint256 amount,
        address receiver,
        address owner
    ) external;

    /**
     * @notice Removes liquidity from a bridge vault 
     * and bridge it to the destination chain.
     * @param amountIn The amount of tokens to remove from the bridge vault.
     * @param dstChainId The chain ID of the destination chain.
     * @param targets The array of target addresses to call.
     * @param values The array of values to send along with the function calls.
     * @param data The array of function call data.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint32 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external payable;

    /**
     * @notice Adds liquidity to the GeniusVault contract 
     * of the source chain in a cross-chain order flow.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    function addLiquiditySwap(
        bytes32 seed,
        address trader,
        address tokenIn,
        uint256 amountIn,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee
    ) external payable;

    /**
     * @notice Removes liquidity from the GeniusVault contract 
     * of the destination chain in a cross-chain order flow.
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
     * @notice Reverts an order on the source chain and executes associated revert actions.
     * @param order The Order struct containing the order details.
     * @param targets The array of target addresses to call.
     * @param data The array of function call data.
     * @param values The array of values to send along with the function calls.
     */
    function revertOrder(
        Order calldata order, 
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external;

    /**
     * @notice Removes reward liquidity from the GeniusVault contract.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external;

    /**
     * @notice Claims fees from the GeniusVault contract.
     * @param amount The amount of fees to claim.
     * @param token The address of the token to claim fees in.
     */
    function claimFees(uint256 amount, address token) external;

    /**
     * @notice Sets the rebalance threshold for the GeniusVault contract.
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
     * @notice Sets the cross-chain fee for the GeniusVault contract.
     * @param fee The new cross-chain fee to be set.
     */
    function setCrosschainFee(uint256 fee) external;

    /**
     * @notice Sets the executor address for the GeniusVault contract.
     * @param executor_ The address of the executor to be set.
     */
    function setExecutor(address executor_) external;

    /**
     * @notice Pauses the contract and locks all functionality in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;

    /**
     * @notice Returns the current state of the assets in the GeniusVault contract.
     * @return balanceStablecoin The total number of assets in the vault.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the vault.
     */
    function allAssets() external view returns (uint256, uint256, uint256);

    /**
     * @notice Calculates the hash of an order.
     * @param order The Order struct to hash.
     * @return The bytes32 hash of the order.
     */
    function orderHash(Order memory order) external pure returns (bytes32);

    /**
     * @notice Returns the total amount of staked assets in the vault.
     * @return The total amount of staked assets.
     */
    function totalStakedAssets() external view returns (uint256);

    /**
     * @notice Returns the current rebalance threshold.
     * @return The rebalance threshold as a percentage.
     */
    function rebalanceThreshold() external view returns (uint256);

     /**
     * @notice Returns the address of the stablecoin used in the vault.
     * @return The IERC20 interface of the stablecoin.
     */
    function STABLECOIN() external view returns (IERC20);
}