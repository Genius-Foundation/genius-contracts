// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "permit2/interfaces/IAllowanceTransfer.sol";
import "./GeniusVault.sol";

/**
 * @title Permit2Multicaller
 * @author altloot
 * 
 * @notice Contract that allows for efficient aggregation of multiple calls
 *         in a single transaction, while "forwarding" the `msg.sender`. Additionally,
 *         this contract also allows for the aggregation of multiple token transfers
 *         and permits utilizing the Permit2 contract.
 * 
 * @dev Originally authored by vectorized.eth, this contract was modified to support
 *      Permit2 token transfers and permits for multiple tokens.
 */
contract Permit2Multicaller {

    IAllowanceTransfer public immutable PERMIT2;
    GeniusVault public immutable VAULT;
    IERC20 public immutable STABLECOIN;

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The lengths of the input arrays are not the same.
     */
    error ArrayLengthsMismatch();

    /**
     * @dev This function does not support reentrancy.
     */
    error Reentrancy();

    /**
     * @dev The spender is not the contract itself.
     */
    error InvalidSpender();

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address _permit2, address _vault) payable {

        PERMIT2 = IAllowanceTransfer(_permit2);
        VAULT = GeniusVault(_vault);
        STABLECOIN = IERC20(VAULT.STABLECOIN());

        assembly {
            // Throughout this code, we will abuse returndatasize
            // in place of zero anywhere before a call to save a bit of gas.
            // We will use storage slot zero to store the caller at
            // bits [0..159] and reentrancy guard flag at bit 160.
            sstore(returndatasize(), shl(160, 1))
        }

    }

    // =============================================================
    //                    AGGREGATION OPERATIONS
    // =============================================================

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
     * @dev Internal function to permit and transfer tokens from the caller's address.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch, // permissions for the batch transfer
        bytes calldata signature // signature for the permit from the owner
    ) private {
        if (permitBatch.spender != address(this)) {
            revert InvalidSpender();
        }
        PERMIT2.permit(msg.sender, permitBatch, signature);

        IAllowanceTransfer.AllowanceTransferDetails[] memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
            permitBatch.details.length
        );
        for (uint i = 0; i < permitBatch.details.length; ) {
            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: msg.sender,
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
        bytes calldata signature
    ) external payable returns (bytes[] memory) {

        _permitAndBatchTransfer(permitBatch, signature);

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
     * @param trader The address of the trader to deposit for.
     */
    function tokenSwapAndDeposit(
        address target, // routers
        bytes calldata data, // calldata
        uint256 value, // native 
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address trader
    ) external payable {
         _permitAndBatchTransfer(permitBatch, signature);
         
        assembly {
            sstore(returndatasize(), caller())
        }

        address tokenToSwapAddress = permitBatch.details[0].token;
        IERC20 tokenToSwap = IERC20(tokenToSwapAddress);

        uint256 amountToSwap = tokenToSwap.balanceOf(address(this));
        require(tokenToSwap.approve(target, amountToSwap), "Approval failed");

        (bool success, ) = target.call{value: value}(data);

        require(success, "External call failed");

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
        require(STABLECOIN.approve(address(VAULT), amountToDeposit), "Approval failed");

        VAULT.addLiquidity(trader, amountToDeposit);

        assembly {
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
        }
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
        require(success, "External call failed");

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
        require(STABLECOIN.approve(address(VAULT), amountToDeposit), "Approval failed");

        VAULT.addLiquidity(trader, amountToDeposit);

        assembly {
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
        }
    }
}