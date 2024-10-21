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
    function swapAndCreateOrderDynamicDeadline(
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

    function swapAndCreateOrderPermit2DynamicDeadline(
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

    function swapAndCreateOrder(
        bytes32 seed,
        address[] calldata tokensIn,
        uint256[] calldata amountsIn,
        address target,
        bytes calldata data,
        address owner,
        uint256 destChainId,
        uint256 fillDeadline,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable;

    function swapAndCreateOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address target,
        bytes calldata data,
        uint256 destChainId,
        uint256 fillDeadline,
        uint256 fee,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) external payable;

    function createOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        uint256 destChainId,
        uint256 fillDeadline,
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
