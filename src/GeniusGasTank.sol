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

import {IGeniusGasTank} from "./interfaces/IGeniusGasTank.sol";
import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";

/**
 * @title GeniusGasTank
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusGasTank contract that handles sponsored transactions using Permit2
 */
contract GeniusGasTank is IGeniusGasTank, AccessControl, Pausable {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    IAllowanceTransfer public immutable PERMIT2;
    IGeniusProxyCall public immutable PROXYCALL;

    address payable private feeRecipient;

    mapping(address => uint256) public nonces;
    mapping(address => mapping(bytes32 => bool)) public seeds;

    constructor(
        address _admin,
        address payable _feeRecipient,
        address _permit2,
        address _multicall
    ) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _setFeeRecipient(_feeRecipient);
        PERMIT2 = IAllowanceTransfer(_permit2);
        PROXYCALL = IGeniusProxyCall(_multicall);
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
     * @dev See {IGeniusGasTank-sponsorOrderedTransactions}.
     */
    function sponsorOrderedTransactions(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        bytes calldata signature
    ) external payable override whenNotPaused {
        if (deadline < block.timestamp)
            revert GeniusErrors.DeadlinePassed(deadline);

        bytes32 messageHash = keccak256(
            abi.encode(
                block.chainid,
                target,
                data,
                permitBatch,
                nonces[owner],
                feeToken,
                feeAmount,
                deadline,
                address(this)
            )
        );

        _verifySignature(messageHash, signature, owner);

        uint256 currentNonce = nonces[owner];
        nonces[owner]++;

        address[] memory tokensIn = _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            owner,
            feeToken,
            feeAmount
        );
        IERC20(feeToken).safeTransfer(feeRecipient, feeAmount);

        if (target == address(PROXYCALL))
            PROXYCALL.execute{value: msg.value}(target, data);
        else {
            PROXYCALL.approveTokensAndExecute{value: msg.value}(
                tokensIn,
                target,
                data
            );
        }

        emit OrderedTransactionsSponsored(
            msg.sender,
            owner,
            target,
            feeToken,
            feeAmount,
            currentNonce
        );
    }

    /**
     * @dev See {IGeniusGasTank-sponsorUnorderedTransactions}.
     */
    function sponsorUnorderedTransactions(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address feeToken,
        uint256 feeAmount,
        uint256 deadline,
        bytes32 seed,
        bytes calldata signature
    ) external payable override whenNotPaused {
        if (deadline < block.timestamp)
            revert GeniusErrors.DeadlinePassed(deadline);
        if (seeds[owner][seed]) revert GeniusErrors.InvalidSeed();

        bytes32 messageHash = keccak256(
            abi.encode(
                block.chainid,
                target,
                data,
                permitBatch,
                seed,
                feeToken,
                feeAmount,
                deadline,
                address(this)
            )
        );
        _verifySignature(messageHash, signature, owner);

        seeds[owner][seed] = true;
        address[] memory tokensIn = _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            owner,
            feeToken,
            feeAmount
        );
        IERC20(feeToken).safeTransfer(feeRecipient, feeAmount);

        if (target == address(PROXYCALL))
            PROXYCALL.execute{value: msg.value}(target, data);
        else {
            PROXYCALL.approveTokensAndExecute{value: msg.value}(
                tokensIn,
                target,
                data
            );
        }

        emit UnorderedTransactionsSponsored(
            msg.sender,
            owner,
            target,
            feeToken,
            feeAmount,
            seed
        );
    }

    /**
     * @dev See {IGeniusGasTank-aggregateWithPermit2}.
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

        address[] memory tokensIn = _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            msg.sender,
            feeToken,
            feeAmount
        );
        IERC20(feeToken).safeTransfer(feeRecipient, feeAmount);

        if (target == address(PROXYCALL)) {
            PROXYCALL.execute{value: msg.value}(target, data);
        } else {
            PROXYCALL.approveAddressAndExecute{value: msg.value}(
                tokensIn,
                target,
                data,
                toApprove
            );
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
     * @dev See {IGeniusGasTank-setProxyCall}.
     */
    function setProxyCall(address _proxyCall) external override onlyAdmin {
        _setProxyCall(_proxyCall);
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
     * @dev internal function to set the proxy call contract address
     *
     * @param _proxyCall The new proxy call contract address
     */
    function _setProxyCall(address _proxyCall) internal {
        if (_proxyCall == address(0)) revert GeniusErrors.NonAddress0();

        _grantRole(PAUSER_ROLE, _proxyCall);
        emit ProxyCallChanged(_proxyCall);
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
        tokensIn = new address[](permitBatch.details.length);

        PERMIT2.permit(owner, permitBatch, permitSignature);

        uint256 detailsLength = permitBatch.details.length;
        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                detailsLength
            );
        for (uint i; i < detailsLength; ++i) {
            tokensIn[i] = permitBatch.details[i].token;
            address toAddress = permitBatch.details[i].token == feeToken
                ? address(this)
                : address(PROXYCALL);

            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: toAddress,
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

        IERC20(feeToken).safeTransfer(
            address(PROXYCALL),
            feeTokenBalance - feeAmount
        );
    }

    /**
     * @dev internal function to verify the signature
     *
     * @param messageHash the hash of the message
     * @param signature the signature to verify
     * @param signer the signer of the message
     */
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
}
