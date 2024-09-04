// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";

import { GeniusPool } from "./GeniusPool.sol";
import { GeniusVault } from "./GeniusVault.sol";
import { GeniusErrors } from "./libs/GeniusErrors.sol";

/**
 * @title GeniusExecutor
 * @author looter
 * 
 * @notice Contract that allows for efficient aggregation of multiple calls
 *         in a single transaction. Additionally, this contract also allows
 *         for the aggregation of multiple token transfers and permits
 *         utilizing the Permit2 contract, as well facilitating interactions
 *         with the GeniusVault contract and the GeniusPool contract.
 */
contract GeniusExecutor {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    IAllowanceTransfer public immutable PERMIT2;
    IERC20 public immutable STABLECOIN;
    GeniusPool public immutable POOL;
    GeniusVault public immutable VAULT;

    constructor(address _permit2, address _pool, address _vault) payable {

        PERMIT2 = IAllowanceTransfer(_permit2);
        VAULT = GeniusVault(_vault);
        POOL = GeniusPool(_pool);
        STABLECOIN = IERC20(POOL.STABLECOIN());

    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Aggregates multiple calls in a single transaction.
     *      This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution.
     *      This method does not support reentrancy.
     * @param targets An array of addresses to call.
     * @param data    An array of calldata to forward to the targets.
     * @param values  How much ETH to forward to each target.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader/owner to aggregate calls for.
     */
    function aggregateWithPermit2(
        address[] calldata targets, // routers
        bytes[] calldata data, // calldata
        uint256[] calldata values, // native 
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable {
        _permitAndBatchTransfer(permitBatch, signature, owner);
        _batchExecution(targets, data, values);
    }

    /**
     * @dev Executes a batch of calls to external contracts with the sender's address.
     * @param targets The array of target contract addresses to call.
     * @param data The array of calldata for each call.
     * @param values The array of ETH values to send with each call.
     */
    function aggregate(
        address[] calldata targets, // routers
        bytes[] calldata data, // calldata
        uint256[] calldata values // native 
    ) external payable {
        _batchExecution(targets, data, values);
    }

       /**
     * @dev Aggregates multiple calls in a single transaction.
     *      This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution.
     *      This method does not support reentrancy.
     * @param target An array of addresses to call.
     * @param data    An array of calldata to forward to the targets.
     * @param value  How much ETH to forward to each target.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to deposit for.
     */
    function tokenSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable {
        _permitAndBatchTransfer(permitBatch, signature, owner);

        address _tokenAddress = permitBatch.details[0].token;
        IERC20 tokenToSwap = IERC20(_tokenAddress);

        uint256 _amountToSwap = tokenToSwap.balanceOf(address(this));

        if (!tokenToSwap.approve(target, _amountToSwap)) revert GeniusErrors.ApprovalFailure(_tokenAddress, _amountToSwap);

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        (bool _success, ) = target.call{value: value}(data);
        if(!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;
        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), _depositAmount);

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount);
    }


    /**
     * @dev Executes multiple swaps and deposits in a single transaction.
     * @param targets The array of target addresses to call.
     * @param data The array of data to pass to each target address.
     * @param values The array of values to send to each target address.
     * @param permitBatch The permit batch containing permit details for token transfers.
     * @param signature The signature for the permit batch.
     *
     * @dev Does not require that every swap utilizes an ERC20 token.
     *      Native swaps can be performed by setting the token address to 0.
     *      If the token address is not 0, the contract will approve the target 
     */
    function multiSwapAndDeposit(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        address[] calldata routers,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable {
        if (
            targets.length != data.length ||
            data.length != values.length ||
            routers.length != permitBatch.details.length
        ) revert GeniusErrors.ArrayLengthsMismatch();

        uint256 _neededNative = 0;
        for (uint i = 0; i < values.length; i++) {
            _neededNative += values[i];
        }
        if (_neededNative > address(this).balance) revert GeniusErrors.InsufficientNativeBalance(
            _neededNative,
            address(this).balance
        );
        
        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveRouters(routers, permitBatch);
        _batchExecution(targets, data, values);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), _depositAmount);

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount);
    }


    /**
    * @dev Simplified function to perform a single swap and then deposit stablecoins to a vault.
    * @param targets The address to call.
    * @param data The calldata to forward to the target.
    * @param values How much ETH to forward to the target.
    * @param trader The address of the trader to deposit for.
    */
    function nativeSwapAndDeposit(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        address trader
    ) external payable {
        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _batchExecution(targets, data, values);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;
        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        POOL.addLiquiditySwap(trader, address(STABLECOIN), _depositAmount);
    }

    function depositToVault(
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external {
        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveVault(amount);
        _depositToVault(owner, amount);
    }

    /**
     * @dev Deposits a specified amount of STABLECOIN tokens to the GeniusVault contract.
     * @param amount The amount of STABLECOIN tokens to be deposited.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to deposit for.
     */
    function withdrawFromVault(
        uint256 amount,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external {

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveVault(amount);
        _withdrawFromVault(owner, amount);

        uint256 _residBalance = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (_residBalance > 0) revert GeniusErrors.ResidualBalance(_residBalance);
    }
    
    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Internal function to permit and transfer tokens from the caller's address.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to deposit for.
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch, // permissions for the batch transfer
        bytes calldata signature, // signature for the permit from the owner
        address owner
    ) private {
        if (permitBatch.spender != address(this)) {
            revert GeniusErrors.InvalidSpender();
        }
        PERMIT2.permit(owner, permitBatch, signature);

        IAllowanceTransfer.AllowanceTransferDetails[] memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
            permitBatch.details.length
        );
        for (uint i = 0; i < permitBatch.details.length; ) {
            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: address(this),
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });

            unchecked { i++; }
        }

        PERMIT2.transferFrom(transferDetails);
    }


    /**
     * @dev Executes a batch of external function calls.
     * @param targets The array of target addresses to call.
     * @param data The array of function call data.
     * @param values The array of values to send along with the function calls.
     */
    function _batchExecution(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) private {
        for (uint i = 0; i < targets.length;) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            require(_success, "External call failed");

            unchecked { i++; }
        }
    }

    /**
     * @dev Approves multiple routers to spend tokens on behalf of the contract.
     * @param routers The addresses of the routers to be approved.
     * @param permitBatch The permit batch containing token and amount details.
     */
    function _approveRouters(
        address[] calldata routers,
        IAllowanceTransfer.PermitBatch calldata permitBatch
    ) private {
        for (uint i = 0; i < permitBatch.details.length;) {
            IERC20 tokenToApprove = IERC20(permitBatch.details[i].token);
            uint256 amountToApprove = permitBatch.details[i].amount;

            if (!tokenToApprove.approve(routers[i], amountToApprove)) revert GeniusErrors.ApprovalFailure(permitBatch.details[i].token, amountToApprove);

            unchecked { i++; }
        }
    }

    /**
     * @dev Approves the transfer of a specified amount of STABLECOIN tokens to the VAULT contract.
     * @param amount The amount of STABLECOIN tokens to be approved for transfer.
     */
    function _approveVault(uint256 amount) private {
        if (!STABLECOIN.approve(address(VAULT), amount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), amount);
    }

    /**
     * @dev Deposits the specified amount to the vault for the given receiver.
     * @param receiver The address of the receiver.
     * @param amount The amount to be deposited.
     */
    function _depositToVault(address receiver, uint256 amount) private {
        VAULT.deposit(amount, receiver);
    }

    /**
     * @dev Withdraws a specified amount from the vault and transfers it to the specified receiver.
     * @param receiver The address of the receiver of the withdrawn amount.
     * @param amount The amount to be withdrawn from the vault.
     */
    function _withdrawFromVault(address receiver, uint256 amount) private {
        VAULT.withdraw(amount, receiver, address(this));
    }
}