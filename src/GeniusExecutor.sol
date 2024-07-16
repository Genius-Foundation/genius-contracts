// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;


import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";

import { GeniusPool } from "./GeniusPool.sol";
import { GeniusVault } from "./GeniusVault.sol";
import { GeniusErrors } from "./libs/GeniusErrors.sol";
import { Orchestrable, Ownable } from "./access/Orchestrable.sol";

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
contract GeniusExecutor is Orchestrable, ReentrancyGuard {

    // =============================================================
    //                           VARIABLES
    // =============================================================
    uint256 public isInitialized = 0;
    address[] public allowedTargets;
    mapping(address => uint256) public isAllowedTarget;

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    IAllowanceTransfer public immutable PERMIT2;
    IERC20 public immutable STABLECOIN;
    GeniusPool public immutable POOL;
    GeniusVault public immutable VAULT;

    constructor(
        address permit2,
        address pool,
        address vault,
        address owner
    ) Ownable(owner) {

        PERMIT2 = IAllowanceTransfer(permit2);
        VAULT = GeniusVault(vault);
        POOL = GeniusPool(pool);
        STABLECOIN = IERC20(POOL.STABLECOIN());

    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    function initialize(address[] calldata routers) external onlyOwner {
        uint256 length = routers.length;
        for (uint256 i = 0; i < length;) {
            address router = routers[i];
            if (router == address(0)) revert GeniusErrors.InvalidRouter(router);
            if (isAllowedTarget[router] == 0) revert GeniusErrors.DuplicateRouter(router);
            
            isAllowedTarget[router] = 1;
            allowedTargets.push(router);

            unchecked { ++i; }
        }

        isInitialized = 1;
    }

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
    ) external payable nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        _checkNative(_sum(values));
        _checkTargets(targets);

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _batchExecution(targets, data, values);

        _sweepERC20s(permitBatch, owner);
        _sweepNative();
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
    ) external payable nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        _checkNative(_sum(values));
        _checkTargets(targets);

        _batchExecution(targets, data, values);
        _sweepNative();
    }

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
    ) external onlyOrchestrator nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        if (permitBatch.details.length != 1) revert GeniusErrors.InvalidPermitBatchLength();

        address[] memory targets = new address[](1);
        targets[0] = target;
        _checkTargets(targets);

        _permitAndBatchTransfer(permitBatch, signature, owner);

        IERC20 tokenToSwap = IERC20(permitBatch.details[0].token);

        if (!tokenToSwap.approve(target, permitBatch.details[0].amount)) revert GeniusErrors.ApprovalFailure(
            permitBatch.details[0].token,
            permitBatch.details[0].amount
        );

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        (bool _success, ) = target.call{value: 0}(data);
        if(!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount);

        _sweepERC20s(permitBatch, owner);
    }


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
        address[] calldata routers,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external payable nonReentrant {
        if (
            targets.length != data.length ||
            data.length != values.length ||
            routers.length != permitBatch.details.length
        ) revert GeniusErrors.ArrayLengthsMismatch();
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();

        _checkNative(_sum(values));
        _checkTargets(targets);
        
        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveRouters(routers, permitBatch);
        _batchExecution(targets, data, values);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), _depositAmount);

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount);

        _sweepERC20s(permitBatch, owner);
        _sweepNative();
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
    ) external payable nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        address[] memory targets = new address[](1);
        targets[0] = target;
        _checkNative(value);
        _checkTargets(targets);

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        (bool _success, ) = target.call{value: value}(data);

        if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

        uint256 _depositAmount = STABLECOIN.balanceOf(address(this)) - _initStableValue;
        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        POOL.addLiquiditySwap(trader, address(STABLECOIN), _depositAmount);

        _sweepNative();
    }

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
    ) external onlyOrchestrator nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        require(permitBatch.details.length == 1, "Invalid permit batch length");
        if (permitBatch.details[0].token != address(STABLECOIN)) {
            revert GeniusErrors.InvalidToken(permitBatch.details[0].token);
        }

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveVault(permitBatch.details[0].amount);
        _depositToVault(owner, permitBatch.details[0].amount);
    }

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
    ) external onlyOrchestrator nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        if (permitBatch.details[0].token != address(VAULT)) {
            revert GeniusErrors.InvalidToken(permitBatch.details[0].token);
        }

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveVault(permitBatch.details[0].amount);
        _withdrawFromVault(owner, permitBatch.details[0].amount);

        uint256 _residBalance = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (_residBalance > 0) revert GeniusErrors.ResidualBalance(_residBalance);
    }
    
    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev Checks if the given targets are valid for generic execution.
     * @param targets The array of addresses representing the targets to be checked.
     * @notice This function reverts if any of the targets is equal to the address of the POOL or VAULT contracts.
     */
    function _checkTargets(address[] memory targets) internal view {
        for (uint i = 0; i < targets.length;) {
            
            if (targets[i] == address(POOL) || targets[i] == address(VAULT)) {
                /**
                 * The GeniusPool and GeniusMultiTokenPool contracts are not allowed as targets
                 * as they implement the Executable access control, which only allows the
                 * `msg.sender` to be the GeniusExecutor contract, and not the orchestrator.
                 */
                revert GeniusErrors.InvalidTarget(targets[i]);
            }

            if (isAllowedTarget[targets[i]] == 0) {
                    /**
                     * Attempt to cast the target address to an ERC20 token
                     */
                try IERC20(targets[i]).totalSupply() {
                    /**
                     * If the cast succeeds, it's an ERC20 token
                     * and is allowed to be targeted. This is to allow for
                     * approvals and transfers.
                     */

                } catch {
                    /**
                     * If the cast fails, it's not an ERC20 token and should
                     * not be allowed to avoid malicious contract interactions
                     */
                    revert GeniusErrors.InvalidTarget(targets[i]);
                }
            }

            unchecked { ++i; }
        }
    }

    /**
     * @dev Checks if the native currency sent with the transaction is equal to the specified amount.
     * @param amount The expected amount of native currency.
     */
    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
    }

    /**
     * @dev Calculates the sum of an array of uint256 values.
     * @param amounts An array of uint256 values.
     * @return total sum of the array elements.
     */
    function _sum(uint256[] calldata amounts) internal pure returns (uint256 total) {
        for (uint i = 0; i < amounts.length;) {
            total += amounts[i];

            unchecked { i++; }
        }
    }

    /**
     * @dev Internal function to sweep all left over tokens to the owner.
     * @param permitBatch The permit batch containing details of tokens to be swept.
     */
    function _sweepERC20s(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        address owner
    ) internal {
        // Sweep all left over tokens to the owner
        for (uint i = 0; i < permitBatch.details.length;) {
            IERC20 token = IERC20(permitBatch.details[i].token);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) {
                uint256 _delta = balance > permitBatch.details[i].amount ? balance - permitBatch.details[i].amount : 0;
                
                if (_delta > 0) {
                    if (!token.transfer(owner, _delta)) revert GeniusErrors.TransferFailed(address(token), _delta);
                }
            }

            unchecked { i++; }
        }
    }

    /**
     * @dev Internal function to sweep native tokens from the contract.
     * If the contract balance is greater than zero, it transfers the balance to the `msg.sender`.
     * If the transfer fails, it reverts with a `TransferFailed` error.
     */
    function _sweepNative() internal {
        if (address(this).balance > 0) {
            if (!payable(msg.sender).send(address(this).balance)) revert GeniusErrors.TransferFailed(address(0), address(this).balance);
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

    /**
     * @dev Fallback function to reject native tokens.
     * Reverts the transaction with an error message indicating that native tokens are not accepted.
     */
    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}