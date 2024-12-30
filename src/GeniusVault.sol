// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

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
        uint256 _stablePriceLowerBound,
        uint256 _stablePriceUpperBound
    ) external initializer {
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold,
            _priceFeed,
            _stablePriceLowerBound,
            _stablePriceUpperBound
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
        if (order.amountIn == 0 || order.amountIn <= order.fee)
            revert GeniusErrors.InvalidAmount();
        if (order.tokenIn != addressToBytes32(address(STABLECOIN)))
            revert GeniusErrors.InvalidTokenIn();
        if (order.tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();
        if (order.destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        uint256 minFee = targetChainMinFee[tokenIn][order.destChainId];
        if (minFee == 0) revert GeniusErrors.TokenOrTargetChainNotSupported();
        if (order.fee < minFee)
            revert GeniusErrors.InsufficientFees(order.fee, minFee, tokenIn);

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();

        STABLECOIN.safeTransferFrom(msg.sender, address(this), order.amountIn);

        feesCollected += order.fee;
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
     * @notice Fetches the amount of fees that can be claimed
     */
    function claimableFees() public view returns (uint256) {
        return feesCollected - feesClaimed;
    }

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(
        uint256 amount,
        address token
    ) external virtual override onlyOrchestratorOrAdmin whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > claimableFees())
            revert GeniusErrors.InsufficientFees(
                amount,
                claimableFees(),
                address(STABLECOIN)
            );
        if (token != address(STABLECOIN))
            revert GeniusErrors.InvalidToken(token);

        feesClaimed += amount;

        STABLECOIN.safeTransfer(msg.sender, amount);

        emit FeesClaimed(address(STABLECOIN), amount);
    }

    /**
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view override returns (uint256) {
        uint256 _totalStaked = _convertToStablecoinDecimals(totalStakedAssets);
        uint256 reduction = (_totalStaked * rebalanceThreshold) / 10_000;
        uint256 minBalance = _totalStaked - reduction;
        return minBalance + claimableFees();
    }
}
