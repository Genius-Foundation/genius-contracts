// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusMultiTokenPool} from "./interfaces/IGeniusMultiTokenPool.sol";

/**
 * @title GeniusMultiTokenPool
 * @author looter
 * 
 * @notice The GeniusMultiTokenPool contract helps to facilitate cross-chain
 *         liquidity management and swaps and can utilize multiple sources of liquidity.
 */
contract GeniusMultiTokenPool is IGeniusMultiTokenPool, Orchestrable, Pausable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================
    
    IERC20 public immutable STABLECOIN;

    address public immutable NATIVE = address(0);
    address public override VAULT;
    address public override EXECUTOR;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public initialized; // Flag to check if the contract has been initialized

    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades
    uint256 public supportedTokensCount; // The total number of supported tokens

    mapping(address => TokenInfo) public tokenInfo; // Mapping of token addresses to TokenInfo structs
    mapping(uint256 => address) public supportedTokensIndex; // Mapping of supported token index to token address
    mapping(address token => uint256 balance) public tokenBalances; // Mapping of token address to balance
    mapping(address bridge => uint256 isSupported) public supportedBridges; // Mapping of bridge address to support status
    mapping(address router => uint256 isSupported) public supportedRouters; // Mapping of router address to support status

    uint32 public totalOrders;
    mapping(bytes32 => OrderStatus) public orderStatus;

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
        tokenInfo[stablecoin] = TokenInfo({isSupported: true, balance: STABLECOIN.balanceOf(address(this))});

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

    modifier onlyExecutor() {
        if (msg.sender != EXECUTOR) revert GeniusErrors.IsNotExecutor();
        _;
    }

    modifier onlyVault() {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        _;
    }

    // =============================================================
    //                        TOKEN MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-manageToken}.
     */
    function manageToken(address token, bool isSupported) external override onlyOwner {
        if (token == address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);
        if (isSupported) {
            if (tokenInfo[token].isSupported) revert GeniusErrors.DuplicateToken(token);
            
            tokenInfo[token] = TokenInfo({isSupported: true, balance: 0});
            supportedTokensIndex[supportedTokensCount] = token;
            supportedTokensCount++;
        } else {
            if (!tokenInfo[token].isSupported) revert GeniusErrors.InvalidToken(token);
            if (tokenInfo[token].balance != 0) revert GeniusErrors.RemainingBalance(tokenInfo[token].balance);
            
            delete tokenInfo[token];
            for (uint256 i = 0; i < supportedTokensCount;) {
                if (supportedTokensIndex[i] == token) {
                    supportedTokensIndex[i] = supportedTokensIndex[supportedTokensCount - 1];
                    delete supportedTokensIndex[supportedTokensCount - 1];
                    supportedTokensCount--;
                    break;
                }
                unchecked { ++i; }
            }
        }
    }

    // =============================================================
    //                            INITIALIZE
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-initialize}.
     */
    function initialize(
        address executor,
        address vaultAddress,
        address[] memory tokens,
        address[] memory bridges,
        address[] memory routers
    ) external override onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();

        VAULT = vaultAddress;
        EXECUTOR = executor;

        // Add the initial supported tokens
        for (uint256 i = 0; i < tokens.length;) {
            if (tokens[i] == address(STABLECOIN)) revert GeniusErrors.DuplicateToken(tokens[i]);
            _addInitialToken(tokens[i]);

            unchecked { i++; }
        }

        // Add the initial supported bridges
        for (uint256 i = 0; i < bridges.length;) {
            if (supportedBridges[bridges[i]] == 1) revert GeniusErrors.InvalidTarget(bridges[i]);
            supportedBridges[bridges[i]] = 1;

            unchecked { i++; }
        }

        // Add the initial supported routers
        for (uint256 i = 0; i < routers.length;) {
            if (supportedRouters[routers[i]] == 1) revert GeniusErrors.DuplicateRouter(routers[i]);
            _addInitialRouter(routers[i]);

            unchecked { i++; }
        }

        initialized = 1;
        _unpause();
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint16 dstChainId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) public payable override onlyOrchestrator whenReady {
        uint256 preTransferAssets = totalAssets();
        uint256 neededLiquidity_ = minAssetBalance();
        // Checks
        _isAmountValid(amountIn, _availableAssets(preTransferAssets, neededLiquidity_));
        _checkNative(_sum(values));
        _checkBridge(targets);

        if (!_isBalanceWithinThreshold(preTransferAssets - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            neededLiquidity_,
            preTransferAssets - amountIn
        );

        // Store pre-execution balances for all supported tokens
        TokenBalance[] memory preBalances = new TokenBalance[](supportedTokensCount);
        for (uint256 i = 0; i < supportedTokensCount; i++) {
            address token = supportedTokensIndex[i];
            uint256 balance = token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));
            preBalances[i] = TokenBalance(token, balance);
        }


        // Interactions
        _batchExecution(targets, data, values);

        // Post-interaction checks
        uint256 postTransferAssets = totalAssets();
        if (preTransferAssets - postTransferAssets != amountIn) revert GeniusErrors.UnexpectedBalanceChange(
            address(STABLECOIN),
            preTransferAssets - amountIn,
            postTransferAssets
        );

        // Check balances of all supported tokens
        for (uint256 i = 0; i < supportedTokensCount; i++) {
            address token = supportedTokensIndex[i];
            uint256 postBalance = token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));

            // Allow for increases in balance due to potential direct transfers
            if (postBalance < preBalances[i].balance) {
                revert GeniusErrors.UnexpectedBalanceDecrease(
                    token,
                    postBalance,
                    preBalances[i].balance
                );
            }

            // Update internal balances to match actual balances
            if (tokenInfo[token].balance != postBalance) {
                emit BalanceUpdate(
                    token,
                    tokenInfo[token].balance,
                    postBalance
                );

                tokenInfo[token].balance = postBalance;
            }
        }

        emit RemovedLiquidity(amountIn, dstChainId);
    }

    /**
     * @dev See {IGeniusMultiTokenPool-totalAssets}.
     */
    function totalAssets() public view override returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev See {IGeniusMultiTokenPool-minAssetBalance}.
     */
    function minAssetBalance() public view override returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        /**
          * Calculate the liquidity needed as the staked assets minus the reduction
          * Ensure not to underflow; if reduction is somehow greater, set neededLiquidity to 0
         */
        return totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
    }

    /**
     * @dev See {IGeniusMultiTokenPool-availableAssets}.
     */
    function availableAssets() public view override returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();
        
        return _availableAssets(_totalAssets, _neededLiquidity);
    }

    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-addLiquiditySwap}.
     */
    function addLiquiditySwap(
        address trader,
        address tokenIn,
        uint256 amountIn,
        uint16 destChainId,
        uint32 fillDeadline
    ) external payable override onlyExecutor whenReady {
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
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

        uint256 preBalance;
        uint256 postBalance;

        if (tokenIn == address(STABLECOIN)) {
            preBalance = totalAssets();
            _transferERC20From(tokenIn, msg.sender, address(this), amountIn);
            postBalance = totalAssets();

            if (postBalance - preBalance != amountIn) revert GeniusErrors.UnexpectedBalanceChange(
                tokenIn,
                amountIn,
                postBalance - preBalance
            );
        } else if (tokenInfo[tokenIn].isSupported) {
            if (tokenIn == NATIVE) {
                if (msg.value != amountIn) revert GeniusErrors.InvalidAmount();
                preBalance = address(this).balance - msg.value;
                postBalance = address(this).balance;
            } else {
                preBalance = IERC20(tokenIn).balanceOf(address(this));
                _transferERC20From(tokenIn, msg.sender, address(this), amountIn);
                postBalance = IERC20(tokenIn).balanceOf(address(this));
            }

            if (postBalance - preBalance != amountIn) revert GeniusErrors.TransferFailed(order.tokenIn, order.amountIn);

            tokenInfo[tokenIn].balance = postBalance;
        } else {
            revert GeniusErrors.InvalidToken(tokenIn);
        }

        // Check for and handle any pre-existing balance
        if (preBalance > tokenInfo[tokenIn].balance) {
            uint256 excess = preBalance - tokenInfo[tokenIn].balance;
            emit ExcessBalance(tokenIn, excess);
        }

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
     * @dev See {IGeniusMultiTokenPool-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order
    ) external override onlyExecutor whenReady {
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
     * @dev See {IGeniusMultiTokenPool-setOrderAsFilled}.
     */
    function setOrderAsFilled(
        Order memory order
    ) external override onlyOrchestrator whenReady {
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
     * @dev See {IGeniusMultiTokenPool-revertOrder}.
     */
    function revertOrder(
        Order memory order, 
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external override onlyOrchestrator whenReady {
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
    //                     REWARD LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-addRewardLiquidity}.
     */
    function removeRewardLiquidity(uint256 amount) external override onlyOrchestrator whenReady {
        // Gas saving
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();

        _isAmountValid(amount, _availableAssets(_totalAssets, _neededLiquidity));

        if (!_isBalanceWithinThreshold(_totalAssets - amount)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _totalAssets - amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, amount);
    }

    // =============================================================
    //                     SWAP TO STABLES
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-swapToStables}.
     */
    function swapToStables(
        address token,
        uint256 amount,
        address target,
        bytes calldata data
    ) external override onlyOrchestrator whenReady {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (!tokenInfo[token].isSupported) revert GeniusErrors.InvalidToken(token);
        if (tokenInfo[token].balance < amount) revert GeniusErrors.InsufficientBalance(token, amount, tokenInfo[token].balance);

        uint256 preSwapStableBalance = STABLECOIN.balanceOf(address(this));
        uint256 preSwapTokenBalance = token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));

        // Effects
        tokenInfo[token].balance -= amount;  // Decrease the balance of the swapped token
        
        // Interactions
        _executeSwap(token, target, data, amount);

        // Post-swap checks and effects
        uint256 postSwapStableBalance = STABLECOIN.balanceOf(address(this));
        uint256 postSwapTokenBalance = token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));

        uint256 stableDelta = postSwapStableBalance - preSwapStableBalance;
        uint256 tokenDelta = preSwapTokenBalance - postSwapTokenBalance;

        if (stableDelta == 0) revert GeniusErrors.InvalidDelta();
        if (tokenDelta > amount) revert GeniusErrors.UnexpectedBalanceChange(token, amount, tokenDelta);

        // Update balances
        tokenInfo[token].balance = postSwapTokenBalance;  // Adjust for any discrepancies

        // Check for unexpected balance changes in other tokens
        for (uint256 i = 0; i < supportedTokensCount; i++) {
            address currentToken = supportedTokensIndex[i];
            if (currentToken != token && currentToken != address(STABLECOIN)) {
                uint256 currentBalance = currentToken == NATIVE ? 
                    address(this).balance : 
                    IERC20(currentToken).balanceOf(address(this));
                
                if (currentBalance != tokenInfo[currentToken].balance) {
                    emit UnexpectedBalanceChange(currentToken, tokenInfo[currentToken].balance, currentBalance);
                    tokenInfo[currentToken].balance = currentBalance;
                }
            }
        }

        emit SwapExecuted(token, amount, stableDelta);
    }

    // =============================================================
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-stakeLiquidity}.
     */
    function stakeLiquidity(address trader, uint256 amount) external override whenReady {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        _updateStakedBalance(amount, 1);

        _transferERC20From(
            address(STABLECOIN),
            msg.sender,
            address(this),
            amount
        );

        emit Stake(
            trader,
            amount,
            amount
        );
    }

    /**
     * @dev See {IGeniusMultiTokenPool-unstakeLiquidity}.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external override whenReady {
        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();

        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalAssets()) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStakedAssets
        );

        _updateStakedBalance(amount, 0);
        
        _transferERC20(address(STABLECOIN), msg.sender, amount);

        emit Unstake(
            trader,
            amount,
            totalStakedAssets
        );
    }

    // =============================================================
    //                     REBALANCE THRESHOLD
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-setRebalanceThreshold}.
     */
    function setRebalanceThreshold(uint256 threshold) external override onlyOwner {
        rebalanceThreshold = threshold;
    }

    // =============================================================
    //                        BRIDGE MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-manageBridge}.
     */
    function manageBridge(address bridge, bool authorize) external override onlyOwner {
        if (authorize) {
            if (supportedBridges[bridge] == 1) revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 1;
        } else {
            if (supportedBridges[bridge] == 0) revert GeniusErrors.InvalidTarget(bridge);
            supportedBridges[bridge] = 0;
        }
    }

    // =============================================================
    //                        ROUTER MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-manageRouter}.
     */
    function manageRouter(address router, bool authorize) external override onlyOwner {
        if (authorize) {
            if (supportedRouters[router] == 1) revert GeniusErrors.DuplicateRouter(router);
            supportedRouters[router] = 1;
        } else {
            if (supportedRouters[router] == 0) revert GeniusErrors.InvalidRouter(router);
            supportedRouters[router] = 0;
        }
    }

    // =============================================================
    //                           EMERGENCY
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-emergencyLock}.
     */
    function emergencyLock() external override onlyOwner {
        _pause();
    }

    /**
     * @dev See {IGeniusMultiTokenPool-emergencyUnlock}.
     */
    function emergencyUnlock() external override onlyOwner {
        _unpause();
    }

    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-isTokenSupported}.
     */
    function isTokenSupported(address token) public view override returns (bool) {
        return tokenInfo[token].isSupported;
    }

    /**
     * @dev See {IGeniusMultiTokenPool-isBridgeSupported}.
     */
    function stablecoinBalances() public view override returns (
        uint256 currentStables,
        uint256 availStables,
        uint256 stakedStables
    ) {
        return (
            totalAssets(),
            availableAssets(),
            totalStakedAssets
        );
    }

    /**
     * @dev See {IGeniusMultiTokenPool-supportedTokenBalances}.
     */
    function supportedTokenBalances() public view override returns (TokenBalance[] memory) {
        TokenBalance[] memory _supportedTokenBalances = new TokenBalance[](supportedTokensCount);

        for (uint256 i = 0; i < supportedTokensCount;) {
            address token = supportedTokensIndex[i];
            _supportedTokenBalances[i] = TokenBalance(token, tokenInfo[token].balance);
            
            unchecked { ++i; }
        }

        return _supportedTokenBalances;
    }

    function orderHash(Order memory order) public pure returns (bytes32) {
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
    function _checkBridge(address[] memory bridgeTargets) internal view {
        
        for (uint256 i = 0; i < bridgeTargets.length;) {
            if (supportedBridges[bridgeTargets[i]] == 0) revert GeniusErrors.InvalidTarget(bridgeTargets[i]);
            unchecked { i++; }
        }

    }

    function _availableAssets(uint256 _totalAssets, uint256 _neededLiquidity) internal pure returns (uint256) {
        if (_totalAssets < _neededLiquidity) {
            return 0;
        }

        return _totalAssets - _neededLiquidity;
    }

    /**
     * @dev Checks if the given amount is valid for a transaction.
     * @param amount_ The amount to be checked.
     * @param availableAssets_ The available balance of STABLECOIN in the pool.
     */
    function _isAmountValid(uint256 amount_, uint256 availableAssets_) internal pure {
        if (amount_ == 0) revert GeniusErrors.InvalidAmount();

        if (amount_ > availableAssets_) revert GeniusErrors.InsufficientLiquidity(
            availableAssets_,
            amount_
        );
    }

    /**
     * @dev Checks if the given balance is within the threshold limit.
     * @param balance The balance to be checked.
     * @return boolean indicating whether the balance is within the threshold limit.
     */
    function _isBalanceWithinThreshold(uint256 balance) internal view returns (bool) {
        uint256 _lowerBound = (totalStakedAssets * rebalanceThreshold) / 100;

        return balance >= _lowerBound;
    }

    /**
     * @dev Checks if the balance of a specific token is sufficient.
     * @param token The address of the token to check the balance for.
     * @param amount The amount to compare against the total balance.
     * @return isSufficient boolean indicating whether the balance is sufficient or not.
     * @return balanceInfo TokenBalance struct The balance of the token.
     */
    function _isBalanceSufficient(address token, uint256 amount) internal view returns (
        bool isSufficient,
        TokenBalance memory balanceInfo
    ) {
        uint256 tokenBalance = 0;

        if (token == NATIVE) {
            tokenBalance = address(this).balance;
        } else {
            tokenBalance = IERC20(token).balanceOf(address(this));
        }

        return (amount <= tokenBalance, TokenBalance(token, tokenBalance));
    }

    /**
     * @dev Adds an initial token to the GeniusMultiTokenPool.
     * @param token The address of the token to be added.
     */
    function _addInitialToken(address token) internal {
        if (tokenInfo[token].isSupported) revert GeniusErrors.DuplicateToken(token);
        
        tokenInfo[token] = TokenInfo({isSupported: true, balance: 0});
        supportedTokensIndex[supportedTokensCount] = token;
        supportedTokensCount++;
    }

    function _addInitialRouter(address router) internal {
        if (supportedRouters[router] == 1) revert GeniusErrors.DuplicateRouter(router);
        supportedRouters[router] = 1;
    }

    /**
     * @dev Updates the staked balance of the contract.
     * @param amount The amount to update the staked balance by.
     * @param add 0 to subtract, 1 to add.
     */
    function _updateStakedBalance(uint256 amount, uint256 add) internal {
        if (add == 1) {
            totalStakedAssets += amount;
        } else {
            totalStakedAssets -= amount;
        }
    }

    /**
     * @dev Updates the balance of a token held by the contract.
     * @param token The address of the token to update the balance for.
     * @notice If the token is the native currency (ETH), the balance is updated with the contract's ETH balance.
     * Otherwise, the balance is updated with the contract's token balance using the IERC20 interface.
     */
    function _updateTokenBalance(address token) internal {
        if (token == NATIVE) {
            tokenBalances[token] = address(this).balance;
        } else {
            tokenBalances[token] = IERC20(token).balanceOf(address(this));
        }
    }

    /**
     * @dev Calculates the sum of an array of uint256 values.
     * @param amounts An array of uint256 values.
     * @return total sum of the array elements.
     */
    function _sum(uint256[] calldata amounts) internal pure returns (uint256 total) {
        for (uint i = 0; i < amounts.length;) {
            total += amounts[i];

            unchecked { i++; }
        }
    }

    /**
     * @dev Internal function to approve an ERC20 token for a spender.
     * @param token The address of the ERC20 token.
     * @param spender The address of the spender.
     * @param amount The amount to be approved.
     */
    function _approveERC20(address token, address spender, uint256 amount) internal {
        (bool approvalSuccess) = IERC20(token).approve(spender, amount);

        if (!approvalSuccess) {
            revert GeniusErrors.ApprovalFailure(token, amount);
        }
    }

    /**
     * @dev Function to transfer ERC20 tokens.
     * @param token The address of the ERC20 token.
     * @param to The address to transfer the tokens to.
     * @param amount The amount of tokens to transfer.
     */
    function _transferERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).transfer(to, amount);
    }

    /**
     * @dev Internal function to transfer ERC20 tokens from one address to another.
     * @param token The address of the ERC20 token contract.
     * @param from The address from which the tokens will be transferred.
     * @param to The address to which the tokens will be transferred.
     * @param amount The amount of tokens to be transferred.
     */
    function _transferERC20From(
        address token,
        address from,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).transferFrom(from, to, amount);
    }

    /**
     * @dev Executes a batch of external function calls.
     * @param target The array of target addresses to call.
     * @param data The array of function call data.
     * @param value The array of values to send along with the function calls.
     */
    function _executeSwap(
        address token,
        address target,
        bytes calldata data,
        uint256 value
    ) internal {

        if (token != NATIVE) {
            _approveERC20(token, target, value);
        }

        uint256 _nativeValue = token == NATIVE ? value : 0;
        (bool success, ) = target.call{value: _nativeValue}(data);

        if (!success) revert GeniusErrors.ExternalCallFailed(target, 0);
    }

    /**
     * @dev Executes a batch of external function calls.
     * @param targets The array of target addresses to call.
     * @param data The array of function call data.
     * @param values The array of values to send along with the function calls.
     */
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