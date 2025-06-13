// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

/**
 * @title GeniusVault
 * @notice A cross-chain stablecoin bridge with price-based deposit protection
 * @dev Uses Chainlink price feeds to protect against stablecoin depegs
 */
contract GeniusVault is GeniusVaultCore {
    using SafeERC20 for IERC20;

    // State variables for fee accounting
    uint256 public deprecated_feesCollected;
    uint256 public deprecated_feesClaimed;

    /**
     * @notice Insurance fees are retained in the vault as additional liquidity to protect
     * against market volatility and potential losses during cross-chain operations.
     * Unlike protocol and LP fees which are transferred to the FeeCollector,
     * insurance fees remain in the vault to increase its stability and resilience.
     */
    uint256 public insuranceFeesAccumulated;

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault with required parameters
     * @param _stablecoin Address of the stablecoin
     * @param _admin Admin address
     * @param _multicall Multicall contract address
     * @param _rebalanceThreshold Rebalance threshold value
     * @param _priceFeed Chainlink price feed address
     */
    function initialize(
        address _stablecoin,
        address _admin,
        address _multicall,
        uint256 _rebalanceThreshold,
        address _priceFeed,
        uint256 _priceFeedHeartbeat,
        uint256 _stablePriceLowerBound,
        uint256 _stablePriceUpperBound,
        uint256 _maxOrderAmount
    ) external initializer {
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold,
            _priceFeed,
            _priceFeedHeartbeat,
            _stablePriceLowerBound,
            _stablePriceUpperBound,
            _maxOrderAmount
        );
    }

    /**
     * @dev See {IGeniusVault-createOrder}.
     */
    function createOrder(
        Order memory order
    ) external payable virtual override whenNotPaused {
        // Check stablecoin price before accepting the order
        _verifyStablecoinPrice();

        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.NonAddress0();
        if (
            order.amountIn == 0 ||
            order.amountIn <= order.fee ||
            order.amountIn > maxOrderAmount
        ) revert GeniusErrors.InvalidAmount();
        if (order.tokenIn != addressToBytes32(address(STABLECOIN)))
            revert GeniusErrors.InvalidTokenIn();
        if (order.tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();
        if (order.destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        // Verify the order's amount it valid
        _convertDecimals(
            order.amountIn - order.fee,
            decimals(),
            uint8(chainStablecoinDecimals[order.destChainId])
        );

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();

        // Call the fee collector to process fees
        uint256 amountToTransfer = feeCollector.collectFromVault(
            orderHash_,
            order.amountIn,
            order.destChainId,
            order.fee
        );

        insuranceFeesAccumulated += order.fee - amountToTransfer;

        STABLECOIN.safeTransferFrom(msg.sender, address(this), order.amountIn);

        // Transfer the appropriate amount to the fee collector
        if (amountToTransfer == 0 || amountToTransfer > order.fee) {
            revert GeniusErrors.InvalidFeeAmount();
        }

        // Transfer fees to fee collector contract
        STABLECOIN.safeTransfer(address(feeCollector), amountToTransfer);

        orderStatus[orderHash_] = OrderStatus.Created;

        emit OrderCreated(
            order.destChainId,
            order.trader,
            order.receiver,
            order.seed,
            orderHash_,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.fee
        );
    }

    /**
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view override returns (uint256) {
        uint256 _totalStaked = totalStakedAssets;
        uint256 reduction = (_totalStaked * rebalanceThreshold) /
            BASE_PERCENTAGE;
        uint256 minBalance = _totalStaked - reduction;
        // claimableFees is no longer relevant since fees are transferred directly
        return minBalance;
    }
}
