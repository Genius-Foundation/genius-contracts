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

    uint256 public crosschainFee; // The fee charged for cross-chain swaps
    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the vault through user deposits
    uint256 public rebalanceThreshold; // The maximum % of deviation from totalStakedAssets before blocking trades

    mapping(address bridge => uint256 isSupported) public supportedBridges; // Mapping of bridge address to support status

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
        rebalanceThreshold = 75;
        crosschainFee = 30;
        
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // =============================================================
    //                      STAKING
    // =============================================================

    /**
     * @dev See {IGeniusVault-stakeDeposit}.
     */
    function stakeDeposit(uint256 amount, address receiver) external override whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        STABLECOIN.safeTransferFrom(msg.sender, address(this), amount);

        _mint(receiver, amount);

        emit StakeDeposit(msg.sender, receiver, amount);

        totalStakedAssets += amount;
    }

    /**
     * @dev See {IGeniusVault-stakeWithdraw}.
     */
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
     * @dev See {IGeniusVault-setCrosschainFee}.
     */
    function setCrosschainFee(uint256 fee) external override onlyAdmin {
        crosschainFee = fee;
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
    function unpause() external override onlyAdmin {
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
        uint256 minBalance = totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
        
        return minBalance;
    }

    /**
     * @dev See {IGeniusVault-orderHash}.
     */
    function orderHash(Order memory order) public override pure returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    /**
     * @notice Returns the current state of the assets in the GeniusVault contract.
     * @return balanceStablecoin The total number of assets in the vault.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the vault.
     */
    function allAssets() external view virtual returns (uint256, uint256, uint256);

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

    function _calculateRefundAmount(uint256 amountIn, uint256 fee) internal view returns (uint256 refundAmount, uint256 protocolFee) {
        uint256 _swapFee = (amountIn * crosschainFee) / 10_000;
        uint256 _protocolFee = fee - _swapFee;

        return (amountIn - _protocolFee, _protocolFee);
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

    /**
     * @dev Authorizes contract upgrades.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal onlyAdmin override {}
}