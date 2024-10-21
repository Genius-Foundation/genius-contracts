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
     * @param seed Seed used for the order, to avoid 2 same orders having the same hash.
     * @param trader The address of the trader.
     * @param receiver The address of the receiver.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens.
     * @param minAmountOut The minimum amount of output tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     * @param fee The fees paid for the order
     */
    struct Order {
        bytes32 seed;
        bytes32 trader;
        bytes32 receiver;
        bytes32 tokenIn;
        bytes32 tokenOut;
        uint256 amountIn;
        uint256 minAmountOut;
        uint256 srcChainId;
        uint256 destChainId;
        uint256 fillDeadline;
        uint256 fee;
    }

    /**
     * @notice Emitted when assets are staked in the GeniusVault contract.
     * @param caller The address of the caller.
     * @param owner The address of the owner of the staked assets.
     * @param amount The amount of assets staked.
     */
    event StakeDeposit(
        address indexed caller,
        address indexed owner,
        uint256 amount
    );

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
     * @notice Emitted on the source chain when a swap deposit is made.
     * @param seed The unique seed of the order.
     * @param trader The address of the trader.
     * @param tokenIn The address of the input token.
     * @param amountIn The amount of input tokens.
     * @param srcChainId The source chain ID.
     * @param destChainId The destination chain ID.
     * @param fillDeadline The deadline for filling the order.
     */
    event OrderCreated(
        bytes32 indexed seed,
        bytes32 indexed trader,
        bytes32 tokenIn,
        uint256 amountIn,
        uint256 srcChainId,
        uint256 indexed destChainId,
        uint256 fillDeadline,
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
    event OrderFilled(
        bytes32 indexed seed,
        bytes32 indexed trader,
        bytes32 receiver,
        bytes32 tokenOut,
        uint256 amountOut,
        uint256 indexed srcChainId,
        uint256 destChainId,
        uint256 fillDeadline
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
        bytes32 indexed trader,
        bytes32 receiver,
        bytes32 tokenIn,
        uint256 amountIn,
        uint256 srcChainId,
        uint256 indexed destChainId,
        uint256 fillDeadline,
        uint256 fee
    );

    /**
     * @notice Emitted when liquidity is removed for rebalancing.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event RemovedLiquidity(uint256 amount, uint256 indexed chainId);

    /**
     * @notice Emitted when fees are claimed from the Vault contract.
     * @param token The address of the token the fees were claimed in.
     * @param amount The amount of fees claimed.
     */
    event FeesClaimed(address indexed token, uint256 amount);

    /**
     * @notice Emitted when the max order time is changed.
     * @param newMaxOrderTime The new maximum order time.
     */
    event MaxOrderTimeChanged(uint256 newMaxOrderTime);

    /**
     * @notice Emitted when the order revert buffer is changed.
     * @param newOrderRevertBuffer The new order revert buffer time.
     */
    event OrderRevertBufferChanged(uint256 newOrderRevertBuffer);

    /**
     * @notice Emitted when the rebalance threshold is changed.
     * @param newThreshold The new rebalance threshold.
     */
    event RebalanceThresholdChanged(uint256 newThreshold);

    /**
     * @notice Emitted when the cross-chain fee is changed.
     * @param newFee The new cross-chain fee.
     */
    event CrosschainFeeChanged(uint256 newFee);

    /**
     * @notice Returns the total balance of the vault.
     * @return The total balance of the vault.
     */
    function stablecoinBalance() external view returns (uint256);

    /**
     * @notice Returns the minimum asset balance required in the vault.
     * @return The minimum asset balance.
     */
    function minLiquidity() external view returns (uint256);

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
     * @param data The array of function call data.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint256 dstChainId,
        address target,
        bytes calldata data
    ) external payable;

    /**
     * @notice Adds liquidity to the GeniusVault contract
     * of the source chain in a cross-chain order flow.
     * @param order The Order struct containing the order details.
     */
    function createOrder(Order memory order) external payable;

    /**
     * @notice Removes liquidity from the GeniusVault contract
     * of the destination chain in a cross-chain order flow.
     * @param order The Order struct containing the order details.
     */
    function fillOrder(
        Order memory order,
        address swapTarget,
        bytes calldata swapData,
        address callTarget,
        bytes calldata callData
    ) external;

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
     * @notice Sets the order revert buffer.
     * @param _orderRevertBuffer The new order revert buffer.
     */
    function setOrderRevertBuffer(uint256 _orderRevertBuffer) external;

    /**
     * @notice Sets the max order time.
     * @param _maxOrderTime The new max order time.
     */
    function setMaxOrderTime(uint256 _maxOrderTime) external;

    /**
     * @notice Pauses the contract and locks all functionality in case of an emergency.
     */
    function pause() external;

    /**
     * @notice Allows the owner to emergency unlock the contract.
     */
    function unpause() external;

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
     * Extract an address from a left-padded bytes32 address
     * @param _input bytes32 containing a left-padded bytes20 address
     */
    function bytes32ToAddress(bytes32 _input) external pure returns (address);

    /**
     * Convert an address to a left-padded bytes32 address
     * @param _input address to convert
     */
    function addressToBytes32(address _input) external pure returns (bytes32);

    function maxOrderTime() external view returns (uint256);

    /**
     * @notice Returns the address of the stablecoin used in the vault.
     * @return The IERC20 interface of the stablecoin.
     */
    function STABLECOIN() external view returns (IERC20);
}
