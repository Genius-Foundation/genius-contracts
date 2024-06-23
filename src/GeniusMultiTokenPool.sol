// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {Orchestrable, Ownable} from "./access/Orchestrable.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";

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
    //                          INTERFACES
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
     * @dev Error thrown when the contract is already initialized.
     */
    error IsNotVault();

    /**
     * @dev Error thrown when the contract is already initialized.
     */
    error Initialized();

    /**
     * @dev Error thrown when the contract is not initialized.
     */
    error NotInitialized();

    /**
     * @dev Error thrown when an invalid amount is encountered.
     */
    error InvalidAmount();

    /**
    * @dev Error thrown when the contract needs to be rebalanced.
    */
     error NeedsRebalance(uint256 totalStakedStables, uint256 availStableBalance);

     error InvalidToken(address invalidToken);

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
        address _stablecoin,
        address _bridgeRouter,
        address _owner,
        address[] memory _supportedTokens
    ) Ownable(_owner) {
        require(_stablecoin != address(0), "GeniusVault: STABLECOIN address is the zero address");
        require(_owner != address(0), "GeniusVault: Owner address is the zero address");

        STABLECOIN = IERC20(_stablecoin);
        STARGATE_ROUTER = IStargateRouter(_bridgeRouter);

        supportedTokens = _supportedTokens;
        initialized = 0;
    }

    /**
     * @dev Initializes the GeniusVault contract.
     * @param _geniusVault The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address _geniusVault) external onlyOwner {
        if (initialized == 1) revert Initialized();
        geniusVault = _geniusVault;

        initialized = 1;
    }

    // =============================================================
    //                 BRIDGE LIQUIDITY REBALANCING
    // =============================================================

    /**
     * @dev Adds liquidity to the bridge pool.
     * @param _amount The amount of stablecoin to add as liquidity.
     * @param _chainId The chain ID of the bridge.
     * @notice Only the orchestrator can call this function.
     * @notice The `_amount` must be greater than 0.
     * @notice Transfers the specified amount of stablecoin from the caller to the contract.
     * @notice Updates the balance and available assets of the bridge pool.
     * @notice Emits a `ReceiveBridgeFunds` event with the amount and chain ID.
     */
    function addBridgeLiquidity(uint256 _amount, uint16 _chainId) public onlyOrchestrator {
        if (initialized == 0) revert NotInitialized();
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
        if (initialized == 0) revert NotInitialized();
        if (_amountIn == 0) revert InvalidAmount();
        if (_amountIn > STABLECOIN.balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - _amountIn)) revert NeedsRebalance(totalStables, availStableBalance);

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
     */
    function addLiquiditySwap(
        address _trader,
        address _token,
        uint256 _amount
    ) external {
        if (initialized == 0) revert NotInitialized();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount == 0) revert InvalidAmount();

        if (_token == address(STABLECOIN)) {
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);

            _updateBalance();
            _updateAvailableAssets();
        } else {
            if (isSupportedToken[_token] == 0) revert InvalidToken(_token);
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);

            _updateTokenBalance(_token);
        }

        emit SwapDeposit(
            _trader,
            _token,
            _amount
        );
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(
        address _trader,
        uint256 _amount
    ) external onlyOrchestrator {
        if (initialized == 0) revert NotInitialized();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalStables) revert InvalidAmount();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - _amount)) revert NeedsRebalance(totalStables, availStableBalance);


        IERC20(STABLECOIN).transfer(msg.sender, _amount);
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
        if (initialized == 0) revert NotInitialized();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalStables) revert InvalidAmount();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - _amount)) revert InvalidAmount();

        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        _updateBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //                     SWAP TO STABLES
    // =============================================================

    /**
     * @dev Swaps tokens to STABLECOIN.
     * @param _token The token to swap.
     * @param _tokenAmount The amount of tokens to swap.
     * @param _target The target address for the swap.
     * @param _calldata The calldata for the swap.
     * @param _nativeAmount The value for the swap, to allow for native swaps.
     * @notice Only an orchestrator can call this function.
     */

     function swapToStables(
         address _token,
         uint256 _tokenAmount,
         address _target,
         bytes calldata _calldata,
         uint256 _nativeAmount
     ) external onlyOrchestrator {
            if (initialized == 0) revert NotInitialized();

            if (_tokenAmount > 0) {
                if (_tokenAmount > IERC20(_token).balanceOf(address(this))) revert InvalidAmount();
            } else if (_nativeAmount > 0) {
                if (_nativeAmount > address(this).balance) revert InvalidAmount();
            }

            uint256 _initialStablecoinBalance = totalStables;

            _executeSwap(_target, _calldata, _nativeAmount);
            _updateBalance();
            _updateAvailableAssets();
            _updateTokenBalance(_token);

            uint256 _finalStablecoinBalance = totalStables;

            require(_finalStablecoinBalance > _initialStablecoinBalance, "Swap must increase stablecoin balance");
     }



    // =============================================================
    //                     STAKING LIQUIDITY
    // =============================================================

    /**
     * @dev Allows a user to stake liquidity tokens.
     * @param _amount The amount of liquidity tokens to stake.
     * @notice The `_amount` parameter must be greater than 0.
     * @notice The function transfers the specified amount of liquidity tokens from the caller to the contract.
     * @notice After the transfer, the function updates the `totalStables` variable with the balance of liquidity tokens held by the contract.
     */
    function stakeLiquidity(address _trader, uint256 _amount) external {
        if (initialized == 0) revert NotInitialized();
        if (msg.sender != geniusVault) revert IsNotVault();
        if (_amount == 0) revert InvalidAmount();

        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), _amount);

        _updateBalance();
        _updateStakedBalance(_amount, true);
        _updateAvailableAssets();

        emit Stake(
            _trader,
            _amount,
            _amount
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
        if (initialized == 0) revert NotInitialized();
        if (msg.sender != geniusVault) revert IsNotVault();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount == 0) revert InvalidAmount();
        if (_amount > totalStables) revert InvalidAmount();
        if (_amount > totalStakedStables) revert InvalidAmount();
        if (!_isBalanceWithinThreshold(totalStables - _amount, _amount)) revert NeedsRebalance(totalStables, availStableBalance);

        IERC20(STABLECOIN).transfer(msg.sender, _amount);

        _updateBalance();
        _updateStakedBalance(_amount, false);
        _updateAvailableAssets();

        emit Unstake(
            _trader,
            _amount,
            totalStakedStables
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
        stableRebalanceThreshold = _threshold;

        _updateBalance();
        _updateAvailableAssets();
    }

    // =============================================================
    //             ADDING AND REMOVING SUPPORTED TOKENS
    // =============================================================

    // Add a new token to the supported tokens list
    function addToken(address _token) external {
        require(isSupportedToken[_token] == 1, "Token is already supported");
        supportedTokens.push(_token);
        isSupportedToken[_token] = 1;
    }


    function removeToken(address _token) external {
        require(isSupportedToken[_token] == 1, "Token is not supported");
        isSupportedToken[_token] = 1;

        // Find the token in the array and remove it
        for (uint256 i = 0; i < supportedTokens.length; i++) {
            if (supportedTokens[i] == _token) {
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
     * @dev Returns the fee and layer zero transaction parameters for a given chain ID.
     * @param _chainId The chain ID for which to retrieve the fee and transaction parameters.
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

    function stablecoinBalances() public view returns (
        uint256,
        uint256,
        uint256
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
     * @return A boolean value indicating whether the balance is within the threshold limit.
     */
    function _isBalanceWithinThreshold(uint256 balance) public view returns (bool) {
        uint256 lowerBound = (totalStakedStables * stableRebalanceThreshold) / 100;

        return balance >= lowerBound;
    }

    /**
     * @dev Checks if the balance is within the threshold after unstaking a certain amount.
     * @param balance The current balance of the account.
     * @param amountToUnstake The amount to be unstaked.
     * @return boolean indicating whether the balance is within the threshold.
     */
    function _isBalanceWithinThreshold(uint256 balance, uint256 amountToUnstake) internal view returns (bool) {
        uint256 lowerBound = ((totalStakedStables - amountToUnstake) * stableRebalanceThreshold) / 100;

        return balance >= lowerBound;
    }

    /**
     * @dev Updates the balance of the contract by fetching the total assets of the STABLECOIN token.
     * This function is internal and can only be called from within the contract.
     */
    function _updateBalance() internal {
        totalStables = STABLECOIN.balanceOf(address(this));
    }

    function _updateStakedBalance(uint256 _amount, bool _add) internal {
        if (_add) {
            totalStakedStables += _amount;
        } else {
            totalStakedStables -= _amount;
        }
    }

    /**
     * @dev Updates the available assets by calculating the liquidity needed based on the staked assets and the rebalance threshold.
     * If the total assets exceed the needed liquidity, the available assets are updated accordingly.
     */
    function _updateAvailableAssets() internal {
        // Calculate the amount that is the threshold percentage of the staked assets
        uint256 reduction = totalStakedStables > 0 ? (totalStakedStables * stableRebalanceThreshold) / 100 : 0;

        // Calculate the liquidity needed as the staked assets minus the reduction
        // Ensure not to underflow; if reduction is somehow greater, set neededLiquidity to 0
        uint256 neededLiquidity = totalStakedStables > reduction ? totalStakedStables - reduction : 0;
        
        // Ensure we do not underflow when calculating available assets
        if (totalStables > neededLiquidity) {
            availStableBalance = totalStables - neededLiquidity;
        } else {
            availStableBalance = 0;
        }
    }

    function _updateTokenBalance(address _token) internal {
        if (_token == NATIVE) {
            tokenBalances[_token] = address(this).balance;
        } else {
            tokenBalances[_token] = IERC20(_token).balanceOf(address(this));
        }
    }

    /**
     * @dev Executes a batch of external function calls.
     * @param target The array of target addresses to call.
     * @param data The array of function call data.
     * @param value The array of values to send along with the function calls.
     */
    function _executeSwap(
        address target,
        bytes calldata data,
        uint256 value
    ) internal {
        (bool success, ) = target.call{value: value}(data);
        require(success, "External call failed");
    }

}