// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IGeniusVault } from "./interfaces/IGeniusVault.sol";
import { GeniusErrors } from "./libs/GeniusErrors.sol";
import { IGeniusExecutor } from "./interfaces/IGeniusExecutor.sol";

/**
 * @title GeniusExecutor
 * @author @altloot, @samuel_vdu
 * 
 * @notice The GeniusExecutor contract allows for the aggregation of multiple calls
 *         in a single transaction, as well as facilitating interactions with the GeniusVault contract.
 */
contract GeniusExecutor is IGeniusExecutor, ReentrancyGuard, AccessControl {
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IAllowanceTransfer public immutable override PERMIT2;
    IERC20 public immutable override STABLECOIN;
    IGeniusVault public immutable VAULT;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         VARIABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    mapping(address => uint256) private allowedTargets;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        CONSTRUCTOR                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    constructor(
        address permit2,
        address vault,
        address admin,
        address[] memory routers
    ) {
        PERMIT2 = IAllowanceTransfer(permit2);
        VAULT = IGeniusVault(vault);
        STABLECOIN = IERC20(VAULT.STABLECOIN());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        uint256 length = routers.length;
        for (uint256 i = 0; i < length;) {
            address router = routers[i];
            if (router == address(0)) revert GeniusErrors.InvalidRouter(router);
            setAllowedTarget(router, true);

            unchecked { ++i; }
        }
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        MODIFIERS                          ║
    // ╚═══════════════════════════════════════════════════════════╝

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert GeniusErrors.IsNotAdmin();
        _;
    }

    modifier onlyOrchestrator() {
        if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) revert GeniusErrors.IsNotOrchestrator();
        _;
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                AGGREGATED SWAP FUNCTIONS                  ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusExecutor-aggregateWithPermit2}.
     */
    function aggregateWithPermit2(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external override payable onlyOrchestrator nonReentrant {
        _checkNative(_sum(values));
        _checkTargets(targets, permitBatch.details, owner);

        if (msg.sender != owner) {
            if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) {
                revert GeniusErrors.IsNotOrchestrator();
            }
        }

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _batchExecution(targets, data, values);

        _sweepERC20s(permitBatch, owner);

        if (msg.value > 0) _sweepNative(msg.sender);
    }

    /**
     * @dev See {IGeniusExecutor-aggregate}.
     */
    function aggregate(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable override nonReentrant {
        IAllowanceTransfer.PermitDetails[] memory emptyPermitDetails = new IAllowanceTransfer.PermitDetails[](0);
        _checkTargets(targets, emptyPermitDetails, msg.sender);
        _checkNative(_sum(values));

        _batchExecution(targets, data, values);
        if (msg.value > 0) _sweepNative(msg.sender);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                MULTICHAIN SWAP FUNCTIONS                  ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusExecutor-tokenSwapAndDeposit}.
     */
    function tokenSwapAndDeposit(
        bytes32 seed,
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee,
        bytes32 receiver
    ) external override nonReentrant {
        if (permitBatch.details.length != 1)
            revert GeniusErrors.InvalidPermitBatchLength();

        address[] memory targets = new address[](1);
        targets[0] = target;
        _checkTargets(targets, permitBatch.details, owner);

        if (msg.sender != owner) {
            if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) {
                revert GeniusErrors.IsNotOrchestrator();
            }
        }

        _permitAndBatchTransfer(permitBatch, signature, owner);

        if (!IERC20(permitBatch.details[0].token).approve(target, permitBatch.details[0].amount)) revert GeniusErrors.ApprovalFailure(
            permitBatch.details[0].token,
            permitBatch.details[0].amount
        );

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        (bool _success, ) = target.call{value: 0}(data);
        if(!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

        uint256 _postStableValue = STABLECOIN.balanceOf(address(this));
        uint256 _depositAmount = _postStableValue > _initStableValue ? _postStableValue - _initStableValue : 0;

        if (_depositAmount == 0) revert GeniusErrors.UnexpectedBalanceChange(
            address(STABLECOIN),
            _initStableValue,
            _postStableValue
        );

        if (!STABLECOIN.approve(address(VAULT), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        VAULT.addLiquiditySwap(
            seed,
            owner,
            address(STABLECOIN),
            _depositAmount,
            destChainId,
            fillDeadline,
            fee,
            receiver
        );

        _sweepERC20s(permitBatch, owner);
    }

    /**
     * @dev See {IGeniusExecutor-multiSwapAndDeposit}.
     */
    function multiSwapAndDeposit(
        bytes32 seed,
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee,
        bytes32 receiver
    ) external payable override nonReentrant {
        if (targets.length != data.length || data.length != values.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        _checkNative(_sum(values));
        _checkTargets(targets, permitBatch.details, owner);

        if (msg.sender != owner) {
            if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) {
                revert GeniusErrors.IsNotOrchestrator();
            }
        }

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _batchExecution(targets, data, values);

        uint256 _postStableValue = STABLECOIN.balanceOf(address(this));
        uint256 _depositAmount = _postStableValue > _initStableValue ? _postStableValue - _initStableValue : 0;

        if (_depositAmount == 0) revert GeniusErrors.UnexpectedBalanceChange(
            address(STABLECOIN),
            _initStableValue,
            _postStableValue
        );

        if (!STABLECOIN.approve(address(VAULT), _depositAmount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), _depositAmount);

        VAULT.addLiquiditySwap(
            seed, 
            owner, 
            address(STABLECOIN), 
            _depositAmount, 
            destChainId, 
            fillDeadline, 
            fee,
            receiver
        );

        _sweepERC20s(permitBatch, owner);
        if (msg.value > 0) _sweepNative(msg.sender);
    }

    /**
     * @dev See {IGeniusExecutor-nativeSwapAndDeposit}.
     */
    function nativeSwapAndDeposit(
        bytes32 seed,
        address target,
        bytes calldata data,
        uint256 value,
        uint32 destChainId,
        uint32 fillDeadline,
        uint256 fee,
        bytes32 receiver
    ) external override payable {
        IAllowanceTransfer.PermitDetails[] memory emptyPermitDetails = new IAllowanceTransfer.PermitDetails[](0);
        address[] memory targets = new address[](1);
        targets[0] = target;

        _checkNative(value);
        _checkTargets(targets, emptyPermitDetails, msg.sender);

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));
        (bool _success, ) = target.call{value: value}(data);

        if (!_success) revert GeniusErrors.ExternalCallFailed(target, 0);

        uint256 _postStableValue = STABLECOIN.balanceOf(address(this));
        uint256 _depositAmount = _postStableValue > _initStableValue ? _postStableValue - _initStableValue : 0;

        if (_depositAmount == 0) revert GeniusErrors.UnexpectedBalanceChange(address(STABLECOIN), _initStableValue, _postStableValue);
        if (!STABLECOIN.approve(address(VAULT), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        VAULT.addLiquiditySwap(
            seed, 
            msg.sender, 
            address(STABLECOIN), 
            _depositAmount, 
            destChainId, 
            fillDeadline, 
            fee,
            receiver
        );

        if (msg.value > 0) _sweepNative(msg.sender);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                     STAKING FUNCTIONS                     ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusExecutor-depositToVault}.
     */
    function depositToVault(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external override onlyOrchestrator nonReentrant {
        if (permitBatch.details.length != 1) revert GeniusErrors.ArrayLengthsMismatch();
        if (permitBatch.details[0].token != address(STABLECOIN)) {
            revert GeniusErrors.InvalidToken(permitBatch.details[0].token);
        }

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _approveVault(permitBatch.details[0].amount);
        _depositToVault(owner, permitBatch.details[0].amount);
    }

    /**
     * @dev See {IGeniusExecutor-withdrawFromVault}.
     */
    function withdrawFromVault(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external override onlyOrchestrator nonReentrant {
        if (permitBatch.details[0].token != address(VAULT)) {
            revert GeniusErrors.InvalidToken(permitBatch.details[0].token);
        }

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _withdrawFromVault(owner, permitBatch.details[0].amount);

        uint256 _residBalance = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (_residBalance > 0) revert GeniusErrors.ResidualBalance(_residBalance);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      ADMIN FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusExecutor-setAllowedTarget}.
     */
    function setAllowedTarget(address target, bool isAllowed) public override onlyAdmin {
        allowedTargets[target] = isAllowed ? 1 : 0;
        emit AllowedTarget(target, isAllowed);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                   INTERNAL FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Transfers ERC20 tokens to a specified address.
     * @param token The address of the token to be transferred.
     * @param to The address to which the tokens will be transferred.
     * @param amount The amount of tokens to be transferred.
     */
    function _transferERC20(
        address token,
        address to,
        uint256 amount
    ) internal {
        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @dev Checks if the targets are allowed to be called.
     * @param targets The addresses of the targets to be checked.
     * @param tokenDetails The details of the tokens to be checked.
     * @param owner The address of the owner of the tokens.
     */
    function _checkTargets(
        address[] memory targets,
        IAllowanceTransfer.PermitDetails[] memory tokenDetails,
        address owner
    ) internal view {
        uint256 targetsLength = targets.length;
        uint256 tokenDetailsLength = tokenDetails.length;

        for (uint256 i; i < targetsLength;) {
            address target = targets[i];

            if (allowedTargets[target] == 0 && target != owner && target != address(STABLECOIN)) {
                if (tokenDetailsLength == 0) {
                    revert GeniusErrors.InvalidTarget(target);
                }

                uint256 isValid;
                for (uint256 j; j < tokenDetailsLength;) {
                    if (target == tokenDetails[j].token) {
                        isValid = 1;
                        break;
                    }

                    unchecked { ++j; }
                }
                if (isValid == 0) {
                    revert GeniusErrors.InvalidTarget(target);
                }
            }

            unchecked { ++i; }
        }
    }

    /**
     * @dev Checks if the amount of native tokens sent is correct.
     * @param amount The amount of native tokens expected.
     */
    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
    }

    /**
     * @dev Sums the amounts in an array.
     * @param amounts The array of amounts to be summed.
     */
    function _sum(uint256[] calldata amounts) internal pure returns (uint256 total) {
        for (uint i; i < amounts.length;) {
            total += amounts[i];

            unchecked { i++; }
        }
    }

    /**
     * @dev Sweeps ERC20 tokens to the owner.
     * @param permitBatch The permit batch details.
     * @param owner The address of the owner of the tokens.
     */
    function _sweepERC20s(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        address owner
    ) internal {
        for (uint i; i < permitBatch.details.length;) {
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
     * @dev Sweeps native tokens to the receiver.
     * @param receiver The address of the receiver of the native tokens.
     */
    function _sweepNative(address receiver) internal {
        uint256 _balance = address(this).balance;

        if (_balance > 0) {
            if (!payable(receiver).send(_balance)) revert GeniusErrors.TransferFailed(address(0), address(this).balance);
        }
    }

    /**
     * @dev Permits and transfers tokens from the owner to the contract.
     * @param permitBatch The permit batch details.
     * @param signature The signature of the permit.
     * @param owner The address of the owner of the tokens.
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) private {
        if (permitBatch.spender != address(this)) {
            revert GeniusErrors.InvalidSpender();
        }
        PERMIT2.permit(owner, permitBatch, signature);

        IAllowanceTransfer.AllowanceTransferDetails[] memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
            permitBatch.details.length
        );
        for (uint i; i < permitBatch.details.length; ) {
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
     * @dev Executes a batch of calls.
     * @param targets The addresses of the targets to be called.
     * @param data The calldata to be used when executing the calls.
     * @param values The values to be sent with the calls.
     */
    function _batchExecution(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) private {
        for (uint i; i < targets.length;) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success) revert GeniusErrors.ExternalCallFailed(targets[i], i);

            unchecked { i++; }
        }
    }

    /**
     * @dev Approves the routers to spend the tokens.
     * @param routers The addresses of the routers to be approved.
     * @param permitBatch The permit batch details.
     */
    function _approveRouters(
        address[] calldata routers,
        IAllowanceTransfer.PermitBatch calldata permitBatch
    ) private {
        for (uint i; i < permitBatch.details.length;) {
            IERC20 tokenToApprove = IERC20(permitBatch.details[i].token);
            uint256 amountToApprove = permitBatch.details[i].amount;

            if (!tokenToApprove.approve(routers[i], amountToApprove)) revert GeniusErrors.ApprovalFailure(permitBatch.details[i].token, amountToApprove);

            unchecked { i++; }
        }
    }

    /**
     * @dev Approves the vault to spend the tokens.
     * @param amount The amount of tokens to be approved.
     */
    function _approveVault(uint256 amount) private {
        if (!STABLECOIN.approve(address(VAULT), amount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), amount);
    }

    /**
     * @dev Deposits tokens to the vault.
     * @param receiver The address of the receiver of the tokens.
     * @param amount The amount of tokens to be deposited.
     */
    function _depositToVault(address receiver, uint256 amount) private {
        VAULT.stakeDeposit(amount, receiver);
    }

    /**
     * @dev Withdraws tokens from the vault.
     * @param receiver The address of the receiver of the tokens.
     * @param amount The amount of tokens to be withdrawn.
     */
    function _withdrawFromVault(address receiver, uint256 amount) private {
        VAULT.stakeWithdraw(amount, receiver, address(this));
    }

    /**
     * @dev Fallback function to prevent native tokens from being sent directly.
     */
    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}