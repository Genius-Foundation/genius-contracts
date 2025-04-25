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

    // State variables
    uint256 public feesCollected;
    uint256 public feesClaimed;
    uint256 public baseFeeCollected;
    uint256 public baseFeeClaimed;
    uint256 public liquidityReinjected;

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

        address tokenIn = address(STABLECOIN);
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

        uint256 minFee = targetChainMinFee[tokenIn][order.destChainId];

        if (minFee == 0 || chainStablecoinDecimals[order.destChainId] == 0)
            revert GeniusErrors.TokenOrTargetChainNotSupported();

        // Calculate complete fee breakdown
        FeeBreakdown memory feeBreakdown = _calculateFeeBreakdown(
            order.amountIn,
            order.destChainId
        );

        // Check if the provided fee is sufficient
        if (order.fee < feeBreakdown.totalFee)
            revert GeniusErrors.InsufficientFees(
                order.fee,
                feeBreakdown.totalFee,
                tokenIn
            );

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();

        STABLECOIN.safeTransferFrom(msg.sender, address(this), order.amountIn);

        // Distribute fees to appropriate buckets
        baseFeeCollected += feeBreakdown.baseFee;
        feesCollected += feeBreakdown.bpsFee;
        liquidityReinjected += feeBreakdown.insuranceFee;

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

        // Emit a detailed fee breakdown event
        emit OrderFeeBreakdown(
            orderHash_,
            feeBreakdown.baseFee,
            feeBreakdown.bpsFee,
            feeBreakdown.insuranceFee,
            feeBreakdown.totalFee
        );
    }

    /**
     * @notice Fetches the amount of fees that can be claimed
     */
    function claimableFees() public view returns (uint256) {
        return feesCollected - feesClaimed;
    }

    /**
     * @notice Fetches the amount of base fees that can be claimed
     */
    function claimableBaseFees() public view returns (uint256) {
        return baseFeeCollected - baseFeeClaimed;
    }

    /**
     * @dev See {IGeniusVault-collectFees}.
     */
    function claimFees() external virtual override whenNotPaused {
        uint256 feesAmount = claimableFees();
        uint256 baseFeesAmount = claimableBaseFees();

        if (feesAmount == 0 && baseFeesAmount == 0)
            revert GeniusErrors.InvalidAmount();

        if (feesAmount > 0) {
            feesClaimed += feesAmount;
            STABLECOIN.safeTransfer(feeCollector, feesAmount);
        }
        if (baseFeesAmount > 0) {
            baseFeeClaimed += baseFeesAmount;
            STABLECOIN.safeTransfer(baseFeeCollector, baseFeesAmount);
        }

        emit FeesClaimed(feesAmount, baseFeesAmount);
    }

    /**
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view override returns (uint256) {
        uint256 _totalStaked = totalStakedAssets;
        uint256 reduction = (_totalStaked * rebalanceThreshold) /
            BASE_PERCENTAGE;
        uint256 minBalance = _totalStaked - reduction;
        return minBalance + claimableFees() + claimableBaseFees();
    }
}
