// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

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
        uint256 fee;
    }

    event StablePriceBoundsChanged(uint256 lower, uint256 upper);

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
     * @param destChainId The destination chain ID.
     * @param trader The address of the trader.
     * @param receiver The address of the receiver.
     * @param seed The seed of the order.
     * @param orderHash The unique hash of the order.
     * @param tokenIn The address of the input token.
     * @param tokenOut The address of the output token.
     * @param amountIn The amount of input tokens.
     * @param minAmountOut The minimum amount of output tokens.
     * @param fee The fees paid for the order
     */
    event OrderCreated(
        uint256 indexed destChainId,
        bytes32 indexed trader,
        bytes32 indexed receiver,
        bytes32 seed,
        bytes32 orderHash,
        bytes32 tokenIn,
        bytes32 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint256 fee
    );

    /**
     * @notice Emitted on the destination chain when a swap withdrawal occurs.
     * @param trader The address of the trader.
     * @param receiver The address of the receiver.
     * @param seed The seed of the order.
     * @param orderHash The unique hash of the order.
     * @param effectiveTokenOut The address of the output token.
     * @param effectiveAmountOut The amount of output tokens.
     * @param amountStablecoinValue The amount of output tokens in stablecoin value.
     * @param srcChainId The source chain ID.
     * @param success False if any external call failed
     */
    event OrderFilled(
        uint256 indexed srcChainId,
        bytes32 indexed trader,
        bytes32 indexed receiver,
        bytes32 seed,
        bytes32 orderHash,
        address effectiveTokenOut,
        uint256 effectiveAmountOut,
        uint256 amountStablecoinValue,
        bool success
    );

    event OrderReverted(
        uint256 indexed srcChainId,
        bytes32 indexed trader,
        bytes32 indexed receiver,
        bytes32 seed,
        bytes32 orderHash
    );

    /**
     * @notice Emitted when liquidity is removed for rebalancing.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event RebalancedLiquidity(uint256 amount, uint256 indexed chainId);

    /**
     * @notice Emitted when fees are claimed from the Vault contract.
     * @param token The address of the token the fees were claimed in.
     * @param amount The amount of fees claimed.
     */
    event FeesClaimed(address indexed token, uint256 amount);

    /**
     * @notice Emitted when the rebalance threshold is changed.
     * @param newThreshold The new rebalance threshold.
     */
    event RebalanceThresholdChanged(uint256 newThreshold);

    /**
     * @notice Emitted when the proxy call address is changed.
     * @param newProxyCall The new proxy call address.
     */
    event ProxyCallChanged(address newProxyCall);

    /**
     * @notice Emitted when the minimum fees for a target chain has changed
     * note: if the min fees are set to 0, the chain or token are not supported
     * @param token the address of the token used as a fee
     * @param targetChainId The id of the target chain
     * @param newMinFee The new minimum fee for the target chain
     */
    event TargetChainMinFeeChanged(
        address token,
        uint256 targetChainId,
        uint256 newMinFee
    );

    event MaxOrderAmountChanged(uint256 newMaxOrderAmount);

    event PriceFeedHeartbeatChanged(uint256 newHeartbeat);

    /**
     * @notice Emitted when the decimals of the stablecoin are changed.
     * @param chainId The chain ID of the stablecoin.
     * @param newDecimals The new decimals of the stablecoin.
     */
    event ChainStablecoinDecimalsChanged(uint256 chainId, uint256 newDecimals);

    /**
     * @notice Emitted when the price feed is updated.
     * @param newPriceFeed The address of the new price feed.
     */
    event PriceFeedUpdated(address newPriceFeed);

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
    function rebalanceLiquidity(
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
     * @notice Fill an order on the destination chain
     *
     * The swap should have the receiver as the receiver if no arbitrary call
     * Otherwise, the swap receiver address should be the proxycall contract
     *
     * If an arbitrary call is present, the tokenOut balance will be transferred
     * to the target before executing the call
     * If an arbitrary call is present, the seed should be keccak256(callTarget,callData)
     *
     * @param order The Order struct containing the order details.
     * @param swapTarget - Swap exec target (address(0) if no swap)
     * @param swapData - Swap exec data (0x if no swap)
     * @param callTarget - Arbitrary call exec target (address(0) if no call)
     * @param callData  - Arbitrary call exec data (0x if no call)
     */
    function fillOrder(
        Order memory order,
        address swapTarget,
        bytes calldata swapData,
        address callTarget,
        bytes calldata callData
    ) external;

    function revertOrder(
        Order memory order,
        bytes memory orchestratorSig
    ) external;

    /**
     * @notice Fill multiple orders on the destination chain
     *
     * The swap should have the receiver as the receiver if no arbitrary call
     * Otherwise, the swap receiver address should be the proxycall contract
     *
     * If an arbitrary call is present, the tokenOut balance will be transferred
     * to the target
     * If an arbitrary call is present, the seed should be keccak256(callTarget,callData)
     * @param orders The Order struct containing the order details.
     */
    function fillOrderBatch(
        Order[] memory orders,
        address[] memory swapsTargets,
        bytes[] memory swapsData,
        address[] memory callsTargets,
        bytes[] memory callsData
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
     * @notice Set the proxy call contract address
     * @param _proxyCall The new proxy call contract address
     */
    function setProxyCall(address _proxyCall) external;

    /**
     * @notice Sets the minimum fees for a target chain has changed
     * note: if the min fees are set to 0, the chain or token are not supported
     * @param _token the address of the token used for the fees
     * @param _targetChainId The id of the target chain
     * @param _minFee The new minimum fee for the target chain
     */
    function setTargetChainMinFee(
        address _token,
        uint256 _targetChainId,
        uint256 _minFee
    ) external;

    /**
     * @notice Sets the stable price bounds for the chainlink price feed checks.
     * @param _lowerBound The new lower bound for the stable price.
     * @param _upperBound The new upper bound for the stable price.
     */
    function setStablePriceBounds(
        uint256 _lowerBound,
        uint256 _upperBound
    ) external;

    /**
     * @notice Sets the maximum order amount that can be created
     * @param _newMaxOrderAmount The new maximum order amount
     */
    function setMaxOrderAmount(uint256 _newMaxOrderAmount) external;

    /**
     * @notice Sets the decimals of the stablecoin for a specific chain
     * @param _chainId The chain ID of the stablecoin.
     * @param _newDecimals The new decimals of the stablecoin.
     */
    function setChainStablecoinDecimals(
        uint256 _chainId,
        uint256 _newDecimals
    ) external;

    /**
     * @notice Sets the heartbeat for the price feed
     * @param _newHeartbeat The new heartbeat
     */
    function setPriceFeedHeartbeat(uint256 _newHeartbeat) external;

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
     * @notice Computes the seed of an order based on the arbitrary call passed
     * @param target The address of the target contract
     * @param data The data of the call
     * @return The seed of the order
     */
    function calldataToSeed(
        address target,
        bytes memory data
    ) external pure returns (bytes32);

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

    /**
     * @notice Returns the address of the stablecoin used in the vault.
     * @return The IERC20 interface of the stablecoin.
     */
    function STABLECOIN() external view returns (IERC20);
}
