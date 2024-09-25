// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
    function removeRewardLiquidity(
        uint256 amount
    ) external onlyOrchestrator whenNotPaused {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        _isAmountValid(
            amount,
            _availableAssets(_totalAssets, _neededLiquidity)
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
    ) external payable virtual override onlyOrchestrator whenNotPaused {
        _isAmountValid(amountIn, availableAssets());
        _checkNative(_sum(values));

        _transferERC20(address(STABLECOIN), address(EXECUTOR), amountIn);

        EXECUTOR.aggregate(targets, data, values);

        emit RemovedLiquidity(amountIn, dstChainId);
    }

    /**
     * @dev See {IGeniusVault-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external virtual override nonReentrant onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.fillDeadline < _currentTimeStamp())
            revert GeniusErrors.DeadlinePassed(order.fillDeadline);
        if (order.srcChainId == _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        _isAmountValid(order.amountIn - order.fee, availableAssets());

        if (order.trader == address(0)) revert GeniusErrors.InvalidTrader();

        orderStatus[orderHash_] = OrderStatus.Filled;
        address receiver = bytes32ToAddress(order.receiver);

        if (targets.length == 0) {
            _transferERC20(
                address(STABLECOIN),
                receiver,
                order.amountIn - order.fee
            );
        } else {
            IERC20 tokenOut = IERC20(bytes32ToAddress(order.tokenOut));

            uint256 preSwapBalance = tokenOut.balanceOf(receiver);

            _transferERC20(
                address(STABLECOIN),
                address(EXECUTOR),
                order.amountIn - order.fee
            );
            EXECUTOR.aggregate(targets, data, values);

            uint256 postSwapBalance = tokenOut.balanceOf(receiver);

            if (postSwapBalance - preSwapBalance < order.minAmountOut)
                revert GeniusErrors.AmountAndDeltaMismatch(
                    order.minAmountOut,
                    postSwapBalance - preSwapBalance
                );
        }

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
        bytes32 receiver,
        address tokenIn,
        bytes32 tokenOut,
        uint256 amountIn,
        uint256 minAmountOut,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee
    ) external payable virtual override onlyExecutor whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (tokenIn != address(STABLECOIN))
            revert GeniusErrors.InvalidToken(tokenIn);
        if (tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();
        if (destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(destChainId);
        if (
            fillDeadline <= _currentTimeStamp() ||
            fillDeadline > _currentTimeStamp() + maxOrderTime
        ) revert GeniusErrors.InvalidDeadline();

        Order memory order = Order({
            trader: trader,
            receiver: receiver,
            amountIn: amountIn,
            seed: seed,
            srcChainId: uint16(_currentChainId()),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: tokenIn,
            fee: fee,
            minAmountOut: minAmountOut,
            tokenOut: tokenOut
        });

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();

        _transferERC20From(
            address(STABLECOIN),
            msg.sender,
            address(this),
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
    function claimFees(
        uint256 amount,
        address token
    ) external virtual override onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > unclaimedFees)
            revert GeniusErrors.InsufficientFees(
                amount,
                unclaimedFees,
                address(STABLECOIN)
            );
        if (token != address(STABLECOIN))
            revert GeniusErrors.InvalidToken(token);

        unclaimedFees -= amount;
        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit FeesClaimed(address(STABLECOIN), amount);
    }

    /**
     * @dev See {IGeniusVault-setOrderAsFilled}.
     */
    function setOrderAsFilled(
        Order memory order
    ) external override onlyOrchestrator whenNotPaused {
        bytes32 _orderHash = orderHash(order);

        if (orderStatus[_orderHash] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

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
        Order calldata order,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external nonReentrant onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (_currentTimeStamp() < order.fillDeadline + orderRevertBuffer)
            revert GeniusErrors.DeadlineNotPassed(
                order.fillDeadline + orderRevertBuffer
            );

        (uint256 _totalRefund, uint256 _protocolFee) = _calculateRefundAmount(
            order.amountIn,
            order.fee
        );

        orderStatus[orderHash_] = OrderStatus.Reverted;

        if (targets.length == 0) {
            _transferERC20(address(STABLECOIN), order.trader, _totalRefund);
        } else {
            _transferERC20(
                address(STABLECOIN),
                address(EXECUTOR),
                _totalRefund
            );
            EXECUTOR.aggregate(targets, data, values);
        }

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

    function minLiquidity() public view override returns (uint256) {
        uint256 reduction = totalStakedAssets > 0
            ? (totalStakedAssets * rebalanceThreshold) / 10_000
            : 0;
        uint256 minBalance = totalStakedAssets > reduction
            ? totalStakedAssets - reduction
            : 0;

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

    function allAssets()
        public
        view
        override
        returns (uint256, uint256, uint256)
    {
        return (stablecoinBalance(), availableAssets(), totalStakedAssets);
    }
}
