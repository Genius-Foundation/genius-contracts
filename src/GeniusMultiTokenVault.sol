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
        address _stablecoin,
        address _admin,
        address _multicall,
        uint256 _rebalanceThreshold,
        uint256 _orderRevertBuffer,
        uint256 _maxOrderTime,
        address[] memory tokens
    ) external initializer {
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold,
            _orderRevertBuffer,
            _maxOrderTime
        );

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
        uint256 dstChainId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external payable override onlyOrchestrator whenNotPaused {
        _isAmountValid(amountIn, availableAssets());

        _transferERC20(address(STABLECOIN), address(MULTICALL), amountIn);
        MULTICALL.aggregateWithValues(targets, data, values);

        emit RemovedLiquidity(amountIn, dstChainId);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       SWAP LIQUIDITY                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-addLiquiditySwap}.
     */
    function createOrder(
        Order memory order
    ) external payable override whenNotPaused {
        address tokenIn = bytes32ToAddress(order.tokenIn);
        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.NonAddress0();
        if (order.amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (supportedTokens[tokenIn] == false)
            revert GeniusErrors.InvalidToken(tokenIn);
        if (order.destChainId == _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (
            order.fillDeadline <= _currentTimeStamp() ||
            order.fillDeadline > _currentTimeStamp() + maxOrderTime
        ) revert GeniusErrors.InvalidDeadline();
        if (order.tokenOut == bytes32(0)) revert GeniusErrors.NonAddress0();

        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Nonexistant)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        if (tokenIn == NATIVE) {
            if (msg.value != order.amountIn)
                revert GeniusErrors.InvalidAmount();
        } else {
            if (!supportedTokens[tokenIn]) revert GeniusErrors.InvalidTokenIn();
            _transferERC20From(
                tokenIn,
                msg.sender,
                address(this),
                order.amountIn
            );
        }

        orderStatus[_orderHash] = OrderStatus.Created;
        supportedTokenReserves[tokenIn] += order.amountIn;

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
     * @dev See {IGeniusMultiTokenPool-removeLiquiditySwap}.
     */
    function fillOrder(
        Order memory order,
        address[] memory targets,
        bytes[] memory data
    ) external override nonReentrant onlyOrchestrator whenNotPaused {
        address tokenIn = bytes32ToAddress(order.tokenIn);
        address receiver = bytes32ToAddress(order.receiver);
        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Nonexistant)
            revert GeniusErrors.OrderAlreadyFilled(_orderHash);
        if (order.destChainId != _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.fillDeadline < _currentTimeStamp())
            revert GeniusErrors.DeadlinePassed(order.fillDeadline);
        if (order.srcChainId == _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.trader == bytes32(0)) revert GeniusErrors.InvalidTrader();

        _isAmountValid(order.amountIn - order.fee, availableAssets());

        orderStatus[_orderHash] = OrderStatus.Filled;

        if (targets.length == 0) {
            _transferERC20(tokenIn, receiver, order.amountIn - order.fee);
        } else {
            IERC20 tokenOut = IERC20(bytes32ToAddress(order.tokenOut));

            uint256 preSwapBalance = tokenOut.balanceOf(receiver);

            _transferERC20(
                tokenIn,
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
            MULTICALL.aggregateWithValues{value: amount}(
                targets,
                dataArray,
                amounts
            );
        } else {
            _transferERC20(token, address(MULTICALL), amount);
            MULTICALL.aggregate(targets, dataArray);
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
        address tokenIn = bytes32ToAddress(order.tokenIn);
        bytes32 _orderHash = orderHash(order);

        if (orderStatus[_orderHash] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        orderStatus[_orderHash] = OrderStatus.Filled;

        supportedTokenFees[tokenIn] += order.fee;
        supportedTokenReserves[tokenIn] -= order.amountIn;

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
        bytes[] memory data
    ) external nonReentrant whenNotPaused {
        address tokenIn = bytes32ToAddress(order.tokenIn);
        address trader = bytes32ToAddress(order.trader);
        if (!hasRole(ORCHESTRATOR_ROLE, msg.sender) && msg.sender != trader) {
            revert GeniusErrors.InvalidTrader();
        }

        bytes32 _orderHash = orderHash(order);
        if (orderStatus[_orderHash] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (_currentTimeStamp() < order.fillDeadline + orderRevertBuffer)
            revert GeniusErrors.DeadlineNotPassed(
                order.fillDeadline + orderRevertBuffer
            );

        orderStatus[_orderHash] = OrderStatus.Reverted;
        supportedTokenReserves[tokenIn] -= order.amountIn;

        if (targets.length == 0) {
            _transferERC20(address(STABLECOIN), trader, order.amountIn);
        } else {
            _transferERC20(
                address(STABLECOIN),
                address(MULTICALL),
                order.amountIn
            );
            MULTICALL.aggregate(targets, data);
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
