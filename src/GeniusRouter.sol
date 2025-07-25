// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IGeniusVault} from "./interfaces/IGeniusVault.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusRouter} from "./interfaces/IGeniusRouter.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";
import {IFeeCollector} from "./interfaces/IFeeCollector.sol";

/**
 * @title GeniusRouter
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusRouter contract allows for the aggregation of multiple calls
 *         in a single transaction, as well as facilitating interactions with the GeniusVault contract.
 */
contract GeniusRouter is IGeniusRouter {
    using SafeERC20 for IERC20;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    IERC20 public immutable override STABLECOIN;
    IGeniusVault public immutable VAULT;
    IAllowanceTransfer public immutable PERMIT2;
    IGeniusProxyCall public immutable PROXYCALL;
    IFeeCollector public immutable FEE_COLLECTOR;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        CONSTRUCTOR                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    constructor(
        address permit2,
        address vault,
        address proxycall,
        address feeCollector
    ) {
        PERMIT2 = IAllowanceTransfer(permit2);
        VAULT = IGeniusVault(vault);
        PROXYCALL = IGeniusProxyCall(proxycall);
        FEE_COLLECTOR = IFeeCollector(feeCollector);

        STABLECOIN = VAULT.STABLECOIN();
        STABLECOIN.approve(address(VAULT), type(uint256).max);
    }

    /**
     * @dev See {IGeniusRouter-swapAndCreateOrder}.
     */
    function swapAndCreateOrder(
        bytes32 seed,
        address[] calldata tokensIn,
        uint256[] calldata amountsIn,
        address target,
        address toApprove,
        bytes calldata data,
        address owner,
        uint256 destChainId,
        uint256 feeSurplus,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) public payable override {
        if (tokensIn.length != amountsIn.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        for (uint256 i = 0; i < tokensIn.length; i++) {
            if (msg.sender != address(PROXYCALL)) {
                IERC20(tokensIn[i]).safeTransferFrom(
                    msg.sender,
                    address(PROXYCALL),
                    amountsIn[i]
                );
            }
        }

        if (target == address(PROXYCALL))
            PROXYCALL.execute{value: msg.value}(target, data);
        else
            PROXYCALL.approveAddressAndExecute{value: msg.value}(
                tokensIn,
                target,
                data,
                toApprove
            );

        uint256 delta = STABLECOIN.balanceOf(address(this));

        // Get the minimum fee for the destination chain
        IFeeCollector.FeeBreakdown memory feeBreakdown = FEE_COLLECTOR
            .getOrderFees(delta, destChainId);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: seed,
            trader: VAULT.addressToBytes32(owner),
            receiver: receiver,
            tokenIn: VAULT.addressToBytes32(address(STABLECOIN)),
            tokenOut: tokenOut,
            amountIn: delta,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            srcChainId: block.chainid,
            fee: feeBreakdown.totalFee + feeSurplus
        });

        VAULT.createOrder(order);
    }

    /**
     * @dev See {IGeniusRouter-swapAndCreateOrderPermit2}.
     */
    function swapAndCreateOrderPermit2(
        bytes32 seed,
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address target,
        address toApprove,
        bytes calldata data,
        uint256 destChainId,
        uint256 feeSurplus,
        bytes32 receiver,
        uint256 minAmountOut,
        bytes32 tokenOut
    ) public payable override {
        address owner = msg.sender;

        address[] memory tokensIn = _permitAndBatchTransfer(
            permitBatch,
            permitSignature,
            owner,
            address(PROXYCALL)
        );

        if (target == address(PROXYCALL))
            PROXYCALL.execute{value: msg.value}(target, data);
        else
            PROXYCALL.approveAddressAndExecute{value: msg.value}(
                tokensIn,
                target,
                data,
                toApprove
            );

        uint256 delta = STABLECOIN.balanceOf(address(this));

        IFeeCollector.FeeBreakdown memory feeBreakdown = FEE_COLLECTOR
            .getOrderFees(delta, destChainId);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: seed,
            trader: VAULT.addressToBytes32(owner),
            receiver: receiver,
            tokenIn: VAULT.addressToBytes32(address(STABLECOIN)),
            tokenOut: tokenOut,
            amountIn: delta,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            srcChainId: block.chainid,
            fee: feeBreakdown.totalFee + feeSurplus
        });

        VAULT.createOrder(order);
    }

    /**
     * @dev See {IGeniusRouter-createOrderPermit2}.
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
    ) external payable override {
        address owner = msg.sender;
        if (permitBatch.details.length != 1)
            revert GeniusErrors.ArrayLengthsMismatch();
        if (permitBatch.details[0].token != address(STABLECOIN))
            revert GeniusErrors.InvalidTokenIn();

        _permitAndBatchTransfer(permitBatch, permitSignature, owner, address(this));

        uint256 delta = STABLECOIN.balanceOf(address(this));

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: seed,
            trader: VAULT.addressToBytes32(owner),
            receiver: receiver,
            tokenIn: VAULT.addressToBytes32(address(STABLECOIN)),
            tokenOut: tokenOut,
            amountIn: delta,
            minAmountOut: minAmountOut,
            destChainId: destChainId,
            srcChainId: block.chainid,
            fee: fee
        });

        VAULT.createOrder(order);
    }

    /**
     * @dev Internal function to permit and batch transfer tokens.
     *
     * @param permitBatch The permit batch details
     * @param permitSignature The permit signature
     * @param owner The owner of the tokens
     */
    function _permitAndBatchTransfer(
        IAllowanceTransfer.PermitBatch calldata permitBatch,
        bytes calldata permitSignature,
        address owner,
        address transferTo
    ) private returns (address[] memory tokensIn) {
        tokensIn = new address[](permitBatch.details.length);
        if (permitBatch.spender != address(this))
            revert GeniusErrors.InvalidSpender();

        PERMIT2.permit(owner, permitBatch, permitSignature);

        IAllowanceTransfer.AllowanceTransferDetails[]
            memory transferDetails = new IAllowanceTransfer.AllowanceTransferDetails[](
                permitBatch.details.length
            );
        for (uint i; i < permitBatch.details.length; i++) {
            tokensIn[i] = permitBatch.details[i].token;
            transferDetails[i] = IAllowanceTransfer.AllowanceTransferDetails({
                from: owner,
                to: transferTo,
                amount: permitBatch.details[i].amount,
                token: permitBatch.details[i].token
            });
        }

        PERMIT2.transferFrom(transferDetails);
    }

    /**
     * @dev Fallback function to prevent native tokens from being sent directly.
     */
    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}
