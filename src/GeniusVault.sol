// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

contract GeniusVault is GeniusVaultCore {
    uint256 public feesCollected;
    uint256 public feesClaimed;

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
        uint256 _rebalanceThreshold
    ) external initializer {
        GeniusVaultCore._initialize(
            _stablecoin,
            _admin,
            _multicall,
            _rebalanceThreshold
        );
    }

    /**
     * @dev See {IGeniusVault-newOrder}.
     */
    function createOrder(
        Order memory order
    ) external payable virtual override whenNotPaused {
        address tokenIn = address(STABLECOIN);
        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.NonAddress0();
        if (order.amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (order.tokenIn != addressToBytes32(tokenIn))
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

        _transferERC20From(
            address(STABLECOIN),
            msg.sender,
            address(this),
            order.amountIn
        );

        feesCollected += order.fee;
        orderStatus[orderHash_] = OrderStatus.Created;

        emit OrderCreated(
            order.seed,
            order.trader,
            order.receiver,
            order.tokenIn,
            order.tokenOut,
            order.amountIn,
            order.minAmountOut,
            order.srcChainId,
            order.destChainId,
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
        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit FeesClaimed(address(STABLECOIN), amount);
    }

    /**
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view override returns (uint256) {
        uint256 reduction = (totalStakedAssets * rebalanceThreshold) / 10_000;
        uint256 minBalance = totalStakedAssets - reduction;
        return minBalance + claimableFees();
    }
}
