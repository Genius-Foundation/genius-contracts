// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { PausableUpgradeable } from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

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
abstract contract GeniusVaultCore is IGeniusVault, UUPSUpgradeable, ERC20Upgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IERC20 public STABLECOIN;
    address public EXECUTOR;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public totalUnclaimedFees; // The total amount of fees that have not been claimed
    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the vault through user deposits
    uint256 public rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades

    mapping(address bridge => uint256 isSupported) public supportedBridges; // Mapping of bridge address to support status

    uint32 public totalOrders;
    mapping(bytes32 => OrderStatus) public orderStatus;

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
    function _initialize(
        address stablecoin,
        address admin
    ) internal onlyInitializing {
        if (stablecoin == address(0)) revert GeniusErrors.NonAddress0();
        if (admin == address(0)) revert GeniusErrors.NonAddress0();

        __ERC20_init("Genius USD", "gUSD");
        __AccessControl_init();
        __Pausable_init();

        STABLECOIN = IERC20(stablecoin);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
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
    ) external payable override virtual onlyOrchestrator whenNotPaused {
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
        uint32 fillDeadline,
        uint256 fee
    ) external payable virtual override onlyExecutor whenNotPaused {
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

        totalUnclaimedFees += order.fee;
        orderStatus[orderHash_] = OrderStatus.Created;

        emit SwapDeposit(
            order.orderId,
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
    //                        FEE LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(uint256 amount, address token) external override virtual onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalUnclaimedFees) revert GeniusErrors.InsufficientFees(amount, totalUnclaimedFees, address(STABLECOIN));
        if (token != address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);

        totalUnclaimedFees -= amount;
        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit FeesClaimed(
            address(STABLECOIN),
            amount
        );
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
            order.fillDeadline,
            order.fee
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
            order.fillDeadline,
            order.fee
        );
    }

    // =============================================================
    //                     ADMIN
    // =============================================================

    /**
     * @dev See {IGeniusVault-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(uint256 threshold) external override onlyAdmin {
        rebalanceThreshold = threshold;
    }

    /**
     * @dev See {IGeniusVault-setExecutor}.
     */
    function setExecutor(address executor_) external override onlyAdmin {
        if (executor_ == address(0)) revert GeniusErrors.NonAddress0();
        EXECUTOR = executor_;
    }

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
    function unpause() external override onlyAdmin {
        _unpause();
    }

    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================

    /**
     * @dev See {IGeniusVault-totalBalanceExcludingFees}.
     */
    function totalBalanceExcludingFees() public view returns (uint256) {
        return stablecoinBalance() - totalUnclaimedFees;
    }

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
        
        // Calculate the minimum balance based on staked assets
        uint256 minBalance = totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
        
        // Add the unclaimed fees to the minimum balance
        uint256 totalMinBalance = minBalance + totalUnclaimedFees;
        
        // Ensure we're not returning a value larger than totalStakedAssets + totalUnclaimedFees
        uint256 totalLiabilities = totalStakedAssets + totalUnclaimedFees;
        return totalMinBalance > totalLiabilities ? totalLiabilities : totalMinBalance;
    }

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public override view returns (uint256) {
        uint256 _totalAssets = totalBalanceExcludingFees();
        uint256 _neededLiquidity = minAssetBalance();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    /**
     * @dev See {IGeniusVault-allAssets}.
     */
    function allAssets() public override view returns (uint256, uint256, uint256, uint256) {
        return (
            stablecoinBalance(),
            availableAssets(),
            totalStakedAssets,
            totalUnclaimedFees
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
        IERC20(token).safeTransfer(to, amount);
    }

    function _transferERC20From(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    function _batchExecution(
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values
    ) internal {
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

    function stakeDeposit(uint256 amount, address receiver) external override whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        // Need to transfer before minting or ERC777s could reenter.
        STABLECOIN.safeTransferFrom(msg.sender, address(this), amount);

        _mint(receiver, amount);

        emit StakeDeposit(msg.sender, receiver, amount);

        totalStakedAssets += amount;
    }

    function stakeWithdraw(
        uint256 amount,
        address receiver,
        address owner
    ) external override whenNotPaused {
        if (_msgSender() != owner) {
            _spendAllowance(owner, _msgSender(), amount);
        }

        if (amount > stablecoinBalance()) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStakedAssets
        );

        totalStakedAssets -= amount;

        _burn(owner, amount);

        emit StakeWithdraw(msg.sender, receiver, owner, amount);

        STABLECOIN.safeTransfer(receiver, amount);
    }

    /**
     * @dev Authorizes contract upgrades.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal onlyAdmin override {}
}