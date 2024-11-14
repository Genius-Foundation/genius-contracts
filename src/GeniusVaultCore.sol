// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";
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
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // Immutable state variables (not actually immutable due to upgradeability)
    IERC20 public STABLECOIN;
    IGeniusProxyCall public PROXYCALL;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    // Mutable state variables
    uint256 public totalStakedAssets;
    uint256 public rebalanceThreshold;

    mapping(address => mapping(uint256 => uint256)) public targetChainMinFee;

    mapping(address => uint256) public supportedBridges;
    mapping(bytes32 => OrderStatus) public orderStatus;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         MODIFIERS                         ║
    // ╚═══════════════════════════════════════════════════════════╝

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

    modifier onlyOrchestratorOrAdmin() {
        if (
            !hasRole(ORCHESTRATOR_ROLE, msg.sender) &&
            !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)
        ) revert GeniusErrors.IsNotOrchestratorNorAdmin();
        _;
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      INITIALIZATION                       ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-initialize}.
     */
    function _initialize(
        address _stablecoin,
        address _admin,
        address _multicall,
        uint256 _rebalanceThreshold
    ) internal onlyInitializing {
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();

        __ERC20_init("Genius USD", "gUSD");
        __AccessControl_init();
        __Pausable_init();

        STABLECOIN = IERC20(_stablecoin);
        PROXYCALL = IGeniusProxyCall(_multicall);
        _setRebalanceThreshold(_rebalanceThreshold);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @dev See {IGeniusVault-rebalanceLiquidity}.
     */
    function rebalanceLiquidity(
        uint256 amountIn,
        uint256 dstChainId,
        address target,
        bytes calldata data
    ) external payable virtual override onlyOrchestrator whenNotPaused {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        _isAmountValid(amountIn, availableAssets());

        _transferERC20(address(STABLECOIN), address(PROXYCALL), amountIn);
        PROXYCALL.approveTokenExecute{value: msg.value}(
            address(STABLECOIN),
            target,
            data
        );

        emit RebalancedLiquidity(amountIn, dstChainId);
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

        totalStakedAssets += amount;

        STABLECOIN.safeTransferFrom(msg.sender, address(this), amount);
        _mint(receiver, amount);

        emit StakeDeposit(msg.sender, receiver, amount);
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

    /**
     * @dev See {IGeniusVault-fillOrder}.
     */
    function fillOrder(
        Order memory order,
        address swapTarget,
        bytes memory swapData,
        address callTarget,
        bytes memory callData
    ) external virtual override nonReentrant onlyOrchestrator whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.srcChainId == _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.InvalidTrader();

        _isAmountValid(order.amountIn - order.fee, availableAssets());

        bool isSwap = swapTarget != address(0);
        bool isCall = callTarget != address(0);

        if (isCall) {
            bytes32 reconstructedSeed = calldataToSeed(callTarget, callData);
            if (reconstructedSeed != order.seed)
                revert GeniusErrors.InvalidSeed();
        }

        orderStatus[orderHash_] = OrderStatus.Filled;
        address receiver = bytes32ToAddress(order.receiver);
        address effectiveTokenOut = address(STABLECOIN);
        uint256 effectiveAmountOut = order.amountIn - order.fee;
        bool success = true;

        if (!isCall && !isSwap) {
            _transferERC20(
                address(STABLECOIN),
                receiver,
                order.amountIn - order.fee
            );
        } else {
            IERC20 tokenOut = IERC20(bytes32ToAddress(order.tokenOut));
            IERC20(address(STABLECOIN)).safeTransfer(
                address(PROXYCALL),
                order.amountIn - order.fee
            );
            (effectiveTokenOut, effectiveAmountOut, success) = PROXYCALL.call(
                receiver,
                swapTarget,
                callTarget,
                address(STABLECOIN),
                address(tokenOut),
                order.minAmountOut,
                swapData,
                callData
            );
        }

        emit OrderFilled(
            order.seed,
            order.trader,
            order.receiver,
            effectiveTokenOut,
            effectiveAmountOut,
            order.destChainId,
            success
        );
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ADMIN FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusVault-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(
        uint256 _rebalanceThreshold
    ) external override onlyAdmin {
        _setRebalanceThreshold(_rebalanceThreshold);
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
     * @dev See {IGeniusVault-minLiquidity}.
     */
    function minLiquidity() public view virtual override returns (uint256);

    /**
     * @dev See {IGeniusVault-availableAssets}.
     */
    function availableAssets() public view returns (uint256) {
        uint256 _totalAssets = stablecoinBalance();
        uint256 _neededLiquidity = minLiquidity();

        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    /**
     * @dev See {IGeniusVault-orderHash}.
     */
    function orderHash(
        Order memory order
    ) public pure override returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
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
                )
            );
    }

    /**
     * @dev See {IGeniusVault-calldataToSeed}.
     */
    function calldataToSeed(
        address target,
        bytes memory data
    ) public pure override returns (bytes32) {
        return keccak256(abi.encodePacked(target, keccak256(data)));
    }

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
        return address(uint160(uint256(_input)));
    }

    /**
     * @dev See {IGeniusVault-addressToBytes32}.
     */
    function addressToBytes32(
        address _input
    ) public pure override returns (bytes32) {
        return bytes32(uint256(uint160(_input)));
    }

    /**
     * @dev See {IGeniusVault-setProxyCall}.
     */
    function setProxyCall(address _proxyCall) external override onlyAdmin {
        _setProxyCall(_proxyCall);
    }

    /**
     * @dev See {IGeniusVault-setTargetChainMinFee}.
     */
    function setTargetChainMinFee(
        address _token,
        uint256 _targetChainId,
        uint256 _minFee
    ) external override onlyAdmin {
        _setTargetChainMinFee(_token, _targetChainId, _minFee);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                   INTERNAL FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Internal function to spend an allowance.
     *
     * @param _token The address of the token to spend.
     * @param _targetChainId The target chain ID.
     * @param _minFee The minimum fee required.
     */
    function _setTargetChainMinFee(
        address _token,
        uint256 _targetChainId,
        uint256 _minFee
    ) internal {
        if (_targetChainId == block.chainid)
            revert GeniusErrors.InvalidDestChainId(_targetChainId);

        targetChainMinFee[_token][_targetChainId] = _minFee;
        emit TargetChainMinFeeChanged(_token, _targetChainId, _minFee);
    }

    /**
     * @dev Internal function to set the address of the proxy call contract.
     *
     * @param _proxyCall The address of the proxy call contract.
     */
    function _setProxyCall(address _proxyCall) internal {
        if (_proxyCall == address(0)) revert GeniusErrors.NonAddress0();

        PROXYCALL = IGeniusProxyCall(_proxyCall);
        emit ProxyCallChanged(_proxyCall);
    }

    /**
     * @dev Internal to set the rebalance threshold value (on a 10_000 denominator)
     * 
     * @param _rebalanceThreshold The new rebalance threshold value.
     */
    function _setRebalanceThreshold(uint256 _rebalanceThreshold) internal {
        _validatePercentage(_rebalanceThreshold);

        rebalanceThreshold = _rebalanceThreshold;
        emit RebalanceThresholdChanged(_rebalanceThreshold);
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
     * @dev internal pure function to validate a percentage.
     * 
     * @param percentage The percentage to validate.
     */
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

    // Storage gap for future upgrades
    uint256[50] private __gap;
}
