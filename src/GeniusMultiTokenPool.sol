// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {Executable} from "./access/Executable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

/**
 * @title GeniusMultiTokenPool
 * @author looter
 * 
 * @notice The GeniusMultiTokenPool contract helps to facilitate cross-chain
 *         liquidity management and swaps and can utilize multiple sources of liquidity.
 */
contract GeniusMultiTokenPool is Orchestrable, Executable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================
    
    IERC20 public immutable STABLECOIN;

    address public immutable NATIVE = address(0);
    address public  VAULT;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public initialized; // Flag to check if the contract has been initialized
    uint256 public isPaused; // Flag to check if the contract is paused

    uint256 public totalStables; // The total amount of stablecoin assets in the contract
    uint256 public minStableBalance; // The minimum amount of stablecoin assets needed to maintain liquidity
    uint256 public availStableBalance; // totalStables - (totalStakedAssets * (1 + stableRebalanceThreshold) (in percentage)
    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public stableRebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades
    uint256 public supportedTokensCount; // The total number of supported tokens

    mapping(uint256 => address) public supportedTokensIndex;
    mapping(address => TokenInfo) public tokenInfo;
    mapping(address bridge => uint256 isSupported) public isSupportedBridge;
    mapping(address token => uint256 balance) public tokenBalances;

    // =============================================================
    //                          EVENTS
    // =============================================================

    /**
     * @dev Emitted when a trader stakes their funds in the GeniusPool contract.
     * @param trader The address of the trader who is staking their funds.
     * @param amountDeposited The amount of funds being deposited by the trader.
     * @param newTotalDeposits The new total amount of funds deposited in the GeniusPool contract after the stake.
     */
    event Stake(
        address indexed trader,
        uint256 amountDeposited,
        uint256 newTotalDeposits
    );

    /**
     * @dev Emitted when a trader unstakes their funds from the GeniusPool contract.
     * @param trader The address of the trader who unstaked their funds.
     * @param amountWithdrawn The amount of funds that were withdrawn by the trader.
     * @param newTotalDeposits The new total amount of deposits in the GeniusPool contract after the withdrawal.
     */
    event Unstake(
        address indexed trader,
        uint256 amountWithdrawn,
        uint256 newTotalDeposits
    );

    /**
     * @dev Emitted when a swap is executed.
     * @param token The address of the token that was swapped.
     * @param amount The amount of tokens that were swapped.
     * @param stableDelta The amount of stablecoins that were swapped.
     */
    event SwapExecuted(
        address token,
        uint256 amount,
        uint256 stableDelta
    );

    /**
     * @dev Emitted when a swap deposit is made.
     * @param trader The address of the trader who made the deposit.
     * @param token The address of the token deposited.
     * @param amountDeposited The amount of tokens deposited.
     */
    event SwapDeposit(
        address indexed trader,
        address token,
        uint256 amountDeposited
    );

    /**
     * @dev Emitted when a swap withdrawal occurs.
     * @param trader The address of the trader who made the withdrawal.
     * @param amountWithdrawn The amount that was withdrawn.
     */
    event SwapWithdrawal(
        address indexed trader,
        uint256 amountWithdrawn
    );

    /**
     * @dev Emitted when funds are bridged to another chain.
     * @param amount The amount of funds being bridged.
     * @param chainId The ID of the chain where the funds are being bridged to.
     */
    event BridgeFunds(
        uint256 amount,
        uint16 chainId
    );

    /**
     * @dev Emitted when the contract receives funds from a bridge.
     * @param amount The amount of funds received.
     * @param chainId The chain ID that funds are received from.
     */
    event ReceiveBridgeFunds(
        uint256 amount,
        uint16 chainId
    );

    /**
     * @dev Emitted when the balance of a token is updated due to token
     *      swaps or liquidity additions.
     * @param token The address of the token.
     * @param oldBalance The previous balance of the token.
     * @param newBalance The new balance of the token.
     */
    event BalanceUpdate(
        address token,
        uint256 oldBalance,
        uint256 newBalance
    );

    /**
     * @dev Emitted when there is an excess balance of a token.
     * @param token The address of the token.
     * @param excess The amount of excess tokens.
     */
    event ExcessBalance(
        address token,
        uint256 excess
    );

    /**
     * @dev Emitted when there is an unexpected decrease in the balance of a token.
     * @param token The address of the token.
     * @param expectedBalance The new balance of the token.
     * @param newBalance The previous balance of the token.
     */
    event UnexpectedBalanceChange(
        address token,
        uint256 expectedBalance,
        uint256 newBalance
    );

    // =============================================================
    //                            STRUCTS
    // =============================================================

    struct TokenBalance {
        address token;
        uint256 balance;
    }

    struct TokenInfo {
        bool isSupported;
        uint256 balance;
    }

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
        isPaused = 1;
    }

    // =============================================================
    //                        TOKEN MANAGEMENT
    // =============================================================

    /**
    * @dev Manages (adds or removes) a token from the list of supported tokens.
    * @param token The address of the token to be managed.
    * @param isSupported True to add the token, false to remove it.
    */
    function manageToken(address token, bool isSupported) external onlyOwner {
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
     * @dev Initializes the GeniusMultiTokenPool contract.
     * @param vaultAddress The address of the GeniusVault contract.
     * @param tokens The array of token addresses to be supported by the contract.
     * @notice This function can only be called once by the contract owner.
     * @notice Once initialized, the `VAULT` address cannot be changed.
     */
    function initialize(
        address executor,
        address vaultAddress,
        address[] memory tokens,
        address[] memory bridgeTargets
    ) external onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();

        VAULT = vaultAddress;
        _initializeExecutor(payable(executor));

        for (uint256 i = 0; i < tokens.length;) {
            if (tokens[i] == address(STABLECOIN)) revert GeniusErrors.DuplicateToken(tokens[i]);
            _addInitialToken(tokens[i]);

            unchecked { i++; }
        }

        for (uint256 i = 0; i < bridgeTargets.length;) {
            if (isSupportedBridge[bridgeTargets[i]] == 1) revert GeniusErrors.InvalidTarget(bridgeTargets[i]);
            isSupportedBridge[bridgeTargets[i]] = 1;

            unchecked { i++; }
        }

        initialized = 1;
        isPaused = 0;
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev Adds liquidity to the bridge.
     * @param amount The amount of tokens to add as liquidity.
     * @param chainId The ID of the chain where the liquidity is being added.
     * @notice Emits a `ReceiveBridgeFunds` event with the amount and chain ID.
     */
    function addBridgeLiquidity(uint256 amount, uint16 chainId) public onlyOrchestrator {
        _isPoolReady();

        if (amount == 0) revert GeniusErrors.InvalidAmount();

        _updateStableBalance(amount, 1);
        _updateAvailableAssets();

        _transferERC20From(
            address(STABLECOIN),
            msg.sender,
            address(this),
            amount
        );

        emit ReceiveBridgeFunds(
            amount,
            chainId
        );
    }

    /**
     * @dev Removes liquidity from a bridge pool and swaps it to the destination chain.
     * @param amountIn The amount of tokens to remove from the bridge pool.
     * @param dstChainId The chain ID of the destination chain.
     * @param targets The array of target addresses to call.
     * @param values The array of values to send along with the function calls.
     * @param data The array of function call data.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint16 dstChainId,
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata data
    ) public onlyOrchestrator payable {
        // Checks
        _isPoolReady();
        _isAmountValid(amountIn);
        _checkNative(_sum(values));
        _checkBridge(targets);

        uint256 actualStableBalance = STABLECOIN.balanceOf(address(this));
        if (actualStableBalance < totalStables) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            totalStables,
            actualStableBalance
        );

        if (!_isBalanceWithinThreshold(actualStableBalance - amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            minStableBalance,
            actualStableBalance - amountIn
        );

        // Store pre-execution balances for all supported tokens
        TokenBalance[] memory preBalances = new TokenBalance[](supportedTokensCount);
        for (uint256 i = 0; i < supportedTokensCount; i++) {
            address token = supportedTokensIndex[i];
            uint256 balance = token == NATIVE ? address(this).balance : IERC20(token).balanceOf(address(this));
            preBalances[i] = TokenBalance(token, balance);
        }

        // Effects
        totalStables = actualStableBalance - amountIn;
        _updateAvailableAssets();

        // Interactions
        _batchExecution(targets, data, values);

        // Post-interaction checks
        uint256 postStableBalance = STABLECOIN.balanceOf(address(this));
        if (postStableBalance != totalStables) revert GeniusErrors.UnexpectedBalanceChange(
            address(STABLECOIN),
            postStableBalance,
            totalStables
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

        emit BridgeFunds(amountIn, dstChainId);
    }


    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @dev Adds liquidity to the GeniusMultiTokenPool contract by swapping tokens.
     * @param trader The address of the trader who is adding liquidity.
     * @param token The address of the token being swapped.
     * @param amount The amount of tokens being swapped.
     * @notice Emits a SwapDeposit event with the trader's address, the token address, and the amount of tokens swapped.
     */
    function addLiquiditySwap(
        address trader,
        address token,
        uint256 amount
    ) external payable onlyExecutor {
        _isPoolReady();

        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        uint256 preBalance;
        uint256 postBalance;

        if (token == address(STABLECOIN)) {
            preBalance = STABLECOIN.balanceOf(address(this));
            _transferERC20From(token, msg.sender, address(this), amount);
            postBalance = STABLECOIN.balanceOf(address(this));

            if (postBalance - preBalance != amount) revert GeniusErrors.UnexpectedBalanceChange(
                token,
                amount,
                postBalance - preBalance
            );

            totalStables = postBalance;
            _updateAvailableAssets();
        } else if (tokenInfo[token].isSupported) {
            if (token == NATIVE) {
                if (msg.value != amount) revert GeniusErrors.InvalidAmount();
                preBalance = address(this).balance - msg.value;
                postBalance = address(this).balance;
            } else {
                preBalance = IERC20(token).balanceOf(address(this));
                _transferERC20From(token, msg.sender, address(this), amount);
                postBalance = IERC20(token).balanceOf(address(this));
            }

            if (postBalance - preBalance != amount) revert GeniusErrors.TransferFailed(token, amount);

            tokenInfo[token].balance = postBalance;
        } else {
            revert GeniusErrors.InvalidToken(token);
        }

        // Check for and handle any pre-existing balance
        if (preBalance > tokenInfo[token].balance) {
            uint256 excess = preBalance - tokenInfo[token].balance;
            emit ExcessBalance(token, excess);
        }

        emit SwapDeposit(trader, token, amount);
    }

    /**
     * @dev Removes liquidity from the GeniusMultiTokenPool contract by swapping stablecoins for the specified amount.
     *      Only the orchestrator can call this function.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of stablecoins to be swapped and transferred to the caller.
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external onlyExecutor {
        _isPoolReady();
        _isAmountValid(amount);
        
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (!_isBalanceWithinThreshold(totalStables - amount)) revert GeniusErrors.ThresholdWouldExceed(
            minStableBalance,
            totalStables - amount
        );

        _updateStableBalance(amount, 0);
        _updateAvailableAssets();

        _transferERC20(address(STABLECOIN), msg.sender, amount);
        
        emit SwapWithdrawal(trader, amount);
    }

    // =============================================================
    //                     REWARD LIQUIDITY
    // =============================================================

    /**
     * @notice Removes reward liquidity from the GeniusMultiTokenPool contract.
     * @dev Only the orchestrator can call this function.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator {
        _isPoolReady();
        _isAmountValid(amount);

        if (!_isBalanceWithinThreshold(totalStables - amount)) revert GeniusErrors.ThresholdWouldExceed(
            minStableBalance,
            totalStables - amount
        );

        _updateStableBalance(amount, 0);
        _updateAvailableAssets();

        _transferERC20(address(STABLECOIN), msg.sender, amount);
    }

    // =============================================================
    //                     SWAP TO STABLES
    // =============================================================

    /**
     * @dev Swaps a specified amount of tokens or native currency to stablecoins.
     * Can only be called by the orchestrator.
     * @param token The address of the token to be swapped. Pass 0x0 for native currency.
     * @param amount The amount of tokens (or native) to be swapped.
     * @param target The address of the target contract to execute the swap.
     * @param data The calldata to be used when executing the swap on the target contract.
     */
    function swapToStables(
        address token,
        uint256 amount,
        address target,
        bytes calldata data
    ) external onlyOrchestrator {
        // Checks
        _isPoolReady();
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
        uint256 actualTokenDelta = preSwapTokenBalance - postSwapTokenBalance;

        if (stableDelta == 0 || actualTokenDelta < amount) revert GeniusErrors.InvalidDelta();

        // Update balances
        totalStables += stableDelta;
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

        // Final effects
        _updateAvailableAssets();

        emit SwapExecuted(token, amount, stableDelta);
    }

    // =============================================================
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev Stakes liquidity into the GeniusMultiTokenPool.
     * @param trader The address of the trader staking the liquidity.
     * @param amount The amount of liquidity to be staked.
     */
    function stakeLiquidity(address trader, uint256 amount) external {
        _isPoolReady();

        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        _updateStableBalance(amount, 1);
        _updateStakedBalance(amount, 1);
        _updateAvailableAssets();

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
     * @dev Removes staked liquidity from the GeniusMultiTokenPool contract.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of liquidity to be removed.
     */
    function removeStakedLiquidity(address trader, uint256 amount) external {
        _isPoolReady();

        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();

        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalStables) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStakedAssets
        );

        _updateStableBalance(amount, 0);
        _updateStakedBalance(amount, 0);
        _updateAvailableAssets();
        
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
     * @dev Sets the rebalance threshold for the GeniusMultiTokenPool contract.
     * Only the contract owner can call this function.
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external onlyOwner {
        _isPoolReady();

        stableRebalanceThreshold = threshold;

        _updateStableBalance(0, 0);
        _updateAvailableAssets();
    }

    // =============================================================
    //                        BRIDGE MANAGEMENT
    // =============================================================

    /**
    * @dev Authorizes or unauthorizes a bridge target.
    * @param bridge The address of the bridge target to be managed.
    * @param authorize True to authorize the bridge, false to unauthorize it.
    * @notice This function can only be called by the contract owner.
    * @notice When authorizing, the bridge must not already be authorized.
    * @notice When unauthorizing, the bridge must be currently authorized.
    */
    function manageBridgeTarget(address bridge, bool authorize) external onlyOwner {
        if (authorize) {
            if (isSupportedBridge[bridge] == 1) revert GeniusErrors.InvalidTarget(bridge);
            isSupportedBridge[bridge] = 1;
        } else {
            if (isSupportedBridge[bridge] == 0) revert GeniusErrors.InvalidTarget(bridge);
            isSupportedBridge[bridge] = 0;
        }
    }

    // =============================================================
    //                           EMERGENCY
    // =============================================================

    /**
     * @dev Pauses the contract and locks all functionality in case of an emergency.
     * This function sets the `isPaused` state to 1, preventing all contract operations.
     */
    function emergencyLock() external onlyOwner {
        isPaused = 1;
    }

    /**
     * @dev Allows the owner to emergency unlock the contract.
     * This function sets the `isPaused` state to 0, allowing normal contract operations to resume.
     */
    function emergencyUnlock() external onlyOwner {
        isPaused = 0;
    }

    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================

    /**
     * @dev Checks if a token is supported by the GeniusMultiTokenPool contract.
     * @param token The address of the token to check.
     * @return boolean indicating whether the token is supported or not.
     */
    function isTokenSupported(address token) public view returns (bool) {
        return tokenInfo[token].isSupported;
    }

    /**
     * @dev Returns the balances of the stablecoins in the GeniusMultiTokenPool contract.
     * @return currentStables The current total balance of stablecoins in the pool.
     * @return availStables The available balance of stablecoins in the pool.
     * @return stakedStables The total balance of staked stablecoins in the pool.
     */
    function stablecoinBalances() public view returns (
        uint256 currentStables,
        uint256 availStables,
        uint256 stakedStables
    ) {
        return (
            totalStables,
            availStableBalance,
            totalStakedAssets
        );
    }

    /**
     * @dev Retrieves the balances of supported tokens.
     * @return array of TokenBalance structs containing the token address and balance.
     */
    function supportedTokenBalances() public view returns (TokenBalance[] memory) {
        TokenBalance[] memory _supportedTokenBalances = new TokenBalance[](supportedTokensCount);

        for (uint256 i = 0; i < supportedTokensCount;) {
            address token = supportedTokensIndex[i];
            _supportedTokenBalances[i] = TokenBalance(token, tokenInfo[token].balance);
            
            unchecked { ++i; }
        }

        return _supportedTokenBalances;
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
            if (isSupportedBridge[bridgeTargets[i]] == 0) revert GeniusErrors.InvalidTarget(bridgeTargets[i]);
            unchecked { i++; }
        }

    }

    /**
     * @dev Checks if the pool is ready for use.
     */
    function _isPoolReady() internal view {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (isPaused == 1) revert GeniusErrors.Paused();
    }

    /**
     * @dev Checks if the given amount is valid for a transaction.
     * @param amount The amount to be checked.
     */
    function _isAmountValid(uint256 amount) internal view {
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        if (amount > totalStables) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStables
        );

        if (amount > availStableBalance) revert GeniusErrors.InsufficientLiquidity(
            availStableBalance,
            amount
        );
    }

    /**
     * @dev Checks if the given balance is within the threshold limit.
     * @param balance The balance to be checked.
     * @return boolean indicating whether the balance is within the threshold limit.
     */
    function _isBalanceWithinThreshold(uint256 balance) internal view returns (bool) {
        uint256 _lowerBound = (totalStakedAssets * stableRebalanceThreshold) / 100;

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

    /**
     * @dev Updates the balance of the contract by retrieving the total balance of the STABLECOIN token.
     * This function is internal and can only be called from within the contract.
     * @param amount The amount to update the balance by.
     * @param add 0 to subtract, 1 to add.
     */
    function _updateStableBalance(uint256 amount, uint256 add) internal {
        if (add == 1) {
            totalStables = STABLECOIN.balanceOf(address(this)) + amount;
        } else {
            totalStables = STABLECOIN.balanceOf(address(this)) - amount;
        }
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
     * @dev Updates the available assets by calculating the available stable balance.
     * The available stable balance is calculated by subtracting the reduction amount from the total staked stables.
     * If the total stables is greater than the needed liquidity, the available stable balance is set to the difference.
     * Otherwise, the available stable balance is set to 0.
     */
    function _updateAvailableAssets() internal {
        uint256 _reduction = 
        totalStakedAssets > 0 ?
        (totalStakedAssets * stableRebalanceThreshold) / 100 : 0;

        uint256 _neededLiquidity =
        totalStakedAssets > _reduction ?
        totalStakedAssets - _reduction : 0;
        
        if (totalStables > _neededLiquidity) {
            availStableBalance = totalStables - _neededLiquidity;
        } else {
            availStableBalance = 0;
        }

        minStableBalance = _neededLiquidity;
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
}