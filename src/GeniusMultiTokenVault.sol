// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusMultiTokenVault} from "./interfaces/IGeniusMultiTokenVault.sol";
import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {GeniusVaultCore} from "./GeniusVault.sol";

/**
 * @title GeniusMultiTokenPool
 * @author @altloot, @samuel_vdu
 * 
 * @notice The GeniusMultiTokenPool contract helps to facilitate cross-chain
 *         liquidity management and swaps and can utilize multiple sources of liquidity.
 */
contract GeniusMultiTokenVault is IGeniusMultiTokenVault, GeniusVaultCore {
    using SafeERC20 for IERC20;

    // =============================================================
    //                          IMMUTABLES
    // =============================================================
    
    address public immutable NATIVE = address(0);

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public supportedTokensCount; // The total number of supported tokens

    mapping(address => bool) public isSupported; // Mapping of token addresses to TokenInfo structs
    mapping(uint256 => address) public supportedTokensIndex; // Mapping of supported token index to token address
    mapping(address router => uint256 isSupported) public supportedRouters; // Mapping of router address to support status
    mapping(address token => uint256) public unclaimedFees; // Mapping of token address to total unclaimed fees

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor() {
        _disableInitializers();
    }

    // =============================================================
    //                            INITIALIZE
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-initialize}.
     */
    function initialize(
        address stablecoin,
        address admin,
        address[] memory tokens,
        address[] memory bridges,
        address[] memory routers
    ) external initializer {
        GeniusVaultCore._initialize(stablecoin, admin);

        isSupported[address(STABLECOIN)] = true;

        // Add the initial supported tokens
        for (uint256 i; i < tokens.length;) {
            if (tokens[i] == address(STABLECOIN)) revert GeniusErrors.DuplicateToken(tokens[i]);
            _addInitialToken(tokens[i]);

            unchecked { i++; }
        }

        // Add the initial supported bridges
        for (uint256 i; i < bridges.length;) {
            if (supportedBridges[bridges[i]] == 1) revert GeniusErrors.InvalidTarget(bridges[i]);
            supportedBridges[bridges[i]] = 1;

            unchecked { i++; }
        }

        // Add the initial supported routers
        for (uint256 i; i < routers.length;) {
            if (supportedRouters[routers[i]] == 1) revert GeniusErrors.DuplicateRouter(routers[i]);
            _addInitialRouter(routers[i]);

            unchecked { i++; }
        }
    }

    function tokenBalance(address token) public view override returns (uint256) {
        if (token == NATIVE) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }

    function supportedTokensBalances() public view override returns (uint256[] memory) {
        uint256[] memory balances = new uint256[](supportedTokensCount);
        for (uint256 i; i < supportedTokensCount; i++) {
            address token = supportedTokensIndex[i];
            uint256 balance = tokenBalance(token);
            balances[i] = balance;
        }
        return balances;
    }

    // =============================================================
    //                        TOKEN MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-manageToken}.
     */
    function manageToken(address token, bool supported) external override onlyAdmin {
        if (token == address(STABLECOIN)) revert GeniusErrors.InvalidToken(token);
        if (supported) {
            if (isSupported[token]) revert GeniusErrors.DuplicateToken(token);
            
            isSupported[token] = true;
            supportedTokensIndex[supportedTokensCount] = token;
            supportedTokensCount++;
        } else {
            if (!isSupported[token]) revert GeniusErrors.InvalidToken(token);
            uint256 _tokenBalance = tokenBalance(token);
            if (_tokenBalance != 0) revert GeniusErrors.RemainingBalance(_tokenBalance);
            
            isSupported[token] = false;
            for (uint256 i; i < supportedTokensCount;) {
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
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-removeBridgeLiquidity}.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint32 dstChainId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) external payable override(GeniusVaultCore, IGeniusVault) onlyOrchestrator whenNotPaused {
        uint256 preTransferAssets = stablecoinBalance();
        uint256 neededLiquidity_ = minAssetBalance();
        // Checks
        _isAmountValid(amountIn, _availableAssets(preTransferAssets, neededLiquidity_));
        _checkNative(_sum(values));
        _checkBridgeTargets(targets);

        if (!_isBalanceWithinThreshold(preTransferAssets - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            neededLiquidity_,
            preTransferAssets - amountIn
        );

        // Store pre-execution balances for all supported tokens
        uint256[] memory preBalances = supportedTokensBalances();

        // Interactions
        _batchExecution(targets, data, values);

        // Post-interaction checks
        uint256 postTransferAssets = stablecoinBalance();
        if (preTransferAssets - postTransferAssets != amountIn) revert GeniusErrors.UnexpectedBalanceChange(
            address(STABLECOIN),
            preTransferAssets - amountIn,
            postTransferAssets
        );

        // Check balances of all supported tokens
        for (uint256 i; i < supportedTokensCount; i++) {
            address token = supportedTokensIndex[i];
            uint256 postBalance = tokenBalance(token);

            // Allow for increases in balance due to potential direct transfers
            if (postBalance < preBalances[i]) {
                revert GeniusErrors.UnexpectedBalanceDecrease(
                    token,
                    postBalance,
                    preBalances[i]
                );
            } else if (preBalances[i] != postBalance) {
                emit BalanceUpdate(
                    token,
                    preBalances[i],
                    postBalance
                );
            }
        }

        emit RemovedLiquidity(amountIn, dstChainId);
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
        uint32 fillDeadline,
        uint256 fee
    ) external payable override(GeniusVaultCore, IGeniusVault) onlyExecutor whenNotPaused {
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
            tokenIn: tokenIn,
            fee: fee
        });

        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.InvalidOrderStatus();

        uint256 preBalance;
        uint256 postBalance;

        if (tokenIn == address(STABLECOIN)) {
            preBalance = stablecoinBalance();
            _transferERC20From(tokenIn, msg.sender, address(this), order.amountIn);
            postBalance = stablecoinBalance();

            if (postBalance - preBalance != order.amountIn) revert GeniusErrors.UnexpectedBalanceChange(
                tokenIn,
                order.amountIn,
                postBalance - preBalance
            );
        } else if (isSupported[tokenIn]) {
            if (tokenIn == NATIVE) {
                if (msg.value != order.amountIn) revert GeniusErrors.InvalidAmount();
                preBalance = address(this).balance - msg.value;
                postBalance = address(this).balance;
            } else {
                preBalance = tokenBalance(tokenIn);
                _transferERC20From(tokenIn, msg.sender, address(this), order.amountIn);
                postBalance = tokenBalance(tokenIn);
            }
        } else {
            revert GeniusErrors.InvalidToken(tokenIn);
        }

        unclaimedFees[tokenIn] += order.fee;
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

    // =============================================================
    //                      REWARD LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-removeLiquiditySwap}.
     */
    function removeLiquiditySwap(
        Order memory order
    ) external override(IGeniusVault, GeniusVaultCore) onlyExecutor whenNotPaused {
        bytes32 orderHash_ = orderHash(order);
        if (orderStatus[orderHash_] != OrderStatus.Nonexistant) revert GeniusErrors.OrderAlreadyFilled(orderHash_);
        if (order.destChainId != _currentChainId()) revert GeniusErrors.InvalidDestChainId(order.destChainId);     
        if (order.fillDeadline < _currentTimeStamp()) revert GeniusErrors.DeadlinePassed(order.fillDeadline); 
        if (order.srcChainId == _currentChainId()) revert GeniusErrors.InvalidSourceChainId(order.srcChainId);

        // Gas saving
        uint256 _stablecoinBalance = stablecoinBalance();
        uint256 _neededLiquidity = minAssetBalance();
        
        _isAmountValid(order.amountIn, _availableAssets(_stablecoinBalance, _neededLiquidity));
        
        if (order.trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (!_isBalanceWithinThreshold(_stablecoinBalance - order.amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            _neededLiquidity,
            _stablecoinBalance - order.amountIn
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
    //                        FEE LIQUIDITY
    // =============================================================

    /**
     * @dev See {IGeniusVault-claimFees}.
     */
    function claimFees(uint256 amount, address token) external override(IGeniusVault, GeniusVaultCore) onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (!isSupported[token]) revert GeniusErrors.InvalidToken(token);
        if (unclaimedFees[token] < amount) revert GeniusErrors.InsufficientFees(
            amount,
            unclaimedFees[token],
            token
        );

        if (token == NATIVE) {
            (bool success, ) = msg.sender.call{value: amount}("");
            if (!success) revert GeniusErrors.TransferFailed(NATIVE, amount);
        } else {
            _transferERC20(token, msg.sender, amount);
        }

        emit FeesClaimed(token, amount);
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
    ) external override onlyOrchestrator whenNotPaused {
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (!isSupported[token]) revert GeniusErrors.InvalidToken(token);
        uint256 _tokenBalance = tokenBalance(token);
        if (_tokenBalance < amount) revert GeniusErrors.InsufficientBalance(token, amount, _tokenBalance);
        if (target == address(0)) revert GeniusErrors.InvalidTarget(target);
        if (supportedRouters[target] == 0) revert GeniusErrors.InvalidTarget(target);

        uint256 preSwapStableBalance = STABLECOIN.balanceOf(address(this));
        
        uint256[] memory preSwapBalances = supportedTokensBalances();

        // Interactions
        if (token == NATIVE) {
            _executeSwap(token, target, data, amount);
        } else {
            _approveERC20(token, target, amount);
            _executeSwap(token, target, data, amount);
        }
        // Post-swap checks and effects
        uint256 postSwapStableBalance = STABLECOIN.balanceOf(address(this));
        uint256 postSwapTokenBalance = tokenBalance(token);

        uint256 stableDelta = postSwapStableBalance - preSwapStableBalance;
        uint256 tokenDelta = _tokenBalance - postSwapTokenBalance;

        if (stableDelta == 0) revert GeniusErrors.InvalidDelta();
        if (tokenDelta > amount) revert GeniusErrors.UnexpectedBalanceChange(token, amount, tokenDelta);

        // Check for unexpected balance changes in other tokens
        for (uint256 i; i < supportedTokensCount; i++) {
            address currentToken = supportedTokensIndex[i];
            if (currentToken != token && currentToken != address(STABLECOIN)) {
                uint256 currentBalance = tokenBalance(currentToken);
                
                if (currentBalance != preSwapBalances[i]) {
                    emit UnexpectedBalanceChange(currentToken, preSwapBalances[i], currentBalance);
                    preSwapBalances[i] = currentBalance;
                }
            }
        }

        emit SwapExecuted(token, amount, stableDelta);
    }



    // =============================================================
    //                        ROUTER MANAGEMENT
    // =============================================================

    /**
     * @dev See {IGeniusMultiTokenPool-manageRouter}.
     */
    function manageRouter(address router, bool authorize) external override onlyAdmin {
        if (authorize) {
            if (supportedRouters[router] == 1) revert GeniusErrors.DuplicateRouter(router);
            supportedRouters[router] = 1;
        } else {
            if (supportedRouters[router] == 0) revert GeniusErrors.InvalidRouter(router);
            supportedRouters[router] = 0;
        }
    }


    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================


    /**
     * @dev See {IGeniusMultiTokenPool-isTokenSupported}.
     */
    function isTokenSupported(address token) public view override returns (bool) {
        return isSupported[token];
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Adds an initial token to the GeniusMultiTokenPool.
     * @param token The address of the token to be added.
     */
    function _addInitialToken(address token) internal {
        if (isSupported[token]) revert GeniusErrors.DuplicateToken(token);
        
        isSupported[token] = true;
        supportedTokensIndex[supportedTokensCount] = token;
        supportedTokensCount++;
    }

    function _addInitialRouter(address router) internal {
        if (supportedRouters[router] == 1) revert GeniusErrors.DuplicateRouter(router);
        supportedRouters[router] = 1;
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
     * @dev Internal function to approve an ERC20 token for a spender.
     * @param token The address of the ERC20 token.
     * @param spender The address of the spender.
     * @param amount The amount to be approved.
     */
    function _approveERC20(address token, address spender, uint256 amount) internal {
        IERC20(token).safeIncreaseAllowance(spender, amount);
    }
}