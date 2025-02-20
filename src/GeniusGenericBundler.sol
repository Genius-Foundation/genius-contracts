// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {IGeniusGenericBundler} from "./interfaces/IGeniusGenericBundler.sol";
import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";

/**
 * @title GeniusGasTank
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusGenericBundler contract handles aggregated transactions using Permit2
 *         Differs from the GeniusGasTank as it does not forward the transaction or tokens
 *         to the proxy call contract, but instead executes the transaction directly. 
 *         This is useful when handling ERC20 tokens that have transfer taxes.
 */
contract GeniusGenericBundler is IGeniusGenericBundler, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    IAllowanceTransfer public immutable PERMIT2;

    address payable private feeRecipient;

    constructor(
        address _admin,
        address payable _feeRecipient,
        address _permit2
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _setFeeRecipient(_feeRecipient);
        PERMIT2 = IAllowanceTransfer(_permit2);
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert GeniusErrors.IsNotAdmin();
        _;
    }

    modifier onlyPauser() {
        if (!hasRole(PAUSER_ROLE, msg.sender))
            revert GeniusErrors.IsNotPauser();
        _;
    }

    /**
     * @dev See {IGeniusGenericBundler-aggregateWithPermit2}.
     */
    function aggregateWithPermit2(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address feeToken,
        uint256 feeAmount,
        address toApprove
    ) external payable override whenNotPaused {
        if (target == address(0)) revert GeniusErrors.NonAddress0();

        _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            msg.sender,
            feeToken,
            feeAmount
        );

        _approveTarget(toApprove, feeToken, type(uint256).max);
        _execute(target, data);

        for (uint i; i < permitBatch.details.length; ++i) {
            address token = permitBatch.details[i].token;
            _sweepERC20(token, msg.sender);
            _removeAllowance(token, address(this));
        }
    }

    /**
     * @dev See {IGeniusGasTank-setFeeRecipient}.
     */
    function setFeeRecipient(
        address payable _feeRecipient
    ) external override onlyAdmin {
        _setFeeRecipient(_feeRecipient);
    }

    /**
     * @dev See {IGeniusGasTank-pause}.
     */
    function pause() external override onlyPauser {
        _pause();
    }

    /**
     * @dev See {IGeniusGasTank-unpause}.
     */
    function unpause() external override onlyAdmin {
        _unpause();
    }

    /**
     * @dev internal function to set the fee recipient address
     *
     * @param _feeRecipient The new fee recipient address
     */
    function _setFeeRecipient(address payable _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert GeniusErrors.NonAddress0();
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    /**
     * @dev internal function to permit and batch transfer tokens
     *
     * @param permitBatch the permit batch details
     * @param permitSignature the signature for the Permit2 transfer
     * @param owner the owner of the tokens being transferred
     * @param feeToken the token used to pay the fee
     * @param feeAmount the amount of fee to be paid
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount
    ) private returns (address[] memory tokensIn) {
        if (permitBatch.spender != address(this))
            revert GeniusErrors.InvalidSpender();

        if (msg.sender != owner) revert GeniusErrors.InvalidTrader();

        tokensIn = new address[](permitBatch.details.length);

        PERMIT2.permit(owner, permitBatch, permitSignature);

        uint256 detailsLength = permitBatch.details.length;
        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                detailsLength
            );
        for (uint i; i < detailsLength; ++i) {
            tokensIn[i] = permitBatch.details[i].token;

            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to:  address(this),
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });
        }

        PERMIT2.transferFrom(transferDetails);

        uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));

        if (feeTokenBalance < feeAmount) {
            revert GeniusErrors.InsufficientBalance(
                feeToken,
                feeAmount,
                feeTokenBalance
            );
        }

        // Transfer the fee to the fee recipient
        IERC20(feeToken).safeTransfer(feeRecipient, feeAmount);
    }

    /**
     * @notice Approves a target to spend a token
     * 
     * @param target The target to approve
     * @param token The token to approve
     * @param amount The amount to approve
     */
    function _approveTarget(address target, address token, uint256 amount) private {
        if (token == address(0)) revert GeniusErrors.NonAddress0();

        if (amount > 0) {
            IERC20(token).approve(target, amount);
        } else {
            revert GeniusErrors.InvalidAmount();
        }
    }

    /**
     * @notice Removes the allowance for a spender
     *
     * @param token The token to remove the allowance for
     * @param spender The spender to remove the allowance for
     */
    function _removeAllowance(address token, address spender) private {
        IERC20(token).approve(spender, 0);
    }

    /**
     * @notice Executes a transaction on a contract
     *
     * @param target The contract to execute the call on
     * @param data The calldata to execute
     */
    function _execute(address target, bytes calldata data) private {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();

        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target);
    }

    /**
     * @notice Sweep ERC20 tokens from the contract to the owner
     *
     * @param token The ERC20 token to sweep
     * @param owner The address to send the tokens to
     */
    function _sweepERC20(address token, address owner) private {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).safeTransfer(owner, balance);
        }
    }

    /**
     * @notice Checks if an address is a contract.
     *
     * @param _addr The address to check if it is a contract.
     */
    function _isContract(address _addr) private view returns (bool hasCode) {
        uint256 length;
        assembly {
            length := extcodesize(_addr)
        }
        return length != 0;
    }
}
