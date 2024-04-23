// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {Orchestratable, Ownable} from "./access/Orchestratable.sol";
import {IStargateRouter} from "./interfaces/IStargateRouter.sol";

/**
 * @title GeniusPool
 * @author altloot
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps.
 *         and other Genius related activities.
 */

contract GeniusPool is Orchestratable {

    // =============================================================
    //                          INTERFACES
    // =============================================================

    IERC20 public immutable STABLECOIN;
    IStargateRouter public immutable STARGATE_ROUTER;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public currentDeposits;
    mapping(address => uint256) public isOrchestrator;
    mapping(address => uint256) public traderDeposits;

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

    // =============================================================
    //                          EVENTS
    // =============================================================

    event Deposit(
        address indexed trader,
        uint256 amountDeposited,
        uint256 oldDepositAmount,
        uint256 newDepositAmount,
        bool isOrchestrator
    );

    event Withdrawal(
        address indexed trader,
        uint256 amountWithdrawn
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
    //                BRIDGE LIQUIDITY REBLANCING
    // =============================================================

    function addBridgeLiquidity(uint256 _amount) onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();

        IERC20(STABLECOIN).transferFrom(tx.origin, address(this), _amount);
    }

    /**
     * @dev Removes liquidity from a bridge pool and swaps it to the destination chain.
     * @param _amountIn The amount of tokens to remove from the bridge pool.
     * @param _minAmountOut The minimum amount of tokens expected to receive after the swap.
     * @param _dstChainId The chain ID of the destination chain.
     * @param _srcPoolId The ID of the source pool on the bridge.
     * @param _dstPoolId The ID of the destination pool on the bridge.
     * @param _amountLD The amount of liquidity tokens to remove from the bridge pool.
     * @param _minAmountLD The minimum amount of liquidity tokens expected to receive after the swap.
     */
    function removeBridgeLiquidity(
        uint256 _amountIn, // = _amountLD
        uint256 _minAmountOut, // = _minAmountLD
        uint16 _dstChainId,
        uint256 _srcPoolId,
        uint256 _dstPoolId,
        uint256 _amountLD,
        uint256 _minAmountLD
    ) onlyOrchestrator payable {
        if (_amountIn == 0) revert InvalidAmount();
        if (_amountIn > STABLECOIN.balanceOf(address(this))) revert InvalidAmount();

        (
        uint256 fee,
        IStargateRouter.lzTxObj memory lzTxParams
        ) = layerZeroFee(_dstChainId, _amountIn);

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
    }

    function layerZeroFee(
        uint16 _chainId,
        uint256 _amount
    ) public view returns (uint256 fee, IStargateRouter.lzTxObj memory lzTxParams) {

        IStargateRouter.lzTxObj memory _lzTxParams = IStargateRouter.lzTxObj({
            dstGasForCall: 0,
            dstNativeAmount: 0,
            dstNativeAddr: abi.encode(tx.origin)
        });

        bytes memory transferAndCallPayload = abi.encode(_lzTxParams); 

        (
        uint256 _irrevelantValue,
        uint256 _fee
        ) = STARGATE_ROUTER.quoteLayerZeroFee(
            _chainId,
            1,
            abi.encode(tx.origin),
            transferAndCallPayload,
            _lzTxParams
        );

        return (_fee, _lzTxParams);
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

        uint256 oldDepositAmount = traderDeposits[_trader];

        // Transfer the amount from the trader to the vault
        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), _amount);

        currentDeposits = STABLECOIN.balanceOf(address(this));

        traderDeposits[_trader] += _amount;

        uint256 newDepositAmount = traderDeposits[_trader];

        bool isSenderOrchestrator = isOrchestrator[tx.origin] == 1 ? true : false;

        emit Deposit(
            _trader,
            _amount,
            oldDepositAmount,
            newDepositAmount,
            isSenderOrchestrator
        );
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquiditySwap(address _trader, uint256 _amount) external onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();
        if (_amount > currentDeposits) revert InvalidAmount();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();


        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        currentDeposits = STABLECOIN.balanceOf(address(this));
        
        emit Withdrawal(_trader, _amount);
    }
}