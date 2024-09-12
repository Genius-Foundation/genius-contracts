// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

contract GeniusVault is GeniusVaultCore {

    uint256 public reservedAssets; // The total amount of assets that have been reserved for unfilled orders
    uint256 public unclaimedFees; // The total amount of fees that are available to be claimed

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the vault
     * @param stablecoin The address of the stablecoin to use
     * @param admin The address of the admin
     */
    function initialize(
        address stablecoin,
        address admin
    ) external initializer {
        GeniusVaultCore._initialize(stablecoin, admin);
    }

    /**
     * @notice Removes liquidity from the vault to be used for rewarding stakers
     * @param amount The amount of liquidity to remove
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator whenNotPaused {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));
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
 
        uint256 preTransferAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        _isAmountValid(amountIn, _availableAssets(preTransferAssets, _neededLiquidity));
        _checkNative(_sum(values));

        _batchExecution(targets, data, values);

        uint256 _stableDelta = preTransferAssets - stablecoinBalance();

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

        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        _isAmountValid(order.amountIn, _availableAssets(_totalAssets, _neededLiquidity));

        if (order.trader == address(0)) revert GeniusErrors.InvalidTrader();

        orderStatus[orderHash_] = OrderStatus.Filled;

        _transferERC20(address(STABLECOIN), msg.sender, order.amountIn);
        
        emit SwapWithdrawal(
            order.seed,
            order.trader,
            order.receiver,
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
        uint256 fee,
        bytes32 receiver
    ) external payable virtual override onlyExecutor whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (tokenIn != address(STABLECOIN)) revert GeniusErrors.InvalidToken(tokenIn);
        if (destChainId == _currentChainId()) revert GeniusErrors.InvalidDestChainId(destChainId);
        if (fillDeadline <= _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(fillDeadline);

        Order memory order = Order({
            trader: trader,
            receiver: receiver,
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

        reservedAssets += order.amountIn;
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
        reservedAssets -= order.amountIn;

        emit OrderFilled(
            order.seed,
            order.trader,
            order.receiver,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline,
            order.fee
        );
    }

   /**
    * @notice Reverts an order and refunds the trader
    * @param order The order to revert
    */
    function revertOrder(
        Order calldata order
    ) external onlyExecutor whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created) revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.fillDeadline >= _currentTimeStamp()) revert GeniusErrors.DeadlineNotPassed(order.fillDeadline);

        (uint256 _totalRefund, uint256 _protocolFee) = _calculateRefundAmount(order.amountIn, order.fee);
        
        orderStatus[orderHash_] = OrderStatus.Reverted;

        _transferERC20(address(STABLECOIN), msg.sender, _totalRefund);
        
        reservedAssets -= order.amountIn;
        unclaimedFees += _protocolFee;

        emit OrderReverted(
            order.seed,
            order.trader,
            order.receiver,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline,
            order.fee
        );
    }

    function minLiquidity() public override view returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        uint256 minBalance = totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
        
        return minBalance + unclaimedFees + reservedAssets;
    }

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public view returns (uint256) {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

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