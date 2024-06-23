// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

/**
 * @title GeniusPool
 * @author altloot
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps,
 *         and other Genius related activities.
 */

contract GeniusMultiTokenPool is Orchestrable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================
    
    IERC20 public immutable STABLECOIN;
    IStargateRouter public immutable STARGATE_ROUTER;
    address public immutable NATIVE = address(0);

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public initialized;
    uint256 public totalStables; // The total amount of stablecoin assets in the contract
    uint256 public availStableBalance; // totalStables - (totalStakedStables * (1 + stableRebalanceThreshold) (in percentage)
    uint256 public totalStakedStables; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public stableRebalanceThreshold = 75; // The maximum % of deviation from totalStakedStables before blocking trades

    address public geniusVault;
    address[] public supportedTokens;

    mapping(address token => uint256 isSupported) public isSupportedToken;
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
     * @dev An event emitted when a swap deposit is made.
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
     * @dev An event emitted when a swap withdrawal occurs.
     * @param trader The address of the trader who made the withdrawal.
     * @param amountWithdrawn The amount that was withdrawn.
     */
    event SwapWithdrawal(
        address indexed trader,
        uint256 amountWithdrawn
    );

    /**
     * @dev Event triggered when funds are bridged to another chain.
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

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        address stablecoin,
        address bridgeRouter,
        address owner,
        address[] memory supportedTokenAddresses
    ) Ownable(owner) {
        require(stablecoin != address(0), "GeniusVault: STABLECOIN address is the zero address");
        require(owner != address(0), "GeniusVault: Owner address is the zero address");

        STABLECOIN = IERC20(stablecoin);
        STARGATE_ROUTER = IStargateRouter(bridgeRouter);

        supportedTokens = supportedTokenAddresses;
        initialized = 0;
    }

    /**
     * @dev Initializes the GeniusMultiTokenPool contract.
     * @param vaultAddress The address of the GeniusVault contract.
     * @notice This function can only be called once by the contract owner.
     * @notice Once initialized, the `geniusVault` address cannot be changed.
     */
    function initialize(address vaultAddress) external onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();
        geniusVault = vaultAddress;

        initialized = 1;
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev Adds liquidity to the bridge.
     * @param amount The amount of tokens to add as liquidity.
     * @param chainId The ID of the chain where the liquidity is being added.
     * @notice This function can only be called by the orchestrator.
     * @notice The contract must be initialized before calling this function.
     * @notice The amount must be greater than zero.
     * @notice The tokens are transferred from the caller to the contract.
     * @notice The balance and available assets are updated after adding liquidity.
     * @notice Emits a `ReceiveBridgeFunds` event with the amount and chain ID.
     */
    function addBridgeLiquidity(uint256 amount, uint16 chainId) public onlyOrchestrator {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        IERC20(STABLECOIN).transferFrom(tx.origin, address(this), amount);
        _updateStableBalance();
        _updateAvailableAssets();

        emit ReceiveBridgeFunds(
            amount,
            chainId
        );
    }

    /**
     * @dev Removes liquidity from the bridge.
     * @param amountIn The amount of tokens to remove.
     * @param minAmountOut The minimum amount of tokens to receive.
     * @param dstChainId The destination chain ID.
     * @param srcPoolId The source pool ID.
     * @param dstPoolId The destination pool ID.
     */
    function removeBridgeLiquidity(
        uint256 amountIn,
        uint256 minAmountOut,
        uint16 dstChainId,
        uint256 srcPoolId,
        uint256 dstPoolId
    ) public onlyOrchestrator payable {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (amountIn == 0) revert GeniusErrors.InvalidAmount();
        if (amountIn > STABLECOIN.balanceOf(address(this))) revert GeniusErrors.InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - amountIn)) revert GeniusErrors.NeedsRebalance(totalStables, availStableBalance);

        (,
        IStargateRouter.lzTxObj memory _lzTxParams
        ) = layerZeroFee(dstChainId, tx.origin);

        STABLECOIN.approve(address(STARGATE_ROUTER), amountIn);

        STARGATE_ROUTER.swap{value:msg.value}(
            dstChainId,
            srcPoolId,
            dstPoolId,
            payable(tx.origin),
            amountIn,
            minAmountOut,
            _lzTxParams,
            abi.encodePacked(tx.origin),
            bytes("") 
        );

        _updateStableBalance();
        _updateAvailableAssets();

        emit BridgeFunds(
            amountIn,
            dstChainId
        );
    }

    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @dev Adds liquidity to the GeniusMultiTokenPool contract by swapping tokens.
     * @param trader The address of the trader who is adding liquidity.
     * @param token The address of the token being swapped.
     * @param amount The amount of tokens being swapped.
     * Emits a SwapDeposit event with the trader's address, the token address, and the amount of tokens swapped.
     */
    function addLiquiditySwap(
        address trader,
        address token,
        uint256 amount
    ) external {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        if (token == address(STABLECOIN)) {
            IERC20(token).transferFrom(msg.sender, address(this), amount);

            _updateStableBalance();
            _updateAvailableAssets();
        } else {
            if (isSupportedToken[token] == 0) revert GeniusErrors.InvalidToken(token);
            IERC20(token).transferFrom(msg.sender, address(this), amount);

            _updateTokenBalance(token);
        }

        emit SwapDeposit(
            trader,
            token,
            amount
        );
    }

    /**
     * @dev Removes liquidity from the GeniusMultiTokenPool contract by swapping stablecoins for the specified amount.
     * Only the orchestrator can call this function.
     * 
     * Requirements:
     * - The contract must be initialized.
     * - The amount must be greater than zero and not exceed the total amount of stables.
     * - The trader address must be valid.
     * - The contract must have sufficient balance of the stablecoin.
     * - The balance of stables after removing liquidity must be within the threshold.
     * 
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of stablecoins to be swapped and transferred to the caller.
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external onlyOrchestrator {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalStables) revert GeniusErrors.InvalidAmount();
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amount > IERC20(STABLECOIN).balanceOf(address(this))) revert GeniusErrors.InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - amount)) revert GeniusErrors.NeedsRebalance(totalStables, availStableBalance);

        IERC20(STABLECOIN).transfer(msg.sender, amount);
        _updateStableBalance();
        _updateAvailableAssets();
        
        emit SwapWithdrawal(trader, amount);
    }

    // =============================================================
    //                     REWARD LIQUIDITY
    // =============================================================

    /**
     * @notice Removes reward liquidity from the GeniusMultiTokenPool contract.
     * @dev Only the orchestrator can call this function.
     * @param amount The amount of reward liquidity to remove.
     * @dev Throws a NotInitialized exception if the contract is not initialized.
     * @dev Throws an InvalidAmount exception if the amount is zero, exceeds the total stables, or exceeds the balance of the STABLECOIN token in the contract.
     * @dev Throws an InvalidAmount exception if the remaining balance after removing the amount is not within the threshold.
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator {
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalStables) revert GeniusErrors.InvalidAmount();
        if (amount > IERC20(STABLECOIN).balanceOf(address(this))) revert GeniusErrors.InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - amount)) revert GeniusErrors.InvalidAmount();

        IERC20(STABLECOIN).transfer(msg.sender, amount);
        _updateStableBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //                     SWAP TO STABLES
    // =============================================================

    /**
     * @dev Swaps a specified amount of tokens or native currency to stablecoins.
     * Can only be called by the orchestrator.
     * @param token The address of the token to be swapped. Pass 0x0 for native currency.
     * @param tokenAmount The amount of tokens to be swapped. Pass 0 if swapping native currency.
     * @param target The address of the target contract to execute the swap.
     * @param data The calldata to be used when executing the swap on the target contract.
     * @param nativeAmount The amount of native currency to be swapped. Pass 0 if swapping tokens.
     */
    function swapToStables(
        address token,
        uint256 tokenAmount,
        address target,
        bytes calldata data,
        uint256 nativeAmount
    ) external onlyOrchestrator {
        if (initialized == 0) revert GeniusErrors.NotInitialized();

        if (tokenAmount > 0) {
            if (tokenAmount > IERC20(token).balanceOf(address(this))) revert GeniusErrors.InvalidAmount();
        } else if (nativeAmount > 0) {
            if (nativeAmount > address(this).balance) revert GeniusErrors.InvalidAmount();
        }

        uint256 _initialStablecoinBalance = totalStables;

        _executeSwap(token, target, data, nativeAmount);
        _updateStableBalance();
        _updateAvailableAssets();
        _updateTokenBalance(token);

        uint256 _finalStablecoinBalance = totalStables;

        require(_finalStablecoinBalance > _initialStablecoinBalance, "Swap must increase stablecoin balance");
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
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (msg.sender != geniusVault) revert GeniusErrors.IsNotVault();
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), amount);

        _updateStableBalance();
        _updateStakedBalance(amount, true);
        _updateAvailableAssets();

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
        if (initialized == 0) revert GeniusErrors.NotInitialized();
        if (msg.sender != geniusVault) revert GeniusErrors.IsNotVault();
        if (trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (amount > totalStables) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedStables) revert GeniusErrors.InvalidAmount();
        if (!_isStakingBalanceWithinThreshold(totalStables - amount, amount)) revert GeniusErrors.NeedsRebalance(totalStables, availStableBalance);

        IERC20(STABLECOIN).transfer(msg.sender, amount);

        _updateStableBalance();
        _updateStakedBalance(amount, false);
        _updateAvailableAssets();

        emit Unstake(
            trader,
            amount,
            totalStakedStables
        );
    }

    // =============================================================
    //                     REBALANCE THRESHOLD
    // =============================================================

    /**
     * @dev Sets the rebalance threshold for the GeniusMultiTokenPool contract.
     * Only the contract owner can call this function.
     * 
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external onlyOwner {
        stableRebalanceThreshold = threshold;

        _updateStableBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //             ADDING AND REMOVING SUPPORTED TOKENS
    // =============================================================

    /**
     * @dev Adds a new token to the list of supported tokens.
     * @param token The address of the token to be added.
     * @notice This function can only be called by the contract owner.
     * @notice The token must not already be supported.
     */
    function addToken(address token) external {
        require(isSupportedToken[token] == 1, "Token is already supported");
        supportedTokens.push(token);
        isSupportedToken[token] = 1;
    }

    /**
     * @dev Removes a token from the list of supported tokens.
     * @param token The address of the token to be removed.
     * @notice This function can only be called by the contract owner.
     * @notice The token must be currently supported by the contract.
     * @notice If the token is successfully removed, it will no longer be supported by the contract.
     */
    function removeToken(address token) external {
        require(isSupportedToken[token] == 1, "Token is not supported");
        isSupportedToken[token] = 1;

        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == token) {
                supportedTokens[i] = supportedTokens[supportedTokens.length - 1];
                supportedTokens.pop();
                break;
            }
        }
    }

    // =============================================================
    //                        READ FUNCTIONS
    // =============================================================

    /**
     * @dev Calculates the layer zero fee and returns the fee amount along with the layer zero transaction parameters.
     * @param chainId The chain ID.
     * @param trader The address of the trader.
     * @return fee The calculated fee amount.
     * @return lzTxParams The layer zero transaction parameters.
     */
    function layerZeroFee(
        uint16 chainId,
        address trader
    ) public view returns (uint256 fee, IStargateRouter.lzTxObj memory lzTxParams) {

        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(trader)
        });

        bytes memory _transferAndCallPayload = abi.encode(_lzTxParams); 

        (, uint256 _fee) = STARGATE_ROUTER.quoteLayerZeroFee(
            chainId,
            1,
            abi.encodePacked(trader),
            _transferAndCallPayload,
            _lzTxParams
        );

        return (_fee, _lzTxParams);
    }

    /**
     * @dev Returns the balances of the stablecoins in the GeniusMultiTokenPool contract.
     * @return currentStableBalance The total balance of stablecoins in the pool.
     * @return currentAvailableStableBalance The available balance of stablecoins in the pool.
     * @return currentStakedStableBalance The total balance of staked stablecoins in the pool.
     */
    function stablecoinBalances() public view returns (
        uint256 currentStableBalance,
        uint256 currentAvailableStableBalance,
        uint256 currentStakedStableBalance
    ) {
        return (
            totalStables,
            availStableBalance,
            totalStakedStables
        );
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Checks if the given balance is within the threshold limit.
     * @param balance The balance to be checked.
     * @return boolean indicating whether the balance is within the threshold limit.
     */
    function _isBalanceWithinThreshold(uint256 balance) public view returns (bool) {
        uint256 _lowerBound = (totalStakedStables * stableRebalanceThreshold) / 100;

        return balance >= _lowerBound;
    }

    /**
     * @dev Checks if the balance is within the specified threshold after unstaking a certain amount.
     * @param balance The current balance of the token.
     * @param amountToUnstake The amount to be unstaked.
     * @return A boolean indicating whether the balance is within the threshold.
     */
    function _isStakingBalanceWithinThreshold(uint256 balance, uint256 amountToUnstake) internal view returns (bool) {
        uint256 _lowerBound = ((totalStakedStables - amountToUnstake) * stableRebalanceThreshold) / 100;

        return balance >= _lowerBound;
    }

    /**
     * @dev Updates the balance of the contract by retrieving the total balance of the STABLECOIN token.
     * This function is internal and can only be called from within the contract.
     */
    function _updateStableBalance() internal {
        totalStables = STABLECOIN.balanceOf(address(this));
    }

    /**
     * @dev Updates the staked balance of the contract.
     * @param amount The amount to update the staked balance by.
     * @param add A boolean indicating whether to add or subtract the amount from the staked balance.
     */
    function _updateStakedBalance(uint256 amount, bool add) internal {
        if (add) {
            totalStakedStables += amount;
        } else {
            totalStakedStables -= amount;
        }
    }

    /**
     * @dev Updates the available assets by calculating the available stable balance.
     * The available stable balance is calculated by subtracting the reduction amount from the total staked stables.
     * If the total stables is greater than the needed liquidity, the available stable balance is set to the difference.
     * Otherwise, the available stable balance is set to 0.
     */
    function _updateAvailableAssets() internal {
        uint256 _reduction = totalStakedStables > 0 ? (totalStakedStables * stableRebalanceThreshold) / 100 : 0;

        uint256 _neededLiquidity = totalStakedStables > _reduction ? totalStakedStables - _reduction : 0;
        
        if (totalStables > _neededLiquidity) {
            availStableBalance = totalStables - _neededLiquidity;
        } else {
            availStableBalance = 0;
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
            (bool approvalSuccess) = IERC20(token).approve(target, value);
            require(approvalSuccess, "Approval failed");
        }

        (bool swapSuccess, ) = target.call{value: value}(data);
        require(swapSuccess, "Swap failed");
    }
}