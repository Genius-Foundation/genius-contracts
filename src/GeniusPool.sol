// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { GeniusErrors } from "./libs/GeniusErrors.sol";
import { IGeniusPool } from "./interfaces/IGeniusPool.sol";

contract GeniusPool is IGeniusPool, AccessControl, Pausable {
    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IERC20 public immutable STABLECOIN;
    address public VAULT;
    address public EXECUTOR;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades

    uint32 public totalOrders;
    mapping(bytes32 => OrderStatus) public orderStatus;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address stablecoin,
        address admin
    ) {
        if (stablecoin == address(0)) revert GeniusErrors.NonAddress0();
        if (admin == address(0)) revert GeniusErrors.NonAddress0();

        STABLECOIN = IERC20(stablecoin);
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _pause();
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier onlyExecutor() {
        if (msg.sender != EXECUTOR) revert GeniusErrors.IsNotExecutor();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert GeniusErrors.IsNotAdmin();
        _;
    }

    modifier onlyPauser() {
        if(!hasRole(PAUSER_ROLE, msg.sender)) revert GeniusErrors.IsNotPauser();
        _;
    }

    modifier onlyOrchestrator() {
        if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) revert GeniusErrors.IsNotOrchestrator();
        _;
    }

    /**
     * @dev See {IGeniusPool-initialize}.
     */
    function initialize(address vaultAddress, address executor) external onlyAdmin {
        if (VAULT != address(0)) revert GeniusErrors.Initialized();
        VAULT = vaultAddress;
        EXECUTOR = executor;

        _unpause();
    }

    /**
     * @dev See {IGeniusPool-totalAssets}.
     */
    function totalAssets() public override view returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev See {IGeniusPool-minAssetBalance}.
     */
    function minAssetBalance() public override view returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        return totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
    }

    /**
     * @dev See {IGeniusPool-availableAssets}.
     */
    function availableAssets() public override view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    /**
     * @dev See {IGeniusPool-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint16 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) public payable override onlyOrchestrator whenNotPaused {
        uint256 totalAssetsBeforeTransfer = totalAssets();
        uint256 neededLiquidty_ = minAssetBalance();

        _isAmountValid(amountIn, _availableAssets(totalAssetsBeforeTransfer, neededLiquidty_));
        _checkNative(_sum(values));

        if (!_isBalanceWithinThreshold(totalAssetsBeforeTransfer - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            neededLiquidty_,
            totalAssetsBeforeTransfer - amountIn
        );

        _batchExecution(targets, data, values);

        uint256 _stableDelta = totalAssetsBeforeTransfer - totalAssets();

        if (_stableDelta != amountIn) revert GeniusErrors.AmountInAndDeltaMismatch(amountIn, _stableDelta);

        emit RemovedLiquidity(
            amountIn,
            dstChainId
        );
    }

    /**
     * @dev See {IGeniusPool-addLiquiditySwap}.
     */
    function addLiquiditySwap(
        address trader,
        address tokenIn,
        uint256 amountIn,
        uint16 destChainId,
        uint32 fillDeadline
    ) external override onlyExecutor whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (tokenIn != address(STABLECOIN)) revert GeniusErrors.InvalidToken(tokenIn);
        if (destChainId == _currentChainId()) revert GeniusErrors.InvalidDestChainId(destChainId);
        if (fillDeadline <= _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(fillDeadline);

        Order memory order = Order({
            trader: trader,
            amountIn: amountIn,
            orderId: totalOrders++,
            srcChainId: uint16(_currentChainId()),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: tokenIn
        });
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.InvalidOrderStatus();

        _transferERC20From(address(STABLECOIN), msg.sender, address(this), order.amountIn);

        orderStatus[orderHash_] = OrderStatus.Created;        

        emit SwapDeposit(
            order.orderId,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    /**
     * @dev See {IGeniusPool-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order
    ) external override onlyExecutor whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId()) revert GeniusErrors.InvalidDestChainId(order.destChainId);     
        if (order.fillDeadline < _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(order.fillDeadline); 
        if (order.srcChainId == _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);


        // Gas saving
        uint256 _totalAssets = totalAssets();
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
            order.orderId,
            order.trader,
            address(STABLECOIN),
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    /**
     * @dev See {IGeniusPool-removeRewardLiquidity}.
     */
    function removeRewardLiquidity(uint256 amount) external override onlyOrchestrator whenNotPaused {
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));

        if (!_isBalanceWithinThreshold(_totalAssets - amount)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);
    }

    /**
     * @dev See {IGeniusPool-stakeLiquidity}.
     */
    function stakeLiquidity(address trader, uint256 amount) external override onlyVault whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        _transferERC20From(address(STABLECOIN), msg.sender, address(this), amount);

        _updateStakedBalance(amount, 1);

        emit Stake(
            trader,
            amount,
            amount
        );
    }

    /**
     * @dev See {IGeniusPool-removeStakedLiquidity}.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external override onlyVault whenNotPaused {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();

        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalAssets()) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStakedAssets
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);

        _updateStakedBalance(amount, 0);

        emit Unstake(
            trader,
            amount,
            amount
        );
    }

    /**
     * @dev See {IGeniusPool-setOrderAsFilled}.
     */
    function setOrderAsFilled(Order memory order) external override onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);

        if (orderStatus[orderHash_] != OrderStatus.Created) revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        orderStatus[orderHash_] = OrderStatus.Filled;

        emit OrderFilled(
            order.orderId,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    /**
     * @dev See {IGeniusPool-revertOrder}.
     */
    function revertOrder(
        Order calldata order, 
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external override onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created) revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.fillDeadline >= _currentTimeStamp()) revert GeniusErrors.DeadlineNotPassed(order.fillDeadline);

        uint256 _totalAssetsPreRevert = totalAssets();

        _batchExecution(targets, data, values);

        uint256 _totalAssetsPostRevert = totalAssets();
        uint256 _delta = _totalAssetsPreRevert - _totalAssetsPostRevert;

        if (_delta != order.amountIn) revert GeniusErrors.InvalidDelta();

        orderStatus[orderHash_] = OrderStatus.Reverted;

        emit OrderReverted(
            order.orderId,
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.srcChainId,
            order.destChainId,
            order.fillDeadline
        );
    }

    // =============================================================
    //                     REBALANCE THRESHOLD
    // =============================================================

    /**
     * @dev See {IGeniusPool-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(uint256 threshold) external override onlyAdmin {
        rebalanceThreshold = threshold;
    }

    /**
     * @dev See {IGeniusPool-emergencyLock}.
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @dev See {IGeniusPool-emergencyUnlock}.
     */
    function unpause() external override onlyPauser {
        _unpause();
    }

    /**
     * @dev See {IGeniusPool-assets}.
     */
    function assets() public override view returns (uint256, uint256, uint256) {
        return (
            totalAssets(),
            availableAssets(),
            totalStakedAssets
        );
    }

    /**
     * @dev See {IGeniusPool-orderHash}.
     */
    function orderHash(Order memory order) public override pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
    }

    function _availableAssets(uint256 _totalAssets, uint256 _neededLiquidity) internal pure returns (uint256) {
        if (_totalAssets < _neededLiquidity) {
            return 0;
        }

        return _totalAssets - _neededLiquidity;
    }

    function _isAmountValid(uint256 amount_, uint256 availableAssets_) internal pure {
        if (amount_ == 0) revert GeniusErrors.InvalidAmount();

        if (amount_ > availableAssets_) revert GeniusErrors.InsufficientLiquidity(
            availableAssets_,
            amount_
        );
    }

    function _isBalanceWithinThreshold(uint256 balance) internal view returns (bool) {
        uint256 lowerBound = (totalStakedAssets * rebalanceThreshold) / 100;

        return balance >= lowerBound;
    }

    function _updateStakedBalance(uint256 amount, uint256 add) internal {
        if (add == 1) {
            totalStakedAssets += amount;
        } else {
            totalStakedAssets -= amount;
        }
    }

    function _sum(uint256[] calldata amounts) internal pure returns (uint256 total) {
        for (uint i = 0; i < amounts.length;) {
            total += amounts[i];

            unchecked { i++; }
        }
    }

    function _transferERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).transfer(to, amount);
    }

    function _transferERC20From(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).transferFrom(from, to, amount);
    }

    function _batchExecution(
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values
    ) private {
        for (uint i = 0; i < targets.length;) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success) revert GeniusErrors.ExternalCallFailed(targets[i], i);

            unchecked { i++; }
        }
    }

    function _currentChainId() internal view returns (uint256) {
        return block.chainid;
    }

    function _currentTimeStamp() internal view returns (uint256) {
        return block.timestamp;
    }
}