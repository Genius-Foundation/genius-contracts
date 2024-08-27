// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {Executable} from "./access/Executable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusPool} from "./interfaces/IGeniusPool.sol";

contract GeniusPool is IGeniusPool, Orchestrable, Executable, Pausable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    IERC20 public immutable override STABLECOIN;

    address public override VAULT;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public override initialized; // Flag to check if the contract has been initialized

    uint256 public override totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public override rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address stablecoin,
        address owner
    ) Ownable(owner) {
        if (stablecoin == address(0)) revert GeniusErrors.InvalidToken(stablecoin);
        if (owner == address(0)) revert GeniusErrors.InvalidOwner();

        STABLECOIN = IERC20(stablecoin);

        initialized = 0;
        _pause();
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier whenReady() {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        _requireNotPaused();
        _;
    }

    /**
     * @dev See {IGeniusPool-initialize}.
     */
    function initialize(address vaultAddress, address executor) external onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();
        VAULT = vaultAddress;
        _initializeExecutor(payable(executor));

        initialized = 1;
        _unpause();
    }

    /**
     * @dev See {IGeniusPool-totalAssets}.
     */
    function totalAssets() public view returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev See {IGeniusPool-minAssetBalance}.
     */
    function minAssetBalance() public view returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        return totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
    }

    /**
     * @dev See {IGeniusPool-availableAssets}.
     */
    function availableAssets() public view returns (uint256) {
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
    ) public payable onlyOrchestrator whenReady {
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

        emit BridgeFunds(
            amountIn,
            dstChainId
        );
    }

    /**
     * @dev See {IGeniusPool-addLiquiditySwap}.
     */
    function addLiquiditySwap(
        address trader,
        address token,
        uint256 amount
    ) external onlyExecutor whenReady {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (token != address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);

        _transferERC20From(address(STABLECOIN), msg.sender,  address(this), amount);

        emit SwapDeposit(
            trader,
            token,
            amount
        );
    }

    /**
     * @dev See {IGeniusPool-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external onlyExecutor whenReady {
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));

        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (!_isBalanceWithinThreshold(_totalAssets - amount)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit SwapWithdrawal(trader, amount);
    }

    /**
     * @dev See {IGeniusPool-removeRewardLiquidity}.
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator whenReady {
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
    function stakeLiquidity(address trader, uint256 amount) external whenReady {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
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
    function removeStakedLiquidity(address trader, uint256 amount) external whenReady {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
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
     * @dev See {IGeniusPool-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(uint256 threshold) external onlyOwner {
        rebalanceThreshold = threshold;
    }

    /**
     * @dev See {IGeniusPool-emergencyLock}.
     */
    function emergencyLock() external onlyOwner {
        _pause();
    }

    /**
     * @dev See {IGeniusPool-emergencyUnlock}.
     */
    function emergencyUnlock() external onlyOwner {
        _unpause();
    }

    /**
     * @dev See {IGeniusPool-assets}.
     */
    function assets() public view returns (uint256, uint256, uint256) {
        return (
            totalAssets(),
            availableAssets(),
            totalStakedAssets
        );
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
}