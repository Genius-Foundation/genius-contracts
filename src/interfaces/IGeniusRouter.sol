// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {IGeniusVault} from "./IGeniusVault.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IGeniusRouter
 * @author looter
 *
 * @notice Interface for efficient aggregation of multiple calls
 *         in a single transaction. This interface allows for the aggregation
 *         of multiple token transfers and permits utilizing the Permit2 contract,
 *         as well as facilitating interactions with the GeniusVault contract
 *         and the GeniusVault contract.
 */
interface IGeniusRouter {
    /**
     * @notice Swaps tokens and creates a cross-chain order using standard token approvals
     * 
     * @param seed Unique identifier for the order
     * @param tokensIn Array of token addresses to be swapped
     * @param amountsIn Array of amounts corresponding to the tokens
     * @param target The contract address to execute the swap on
     * @param data The calldata for executing the swap
     * @param owner The address that owns the tokens and will create the order
     * @param destChainId The destination chain ID for the cross-chain order
     * @param fee The fee to be paid for the cross-chain transaction
     * @param receiver The receiver address on the destination chain (in bytes32 format)
     * @param minAmountOut The minimum amount of tokens to receive on the destination chain
     * @param tokenOut The token to receive on the destination chain (in bytes32 format)
     */
    function swapAndCreateOrder(
        bytes32 seed,
        address[] calldata tokensIn,
        uint256[] calldata amountsIn,
        address target,
        bytes calldata data,
        address owner,
        uint256 destChainId,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable;

    /**
     * @notice Swaps tokens and creates a cross-chain order using Permit2 for token approvals
     * 
     * @param seed Unique identifier for the order
     * @param permitBatch The Permit2 batch transfer details
     * @param permitSignature The signature for the Permit2 transfer
     * @param target The contract address to execute the swap on
     * @param data The calldata for executing the swap
     * @param destChainId The destination chain ID for the cross-chain order
     * @param fee The fee to be paid for the cross-chain transaction
     * @param receiver The receiver address on the destination chain (in bytes32 format)
     * @param minAmountOut The minimum amount of tokens to receive on the destination chain
     * @param tokenOut The token to receive on the destination chain (in bytes32 format)
     */
    function swapAndCreateOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address target,
        bytes calldata data,
        uint256 destChainId,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable;

    /**
     * @notice Creates a cross-chain order directly with stablecoins using Permit2
     * 
     * @param seed Unique identifier for the order
     * @param permitBatch The Permit2 batch transfer details (must contain only STABLECOIN)
     * @param permitSignature The signature for the Permit2 transfer
     * @param destChainId The destination chain ID for the cross-chain order
     * @param fee The fee to be paid for the cross-chain transaction
     * @param receiver The receiver address on the destination chain (in bytes32 format)
     * @param minAmountOut The minimum amount of tokens to receive on the destination chain
     * @param tokenOut The token to receive on the destination chain (in bytes32 format)
     */
    function createOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        uint256 destChainId,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable;

    // =============================================================
    //                           VARIABLES
    // =============================================================

    /**
     * @notice The address of the Permit2 contract.
     * @return IAllowanceTransfer The Permit2 contract interface.
     */
    function PERMIT2() external view returns (IAllowanceTransfer);

    /**
     * @notice The address of the STABLECOIN token used in the protocol.
     * @return IERC20 The STABLECOIN token interface.
     */
    function STABLECOIN() external view returns (IERC20);
}
