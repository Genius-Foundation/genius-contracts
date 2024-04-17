// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "permit2/interfaces/ISignatureTransfer.sol";
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

    ISignatureTransfer public immutable PERMIT2;
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

        PERMIT2 = ISignatureTransfer(_permit2);
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
    * @dev Facilitates the deposit of multiple types of tokens into the contract using a signed batch transfer permit.
    * This function is orchestrated by a third party (orchestrator) who uses a permit signed by the token owner.
    * The owner signs a permit authorizing the transfer of specific tokens in specific amounts, which the orchestrator
    * then uses to execute the transfer, ensuring that token movements are fully authorized but not directly initiated by the token owner.
    *
    * Process Overview:
    *
    *     Token Owner ──────────────────────────────────┐
    *         │                                         │
    *         │ [Signs Permit]                          │
    *         │     │                                   │
    *         │     ▼                                   │
    *     Orchestrator ─────────────────────────────────┼───────────┐
    *         │                                         │           │
    *         │ [Calls function with signature]         │           │
    *         │     │                                   │           │
    *         │     ▼                                   │           │ Permit2 Contract
    *         │  [Signature Verified]                   │           │       │
    *         │     │                                   │           │       │  [Batch Transfer Authorized]
    *         │     └───────────────────────────────────┼───────────┼───────┘
    *         │                                         │           │
    *         │                                         │           │
    *         │    [Batch Transfer Executed]            │           │
    *         │       │                                 │           │
    *         │       ▼                                 │           │
    *         │    [Tokens Deposited into Contract]     │           │
    *         │                                         │           │
    *         └─────────────────────────────────────────┘           │
    *                                                               │
    *                                                               └────Tokens utilized by multicall contract─────►
    *
    * Key Steps:
    * 1. The token owner generates a signature for a batch transfer, specifying the tokens and amounts they authorize to be transferred.
    * 2. The orchestrator initiates the transaction by invoking this function, passing the owner's signature and the specified token details.
    * 3. The function verifies the owner's signature via the Permit2 system, confirming that the transfer details match the owner's authorization.
    * 4. Upon successful verification, the Permit2 contract executes the batch transfer of the specified tokens to this contract.
    *
    * @param _owner The address of the token owner who has signed the permit.
    * @param _amounts Array of amounts for each token type, dictating how much of each token to transfer.
    * @param _tokenAddresses Array of token addresses, specifying which tokens are to be transferred.
    * @param _permit A signed PermitBatchTransferFrom structure containing the authorized transfers.
    * @param _signature The digital signature from the token owner, proving authorization of the batch transfer.
    */
    function _permitAndTransferBatch(
        address _owner,
        uint256[] memory _amounts,
        address[] memory _tokenAddresses,
        ISignatureTransfer.PermitBatchTransferFrom calldata _permit,
        bytes calldata _signature
    ) internal {
        if (_amounts.length == _tokenAddresses.length) revert ArrayLengthsMismatch();
        if (_amounts.length == _permit.permitted.length) revert ArrayLengthsMismatch();

        uint256 len = _amounts.length;
        ISignatureTransfer.SignatureTransferDetails[] memory details = new ISignatureTransfer.SignatureTransferDetails[](len);

        for (uint256 i = 0; i < len;) {
            // Permissions can only be granted to the multicall contract
            details[i] = ISignatureTransfer.SignatureTransferDetails({
                to: address(this),
                requestedAmount: _amounts[i]
            });

            unchecked { ++i; }
        }

        // Call Permit2 to perform the batch transfer using the provided signature
        PERMIT2.permitTransferFrom(
            _permit,    // The batch permit message
            details,   // The details about each individual token transfer
            _owner, // Owner of the tokens and signer of the message
            _signature   // The packed signature from the token owner
        );
    }



    /**
     * @dev Aggregates multiple calls in a single transaction.
     *      This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution. Utilizes Permit2 for token transfers
     *      to allow for batched token transfers without direct owner interaction.
     * @param targets An array of addresses to call.
     * @param data    An array of calldata to forward to the targets.
     * @param values  How much ETH to forward to each target.
     * @return An array of the returndata from each call.
     */
    function aggregatePermit2WithSender(
        address[] calldata targets, // routers
        bytes[] calldata data, // calldata
        uint256[] calldata values, // native 
        ISignatureTransfer.PermitBatchTransferFrom calldata permitBatch, // permissions for the batch transfer
        address owner, // owner of the tokens
        bytes calldata signature // signature for the permit from the owner
    ) external payable returns (bytes[] memory) {

        uint256[] memory tokenAmounts = new uint256[](permitBatch.permitted.length);
        address[] memory tokenAddresses = new address[](permitBatch.permitted.length);

        for (uint256 i = 0; i < permitBatch.permitted.length;) {
            tokenAmounts[i] = permitBatch.permitted[i].amount;
            tokenAddresses[i] = permitBatch.permitted[i].token;

            unchecked { ++i; }
        }

        _permitAndTransferBatch(
            owner,
            tokenAmounts,
            tokenAddresses,
            permitBatch,
            signature
        );

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
     * @dev A contract that allows multiple calls to be aggregated and executed in a single transaction.
     */
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
    * @dev Executes multiple operations in a single transaction, combining token swapping,
    *      permission verification, and liquidity deposit actions. This function is designed
    *      to first transfer tokens based on a pre-authorized permit, swap tokens at a specified
    *      address (router), and then deposit the swapped tokens into a liquidity pool.
    * 
    * Process Overview:
    * 
    *     Trader/Owner─────────────────────────────────┐
    *        │                                         │
    *        │ [Provides Signature for Batch Transfer] │
    *        │       │                                 │    Permit2 Contract
    *        │       ▼                                 │  [Verifies Signature]
    *     Orchestrator───► Permit2Multicaller ─────────┼───────────┐
    *        │                                         │           │
    *        │       ┌─────────────────────────────────┼───────────┘
    *        │       │                                 │           
    *        │ [Initiates TokenSwapAndDeposit]         │           
    *        │       │                                 │           
    *        │       │ ────────┐                       │           
    *        │       │ [Batch Transfer Tokens]         │           
    *        │       │ ────────┘                       │           
    *        │       │                                 │          
    *        │       │                                 │        
    *        │       │ ────────┐                       │        
    *        │       │ [Swap Tokens at Target]         │           
    *        │       │ ────────┘                       │          
    *        │       │                                 │          
    *        │       │ ────────┐                       │           
    *        │       │ [Approve & Deposit into Vault]  │           
    *        │       │ ────────┘                       │           
    *        │       ▼                                 │           
    *     Genius Vault ────────────────────────────────┘                                                                
    *                                                             
    *
    * Key Steps:
    * 1. A batch transfer is initiated using a signature from the owner for the specified tokens.
    * 2. Tokens are then swapped at a target address.
    * 3. The swapped tokens are deposited into the Genius Vault.
    *
    * @param target The address where the token swap will occur (e.g., a DEX router).
    * @param data The calldata to be used for the swap operation at the target.
    * @param value The amount of native tokens (e.g., ETH) to be sent with the call for purposes like gas fees.
    * @param permitBatch The batch of permits detailing what tokens are allowed to be transferred by this contract.
    * @param signature The digital signature from the token owner authorizing the batch transfer.
    * @param owner The address of the token owner who is the signer and whose tokens are being swapped and deposited.
    *
    */
    function singleSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value,
        ISignatureTransfer.PermitBatchTransferFrom calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable {

        uint256[] memory tokenAmounts = new uint256[](permitBatch.permitted.length);
        address[] memory tokenAddresses = new address[](permitBatch.permitted.length);

        for (uint256 i = 0; i < permitBatch.permitted.length;) {
            tokenAmounts[i] = permitBatch.permitted[i].amount;
            tokenAddresses[i] = permitBatch.permitted[i].token;

            unchecked { ++i; }
        }
        
        _permitAndTransferBatch(
            owner,
            tokenAmounts,
            tokenAddresses,
            permitBatch,
            signature
        );
         
        assembly {
            sstore(returndatasize(), caller())
        }

        address tokenToSwapAddress = permitBatch.permitted[0].token;
        IERC20 tokenToSwap = IERC20(tokenToSwapAddress);

        uint256 amountToSwap = tokenToSwap.balanceOf(address(this));
        require(tokenToSwap.approve(target, amountToSwap), "Approval failed");

        (bool success, ) = target.call{value: value}(data);

        require(success, "External call failed");

        uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
        require(STABLECOIN.approve(address(VAULT), amountToDeposit), "Approval failed");

        VAULT.addLiquidity(owner, amountToDeposit);

        assembly {
            // Restore the `sender` slot.
            sstore(0, shl(160, 1))
        }
    }

/**
 * Executes multiple swap operations and deposits the swapped tokens into a liquidity pool.
 * @param targets Array of router addresses for each token swap.
 * @param data Array of calldata for each swap corresponding to the targets.
 * @param values Array of native tokens (e.g., ETH) amounts to send with each swap call.
 * @param permitBatch The permit information for batch transfer.
 * @param signature The signature for the permit.
 * @param owner The address of the trader to deposit for.
 */
function multiTokenSwapAndDeposit(
    address[] calldata targets,
    bytes[] calldata data,
    uint256[] calldata values,
    ISignatureTransfer.PermitBatchTransferFrom calldata permitBatch,
    bytes calldata signature,
    address owner
) external payable {
    if (
    targets.length != data.length ||
    targets.length != values.length ||
    targets.length != permitBatch.permitted.length
    ) revert ArrayLengthsMismatch();

    uint256[] memory tokenAmounts = new uint256[](permitBatch.permitted.length);
    address[] memory tokenAddresses = new address[](permitBatch.permitted.length);

    for (uint256 i = 0; i < permitBatch.permitted.length;) {
        tokenAmounts[i] = permitBatch.permitted[i].amount;
        tokenAddresses[i] = permitBatch.permitted[i].token;
        unchecked { ++i; }
    }

    _permitAndTransferBatch(
        owner,
        tokenAmounts,
        tokenAddresses,
        permitBatch,
        signature
    );

    assembly {
        // Set the sender slot temporarily for the span of this transaction.
        sstore(returndatasize(), caller())
    }

    // Execute each swap and handle deposits
    for (uint256 i = 0; i < targets.length;) {
        IERC20 tokenToSwap = IERC20(tokenAddresses[i]);
        uint256 amountToSwap = tokenToSwap.balanceOf(address(this));
        require(tokenToSwap.approve(targets[i], amountToSwap), "Approval failed");

        (bool success, ) = targets[i].call{value: values[i]}(data[i]);
        require(success, "Swap call failed");

        unchecked { ++i; }
    }

    // Deposit all received stablecoin into the liquidity pool
    uint256 amountToDeposit = STABLECOIN.balanceOf(address(this));
    require(STABLECOIN.approve(address(VAULT), amountToDeposit), "Approval failed");
    VAULT.addLiquidity(owner, amountToDeposit);

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