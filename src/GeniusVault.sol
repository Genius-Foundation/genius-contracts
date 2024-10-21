// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusVaultCore} from "./GeniusVaultCore.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

contract GeniusVault is GeniusVaultCore {
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
     * @dev See {IGeniusVault-newOrder}.
     */
    function createOrder(
        Order memory order
    ) external payable virtual override whenNotPaused {
        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.NonAddress0();
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

        unclaimedFees += order.fee;
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

    function minLiquidity() public view override returns (uint256) {
        uint256 reduction = totalStakedAssets > 0
            ? (totalStakedAssets * rebalanceThreshold) / 10_000
            : 0;
        uint256 minBalance = totalStakedAssets > reduction
            ? totalStakedAssets - reduction
            : 0;

        return minBalance + unclaimedFees;
    }
}
