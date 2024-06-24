// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

/**
 * @title GeniusPool
 * @author looter
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps,
 *         and other Genius related activities.
 */

contract GeniusPool is Orchestrable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    IERC20 public immutable STABLECOIN;
    IStargateRouter public immutable STARGATE_ROUTER;

    address public VAULT;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public initialized; // Flag to check if the contract has been initialized
    uint256 public isPaused; // Flag to check if the contract is paused

    uint256 public totalAssets; // The total amount of stablecoin assets in the contract
    uint256 public minAssetBalance; // The minimum amount of assets that must be in the contract
    uint256 public availableAssets; // totalAssets - (totalStakedAssets * (1 + rebalanceThreshold) (in percentage)
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
     * @dev An event emitted when a swap deposit is made.
     * @param trader The address of the trader who made the deposit.
     * @param amountDeposited The amount of tokens deposited.
     */
    event SwapDeposit(
        address indexed trader,
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
        address _stablecoin,
        address _bridgeRouter,
        address _owner
    ) Ownable(_owner) {
        require(_stablecoin != address(0), "GeniusVault: STABLECOIN address is the zero address");
        require(_owner != address(0), "GeniusVault: Owner address is the zero address");

        STABLECOIN = IERC20(_stablecoin);
        STARGATE_ROUTER = IStargateRouter(_bridgeRouter);

        initialized = 0;
        isPaused = 1;
    }

    /**
     * @dev Initializes the GeniusVault contract.
     * @param _geniusVault The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address _geniusVault) external onlyOwner {
        if (initialized == 1) revert GeniusErrors.Initialized();
        VAULT = _geniusVault;

        initialized = 1;
        isPaused = 0;
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev Adds liquidity to the bridge pool.
     * @param _amount The amount of stablecoin to add as liquidity.
     * @param _chainId The chain ID of the bridge.
     * @notice Emits a `ReceiveBridgeFunds` event with the amount and chain ID.
     */
    function addBridgeLiquidity(uint256 _amount, uint16 _chainId) public onlyOrchestrator {
        _isPoolReady();

        if (_amount == 0) revert GeniusErrors.InvalidAmount();

        _transferERC20From(address(STABLECOIN), tx.origin, address(this), _amount);

        _updateBalance();
        _updateAvailableAssets();

        emit ReceiveBridgeFunds(
            _amount,
            _chainId
        );
    }

    /**
     * @dev Removes liquidity from a bridge pool and swaps it to the destination chain.
     * @param _amountIn The amount of tokens to remove from the bridge pool.
     * @param _minAmountOut The minimum amount of tokens expected to receive after the swap.
     * @param _dstChainId The chain ID of the destination chain.
     * @param _srcPoolId The ID of the source pool on the bridge.
     * @param _dstPoolId The ID of the destination pool on the bridge.
     */
    function removeBridgeLiquidity(
        uint256 _amountIn,
        uint256 _minAmountOut,
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId
    ) public onlyOrchestrator payable {
        _isPoolReady();
        _isAmountValid(_amountIn);

        if (!_isBalanceWithinThreshold(totalAssets - _amountIn)) revert GeniusErrors.ThresholdWouldExceed(
            minAssetBalance,
            totalAssets - _amountIn
        );

        (,
        IStargateRouter.lzTxObj memory lzTxParams
        ) = layerZeroFee(_dstChainId, tx.origin);

        STABLECOIN.approve(address(STARGATE_ROUTER), _amountIn);

        STARGATE_ROUTER.swap{value:msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            payable(tx.origin),
            _amountIn,
            _minAmountOut,
            lzTxParams,
            abi.encodePacked(tx.origin),
            bytes("") 
        );

        _updateBalance();
        _updateAvailableAssets();

        emit BridgeFunds(
            _amountIn,
            _dstChainId
        );
    }

    // =============================================================
    //                      SWAP LIQUIDITY
    // =============================================================

    /**
     * @notice Deposits tokens into the vault
     * @param _trader The address of the trader that tokens are being deposited for
     * @param _amount The amount of tokens to deposit
     * @notice Emits a SwapDeposit event with the trader's address, the token address, and the amount of tokens swapped.
     */
    function addLiquiditySwap(
        address _trader,
        uint256 _amount
    ) external {
        _isPoolReady();

        if (_trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (_amount == 0) revert GeniusErrors.InvalidAmount();

        _transferERC20From(address(STABLECOIN), msg.sender,  address(this), _amount);

        _updateBalance();
        _updateAvailableAssets();

        emit SwapDeposit(
            _trader,
            _amount
        );
    }

    /**
     * @dev Removes liquidity from the GeniusPool contract by swapping stablecoins for the specified amount.
     *      Only the orchestrator can call this function.
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(
        address _trader,
        uint256 _amount
    ) external onlyOrchestrator {
        _isPoolReady();
        _isAmountValid(_amount);

        if (_trader == address(0)) revert GeniusErrors.InvalidTrader();
        if (!_isBalanceWithinThreshold(totalAssets - _amount)) revert GeniusErrors.ThresholdWouldExceed(
            minAssetBalance,
            totalAssets - _amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, _amount);

        _updateBalance();
        _updateAvailableAssets();
        
        emit SwapWithdrawal(_trader, _amount);
    }

    // =============================================================
    //                     REWARD LIQUIDITY
    // =============================================================

    /**
     * @dev Removes reward liquidity from the GeniusPool contract.
     * @param _amount The amount of reward liquidity to remove.
     * @notice Only the orchestrator can call this function.
     * @notice The `_amount` must be greater than 0, less than or equal to the total assets in the contract,
     * and less than or equal to the balance of the STABLECOIN token held by the contract.
     * @notice The total assets in the contract must remain within a certain threshold after removing the reward liquidity.
     * @notice This function transfers the specified amount of STABLECOIN tokens to the caller's address.
     * @notice It also updates the balance and available assets in the contract.
     */
    function removeRewardLiquidity(uint256 _amount) external onlyOrchestrator {
        _isPoolReady();
        _isAmountValid(_amount);

        if (!_isBalanceWithinThreshold(totalAssets - _amount)) revert GeniusErrors.ThresholdWouldExceed(
            minAssetBalance,
            totalAssets - _amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, _amount);

        _updateBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev Allows a user to stake liquidity tokens.
     * @param _trader The address of the trader who is staking the liquidity tokens.
     * @param _amount The amount of liquidity tokens to stake.
     */
    function stakeLiquidity(address _trader, uint256 _amount) external {
        _isPoolReady();

        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (_amount == 0) revert GeniusErrors.InvalidAmount();

        _transferERC20From(address(STABLECOIN), msg.sender, address(this), _amount);

        _updateBalance();
        _updateStakedBalance(_amount, 1);
        _updateAvailableAssets();

        emit Stake(
            _trader,
            _amount,
            _amount
        );
    }

    /**
     * @dev Removes staked liquidity from the GeniusPool contract.
     * @param _trader The address of the trader who wants to remove liquidity.
     * @param _amount The amount of liquidity to be removed.
     */
    function removeStakedLiquidity(address _trader, uint256 _amount) external {
        _isPoolReady();

        if (msg.sender != VAULT) revert GeniusErrors.IsNotVault();
        if (_trader == address(0)) revert GeniusErrors.InvalidTrader();

        if (_amount == 0) revert GeniusErrors.InvalidAmount();
        if (_amount > totalAssets) revert GeniusErrors.InvalidAmount();
        if (amount > totalStakedAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalStakedAssets
        );
        if (!_isBalanceWithinThreshold(totalAssets - _amount)) revert GeniusErrors.ThresholdWouldExceed(
            minAssetBalance,
            totalAssets - _amount
        );

        _transferERC20(address(STABLECOIN), msg.sender, _amount);

        _updateBalance();
        _updateStakedBalance(_amount, 0);
        _updateAvailableAssets();


        emit Unstake(
            _trader,
            _amount,
            _amount
        );
    }

    // =============================================================
    //                     REBALANCE THRESHOLD
    // =============================================================

    /**
     * @dev Sets the rebalance threshold for the GeniusPool contract.
     * @param _threshold The new rebalance threshold to be set.
     * Requirements:
     * - Only the contract owner can call this function.
     */
    function setRebalanceThreshold(uint256 _threshold) external onlyOwner {
        rebalanceThreshold = _threshold;

        _updateBalance();   
        _updateAvailableAssets();
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
    //                     READ FUNCTIONS
    // =============================================================

    /**
     * @dev Returns the fee and layer zero transaction parameters for a given chain ID.
     * @param _chainId The chain ID for which to retrieve the fee and transaction parameters.
     * @param _trader The address of the trader.
     * @return fee The fee amount for the layer zero transaction.
     * @return lzTxParams The layer zero transaction parameters.
     */
    function layerZeroFee(
        uint16 _chainId,
        address _trader
    ) public view returns (uint256 fee, IStargateRouter.lzTxObj memory lzTxParams) {

        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encodePacked(_trader)
        });

        bytes memory transferAndCallPayload = abi.encode(_lzTxParams); 

        (, uint256 _fee) = STARGATE_ROUTER.quoteLayerZeroFee(
            _chainId,
            1,
            abi.encodePacked(_trader),
            transferAndCallPayload,
            _lzTxParams
        );

        return (_fee, _lzTxParams);
    }

    /**
     * @dev Returns the current state of the assets in the GeniusPool contract.
     * @return totalAssets The total number of assets in the pool.
     * @return availableAssets The number of assets available for use.
     * @return totalStakedAssets The total number of assets currently staked in the pool.
     */
    function assets() public view returns (uint256, uint256, uint256) {
        return (
            totalAssets,
            availableAssets,
            totalStakedAssets
        );
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Checks if the pool is ready for use.
     */
    function _isPoolReady() internal view {
        if (isPaused == 1) revert GeniusErrors.Paused();
        if (initialized == 0) revert GeniusErrors.NotInitialized();
    }

    /**
     * @dev Checks if the given amount is valid for a transaction.
     * @param amount The amount to be checked.
     */
    function _isAmountValid(uint256 amount) internal view {
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        if (amount > totalAssets) revert GeniusErrors.InsufficientBalance(
            address(STABLECOIN),
            amount,
            totalAssets
        );

        if (amount > availableAssets) revert GeniusErrors.InsufficientLiquidity(
            availableAssets,
            amount
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
     * @dev Updates the balance of the contract by fetching the total assets of the STABLECOIN token.
     * This function is internal and can only be called from within the contract.
     */
    function _updateBalance() internal {
        totalAssets = STABLECOIN.balanceOf(address(this));
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
     * @dev Updates the available assets by calculating the liquidity needed based on the staked assets and the rebalance threshold.
     * If the total assets exceed the needed liquidity, the available assets are updated accordingly.
     */
    function _updateAvailableAssets() internal {
        // Calculate the amount that is the threshold percentage of the staked assets
        uint256 reduction = totalStakedAssets > 0 ? (totalStakedAssets * rebalanceThreshold) / 100 : 0;

        // Calculate the liquidity needed as the staked assets minus the reduction
        // Ensure not to underflow; if reduction is somehow greater, set neededLiquidity to 0
        uint256 neededLiquidity = totalStakedAssets > reduction ? totalStakedAssets - reduction : 0;
        
        // Ensure we do not underflow when calculating available assets
        if (totalAssets > neededLiquidity) {
            availableAssets = totalAssets - neededLiquidity;
        } else {
            availableAssets = 0;
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

}