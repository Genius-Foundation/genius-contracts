// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IFeeCalculator} from "./interfaces/IFeeCalculator.sol";
import {IFeeCollector} from "./interfaces/IFeeCollector.sol";

/**
 * @title GeniusVault
 * @notice A cross-chain stablecoin bridge with price-based deposit protection
 * @dev Uses Chainlink price feeds to protect against stablecoin depegs
 */
contract GeniusVault is GeniusVaultCore {
    using SafeERC20 for IERC20;

    // State variables for fee accounting
    uint256 public feesCollected;
    uint256 public feesClaimed;
    uint256 public feesReinjected;

    // Fee contracts
    IFeeCalculator public feeCalculator;
    IFeeCollector public feeCollector;

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

        // Get fee breakdown from fee calculator
        IFeeCalculator.FeeBreakdown memory feeBreakdown = feeCalculator.getOrderFees(
            tokenIn,
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

        // Calculate any surplus fee over the required minimum
        uint256 feeSurplus = 0;
        if (order.fee > feeBreakdown.totalFee) {
            feeSurplus = order.fee - feeBreakdown.totalFee;
        }

        // Update fee accounting
        feesCollected += order.fee - feeBreakdown.totalFee;
        feesReinjected += feeBreakdown.insuranceFee;

        // Update the fee collector contract
        feeCollector.updateFees(
            feeBreakdown.bpsFee,
            feeBreakdown.baseFee,
            feeSurplus
        );

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
     * @dev See {IGeniusVault-collectFees}.
     */
    function claimFees() external virtual override whenNotPaused {
        uint256 feesAmount = claimableFees();

        if (feesAmount == 0)
            revert GeniusErrors.InvalidAmount();

        feesClaimed += feesAmount;
        STABLECOIN.safeTransfer(address(feeCollector), feesAmount);

        emit FeesClaimed(feesAmount, 0); // Keep the same event signature but set base fees to 0
    }

    /**
     * @notice Set the fee calculator contract
     * @param _feeCalculator Address of the fee calculator contract
     */
    function setFeeCalculator(address _feeCalculator) external onlyAdmin {
        if (_feeCalculator == address(0)) revert GeniusErrors.NonAddress0();
        feeCalculator = IFeeCalculator(_feeCalculator);
        emit FeeCalculatorSet(_feeCalculator);
    }

    /**
     * @notice Set the fee collector contract
     * @param _feeCollector Address of the fee collector contract
     */
    function setFeeCollector(address _feeCollector) external onlyAdmin {
        if (_feeCollector == address(0)) revert GeniusErrors.NonAddress0();
        feeCollector = IFeeCollector(_feeCollector);
        emit FeeCollectorSet(_feeCollector);
    }

    /**
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view override returns (uint256) {
        uint256 _totalStaked = totalStakedAssets;
        uint256 reduction = (_totalStaked * rebalanceThreshold) /
            BASE_PERCENTAGE;
        uint256 minBalance = _totalStaked - reduction;
        return minBalance + claimableFees();
    }
}