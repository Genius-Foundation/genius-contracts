// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

contract GeniusVault is GeniusVaultCore {

    uint256 public unclaimedFees; // The total amount of fees that are available to be claimed
    uint256 public reservedFees; // The total amount of fees that have been reserved for unfilled orders

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address stablecoin,
        address admin
    ) external initializer {
        GeniusVaultCore._initialize(stablecoin, admin);
    }

    /**
     * @dev See {IGeniusVault-removeRewardLiquidity}.
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator whenNotPaused {
        uint256 _totalAssets = balanceMinusFees(address(STABLECOIN));
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));

        if (!_isBalanceWithinThreshold(_totalAssets - amount)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);
    }

    /**
     * @dev See {IGeniusVault-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint32 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external payable override virtual onlyOrchestrator whenNotPaused {
        _checkBridgeTargets(targets);
 
        uint256 preTransferAssets = balanceMinusFees(address(STABLECOIN));
        uint256 neededLiquidty_ = minAssetBalance();

        _isAmountValid(amountIn, _availableAssets(preTransferAssets, neededLiquidty_));
        _checkNative(_sum(values));

        if (!_isBalanceWithinThreshold(preTransferAssets - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            neededLiquidty_,
            preTransferAssets - amountIn
        );

        _batchExecution(targets, data, values);

        uint256 _stableDelta = preTransferAssets - balanceMinusFees(address(STABLECOIN));

        if (_stableDelta != amountIn) revert GeniusErrors.AmountInAndDeltaMismatch(amountIn, _stableDelta);

        emit RemovedLiquidity(
            amountIn,
            dstChainId
        );
    }

        /**
     * @dev See {IGeniusVault-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order
    ) external virtual override onlyExecutor whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId()) revert GeniusErrors.InvalidDestChainId(order.destChainId);     
        if (order.fillDeadline < _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(order.fillDeadline); 
        if (order.srcChainId == _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        uint256 _totalAssets = balanceMinusFees(address(STABLECOIN));
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(order.amountIn, _availableAssets(_totalAssets, _neededLiquidity));

        if (order.trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (!_isBalanceWithinThreshold(_totalAssets - order.amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - order.amountIn
        );

        orderStatus[orderHash_] = OrderStatus.Filled;

        _transferERC20(address(STABLECOIN), msg.sender, order.amountIn);
        
        emit SwapWithdrawal(
            order.seed,
            order.trader,
            address(STABLECOIN),
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    /**
     * @dev See {IGeniusVault-addLiquiditySwap}.
     */
    function addLiquiditySwap(
        bytes32 seed,
        address trader,
        address tokenIn,
        uint256 amountIn,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee
    ) external payable virtual override onlyExecutor whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (tokenIn != address(STABLECOIN)) revert GeniusErrors.InvalidToken(tokenIn);
        if (destChainId == _currentChainId()) revert GeniusErrors.InvalidDestChainId(destChainId);
        if (fillDeadline <= _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(fillDeadline);

        Order memory order = Order({
            trader: trader,
            amountIn: amountIn,
            seed: seed,
            srcChainId: uint16(_currentChainId()),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: tokenIn,
            fee: fee
        });

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.InvalidOrderStatus();

        // Pre transfer check
        uint256 _preTotalAssets = stablecoinBalance();

        _transferERC20From(address(STABLECOIN), msg.sender, address(this), order.amountIn);

        // Check that the transfer was successful
        uint256 _postTotalAssets = stablecoinBalance();

        if (_postTotalAssets != _preTotalAssets + order.amountIn) revert GeniusErrors.TransferFailed(
            address(STABLECOIN),
            order.amountIn
        );

        reservedFees += fee;
        orderStatus[orderHash_] = OrderStatus.Created;

        emit SwapDeposit(
            order.seed,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline,
            order.fee
        );
    }

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(uint256 amount, address token) external override virtual onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > unclaimedFees) revert GeniusErrors.InsufficientFees(amount, unclaimedFees, address(STABLECOIN));
        if (token != address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);

        unclaimedFees -= amount;
        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit FeesClaimed(
            address(STABLECOIN),
            amount
        );
    }

    /**
     * @dev See {IGeniusVault-setOrderAsFilled}.
     */
    function setOrderAsFilled(Order memory order) external override onlyOrchestrator whenNotPaused {
        bytes32 _orderHash = orderHash(order);

        if (orderStatus[_orderHash] != OrderStatus.Created) revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        orderStatus[_orderHash] = OrderStatus.Filled;
        unclaimedFees += order.fee;
        reservedFees -= order.fee;

        emit OrderFilled(
            order.seed,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline,
            order.fee
        );
    }

    /**
     * @dev See {IGeniusVault-revertOrder}.
     */
    function revertOrder(
        Order calldata order, 
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created) revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.fillDeadline >= _currentTimeStamp()) revert GeniusErrors.DeadlineNotPassed(order.fillDeadline);

        (uint256 _totalRefund, uint256 _protocolFee) = _calculateRefundAmount(order.amountIn, order.fee);
        uint256 _totalAssetsPreRevert = stablecoinBalance();
        _batchExecution(targets, data, values);

        uint256 _totalAssetsPostRevert = stablecoinBalance();
        uint256 _delta = _totalAssetsPreRevert - _totalAssetsPostRevert;

        if (_delta != _totalRefund) revert GeniusErrors.InvalidDelta();
        
        orderStatus[orderHash_] = OrderStatus.Reverted;

        reservedFees -= order.fee;
        unclaimedFees += _protocolFee;

        emit OrderReverted(
            order.seed,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline,
            order.fee
        );
    }

    /**
     * @dev See {IGeniusVault-balanceMinusFees}.
     */
    function balanceMinusFees(address token) public virtual view returns (uint256) {
        if (token != address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);
        return stablecoinBalance() - (unclaimedFees + reservedFees);
    }

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public view returns (uint256) {
        uint256 _totalAssets = balanceMinusFees(address(STABLECOIN));
        uint256 _neededLiquidity = minAssetBalance();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    function allAssets() public override view returns (uint256, uint256, uint256) {
        return (
            stablecoinBalance(),
            availableAssets(),
            totalStakedAssets
        );
    }
}