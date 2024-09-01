// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC4626, ERC20 } from "@solmate/tokens/ERC4626.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { GeniusErrors } from "./libs/GeniusErrors.sol";
import { IGeniusVault } from "./interfaces/IGeniusVault.sol";

/**
 * @title GeniusVault
 * @author @altloot, @samuel_vdu
 * 
 * @notice The GeniusVault contract helps to facilitate cross-chain
 *         liquidity management and swaps utilizing stablecoins as the
 *         primary asset.
 */
contract GeniusVault is IGeniusVault, ERC4626, AccessControl, Pausable {
    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IERC20 public immutable STABLECOIN;
    address public EXECUTOR;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the vault through user deposits
    uint256 public rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades

    mapping(address bridge => uint256 isSupported) public supportedBridges; // Mapping of bridge address to support status

    uint32 public totalOrders;
    mapping(bytes32 => OrderStatus) public orderStatus;

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address stablecoin,
        address admin
    ) ERC4626(ERC20(stablecoin), "Genius USD", "gUSD") {
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

    // =============================================================
    //                            INITIALIZE
    // =============================================================

    /**
     * @dev See {IGeniusVault-initialize}.
     */
    function initialize(address executor) external onlyAdmin {
        if (executor == address(0)) revert GeniusErrors.NonAddress0();
        // Can only be set once
        if (EXECUTOR != address(0)) revert GeniusErrors.Initialized();
        EXECUTOR = executor;

        _unpause();
    }


    function totalAssets() public view override returns (uint256) {
        return totalStakedAssets;
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev See {IGeniusVault-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint16 dstChainId,
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) public payable override onlyOrchestrator whenNotPaused {
        _checkBridgeTargets(targets);
 
        uint256 totalAssetsBeforeTransfer = stablecoinBalance();
        uint256 neededLiquidty_ = minAssetBalance();

        _isAmountValid(amountIn, _availableAssets(totalAssetsBeforeTransfer, neededLiquidty_));
        _checkNative(_sum(values));

        if (!_isBalanceWithinThreshold(totalAssetsBeforeTransfer - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            neededLiquidty_,
            totalAssetsBeforeTransfer - amountIn
        );

        _batchExecution(targets, data, values);

        uint256 _stableDelta = totalAssetsBeforeTransfer - stablecoinBalance();

        if (_stableDelta != amountIn) revert GeniusErrors.AmountInAndDeltaMismatch(amountIn, _stableDelta);

        emit RemovedLiquidity(
            amountIn,
            dstChainId
        );
    }

    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusVault-addLiquiditySwap}.
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
     * @dev See {IGeniusVault-removeLiquiditySwap}.
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
        uint256 _totalAssets = stablecoinBalance();
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

    // =============================================================
    //                      REWARD LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusVault-removeRewardLiquidity}.
     */
    function removeRewardLiquidity(uint256 amount) external override onlyOrchestrator whenNotPaused {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));

        if (!_isBalanceWithinThreshold(_totalAssets - amount)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);
    }

    // =============================================================
    //                      ORDER MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusVault-setOrderAsFilled}.
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
     * @dev See {IGeniusVault-revertOrder}.
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

        uint256 _totalAssetsPreRevert = stablecoinBalance();

        _batchExecution(targets, data, values);

        uint256 _totalAssetsPostRevert = stablecoinBalance();
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
     * @dev See {IGeniusVault-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(uint256 threshold) external override onlyAdmin {
        rebalanceThreshold = threshold;
    }

    // =============================================================
    //                        BRIDGE MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenVault-manageBridge}.
     */
    function manageBridge(address bridge, bool authorize) external override onlyAdmin {
        if (authorize) {
            if (supportedBridges[bridge] == 1) revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 1;
        } else {
            if (supportedBridges[bridge] == 0) revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 0;
        }
    }

    // =============================================================
    //                           EMERGENCY
    // =============================================================

    /**
     * @dev See {IGeniusVault-emergencyLock}.
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @dev See {IGeniusVault-emergencyUnlock}.
     */
    function unpause() external override onlyPauser {
        _unpause();
    }

    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================

    /**
     * @dev See {IGeniusVault-totalAssets}.
     */
    function stablecoinBalance() public override view returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev See {IGeniusVault-minAssetBalance}.
     */
    function minAssetBalance() public override view returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        return totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
    }

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public override view returns (uint256) {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minAssetBalance();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    /**
     * @dev See {IGeniusVault-allAssets}.
     */
    function allAssets() public override view returns (uint256, uint256, uint256) {
        return (
            stablecoinBalance(),
            availableAssets(),
            totalStakedAssets
        );
    }

    /**
     * @dev See {IGeniusVault-orderHash}.
     */
    function orderHash(Order memory order) public override pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Checks if the native currency sent with the transaction is equal to the specified amount.
     * @param amount The expected amount of native currency.
     */
    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
    }

    /**
     * @dev Internal function to check if the given bridge targets are supported.
     * @param bridgeTargets The array of bridge target addresses to check.
     */
    function _checkBridgeTargets(address[] memory bridgeTargets) internal view {
        
        for (uint256 i; i < bridgeTargets.length;) {
            if (supportedBridges[bridgeTargets[i]] == 0) {
                if (bridgeTargets[i] != address(STABLECOIN)) {
                    revert GeniusErrors.InvalidTarget(bridgeTargets[i]);
                }
            }

            unchecked { i++; }

        }

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

    function afterDeposit(uint256 assets, uint256 shares) internal override whenNotPaused {
        totalStakedAssets += assets;
    }

    function beforeWithdraw(uint256 assets, uint256 shares) internal override whenNotPaused {
        if (assets > stablecoinBalance()) revert GeniusErrors.InvalidAmount();
        if (assets > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            assets,
            totalStakedAssets
        );

        totalStakedAssets -= assets;
    }
}