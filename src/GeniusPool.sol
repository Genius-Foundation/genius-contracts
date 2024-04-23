// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";

/**
 * @title GeniusPool
 * @author altloot
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps.
 *         and other Genius related activities.
 */

contract GeniusPool is Orchestrable {

    // =============================================================
    //                          INTERFACES
    // =============================================================

    IERC20 public immutable STABLECOIN;
    IStargateRouter public immutable STARGATE_ROUTER;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public totalAssets; // The total amount of stablecoin assets in the contract
    uint256 public availableAssets; // totalAssets - (totalStakedAssets * (1 + rebalanceThreshold) (in percentage)
    uint256 public totalStakedAssets; // The total amount of stablecoin assets made available to the pool through user deposits
    uint256 public rebalanceThreshold = 10; // The maximum % of deviation from totalStakedAssets before blocking trades

    mapping(address => uint256) public stakedDeposits;

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev Error thrown when an invalid spender is encountered.
     */
    error InvalidSpender();

    /**
     * @dev Error thrown when an invalid trader is encountered.
     */
    error InvalidTrader();

    /**
     * @dev Error thrown when an invalid amount is encountered.
     */
    error InvalidAmount();

    /**
     * @dev Error thrown when an invalid deposit token is encountered.
     */
     error InvalidDepositToken();

    /**
    * @dev Error thrown when the contract needs to be rebalanced.
    */
     error NeedsRebalance(uint256 totalStakedAssets, uint256 availableAssets);

    // =============================================================
    //                          EVENTS
    // =============================================================

    event Stake(
        address indexed trader,
        uint256 amountDeposited,
        uint256 newTotalDeposits
    );

    event Unstake(
        address indexed trader,
        uint256 amountWithdrawn,
        uint256 newTotalDeposits
    );

    event SwapDeposit(
        address indexed trader,
        uint256 amountDeposited
    );

    event SwapWithdrawal(
        address indexed trader,
        uint256 amountWithdrawn
    );

    event BridgeFunds(
        uint256 amount,
        uint16 chainId
    );

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
        require(_owner == address(msg.sender), "GeniusVault: Owner address is not the deployer");

        STABLECOIN = IERC20(_stablecoin);
        STARGATE_ROUTER = IStargateRouter(_bridgeRouter);
    }
    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    function addBridgeLiquidity(uint256 _amount, uint16 _chainId) public onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();

        IERC20(STABLECOIN).transferFrom(tx.origin, address(this), _amount);
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
        uint256 _amountIn, // = _amountLD
        uint256 _minAmountOut, // = _minAmountLD
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId
    ) public onlyOrchestrator payable {
        if (_amountIn == 0) revert InvalidAmount();
        if (_amountIn > STABLECOIN.balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalAssets - _amountIn)) revert NeedsRebalance(totalAssets, availableAssets);

        (
        uint256 fee,
        IStargateRouter.lzTxObj memory lzTxParams
        ) = layerZeroFee(_dstChainId);

        if (msg.value != fee) revert InvalidAmount();

        STABLECOIN.approve(address(STARGATE_ROUTER), _amountIn);

        STARGATE_ROUTER.swap{value:msg.value}(
            _dstChainId,
            _srcPoolId,
            _dstPoolId,
            payable(tx.origin),
            _amountIn,
            _minAmountOut,
            lzTxParams,
            abi.encode(tx.origin),
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
     */
    function addLiquiditySwap(
        address _trader,
        uint256 _amount
    ) external {
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount == 0) revert InvalidAmount();

        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), _amount);
        _updateBalance();
        _updateAvailableAssets();

        emit SwapDeposit(
            _trader,
            _amount
        );
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(address _trader, uint256 _amount) external onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalAssets) revert InvalidAmount();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalAssets - _amount)) revert NeedsRebalance(totalAssets, availableAssets);


        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        _updateBalance();
        _updateAvailableAssets();
        
        emit SwapWithdrawal(_trader, _amount);
    }

    // =============================================================
    //                     REWARD LIQUIDITY
    // =============================================================

    function removeRewardLiquidity(uint256 _amount) external onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalAssets) revert InvalidAmount();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalAssets - _amount)) revert InvalidAmount();

        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        _updateBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev Allows a user to stake liquidity tokens.
     * @param _amount The amount of liquidity tokens to stake.
     * @notice The `_amount` parameter must be greater than 0.
     * @notice The function transfers the specified amount of liquidity tokens from the caller to the contract.
     * @notice After the transfer, the function updates the `totalAssets` variable with the balance of liquidity tokens held by the contract.
     */
    function stakeLiquidity(address _trader, uint256 _amount) external {
        if (_amount == 0) revert InvalidAmount();

        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), _amount);
        _updateBalance();

        stakedDeposits[_trader] += _amount;
        totalStakedAssets += _amount;

        _updateAvailableAssets();

        emit Stake(
            _trader,
            _amount,
            stakedDeposits[_trader] + _amount
        );
    }

    /**
     * @dev Removes staked liquidity from the GeniusPool contract.
     * @param _amount The amount of liquidity to be removed.
     * @notice The `_amount` must be greater than zero, less than or equal to the current deposits, and less than or equal to the balance of the STABLECOIN token in the contract.
     * @notice Transfers the specified `_amount` of STABLECOIN tokens to the caller's address.
     * @notice Updates the current deposits by getting the updated balance of the STABLECOIN token in the contract.
     * @notice Throws an exception if any of the conditions are not met.
     */
    function removeStakedLiquidity(address _trader, uint256 _amount) external {
        if (_trader != tx.origin) revert InvalidTrader();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalAssets) revert InvalidAmount();
        if (_amount > stakedDeposits[_trader]) revert InvalidAmount();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalAssets - _amount, _amount)) revert NeedsRebalance(totalAssets, availableAssets);

        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        _updateBalance();

        stakedDeposits[_trader] -= _amount;
        totalStakedAssets -= _amount;

        _updateAvailableAssets();

        emit Unstake(
            _trader,
            _amount,
            stakedDeposits[_trader] - _amount
        );
    }

    function setRebalanceThreshold(uint256 _threshold) external onlyOwner {
        rebalanceThreshold = _threshold;
    }

    // =============================================================
    //                     READ FUNCTIONS
    // =============================================================

    function layerZeroFee(
        uint16 _chainId
    ) public view returns (uint256 fee, IStargateRouter.lzTxObj memory lzTxParams) {

        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encode(tx.origin)
        });

        bytes memory transferAndCallPayload = abi.encode(_lzTxParams); 

        (, uint256 _fee) = STARGATE_ROUTER.quoteLayerZeroFee(
            _chainId,
            1,
            abi.encode(tx.origin),
            transferAndCallPayload,
            _lzTxParams
        );

        return (_fee, _lzTxParams);
    }

    // =============================================================
    //                     INTERNAL FUNCTIONS
    // =============================================================

    // balance is the current balance of the stable coin in the contract
    function _isBalanceWithinThreshold(uint256 balance) public view returns (bool) {
        uint256 lowerBound = (totalStakedAssets * rebalanceThreshold) / 100;

        return balance >= lowerBound;
    }

    function _isBalanceWithinThreshold(uint256 balance, uint256 amountToUnstake) internal view returns (bool) {
        uint256 lowerBound = ((totalStakedAssets - amountToUnstake) * rebalanceThreshold) / 100;

        return balance >= lowerBound;
    }

    function _updateBalance() internal {
        totalAssets = STABLECOIN.balanceOf(address(this));
    }

    function _updateAvailableAssets() internal {
        // Calculate the amount that is the threshold percentage of the staked assets
        uint256 reduction = (totalStakedAssets * rebalanceThreshold) / 100;

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

}