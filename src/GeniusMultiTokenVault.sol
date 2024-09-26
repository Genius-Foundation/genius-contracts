// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusMultiTokenVault} from "./interfaces/IGeniusMultiTokenVault.sol";
import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {GeniusVaultCore} from "./GeniusVault.sol";

/**
 * @title GeniusMultiTokenPool
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusMultiTokenPool contract helps to facilitate cross-chain
 *         liquidity management and swaps and can utilize multiple sources of liquidity.
 */
contract GeniusMultiTokenVault is IGeniusMultiTokenVault, GeniusVaultCore {
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    address public immutable NATIVE = address(0);

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         VARIABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    mapping(address token => bool isSupported) public supportedTokens; // Mapping of token addresses to TokenInfo structs
    mapping(address token => uint256 amount) public supportedTokenFees; // Mapping of token address to total unclaimed fees
    mapping(address token => uint256 amount) public supportedTokenReserves; // Mapping of token address to total reserved assets

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        CONSTRUCTOR                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    constructor() {
        _disableInitializers();
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      INITIALIZATION                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-initialize}.
     */
    function initialize(
        address stablecoin,
        address admin,
        address[] memory tokens
    ) external initializer {
        GeniusVaultCore._initialize(stablecoin, admin);

        supportedTokens[address(STABLECOIN)] = true;
        emit TokenSupported(address(STABLECOIN), true);

        for (uint256 i; i < tokens.length; ) {
            setTokenSupported(tokens[i], true);

            unchecked {
                i++;
            }
        }
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                  BRIDGE LIQUIDITY BALANCING               ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint32 dstChainId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external payable override onlyOrchestrator whenNotPaused {
        _isAmountValid(amountIn, availableAssets());
        _checkNative(_sum(values));

        _transferERC20(address(STABLECOIN), address(EXECUTOR), amountIn);
        EXECUTOR.aggregate(targets, data, values);

        emit RemovedLiquidity(amountIn, dstChainId);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       SWAP LIQUIDITY                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-addLiquiditySwap}.
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
    ) external payable override onlyExecutor whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (supportedTokens[tokenIn] == false)
            revert GeniusErrors.InvalidToken(tokenIn);
        if (destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(destChainId);
        if (
            fillDeadline <= _currentTimeStamp() ||
            fillDeadline > _currentTimeStamp() + maxOrderTime
        ) revert GeniusErrors.InvalidDeadline();
        if (tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();

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

        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();

        if (tokenIn == NATIVE) {
            if (msg.value != amountIn) revert GeniusErrors.InvalidAmount();
        } else {
            if (!supportedTokens[tokenIn])
                revert GeniusErrors.InvalidToken(tokenIn);
            _transferERC20From(tokenIn, msg.sender, address(this), amountIn);
        }

        orderStatus[_orderHash] = OrderStatus.Created;
        supportedTokenReserves[tokenIn] += amountIn;

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
     * @dev See {IGeniusMultiTokenPool-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external override nonReentrant onlyOrchestrator whenNotPaused {
        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Nonexistant)
            revert GeniusErrors.OrderAlreadyFilled(_orderHash);
        if (order.destChainId != _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.fillDeadline < _currentTimeStamp())
            revert GeniusErrors.DeadlinePassed(order.fillDeadline);
        if (order.srcChainId == _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.trader == address(0)) revert GeniusErrors.InvalidTrader();

        _isAmountValid(order.amountIn - order.fee, availableAssets());

        orderStatus[_orderHash] = OrderStatus.Filled;
        address receiver = bytes32ToAddress(order.receiver);

        if (targets.length == 0) {
            _transferERC20(order.tokenIn, receiver, order.amountIn - order.fee);
        } else {
            IERC20 tokenOut = IERC20(bytes32ToAddress(order.tokenOut));

            uint256 preSwapBalance = tokenOut.balanceOf(receiver);

            _transferERC20(
                order.tokenIn,
                address(EXECUTOR),
                order.amountIn - order.fee
            );
            EXECUTOR.aggregate(targets, data, values);

            uint256 postSwapBalance = tokenOut.balanceOf(receiver);

            if (postSwapBalance - preSwapBalance < order.minAmountOut)
                revert GeniusErrors.InvalidAmountOut(
                    postSwapBalance - preSwapBalance,
                    order.minAmountOut
                );
        }

        emit SwapWithdrawal(
            order.seed,
            order.trader,
            order.receiver,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       SWAP FUNCTION                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-swapToStables}.
     */
    function swapToStables(
        address token,
        uint256 amount,
        address target,
        bytes calldata data
    ) external override onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (!supportedTokens[token]) revert GeniusErrors.InvalidToken(token);
        if (target == address(0)) revert GeniusErrors.InvalidTarget(target);

        uint256 _tokenBalance = tokenBalance(token);
        if (_tokenBalance < amount)
            revert GeniusErrors.InsufficientBalance(
                token,
                amount,
                _tokenBalance
            );

        address[] memory targets = new address[](1);
        targets[0] = target;
        bytes[] memory dataArray = new bytes[](1);
        dataArray[0] = data;
        uint256[] memory amounts = new uint256[](1);

        uint256 preSwapBalance = stablecoinBalance();

        if (token == NATIVE) {
            EXECUTOR.aggregate{value: amount}(targets, dataArray, amounts);
        } else {
            _transferERC20(token, address(EXECUTOR), amount);
            EXECUTOR.aggregate(targets, dataArray, amounts);
        }

        uint256 postSwapBalance = stablecoinBalance();

        if (postSwapBalance <= preSwapBalance)
            revert GeniusErrors.TransferFailed(token, amount);

        emit SwapExecuted(token, amount, postSwapBalance - preSwapBalance);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ORDER FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-setOrderAsFilled}.
     */
    function setOrderAsFilled(
        Order memory order
    ) external override(IGeniusVault) onlyOrchestrator whenNotPaused {
        bytes32 _orderHash = orderHash(order);

        if (orderStatus[_orderHash] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        orderStatus[_orderHash] = OrderStatus.Filled;

        supportedTokenFees[order.tokenIn] += order.fee;
        supportedTokenReserves[order.tokenIn] -= order.amountIn;

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
     * @dev See {IGeniusVault-revertOrder}.
     */
    function revertOrder(
        Order calldata order,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) external nonReentrant onlyOrchestrator whenNotPaused {
        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Created)
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

        orderStatus[_orderHash] = OrderStatus.Reverted;
        supportedTokenFees[order.tokenIn] += _protocolFee;
        supportedTokenReserves[order.tokenIn] -= order.amountIn;

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

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ADMIN FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-setTokenSupported}.
     */
    function setTokenSupported(
        address token,
        bool supported
    ) public override onlyAdmin {
        if (token == address(STABLECOIN)) {
            revert GeniusErrors.InvalidToken(token);
        }
        supportedTokens[token] = supported;
        emit TokenSupported(token, supported);
    }

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(
        uint256 amount,
        address token
    ) external override onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (supportedTokenFees[token] < amount)
            revert GeniusErrors.InsufficientFees(
                amount,
                supportedTokenFees[token],
                token
            );

        if (token == NATIVE) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert GeniusErrors.TransferFailed(NATIVE, amount);
        } else {
            _transferERC20(token, msg.sender, amount);
        }

        emit FeesClaimed(token, amount);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       READ FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenVault-tokenBalance}.
     */
    function tokenBalance(
        address token
    ) public view override returns (uint256) {
        if (token == NATIVE) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function minLiquidity() public view override returns (uint256) {
        uint256 reduction = totalStakedAssets > 0
            ? (totalStakedAssets * rebalanceThreshold) / 10_000
            : 0;
        uint256 minBalance = totalStakedAssets > reduction
            ? totalStakedAssets - reduction
            : 0;

        uint256 result = minBalance +
            supportedTokenFees[address(STABLECOIN)] +
            supportedTokenReserves[address(STABLECOIN)];

        return result;
    }

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public view returns (uint256) {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    /**
     * @dev See {IGeniusVault-allAssets}.
     */
    function allAssets()
        public
        view
        override
        returns (uint256, uint256, uint256)
    {
        return (stablecoinBalance(), availableAssets(), totalStakedAssets);
    }

    /**
     * @dev See {IGeniusMultiTokenPool-isTokenSupported}.
     */
    function isTokenSupported(
        address token
    ) public view override returns (bool) {
        return supportedTokens[token];
    }
}
