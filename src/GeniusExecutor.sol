// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { GeniusPool } from "./GeniusPool.sol";

/**
 * @title GeniusExecutor
 * @author looter
 * 
 * @notice Contract that allows for efficient aggregation of multiple calls
 *         in a single transaction, while "forwarding" the `msg.sender`. Additionally,
 *         this contract also allows for the aggregation of multiple token transfers
 *         and permits utilizing the Permit2 contract, as well as depositing stablecoins
 *         to a Genius Vault.
 */
contract GeniusExecutor {

    // =============================================================
    //                          INTERFACES
    // =============================================================

    IAllowanceTransfer public immutable PERMIT2;
    GeniusPool public immutable POOL;
    IERC20 public immutable STABLECOIN;

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
    * @dev Error thrown when the array lengths do not match.
    */
    error ArrayLengthsMismatch();

    /**
     * @dev Error thrown when an invalid spender is encountered.
     */
    error InvalidSpender(address invalidSpender);

    /**
     * @dev Error thrown when an approval fails.
     */
    error ApprovalFailure(address token, uint256 amount);

    /**
     * @dev Error thrown when an external call fails.
     */
    error ExternalCallFailed(address target, uint256 index);

    /**
     * @dev Error thrown when there is insufficient native balance.
     */
    error InsufficientNativeBalance(uint256 expectedAmount, uint256 actualAmount);

    constructor(address _permit2, address _pool) payable {

        PERMIT2 = IAllowanceTransfer(_permit2);
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

        address tokenToSwapAddress = permitBatch.details[0].token;
        IERC20 tokenToSwap = IERC20(tokenToSwapAddress);

        uint256 amountToSwap = tokenToSwap.balanceOf(address(this));
        if (!tokenToSwap.approve(target, amountToSwap)) revert ApprovalFailure(tokenToSwapAddress, amountToSwap);

        uint256 initialStablecoinValue = STABLECOIN.balanceOf(address(this));

        (bool success, ) = target.call{value: value}(data);
        if(!success) revert ExternalCallFailed(target, 0);

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this)) - initialStablecoinValue;
        if (!STABLECOIN.approve(address(POOL), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        POOL.addLiquiditySwap(owner, amountToDeposit);
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
        ) revert ArrayLengthsMismatch();

        uint256 totalRequiredValue = 0;
        for (uint i = 0; i < values.length; i++) {
            totalRequiredValue += values[i];
        }
        if (totalRequiredValue > address(this).balance) revert InsufficientNativeBalance(totalRequiredValue, address(this).balance);

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveRouters(routers, permitBatch);

        uint256 initialStablecoinValue = STABLECOIN.balanceOf(address(this));
        
        _batchExecution(targets, data, values);

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this)) - initialStablecoinValue;

        if (!STABLECOIN.approve(address(POOL), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        POOL.addLiquiditySwap(owner, amountToDeposit);
    }


    /**
    * @dev Simplified function to perform a single swap and then deposit stablecoins to a vault.
    * @param target The address to call.
    * @param data The calldata to forward to the target.
    * @param value How much ETH to forward to the target.
    * @param trader The address of the trader to deposit for.
    */
    function nativeSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value,
        address trader
    ) external payable {
        require(target != address(0), "Invalid target address");

        (bool success, ) = target.call{value: value}(data);

        if (!success) revert ExternalCallFailed(target, 0);

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
        if (!STABLECOIN.approve(address(POOL), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        POOL.addLiquiditySwap(trader, amountToDeposit);
    }


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
            revert InvalidSpender(permitBatch.spender);
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


    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

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
            (bool success, ) = targets[i].call{value: values[i]}(data[i]);
            require(success, "External call failed");

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

            if (!tokenToApprove.approve(routers[i], amountToApprove)) revert ApprovalFailure(permitBatch.details[i].token, amountToApprove);

            unchecked { i++; }
        }
    }
}