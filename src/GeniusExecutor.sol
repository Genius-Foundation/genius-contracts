// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { IAllowanceTransfer } from "permit2/interfaces/IAllowanceTransfer.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { IGeniusPool } from "./interfaces/IGeniusPool.sol";
import { IERC4626 } from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import { GeniusErrors } from "./libs/GeniusErrors.sol";
import { IGeniusExecutor } from "./interfaces/IGeniusExecutor.sol";

/**
 * @title GeniusExecutor
 * @author @altloot, @samuel_vdu
 * 
 * @notice The GeniusExecutor contract is a contract that allows for the aggregation of multiple calls
 *         in a single transaction, as well as facilitating interactions with the GeniusPool contract
 *         and the GeniusVault contract.
 */
contract GeniusExecutor is IGeniusExecutor, ReentrancyGuard, AccessControl {
    // =============================================================
    //                           VARIABLES
    // =============================================================
    uint256 public override isInitialized;
    mapping(address => uint256) private allowedTargets;

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    IAllowanceTransfer public immutable override PERMIT2;
    IERC20 public immutable override STABLECOIN;
    IGeniusPool public immutable override POOL;
    IERC4626 public immutable override VAULT;

    constructor(
        address permit2,
        address pool,
        address vault,
        address admin
    ) {
        PERMIT2 = IAllowanceTransfer(permit2);
        VAULT = IERC4626(vault);
        POOL = IGeniusPool(pool);
        STABLECOIN = IERC20(POOL.STABLECOIN());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert GeniusErrors.IsNotAdmin();
        _;
    }

    modifier onlyOrchestrator() {
        if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) revert GeniusErrors.IsNotOrchestrator();
        _;
    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @dev See {IGeniusExecutor-initialize}.
     */
    function initialize(address[] calldata routers) external override onlyAdmin {
        uint256 length = routers.length;
        for (uint256 i = 0; i < length;) {
            address router = routers[i];
            if (router == address(0)) revert GeniusErrors.InvalidRouter(router);
            if (allowedTargets[router] == 1) revert GeniusErrors.DuplicateRouter(router);

            allowedTargets[router] = 1;

            unchecked { ++i; }
        }

        isInitialized = 1;
    }

    /**
     * @dev See {IGeniusExecutor-setAllowedTarget}.
     */
    function setAllowedTarget(address target, bool isAllowed) external override onlyAdmin {
        allowedTargets[target] = isAllowed ? 1 : 0;
    }

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
    ) external override payable nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        _checkNative(_sum(values));
        _checkTargets(targets, permitBatch.details, owner);

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
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();        
        IAllowanceTransfer.PermitDetails[] memory emptyPermitDetails = new IAllowanceTransfer.PermitDetails[](0);
        _checkTargets(targets, emptyPermitDetails, msg.sender);
        _checkNative(_sum(values));

        _batchExecution(targets, data, values);
        if (msg.value > 0) _sweepNative(msg.sender);
    }

    /**
     * @dev See {IGeniusExecutor-tokenSwapAndDeposit}.
     */
    function tokenSwapAndDeposit(
        address target,
        bytes calldata data,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner,
        uint16 destChainId,
        uint32 fillDeadline
    ) external override onlyOrchestrator nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        if (permitBatch.details.length != 1) revert GeniusErrors.InvalidPermitBatchLength();

        address[] memory targets = new address[](1);
        targets[0] = target;
        _checkTargets(targets, permitBatch.details, owner);

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

        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount, destChainId, fillDeadline);

        _sweepERC20s(permitBatch, owner);
    }

    /**
     * @dev See {IGeniusExecutor-multiSwapAndDeposit}.
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
    ) external override payable nonReentrant {
        if (
            targets.length != data.length ||
            data.length != values.length
        ) revert GeniusErrors.ArrayLengthsMismatch();
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();

        _checkNative(_sum(values));
        _checkTargets(targets, permitBatch.details, owner);

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

        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), _depositAmount);

        POOL.addLiquiditySwap(owner, address(STABLECOIN), _depositAmount, destChainId, fillDeadline);

        _sweepERC20s(permitBatch, owner);
        if (msg.value > 0) _sweepNative(msg.sender);
    }

    /**
     * @dev See {IGeniusExecutor-nativeSwapAndDeposit}.
     */
    function nativeSwapAndDeposit(
        address target,
        bytes calldata data,
        uint256 value,
        uint16 destChainId,
        uint32 fillDeadline
    ) external override payable {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();

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
        if (!STABLECOIN.approve(address(POOL), _depositAmount)) revert GeniusErrors.ApprovalFailure(
            address(STABLECOIN),
            _depositAmount
        );

        POOL.addLiquiditySwap(msg.sender, address(STABLECOIN), _depositAmount, destChainId, fillDeadline);

        if (msg.value > 0) _sweepNative(msg.sender);
    }

    /**
     * @dev See {IGeniusExecutor-depositToVault}.
     */
    function depositToVault(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata signature,
        address owner
    ) external override onlyOrchestrator nonReentrant {
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
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
        if (isInitialized == 0) revert GeniusErrors.NotInitialized();
        if (permitBatch.details[0].token != address(VAULT)) {
            revert GeniusErrors.InvalidToken(permitBatch.details[0].token);
        }

        uint256 _initStableValue = STABLECOIN.balanceOf(address(this));

        _permitAndBatchTransfer(permitBatch, signature, owner);
        _withdrawFromVault(owner, permitBatch.details[0].amount);

        uint256 _residBalance = STABLECOIN.balanceOf(address(this)) - _initStableValue;

        if (_residBalance > 0) revert GeniusErrors.ResidualBalance(_residBalance);
    }

    // =============================================================
    //                      INTERNAL FUNCTIONS
    // =============================================================

    function _checkTargets(
        address[] memory targets,
        IAllowanceTransfer.PermitDetails[] memory tokenDetails,
        address owner
    ) internal view {
        uint256 targetsLength = targets.length;
        uint256 tokenDetailsLength = tokenDetails.length;

        for (uint256 i; i < targetsLength;) {
            address target = targets[i];

            if (target == address(POOL) || target == address(VAULT)) {

                if (!hasRole(ORCHESTRATOR_ROLE, msg.sender)) {
                    revert GeniusErrors.InvalidTarget(target);
                }

            }

            if (allowedTargets[target] == 0 && target != owner) {
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

    function _checkNative(uint256 amount) internal {
        if (msg.value != amount) revert GeniusErrors.InvalidNativeAmount(amount);
    }

    function _sum(uint256[] calldata amounts) internal pure returns (uint256 total) {
        for (uint i = 0; i < amounts.length;) {
            total += amounts[i];

            unchecked { i++; }
        }
    }

    function _sweepERC20s(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        address owner
    ) internal {
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

    function _sweepNative(address receiver) internal {
        uint256 _balance = address(this).balance;

        if (_balance > 0) {
            if (!payable(receiver).send(_balance)) revert GeniusErrors.TransferFailed(address(0), address(this).balance);
        }
    }

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

    function _batchExecution(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) private {
        for (uint i = 0; i < targets.length;) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success) revert GeniusErrors.ExternalCallFailed(targets[i], i);

            unchecked { i++; }
        }
    }

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

    function _approveVault(uint256 amount) private {
        if (!STABLECOIN.approve(address(VAULT), amount)) revert GeniusErrors.ApprovalFailure(address(STABLECOIN), amount);
    }

    function _depositToVault(address receiver, uint256 amount) private {
        VAULT.deposit(amount, receiver);
    }

    function _withdrawFromVault(address receiver, uint256 amount) private {
        VAULT.withdraw(amount, receiver, address(this));
    }

    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}