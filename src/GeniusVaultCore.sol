// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {IGeniusExecutor} from "./interfaces/IGeniusExecutor.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusVault} from "./interfaces/IGeniusVault.sol";

/**
 * @title GeniusVault
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusVaultCore contract helps to facilitate cross-chain
 *         liquidity management and swaps utilizing stablecoins as the
 *         primary asset.
 */
abstract contract GeniusVaultCore is
    IGeniusVault,
    UUPSUpgradeable,
    ERC20Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IERC20 public STABLECOIN;
    IGeniusExecutor public EXECUTOR;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         VARIABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    uint32 public maxOrderTime; // In seconds
    uint32 public orderRevertBuffer; // In seconds

    uint256 public feeRefundPercentage; // The percentage for which fees are refunded in case of revert
    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the vault through user deposits
    uint256 public rebalanceThreshold; // The maximum % of deviation from totalStakedAssets before blocking trades

    mapping(address bridge => uint256 isSupported) public supportedBridges; // Mapping of bridge address to support status
    mapping(bytes32 => OrderStatus) public orderStatus; // Mapping of order hash to order status

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         MODIFIERS                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    modifier onlyExecutor() {
        if (msg.sender != address(EXECUTOR))
            revert GeniusErrors.IsNotExecutor();
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert GeniusErrors.IsNotAdmin();
        _;
    }

    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender))
            revert GeniusErrors.IsNotPauser();
        _;
    }

    modifier onlyOrchestrator() {
        if (!hasRole(ORCHESTRATOR_ROLE, msg.sender))
            revert GeniusErrors.IsNotOrchestrator();
        _;
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      INITIALIZATION                       ║
    // ╚═══════════════════════════════════════════════════════════╝

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
        rebalanceThreshold = 7_500; // 75%
        feeRefundPercentage = 5_000; // 50%
        orderRevertBuffer = 60;
        maxOrderTime = 300;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    STAKING FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-stakeDeposit}.
     */
    function stakeDeposit(
        uint256 amount,
        address receiver
    ) external override whenNotPaused {
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
        if (amount > totalStakedAssets)
            revert GeniusErrors.InsufficientBalance(
                address(STABLECOIN),
                amount,
                totalStakedAssets
            );

        totalStakedAssets -= amount;

        _burn(owner, amount);

        emit StakeWithdraw(msg.sender, receiver, owner, amount);

        STABLECOIN.safeTransfer(receiver, amount);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ADMIN FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-setMaxOrderTime}.
     */
    function setMaxOrderTime(uint32 _maxOrderTime) external override onlyAdmin {
        maxOrderTime = _maxOrderTime;
        emit MaxOrderTimeChanged(_maxOrderTime);
    }

    /**
     * @dev See {IGeniusVault-setOrderRevertBuffer}.
     */
    function setOrderRevertBuffer(
        uint32 _orderRevertBuffer
    ) external override onlyAdmin {
        orderRevertBuffer = _orderRevertBuffer;
        emit OrderRevertBufferChanged(_orderRevertBuffer);
    }

    /**
     * @dev See {IGeniusVault-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(
        uint256 _rebalanceThreshold
    ) external override onlyAdmin {
        _validatePercentage(_rebalanceThreshold);

        rebalanceThreshold = _rebalanceThreshold;
        emit RebalanceThresholdChanged(_rebalanceThreshold);
    }

    /**
     * @dev See {IGeniusVault-setExecutor}.
     */
    function setExecutor(address executor) external override onlyAdmin {
        if (executor == address(0)) revert GeniusErrors.NonAddress0();
        EXECUTOR = IGeniusExecutor(executor);
        emit ExecutorChanged(executor);
    }

    /**
     * @dev See {IGeniusVault-setFeeRefundPercentage}.
     */
    function setFeeRefundPercentage(
        uint256 _feeRefundPercentage
    ) external override onlyAdmin {
        _validatePercentage(_feeRefundPercentage);

        feeRefundPercentage = _feeRefundPercentage;
        emit FeeRefundPercentageChanged(_feeRefundPercentage);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    BRIDGE MANAGEMENT                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusMultiTokenVault-manageBridge}.
     */
    function manageBridge(
        address bridge,
        bool authorize
    ) external override onlyAdmin {
        if (authorize) {
            if (supportedBridges[bridge] == 1)
                revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 1;
        } else {
            if (supportedBridges[bridge] == 0)
                revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 0;
        }
        emit BridgeAuthorized(bridge, authorize);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         EMERGENCY                         ║
    // ╚═══════════════════════════════════════════════════════════╝

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

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       READ FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-totalAssets}.
     */
    function stablecoinBalance() public view override returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev See {IGeniusVault-orderHash}.
     */
    function orderHash(
        Order memory order
    ) public pure override returns (bytes32) {
        return keccak256(abi.encode(order));
    }

    /**
     * @notice Returns the current state of the assets in the GeniusVault contract.
     * @return balanceStablecoin The total number of assets in the vault.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the vault.
     */
    function allAssets()
        external
        view
        virtual
        returns (uint256, uint256, uint256);

    /**
     * @dev See {IGeniusVault-bytes32ToAddress}.
     */
    function bytes32ToAddress(
        bytes32 _input
    ) public pure override returns (address) {
        require(
            uint96(uint256(_input) >> 160) == 0,
            "First 12 bytes must be zero"
        );
        address extractedAddress = address(uint160(uint256(_input)));
        require(extractedAddress != address(0), "Invalid zero address");
        return extractedAddress;
    }

    /**
     * @dev See {IGeniusVault-addressToBytes32}.
     */
    function addressToBytes32(
        address _input
    ) public pure override returns (bytes32) {
        return bytes32(uint256(uint160(_input)));
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                   INTERNAL FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Checks if the native currency sent with the transaction is equal to the specified amount.
     * @param amount The expected amount of native currency.
     */
    function _checkNative(uint256 amount) internal {
        if (msg.value != amount)
            revert GeniusErrors.InvalidNativeAmount(amount);
    }

    /**
     * @dev Internal function to check if the given bridge targets are supported.
     * @param bridgeTargets The array of bridge target addresses to check.
     */
    function _checkBridgeTargets(address[] memory bridgeTargets) internal view {
        for (uint256 i; i < bridgeTargets.length; ) {
            if (supportedBridges[bridgeTargets[i]] == 0) {
                if (bridgeTargets[i] != address(STABLECOIN)) {
                    revert GeniusErrors.InvalidTarget(bridgeTargets[i]);
                }
            }

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Internal function to find the available assets for a given amount.
     * @param _totalAssets The total assets available after the operation.
     * @param _neededLiquidity The amount of assets needed for the operation.
     */
    function _availableAssets(
        uint256 _totalAssets,
        uint256 _neededLiquidity
    ) internal pure returns (uint256) {
        if (_totalAssets < _neededLiquidity) {
            return 0;
        }

        return _totalAssets - _neededLiquidity;
    }

    /**
     * @dev Internal function to determine if a given amount is valid for withdrawal.
     * @param _amount The amount to withdraw.
     * @param _availableLiquidity The total available assets.
     */
    function _isAmountValid(
        uint256 _amount,
        uint256 _availableLiquidity
    ) internal pure {
        if (_amount == 0) revert GeniusErrors.InvalidAmount();

        if (_amount > _availableLiquidity)
            revert GeniusErrors.InsufficientLiquidity(
                _availableLiquidity,
                _amount
            );
    }

    /**
     * @dev Internal function to update the staked balance.
     * @param amount The amount to update the balance with.
     * @param add The operation to perform. 1 for addition, 0 for subtraction.
     */
    function _updateStakedBalance(uint256 amount, uint256 add) internal {
        if (add == 1) {
            totalStakedAssets += amount;
        } else {
            totalStakedAssets -= amount;
        }
    }

    /**
     * @dev Internal function to sum token amounts.
     * @param amounts The array of token amounts to sum.
     */
    function _sum(
        uint256[] calldata amounts
    ) internal pure returns (uint256 total) {
        for (uint i = 0; i < amounts.length; ) {
            total += amounts[i];

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Internal function to calculate the refund amount for a reverted order.
     * @param fees The total fees charged for the order.
     * @return refundAmount The amount to refund to the user.
     */
    function _feeRefundAmount(uint256 fees) internal view returns (uint256) {
        return (fees * feeRefundPercentage) / 10_000;
    }

    function _validatePercentage(uint256 percentage) internal pure {
        if (percentage > 10_000) revert GeniusErrors.InvalidPercentage();
    }

    /**
     * @dev Internal function to safeTransfer ERC20 tokens.
     * @param token The address of the token to transfer.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transferERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Internal function to safeTransferFrom ERC20 tokens.
     * @param token The address of the token to transfer.
     * @param from The address to transfer the tokens from.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transferERC20From(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransferFrom(from, to, amount);
    }

    /**
     * @dev Internal function to batch execute external calls.
     * @param targets The array of target addresses to call.
     * @param data The array of data to pass to the target addresses.
     * @param values The array of values to send to the target addresses.
     */
    function _batchExecution(
        address[] memory targets,
        bytes[] memory data,
        uint256[] memory values
    ) internal {
        for (uint i = 0; i < targets.length; ) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success)
                revert GeniusErrors.ExternalCallFailed(targets[i], i);

            unchecked {
                i++;
            }
        }
    }

    /**
     * @dev Internal function to fetch the current chain ID.
     */
    function _currentChainId() internal view returns (uint256) {
        return block.chainid;
    }

    /**
     * @dev Internal function to fetch the current timestamp.
     */
    function _currentTimeStamp() internal view returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Authorizes contract upgrades.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyAdmin {}
}
