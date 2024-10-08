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
     */
    function initialize(
        address _stablecoin,
        address _admin,
        address _multicall,
        uint256 _rebalanceThreshold,
        uint256 _orderRevertBuffer,
        uint256 _maxOrderTime
    ) external initializer {
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold,
            _orderRevertBuffer,
            _maxOrderTime
        );
    }

    /**
     * @dev See {IGeniusVault-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint256 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external payable virtual override onlyOrchestrator whenNotPaused {
        _isAmountValid(amountIn, availableAssets());
        _checkNative(_sum(values));

        _transferERC20(address(STABLECOIN), address(MULTICALL), amountIn);

        MULTICALL.aggregateWithValues(targets, data, values);

        emit RemovedLiquidity(amountIn, dstChainId);
    }

    /**
     * @dev See {IGeniusVault-fillOrder}.
     */
    function fillOrder(
        Order memory order,
        address[] memory targets,
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

        if (order.trader == bytes32(0)) revert GeniusErrors.InvalidTrader();

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
                address(MULTICALL),
                order.amountIn - order.fee
            );
            MULTICALL.aggregate(targets, data);

            uint256 postSwapBalance = tokenOut.balanceOf(receiver);

            if (postSwapBalance - preSwapBalance < order.minAmountOut)
                revert GeniusErrors.InvalidAmountOut(
                    postSwapBalance - preSwapBalance,
                    order.minAmountOut
                );
        }

        emit OrderFilled(
            order.seed,
            order.trader,
            order.receiver,
            addressToBytes32(address(STABLECOIN)),
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    /**
     * @dev See {IGeniusVault-newOrder}.
     */
    function createOrder(
        Order memory order
    ) external payable virtual override whenNotPaused {
        if (order.trader == bytes32(0)) revert GeniusErrors.InvalidTrader();
        if (order.amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (order.tokenIn != addressToBytes32(address(STABLECOIN)))
            revert GeniusErrors.InvalidTokenIn();
        if (order.tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();
        if (order.destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (
            order.fillDeadline <= _currentTimeStamp() ||
            order.fillDeadline > _currentTimeStamp() + maxOrderTime
        ) revert GeniusErrors.InvalidDeadline();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

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

        emit OrderCreated(
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
        bytes[] memory data
    ) external override nonReentrant whenNotPaused {
        if (
            !hasRole(ORCHESTRATOR_ROLE, msg.sender) &&
            msg.sender != bytes32ToAddress(order.trader)
        ) {
            revert GeniusErrors.InvalidTrader();
        }

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (_currentTimeStamp() < order.fillDeadline + orderRevertBuffer)
            revert GeniusErrors.DeadlineNotPassed(
                order.fillDeadline + orderRevertBuffer
            );

        orderStatus[orderHash_] = OrderStatus.Reverted;

        if (targets.length == 0) {
            _transferERC20(
                address(STABLECOIN),
                bytes32ToAddress(order.trader),
                order.amountIn
            );
        } else {
            _transferERC20(
                address(STABLECOIN),
                address(MULTICALL),
                order.amountIn
            );
            MULTICALL.aggregate(targets, data);
        }

        reservedAssets -= order.amountIn;

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
