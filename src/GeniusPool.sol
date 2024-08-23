// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {Executable} from "./access/Executable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {GeniusExecutor} from "./GeniusExecutor.sol";

/**
 * @title GeniusPool
 * @author looter
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps,
 *         and other Genius related activities.
 */

contract GeniusPool is Orchestrable, Executable, Pausable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    IERC20 public immutable STABLECOIN;

    address public VAULT;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public initialized; // Flag to check if the contract has been initialized

    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public rebalanceThreshold = 75; // The maximum % of deviation from totalStakedAssets before blocking trades

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
     * @dev Emitted when a swap deposit is made.
     * @param trader The address of the trader who made the deposit.
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
     * @dev Initializes the GeniusVault contract.
     * @param vaultAddress The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address vaultAddress, address executor) external onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();
        VAULT = vaultAddress;
        _initializeExecutor(payable(executor));

        initialized = 1;
        _unpause();
    }

    function totalAssets() public view returns (uint256) {
        return STABLECOIN.balanceOf(address(this));
    }

    function minAssetBalance() public view returns (uint256) {
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;
        /**
          * Calculate the liquidity needed as the staked assets minus the reduction
          * Ensure not to underflow; if reduction is somehow greater, set neededLiquidity to 0
         */
        return totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
    }

    function availableAssets() public view returns (uint256) {
        uint256 _totalAssets = totalAssets();
        uint256 _neededLiquidity = minAssetBalance();
        
        return _availableAssets(_totalAssets, _neededLiquidity);
    }


    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

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
        address[] memory targets,
        uint256[] calldata values,
        bytes[] memory data
    ) public payable onlyOrchestrator whenReady {
        // Gas saving
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

        if (_stableDelta != amountIn) revert GeniusErrors.InvalidAmount();

        emit BridgeFunds(
            amountIn,
            dstChainId
        );
    }

    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @notice Deposits tokens into the vault
     * @param trader The address of the trader that tokens are being deposited for
     * @param amount The amount of tokens to deposit
     * @notice Emits a SwapDeposit event with the trader's address, the token address, and the amount of tokens swapped.
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
     * @dev Removes liquidity from the GeniusPool contract by swapping stablecoins for the specified amount.
     *      Only the orchestrator can call this function.
     * @param trader The address of the trader to use for 
     * @param amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(
        address trader,
        uint256 amount
    ) external onlyExecutor whenReady {
        // Gas saving
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

    // =============================================================
    //                     REWARD LIQUIDITY
    // =============================================================

    /**
     * @dev Removes reward liquidity from the GeniusPool contract.
     * @param amount The amount of reward liquidity to remove.
     */
    function removeRewardLiquidity(uint256 amount) external onlyOrchestrator whenReady {
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
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev Allows a user to stake liquidity tokens.
     * @param trader The address of the trader who is staking the liquidity tokens.
     * @param amount The amount of liquidity tokens to stake.
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
     * @dev Removes staked liquidity from the GeniusPool contract.
     * @param trader The address of the trader who wants to remove liquidity.
     * @param amount The amount of liquidity to be removed.
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

    // =============================================================
    //                     REBALANCE THRESHOLD
    // =============================================================

    /**
     * @dev Sets the rebalance threshold for the GeniusPool contract.
     * @param threshold The new rebalance threshold to be set.
     */
    function setRebalanceThreshold(uint256 threshold) external onlyOwner {
        rebalanceThreshold = threshold;
    }

    // =============================================================
    //                           EMERGENCY
    // =============================================================

    /**
     * @dev Pauses the contract and locks all functionality in case of an emergency.
     * This function sets the `Paused` state to true, preventing all contract operations.
     */
    function emergencyLock() external onlyOwner {
        _pause();
    }

    /**
     * @dev Allows the owner to emergency unlock the contract.
     * This function sets the `Paused` state to true, allowing normal contract operations to resume.
     */
    function emergencyUnlock() external onlyOwner {
        _unpause();
    }

    // =============================================================
    //                     READ FUNCTIONS
    // =============================================================

    /**
     * @dev Returns the current state of the assets in the GeniusPool contract.
     * @return totalAssets The total number of assets in the pool.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the pool.
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

    /**
     * @dev Checks if the native currency sent with the transaction is equal to the specified amount.
     * @param amount The expected amount of native currency.
     */
    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
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
     * @return A boolean value indicating whether the balance is within the threshold limit.
     */
    function _isBalanceWithinThreshold(uint256 balance) internal view returns (bool) {
        uint256 lowerBound = (totalStakedAssets * rebalanceThreshold) / 100;

        return balance >= lowerBound;
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