// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {IGeniusGasTank} from "./interfaces/IGeniusGasTank.sol";
import {IGeniusMulticall} from "./interfaces/IGeniusMulticall.sol";

/**
 * @title GeniusGasTank
 * @author @altloot, @samuel_vdu
 *
 * @notice
 */
contract GeniusGasTank is IGeniusGasTank, AccessControl {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    IAllowanceTransfer public immutable PERMIT2;
    IGeniusMulticall public immutable MULTICALL;

    address payable private feeRecipient;
    mapping(address => bool) private allowedTargets;

    mapping(address => uint256) public nonces;

    constructor(
        address _admin,
        address payable _feeRecipient,
        address _permit2,
        address _multicall,
        address[] memory _allowedTargets
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _setFeeRecipient(_feeRecipient);
        PERMIT2 = IAllowanceTransfer(_permit2);
        MULTICALL = IGeniusMulticall(_multicall);

        for (uint256 i = 0; i < _allowedTargets.length; i++)
            _setAllowedTarget(_allowedTargets[i], true);
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

    function sponsorTransactions(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount,
        bytes calldata signature
    ) external payable override {
        _checkTargets(targets, permitBatch.details);

        bytes32 messageHash = keccak256(
            abi.encode(
                targets,
                data,
                values,
                permitBatch,
                nonces[owner],
                address(this)
            )
        );

        _verifySignature(messageHash, signature, owner);
        _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            owner,
            feeToken,
            feeAmount
        );

        MULTICALL.aggregateWithValues(targets, data, values);

        uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));

        if (feeTokenBalance < feeAmount)
            revert GeniusErrors.InsufficientFees(
                feeTokenBalance,
                feeAmount,
                feeToken
            );
        else {
            IERC20(feeToken).safeTransfer(feeRecipient, feeTokenBalance);
        }

        emit TransactionsSponsored(
            msg.sender,
            owner,
            feeToken,
            feeAmount,
            nonces[owner],
            targets.length
        );

        _sweepNative();
        nonces[owner]++;
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
     * @dev See {IGeniusGasTank-setAllowedTarget}.
     */
    function setAllowedTarget(
        address target,
        bool isAllowed
    ) external override onlyAdmin {
        _setAllowedTarget(target, isAllowed);
    }

    function _setFeeRecipient(address payable _feeRecipient) internal {
        if (_feeRecipient == address(0)) revert GeniusErrors.NonAddress0();
        feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(_feeRecipient);
    }

    function _setAllowedTarget(address target, bool isAllowed) internal {
        if (target == address(0)) revert GeniusErrors.InvalidTarget(target);
        allowedTargets[target] = isAllowed;
        emit AllowedTarget(target, isAllowed);
    }

    function _checkTargets(
        address[] memory targets,
        IAllowanceTransfer.PermitDetails[] memory tokenDetails
    ) internal view {
        for (uint256 i = 0; i < targets.length; i++) {
            address target = targets[i];
            if (!allowedTargets[target]) {
                bool isToken = false;

                for (uint256 j; j < tokenDetails.length; j++) {
                    if (target == tokenDetails[j].token) {
                        isToken = true;
                        break;
                    }
                }

                if (!isToken) revert GeniusErrors.InvalidTarget(target);
            }
        }
    }

    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount
    ) private {
        if (permitBatch.spender != address(this))
            revert GeniusErrors.InvalidSpender();

        PERMIT2.permit(owner, permitBatch, permitSignature);

        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                permitBatch.details.length
            );
        for (uint i; i < permitBatch.details.length; i++) {
            address toAddress = permitBatch.details[i].token == feeToken
                ? address(this)
                : address(MULTICALL);

            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: toAddress,
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });
        }

        PERMIT2.transferFrom(transferDetails);

        uint256 feeTokenBalance = IERC20(feeToken).balanceOf(address(this));
        IERC20(feeToken).safeTransfer(
            address(MULTICALL),
            feeTokenBalance - feeAmount
        );
    }

    function _verifySignature(
        bytes32 messageHash,
        bytes memory signature,
        address signer
    ) internal pure {
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recoveredSigner = ethSignedMessageHash.recover(signature);
        if (recoveredSigner != signer) {
            revert GeniusErrors.InvalidSignature();
        }
    }

    function _sweepNative() internal {
        uint256 nativeBalanceLeft = address(this).balance;
        if (nativeBalanceLeft > 0)
            feeRecipient.call{value: nativeBalanceLeft}("");
    }
}
