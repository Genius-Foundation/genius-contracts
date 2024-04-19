// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { GeniusVault } from "./GeniusVault.sol";

/**
 * @title GeniusExecutor
 * @author altloot
 * 
 * @notice Contract that allows for efficient aggregation of multiple calls
 *         in a single transaction, while "forwarding" the `msg.sender`. Additionally,
 *         this contract also allows for the aggregation of multiple token transfers
 *         and permits utilizing the Permit2 contract, as well as depositing stablecoins
 *         to a Genius Vault.
 * 
 * @dev Originally authored by vectorized.eth, this contract was modified to support
 *      Permit2 token transfers and permits for multiple tokens.
 */
contract GeniusExecutor {

    IAllowanceTransfer public immutable PERMIT2;
    GeniusVault public immutable VAULT;
    IERC20 public immutable STABLECOIN;

    error ArrayLengthsMismatch();
    error Reentrancy();
    error InvalidSpender(address invalidSpender);
    error ApprovalFailure(address token, uint256 amount);
    error ExternalCallFailed(address target, uint256 index);
    error InsufficientNativeBalance(uint256 expectedAmount, uint256 actualAmount);

    constructor(address _permit2, address _vault) payable {

        PERMIT2 = IAllowanceTransfer(_permit2);
        VAULT = GeniusVault(_vault);
        STABLECOIN = IERC20(VAULT.STABLECOIN());

        assembly {
            sstore(returndatasize(), shl(160, 1))
        }

    }

    /**
     * @dev Returns the address that called `aggregateWithSender` on this contract.
     *      The value is always the zero address outside a transaction.
     */
    receive() external payable {
        assembly {
            mstore(returndatasize(), and(sub(shl(160, 1), 1), sload(returndatasize())))
            return(returndatasize(), 0x20)
        }
    }


    /**
     * @dev Aggregates multiple calls in a single transaction.
     *      This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution.
     *      This method does not support reentrancy.
     * @param targets An array of addresses to call.
     * @param data    An array of calldata to forward to the targets.
     * @param values  How much ETH to forward to each target.
     * @return An array of the returndata from each call.
     */
    function aggregatePermit2WithSender(
        address[] calldata targets, // routers
        bytes[] calldata data, // calldata
        uint256[] calldata values, // native 
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable returns (bytes[] memory) {

        _permitAndBatchTransfer(permitBatch, signature, owner);

        assembly {
            if iszero(and(eq(targets.length, data.length), eq(data.length, values.length))) {
                // Store the function selector of `ArrayLengthsMismatch()`.
                mstore(returndatasize(), 0x3b800a46)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            if iszero(and(sload(returndatasize()), shl(160, 1))) {
                // Store the function selector of `Reentrancy()`.
                mstore(returndatasize(), 0xab143c06)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            mstore(returndatasize(), 0x20) // Store the memory offset of the `results`.
            mstore(0x20, data.length) // Store `data.length` into `results`.
            // Early return if no data.
            if iszero(data.length) { return(returndatasize(), 0x40) }

            // Set the sender slot temporarily for the span of this transaction.
            sstore(returndatasize(), caller())

            let results := 0x40
            // Left shift by 5 is equivalent to multiplying by 0x20.
            data.length := shl(5, data.length)
            // Copy the offsets from calldata into memory.
            calldatacopy(results, data.offset, data.length)
            // Offset into `results`.
            let resultsOffset := data.length
            // Pointer to the end of `results`.
            // Recycle `data.length` to avoid stack too deep.
            data.length := add(results, data.length)

            for {} 1 {} {
                // The offset of the current bytes in the calldata.
                let o := add(data.offset, mload(results))
                let memPtr := add(resultsOffset, 0x40)
                // Copy the current bytes from calldata to the memory.
                calldatacopy(
                    memPtr,
                    add(o, 0x20), // The offset of the current bytes' bytes.
                    calldataload(o) // The length of the current bytes.
                )
                if iszero(
                    call(
                        gas(), // Remaining gas.
                        calldataload(targets.offset), // Address to call.
                        calldataload(values.offset), // ETH to send.
                        memPtr, // Start of input calldata in memory.
                        calldataload(o), // Size of input calldata.
                        0x00, // We will use returndatacopy instead.
                        0x00 // We will use returndatacopy instead.
                    )
                ) {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
                // Advance the `targets.offset`.
                targets.offset := add(targets.offset, 0x20)
                // Advance the `values.offset`.
                values.offset := add(values.offset, 0x20)
                // Append the current `resultsOffset` into `results`.
                mstore(results, resultsOffset)
                results := add(results, 0x20)
                // Append the returndatasize, and the returndata.
                mstore(memPtr, returndatasize())
                returndatacopy(add(memPtr, 0x20), 0x00, returndatasize())
                // Advance the `resultsOffset` by `returndatasize() + 0x20`,
                // rounded up to the next multiple of 0x20.
                resultsOffset := and(add(add(resultsOffset, returndatasize()), 0x3f), not(0x1f))
                if iszero(lt(results, data.length)) { break }
            }
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
            // Direct return.
            return(0x00, add(resultsOffset, 0x40))
        }
    }

    function aggregateWithSender(
        address[] calldata targets, // routers
        bytes[] calldata data, // calldata
        uint256[] calldata values // native 
    ) external payable returns (bytes[] memory) {

        assembly {
            if iszero(and(eq(targets.length, data.length), eq(data.length, values.length))) {
                // Store the function selector of `ArrayLengthsMismatch()`.
                mstore(returndatasize(), 0x3b800a46)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            if iszero(and(sload(returndatasize()), shl(160, 1))) {
                // Store the function selector of `Reentrancy()`.
                mstore(returndatasize(), 0xab143c06)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            mstore(returndatasize(), 0x20) // Store the memory offset of the `results`.
            mstore(0x20, data.length) // Store `data.length` into `results`.
            // Early return if no data.
            if iszero(data.length) { return(returndatasize(), 0x40) }

            // Set the sender slot temporarily for the span of this transaction.
            sstore(returndatasize(), caller())

            let results := 0x40
            // Left shift by 5 is equivalent to multiplying by 0x20.
            data.length := shl(5, data.length)
            // Copy the offsets from calldata into memory.
            calldatacopy(results, data.offset, data.length)
            // Offset into `results`.
            let resultsOffset := data.length
            // Pointer to the end of `results`.
            // Recycle `data.length` to avoid stack too deep.
            data.length := add(results, data.length)

            for {} 1 {} {
                // The offset of the current bytes in the calldata.
                let o := add(data.offset, mload(results))
                let memPtr := add(resultsOffset, 0x40)
                // Copy the current bytes from calldata to the memory.
                calldatacopy(
                    memPtr,
                    add(o, 0x20), // The offset of the current bytes' bytes.
                    calldataload(o) // The length of the current bytes.
                )
                if iszero(
                    call(
                        gas(), // Remaining gas.
                        calldataload(targets.offset), // Address to call.
                        calldataload(values.offset), // ETH to send.
                        memPtr, // Start of input calldata in memory.
                        calldataload(o), // Size of input calldata.
                        0x00, // We will use returndatacopy instead.
                        0x00 // We will use returndatacopy instead.
                    )
                ) {
                    // Bubble up the revert if the call reverts.
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
                // Advance the `targets.offset`.
                targets.offset := add(targets.offset, 0x20)
                // Advance the `values.offset`.
                values.offset := add(values.offset, 0x20)
                // Append the current `resultsOffset` into `results`.
                mstore(results, resultsOffset)
                results := add(results, 0x20)
                // Append the returndatasize, and the returndata.
                mstore(memPtr, returndatasize())
                returndatacopy(add(memPtr, 0x20), 0x00, returndatasize())
                // Advance the `resultsOffset` by `returndatasize() + 0x20`,
                // rounded up to the next multiple of 0x20.
                resultsOffset := and(add(add(resultsOffset, returndatasize()), 0x3f), not(0x1f))
                if iszero(lt(results, data.length)) { break }
            }
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
            // Direct return.
            return(0x00, add(resultsOffset, 0x40))
        }
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
         
        assembly {
            sstore(returndatasize(), caller())
        }

        address tokenToSwapAddress = permitBatch.details[0].token;
        IERC20 tokenToSwap = IERC20(tokenToSwapAddress);

        uint256 amountToSwap = tokenToSwap.balanceOf(address(this));
        if (!tokenToSwap.approve(target, amountToSwap)) revert ApprovalFailure(tokenToSwapAddress, amountToSwap);

        uint256 initialStablecoinValue = STABLECOIN.balanceOf(address(this));

        (bool success, ) = target.call{value: value}(data);
        if(!success) revert ExternalCallFailed(target, 0);

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this)) - initialStablecoinValue;
        if (!STABLECOIN.approve(address(VAULT), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        VAULT.addLiquidity(owner, amountToDeposit);

        assembly {
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
        }
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

        for (uint i = 0; i < permitBatch.details.length;) {
            IERC20 tokenToApprove = IERC20(permitBatch.details[i].token);
            uint256 amountToApprove = permitBatch.details[i].amount;

            if (!tokenToApprove.approve(routers[i], amountToApprove)) revert ApprovalFailure(permitBatch.details[i].token, amountToApprove);

            unchecked { i++; }
        }

        uint256 initialStablecoinValue = STABLECOIN.balanceOf(address(this));
        
        for (uint i = 0; i < targets.length; i++) {
            (bool success, ) = targets[i].call{value: values[i]}(data[i]);
            require(success, "External call failed");
        }

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this)) - initialStablecoinValue;

        if (!STABLECOIN.approve(address(VAULT), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        VAULT.addLiquidity(owner, amountToDeposit);
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

        assembly {
            // Set the sender slot temporarily for the span of this transaction.
            sstore(returndatasize(), caller())
        }

        (bool success, ) = target.call{value: value}(data);

        if (!success) revert ExternalCallFailed(target, 0);

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
        if (!STABLECOIN.approve(address(VAULT), amountToDeposit)) revert ApprovalFailure(address(STABLECOIN), amountToDeposit);

        VAULT.addLiquidity(trader, amountToDeposit);

        assembly {
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
        }
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

            unchecked {
                i++;
            }
        }

        PERMIT2.transferFrom(transferDetails);
    }
}