// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusMultiTokenVault} from "./interfaces/IGeniusMultiTokenVault.sol";
import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {GeniusVaultCore} from "./GeniusVault.sol";

/**
 * @notice This contract is deprecated and is not used in the current implementation.
 */
contract GeniusMultiTokenVault is IGeniusMultiTokenVault, GeniusVaultCore {
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         VARIABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    address public NATIVE;
    mapping(address token => uint256 amount) public feesCollected;
    mapping(address token => uint256 amount) public feesClaimed;

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
        address _native,
        address _stablecoin,
        address _admin,
        address _multicall,
        uint256 _rebalanceThreshold,
        address _priceFeed,
        uint256 _stablePriceLowerBound,
        uint256 _stablePriceUpperBound,
        uint256 _maxOrderAmount
    ) external initializer {
        NATIVE = _native;
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold,
            _priceFeed,
            _stablePriceLowerBound,
            _stablePriceUpperBound,
            _maxOrderAmount
        );
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
        if (order.amountIn == 0 || order.amountIn <= order.fee)
            revert GeniusErrors.InvalidAmount();
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

        if (tokenIn == NATIVE) {
            if (msg.value != order.amountIn)
                revert GeniusErrors.InvalidAmount();
        } else {
            if (tokenIn == address(STABLECOIN)) {
                _verifyStablecoinPrice();
            }
            IERC20(tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                order.amountIn
            );
        }

        feesCollected[tokenIn] += order.fee;
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

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       SWAP FUNCTION                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenPool-swapToStables}.
     */
    function swapToStables(
        address token,
        uint256 amount,
        uint256 minAmountOut,
        address target,
        bytes calldata data
    ) external override onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
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

        uint256 preSwapBalance = stablecoinBalance();

        if (token == NATIVE) {
            PROXYCALL.execute{value: amount}(target, data);
        } else {
            IERC20(token).safeTransfer(address(PROXYCALL), amount);
            PROXYCALL.approveTokenExecute(token, target, data);
        }

        uint256 postSwapBalance = stablecoinBalance();

        if (postSwapBalance - preSwapBalance >= minAmountOut)
            revert GeniusErrors.InvalidAmountOut(
                postSwapBalance - preSwapBalance,
                minAmountOut
            );

        emit SwapExecuted(token, amount, postSwapBalance - preSwapBalance);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ADMIN FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(
        uint256 amount,
        address token
    ) external override onlyOrchestratorOrAdmin whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > claimableFees(token))
            revert GeniusErrors.InsufficientFees(
                amount,
                claimableFees(token),
                token
            );

        feesClaimed[token] += amount;

        if (token == NATIVE) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert GeniusErrors.TransferFailed(NATIVE, amount);
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }

        emit FeesClaimed(token, amount);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       READ FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev function to get the amount of fees that can be claimed
     *
     * @param token The token to check for claimable fees
     *
     * @return uint256 The amount of fees that can be claimed
     */
    function claimableFees(address token) public view returns (uint256) {
        return feesCollected[token] - feesClaimed[token];
    }

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

    /**
     * @dev See {IGeniusMultiTokenVault-minLiquidity}.
     */
    function minLiquidity()
        public
        view
        override(IGeniusVault, GeniusVaultCore)
        returns (uint256)
    {
        uint256 _totalStaked = _convertToStablecoinDecimals(totalStakedAssets);

        uint256 reduction = _totalStaked > 0
            ? (_totalStaked * rebalanceThreshold) / BASE_PERCENTAGE
            : 0;
        uint256 minBalance = _totalStaked > reduction
            ? _totalStaked - reduction
            : 0;

        return minBalance + claimableFees(address(STABLECOIN));
    }
}
