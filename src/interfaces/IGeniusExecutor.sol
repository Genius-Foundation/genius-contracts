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
 *         in a single transaction. Additionally, this interface allows
 *         for the aggregation of multiple token transfers and permits
 *         utilizing the Permit2 contract, as well facilitating interactions
 *         with the GeniusVault contract and the GeniusPool contract.
 */
interface IGeniusExecutor {
    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    function initialize(address[] calldata routers) external;

    /**
     * @dev Sets the allowed status for a target address.
     * @param target The address to set the allowed status for.
     * @param isAllowed The allowed status to set. True for allowed, false for not allowed.
     */
    function setAllowedTarget(address target, bool isAllowed) external;

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
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable;

    /**
     * @dev Executes a batch of calls to external contracts with the sender's address.
     * @param targets The array of target contract addresses to call.
     * @param data The array of calldata for each call.
     * @param values The array of ETH values to send with each call.
     *
     * @dev This function only allows native tokens to be sent with the transaction. Additionally,
     *       The only valid targets are allowedTargets (protocol approved routers) and the msg.sender.
     */
    function aggregate(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable;

    /**
     * @dev Aggregates multiple calls in a single transaction.
     *      This method will set `sender` to the `msg.sender` temporarily
     *      for the span of its execution.
     *      This method does not support reentrancy.
     * @param target An array of addresses to call.
     * @param data    An array of calldata to forward to the targets.
     * @param permitBatch The permit information for batch transfer.
     * @param signature The signature for the permit.
     * @param owner The address of the trader to deposit for.
     */
    function tokenSwapAndDeposit(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external;

    /**
     * @dev Executes multiple swaps and deposits in a single transaction.
     * @param targets The array of target addresses to call.
     * @param data The array of data to pass to each target address.
     * @param values The array of values to send to each target address.
     * @param permitBatch The permit batch containing permit details for token transfers.
     * @param signature The signature for the permit batch.
     *
     */
    function multiSwapAndDeposit(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable;

    /**
    * @dev Simplified function to perform a single swap and then deposit stablecoins to a vault.
    * @param target The address to call.
    * @param data The calldata to forward to the target.
    * @param value How much ETH to forward to the target.
    */
    function nativeSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value
    ) external payable;

    /**
     * @dev Deposits a specified amount of tokens to the vault.
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
     * @dev Withdraws a specified amount of STABLECOIN from the vault.
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
    function isInitialized() external view returns (uint256);
    function PERMIT2() external view returns (IAllowanceTransfer);
    function STABLECOIN() external view returns (IERC20);
    function POOL() external view returns (IGeniusPool);
    function VAULT() external view returns (IERC4626);
}