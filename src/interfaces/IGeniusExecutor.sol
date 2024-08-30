// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { IGeniusPool } from "./IGeniusPool.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/**
 * @title IGeniusExecutor
 * @author looter
 * 
 * @notice Interface for efficient aggregation of multiple calls
 *         in a single transaction. This interface allows for the aggregation
 *         of multiple token transfers and permits utilizing the Permit2 contract,
 *         as well as facilitating interactions with the GeniusVault contract
 *         and the GeniusPool contract.
 */
interface IGeniusExecutor {
    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Initializes the contract with a list of allowed router addresses.
     * @param routers An array of router addresses to be set as allowed targets.
     * @dev This function can only be called by the contract owner.
     */
    function initialize(address[] calldata routers) external;

    /**
     * @notice Sets the allowed status for a target address.
     * @param target The address to set the allowed status for.
     * @param isAllowed The allowed status to set. True for allowed, false for not allowed.
     * @dev This function can only be called by the contract owner.
     */
    function setAllowedTarget(address target, bool isAllowed) external;

    /**
     * @notice Aggregates multiple calls in a single transaction with Permit2 integration.
     * @param targets An array of addresses to call.
     * @param data An array of calldata to forward to the targets.
     * @param values How much ETH to forward to each target.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader/owner to aggregate calls for.
     * @dev This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution. This method does not support reentrancy.
     */
    function aggregateWithPermit2(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable;

    /**
     * @notice Executes a batch of calls to external contracts with the sender's address.
     * @param targets The array of target contract addresses to call.
     * @param data The array of calldata for each call.
     * @param values The array of ETH values to send with each call.
     * @dev The only valid targets are allowedTargets (protocol approved routers) and the msg.sender.
     */
    function aggregate(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable;

    /**
     * @notice Executes a token swap and deposits the result into the GeniusPool.
     * @param target The address of the swap router to call.
     * @param data The calldata to forward to the target.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to deposit for.
     * @param destChainId The destination chain ID for the liquidity.
     * @param fillDeadline The deadline for filling the liquidity request.
     * @dev This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution. This method does not support reentrancy.
     */
    function tokenSwapAndDeposit(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner,
        uint16 destChainId,
        uint32 fillDeadline
    ) external;

    /**
     * @notice Executes multiple swaps and deposits in a single transaction.
     * @param targets The array of target addresses to call.
     * @param data The array of data to pass to each target address.
     * @param values The array of values to send to each target address.
     * @param permitBatch The permit batch containing permit details for token transfers.
     * @param signature The signature for the permit batch.
     * @param owner The address of the trader to deposit for.
     * @param destChainId The destination chain ID for the liquidity.
     * @param fillDeadline The deadline for filling the liquidity request.
     */
    function multiSwapAndDeposit(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner,
        uint16 destChainId,
        uint32 fillDeadline
    ) external payable;

    /**
     * @notice Simplified function to perform a single swap with native tokens and then deposit stablecoins to the GeniusPool.
     * @param target The address of the swap router to call.
     * @param data The calldata to forward to the target.
     * @param value How much ETH to forward to the target.
     * @param destChainId The destination chain ID for the liquidity.
     * @param fillDeadline The deadline for filling the liquidity request.
     */
    function nativeSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value,
        uint16 destChainId,
        uint32 fillDeadline
    ) external payable;

    /**
     * @notice Deposits a specified amount of tokens to the GeniusVault.
     * @param permitBatch The permit batch data for permit approvals and transfers.
     * @param signature The signature for permit approvals.
     * @param owner The address of the owner of the tokens.
     */
    function depositToVault(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external;

    /**
     * @notice Withdraws a specified amount of STABLECOIN from the GeniusVault.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to withdraw for.
     */
    function withdrawFromVault(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external;

    // =============================================================
    //                           VARIABLES
    // =============================================================
    
    /**
     * @notice Returns whether the contract has been initialized.
     * @return 1 if initialized, 0 otherwise.
     */
    function isInitialized() external view returns (uint256);

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

    /**
     * @notice The address of the GeniusPool contract.
     * @return IGeniusPool The GeniusPool contract interface.
     */
    function POOL() external view returns (IGeniusPool);

    /**
     * @notice The address of the GeniusVault contract.
     * @return IERC4626 The GeniusVault contract interface (ERC4626).
     */
    function VAULT() external view returns (IERC4626);
}