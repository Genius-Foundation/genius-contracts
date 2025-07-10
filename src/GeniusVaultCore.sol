// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";
import {IFeeCollector} from "./interfaces/IFeeCollector.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

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
    ERC4626Upgradeable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    using MessageHashUtils for bytes32;
    using ECDSA for bytes32;
    using Math for uint256;

    uint256 public constant BASE_PERCENTAGE = 10_000;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    // Immutable state variables (not actually immutable due to upgradeability)
    IERC20 public STABLECOIN;
    IGeniusProxyCall public PROXYCALL;

    // Mutable state variables
    AggregatorV3Interface public stablecoinPriceFeed;
    uint256 public totalStakedAssets;
    uint256 public rebalanceThreshold;

    // Price bounds (8 decimals like Chainlink)
    uint256 public stablePriceLowerBound;
    uint256 public stablePriceUpperBound;

    mapping(address => mapping(uint256 => uint256))
        public deprecated_targetChainMinFee;
    mapping(bytes32 => OrderStatus) public orderStatus;

    uint256 public maxOrderAmount;
    uint256 public priceFeedHeartbeat;

    mapping(uint256 => uint256) public chainStablecoinDecimals;

    // Fee collector contract
    IFeeCollector public feeCollector;

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
        uint256 _rebalanceThreshold,
        address _priceFeed,
        uint256 _priceFeedHeartbeat,
        uint256 _stablePriceLowerBound,
        uint256 _stablePriceUpperBound,
        uint256 _maxOrderAmount
    ) internal onlyInitializing {
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();

        __ERC4626_init(IERC20(_stablecoin));
        __ERC20_init("Genius USD", "gUSD");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        STABLECOIN = IERC20(_stablecoin);
        PROXYCALL = IGeniusProxyCall(_multicall);
        _setRebalanceThreshold(_rebalanceThreshold);
        _setPriceFeed(_priceFeed);
        _setStablePriceBounds(_stablePriceLowerBound, _stablePriceUpperBound);
        _setMaxOrderAmount(_maxOrderAmount);
        _setPriceFeedHeartbeat(_priceFeedHeartbeat);

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

        STABLECOIN.safeTransfer(address(PROXYCALL), amountIn);

        PROXYCALL.approveTokenExecute{value: msg.value}(
            address(STABLECOIN),
            target,
            data
        );

        emit RebalancedLiquidity(amountIn, dstChainId);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ERC4626 OVERRIDES                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Override deposit to update totalStakedAssets and emit custom event
     */
    function deposit(uint256 assets, address receiver) public virtual override(ERC4626Upgradeable, IERC4626) whenNotPaused returns (uint256) {
        uint256 shares = super.deposit(assets, receiver);
        totalStakedAssets += assets;
        return shares;
    }

    /**
     * @dev Override withdraw to update totalStakedAssets and emit custom event
     */
    function withdraw(uint256 assets, address receiver, address owner) public virtual override(ERC4626Upgradeable, IERC4626) whenNotPaused nonReentrant returns (uint256) {
        uint256 shares = super.withdraw(assets, receiver, owner);
        totalStakedAssets -= assets;
        return shares;
    }

    /**
     * @dev Override mint to update totalStakedAssets and emit custom event
     */
    function mint(uint256 shares, address receiver) public virtual override(ERC4626Upgradeable, IERC4626) whenNotPaused returns (uint256) {
        uint256 assets = super.mint(shares, receiver);
        totalStakedAssets += assets;
        return assets;
    }

    /**
     * @dev Override redeem to update totalStakedAssets and emit custom event
     */
    function redeem(uint256 shares, address receiver, address owner) public virtual override(ERC4626Upgradeable, IERC4626) whenNotPaused nonReentrant returns (uint256) {
        uint256 assets = super.redeem(shares, receiver, owner);
        totalStakedAssets -= assets;
        return assets;
    }

    /**
     * @dev Override totalAssets to return the stablecoin balance
     */
    function totalAssets() public view virtual override(ERC4626Upgradeable, IERC4626) returns (uint256) {
        return totalStakedAssets;
    }

    /**
     * @dev Override asset to return the stablecoin address
     */
    function asset() public view virtual override(ERC4626Upgradeable, IERC4626) returns (address) {
        return address(STABLECOIN);
    }

    /**
     * @dev Override internal conversion functions to use real share count
     */
    function _convertToShares(uint256 assets, Math.Rounding rounding) internal view virtual override returns (uint256) {
        return assets.mulDiv(super.totalSupply() + 10 ** _decimalsOffset(), totalAssets() + 1, rounding);
    }

    function _convertToAssets(uint256 shares, Math.Rounding rounding) internal view virtual override returns (uint256) {
        return shares.mulDiv(totalAssets() + 1, super.totalSupply() + 10 ** _decimalsOffset(), rounding);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    ERC20 OVERRIDES                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Override balanceOf to return asset value instead of shares
     */
    function balanceOf(address account) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return convertToAssets(super.balanceOf(account));
    }

    /**
     * @dev Override totalSupply to return total assets instead of total shares
     */
    function totalSupply() public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return totalAssets();
    }

    /**
     * @dev Override transfer to work with asset amounts
     */
    function transfer(address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.transfer(to, shares);
    }

    /**
     * @dev Override transferFrom to work with asset amounts
     */
    function transferFrom(address from, address to, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.transferFrom(from, to, shares);
    }

    /**
     * @dev Override approve to work with asset amounts
     */
    function approve(address spender, uint256 amount) public virtual override(ERC20Upgradeable, IERC20) returns (bool) {
        uint256 shares = convertToShares(amount);
        return super.approve(spender, shares);
    }

    /**
     * @dev Override allowance to return asset value instead of shares
     */
    function allowance(address owner, address spender) public view virtual override(ERC20Upgradeable, IERC20) returns (uint256) {
        return convertToAssets(super.allowance(owner, spender));
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                    REWARDS FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Submit rewards to the vault without minting shares
     * @param amount The amount of rewards to submit
     */
    function submitRewards(uint256 amount) external override whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        
        // Transfer assets from sender to contract
        STABLECOIN.safeTransferFrom(msg.sender, address(this), amount);
        
        // Increase totalStakedAssets by the reward amount
        totalStakedAssets += amount;
        
        emit RewardsSubmitted(msg.sender, amount);
    }

    function revertOrder(
        Order memory order,
        bytes memory orchestratorSig
    ) external override nonReentrant whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Created)
            revert GeniusErrors.InvalidOrderStatus();
        if (order.srcChainId != _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        _isAmountValid(order.amountIn - order.fee, availableAssets());

        bytes32 orderDigest = _revertOrderDigest(orderHash_);

        _verifyOrchestratorSignature(orderDigest, orchestratorSig);

        orderStatus[orderHash_] = OrderStatus.Reverted;

        STABLECOIN.safeTransfer(
            bytes32ToAddress(order.trader),
            order.amountIn - order.fee
        );

        emit OrderReverted(
            order.srcChainId,
            order.trader,
            order.receiver,
            order.seed,
            orderHash_
        );
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
    ) external override onlyOrchestrator nonReentrant {
        _fillOrder(order, swapTarget, swapData, callTarget, callData);
    }

    /**
     * @dev See {IGeniusVault-fillOrders}.
     */
    function fillOrderBatch(
        Order[] memory orders,
        address[] memory swapsTargets,
        bytes[] memory swapsData,
        address[] memory callsTargets,
        bytes[] memory callsData
    ) external override onlyOrchestrator nonReentrant {
        uint256 ordersLength = orders.length;
        if (
            swapsTargets.length != ordersLength ||
            swapsData.length != ordersLength ||
            callsTargets.length != ordersLength ||
            callsData.length != ordersLength
        ) revert GeniusErrors.ArrayLengthsMismatch();

        for (uint256 i = 0; i < ordersLength; i++) {
            _fillOrder(
                orders[i],
                swapsTargets[i],
                swapsData[i],
                callsTargets[i],
                callsData[i]
            );
        }
    }

    /**
     * Fill an order on the target chain
     *
     * @param order - Order to fill
     * @param swapTarget - Swap target (address(0) if no swap)
     * @param swapData - Swap data (0x if no swap)
     * @param callTarget - Call target (address(0) if no call)
     * @param callData  - Call data (0x if no call)
     */
    function _fillOrder(
        Order memory order,
        address swapTarget,
        bytes memory swapData,
        address callTarget,
        bytes memory callData
    ) internal whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant)
            revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId())
            revert GeniusErrors.InvalidDestChainId(order.destChainId);
        if (order.srcChainId == _currentChainId())
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);
        if (order.trader == bytes32(0) || order.receiver == bytes32(0))
            revert GeniusErrors.InvalidTrader();

        uint256 sourceChainDecimals = chainStablecoinDecimals[order.srcChainId];
        if (sourceChainDecimals == 0)
            revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        uint256 formattedStablecoinAmountOut = _convertDecimals(
            order.amountIn - order.fee,
            uint8(sourceChainDecimals),
            decimals()
        );

        _isAmountValid(formattedStablecoinAmountOut, availableAssets());

        bool isSwap = swapTarget != address(0);
        bool isCall = callTarget != address(0);

        if (isCall) {
            bytes32 reconstructedSeed = calldataToSeed(callTarget, callData);
            if (bytes16(reconstructedSeed) != bytes16(order.seed))
                revert GeniusErrors.InvalidSeed();
        }

        orderStatus[orderHash_] = OrderStatus.Filled;
        address receiver = bytes32ToAddress(order.receiver);
        address effectiveTokenOut = address(STABLECOIN);
        uint256 effectiveAmountOut = formattedStablecoinAmountOut;
        bool success = true;

        if (!isCall && !isSwap) {
            STABLECOIN.safeTransfer(receiver, formattedStablecoinAmountOut);
        } else {
            IERC20 tokenOut = IERC20(bytes32ToAddress(order.tokenOut));
            STABLECOIN.safeTransfer(
                address(PROXYCALL),
                formattedStablecoinAmountOut
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
            order.srcChainId,
            order.trader,
            order.receiver,
            order.seed,
            orderHash_,
            effectiveTokenOut,
            effectiveAmountOut,
            formattedStablecoinAmountOut,
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
        if (uint96(uint256(_input) >> 160) != 0)
            revert GeniusErrors.InvalidBytes32Address();
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
     * @notice Set the fee collector contract
     * @param _feeCollector Address of the fee collector contract
     */
    function setFeeCollector(address _feeCollector) external onlyAdmin {
        _setFeeCollector(_feeCollector);
    }

    /**
     * @dev See {IGeniusVault-setPriceFeed}.
     */
    function setPriceFeed(address _priceFeed) external onlyAdmin {
        _setPriceFeed(_priceFeed);
    }

    /**
     * @dev See {IGeniusVault-setChainStablecoinDecimals}.
     */
    function setChainStablecoinDecimals(
        uint256 _chainId,
        uint256 _decimals
    ) external override onlyAdmin {
        _setChainStablecoinDecimals(_chainId, _decimals);
    }

    /**
     * @dev See {IGeniusVault-setStablePriceBounds}.
     */
    function setStablePriceBounds(
        uint256 _lowerBound,
        uint256 _upperBound
    ) external override onlyAdmin {
        _setStablePriceBounds(_lowerBound, _upperBound);
    }

    /**
     * @dev See {IGeniusVault-setMaxOrderAmount}.
     */
    function setMaxOrderAmount(
        uint256 _maxOrderAmount
    ) external override onlyAdmin {
        _setMaxOrderAmount(_maxOrderAmount);
    }

    /**
     * @dev See {IGeniusVault-setPriceFeedHeartbeat}.
     */
    function setPriceFeedHeartbeat(
        uint256 _priceFeedHeartbeat
    ) external override onlyAdmin {
        _setPriceFeedHeartbeat(_priceFeedHeartbeat);
    }


    // ╔═══════════════════════════════════════════════════════════╗
    // ║                   INTERNAL FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    function _setMaxOrderAmount(uint256 _maxOrderAmount) internal {
        maxOrderAmount = _maxOrderAmount;
        emit MaxOrderAmountChanged(_maxOrderAmount);
    }

    function _setPriceFeedHeartbeat(uint256 _priceFeedHeartbeat) internal {
        priceFeedHeartbeat = _priceFeedHeartbeat;
        emit PriceFeedHeartbeatChanged(_priceFeedHeartbeat);
    }

    function _revertOrderDigest(
        bytes32 _orderHash
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked("PREFIX_CANCEL_ORDER_HASH", _orderHash));
    }

    function _verifyOrchestratorSignature(
        bytes32 messageHash,
        bytes memory signature
    ) internal view {
        address recoveredSigner = messageHash.recover(signature);
        if (!hasRole(ORCHESTRATOR_ROLE, recoveredSigner)) {
            revert GeniusErrors.InvalidSignature();
        }
    }

    /**
     * @dev Internal function to set stablecoin price bounds for chainlink price feed checks.
     *
     * @param _lowerBound The lower bound for the stablecoin price.
     * @param _upperBound The upper bound for the stablecoin price.
     */
    function _setStablePriceBounds(
        uint256 _lowerBound,
        uint256 _upperBound
    ) internal {
        stablePriceLowerBound = _lowerBound;
        stablePriceUpperBound = _upperBound;

        emit StablePriceBoundsChanged(_lowerBound, _upperBound);
    }

    /**
     * @notice Checks if the stablecoin price is within acceptable bounds
     * @dev Reverts if price is stale or out of bounds
     * @return bool True if price is valid
     */
    function _verifyStablecoinPrice() internal view returns (bool) {
        try stablecoinPriceFeed.latestRoundData() returns (
            uint80 roundId,
            int256 price,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) {
            if (startedAt == 0) revert GeniusErrors.InvalidRound();
            if (answeredInRound < roundId)
                revert GeniusErrors.StalePrice(updatedAt);

            if (block.timestamp - updatedAt > priceFeedHeartbeat)
                revert GeniusErrors.StalePrice(updatedAt);

            if (price <= 0) revert GeniusErrors.InvalidPrice();

            uint256 priceUint = uint256(price);
            if (
                priceUint < stablePriceLowerBound ||
                priceUint > stablePriceUpperBound
            ) {
                revert GeniusErrors.PriceOutOfBounds(priceUint);
            }

            return true;
        } catch {
            revert GeniusErrors.PriceFeedError();
        }
    }

    /**
     * @dev Internal function to set the number of decimals for a stablecoin on a given chain.
     *
     * @param _chainId The chain ID.
     * @param _decimals The number of decimals for the stablecoin.
     */
    function _setChainStablecoinDecimals(
        uint256 _chainId,
        uint256 _decimals
    ) internal {
        chainStablecoinDecimals[_chainId] = _decimals;
        emit ChainStablecoinDecimalsChanged(_chainId, _decimals);
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
     * @dev Internal function to set the address of the fee collector contract.
     *
     * @param _feeCollector The address of the fee collector contract.
     */
    function _setFeeCollector(address _feeCollector) internal {
        if (_feeCollector == address(0)) revert GeniusErrors.NonAddress0();

        feeCollector = IFeeCollector(_feeCollector);
        emit FeeCollectorChanged(_feeCollector);
    }

    /**
     * @dev Internal function to set the address of the price feed contract.m
     *
     * @param _priceFeed The address of the price feed contract.
     */
    function _setPriceFeed(address _priceFeed) internal {
        if (_priceFeed == address(0)) revert GeniusErrors.NonAddress0();

        stablecoinPriceFeed = AggregatorV3Interface(_priceFeed);
        emit PriceFeedUpdated(_priceFeed);
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
     * @dev internal pure function to validate a percentage.
     *
     * @param percentage The percentage to validate.
     */
    function _validatePercentage(uint256 percentage) internal pure {
        if (percentage > BASE_PERCENTAGE)
            revert GeniusErrors.InvalidPercentage();
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
     * @dev Converts amount between tokens with different decimals
     * @param amount The amount to convert
     * @param fromDecimals The decimals of the token to convert from
     * @param toDecimals The decimals of the token to convert to
     * @return The converted amount
     */
    function _convertDecimals(
        uint256 amount,
        uint8 fromDecimals,
        uint8 toDecimals
    ) internal pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        }

        uint256 result;
        if (fromDecimals > toDecimals) {
            result = amount / (10 ** (fromDecimals - toDecimals));
        } else {
            result = amount * (10 ** (toDecimals - fromDecimals));
        }

        if (amount != 0 && result == 0) revert GeniusErrors.InvalidAmount();

        return result;
    }

    /**
     * @dev Authorizes contract upgrades.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyAdmin {}

    // Storage gap for future upgrades
    uint256[46] private __gap;
}
