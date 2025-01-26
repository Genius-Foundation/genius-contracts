// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusProxyCall} from "./interfaces/IGeniusProxyCall.sol";
import {MultiSendCallOnly} from "./libs/MultiSendCallOnly.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title GeniusProxyCall
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusProxyCall contract allows for the aggregation of multiple calls
 *         in a single transaction.
 */
contract GeniusProxyCall is IGeniusProxyCall, MultiSendCallOnly, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant CALLER_ROLE = keccak256("CALLER_ROLE");

    constructor(address _admin, address[] memory callers) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        uint256 callersLength = callers.length;
        for (uint256 i; i < callersLength; i++) {
            _grantRole(CALLER_ROLE, callers[i]);
        }
    }

    modifier onlyCallerOrSelf() {
        if (!hasRole(CALLER_ROLE, msg.sender) && msg.sender != address(this))
            revert GeniusErrors.InvalidCaller();
        _;
    }

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert GeniusErrors.IsNotAdmin();
        _;
    }

    /**
     * @dev See {IGeniusProxyCall-aggregate}.
     */
    function execute(
        address target,
        bytes calldata data
    ) external payable override onlyCallerOrSelf {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();

        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target);
    }

    /**
     * @dev See {IGeniusProxyCall-call}.
     */
    function call(
        address receiver,
        address swapTarget,
        address callTarget,
        address stablecoin,
        address tokenOut,
        uint256 minAmountOut,
        bytes calldata swapData,
        bytes calldata callData
    )
        external
        override
        onlyCallerOrSelf
        returns (
            address effectiveTokenOut,
            uint256 effectiveAmountOut,
            bool success
        )
    {
        bool isSwap = swapTarget != address(0);
        bool isCall = callTarget != address(0);

        uint256 stablecoinBalance = IERC20(stablecoin).balanceOf(address(this));
        effectiveAmountOut = stablecoinBalance;
        effectiveTokenOut = stablecoin;
        success = true;

        if (!isCall && !isSwap) {
            IERC20(stablecoin).safeTransfer(receiver, stablecoinBalance);
            return (stablecoin, stablecoinBalance, success);
        }

        if (isSwap) {
            bytes memory wrappedSwapData = abi.encodeWithSelector(
                IGeniusProxyCall.approveTokenExecuteAndVerify.selector,
                stablecoin,
                swapTarget,
                swapData,
                tokenOut,
                minAmountOut,
                isCall ? address(this) : receiver
            );
            bytes memory returnData;
            (success, returnData) = address(this).call(wrappedSwapData);
            if (success) {
                effectiveTokenOut = tokenOut;
                effectiveAmountOut = abi.decode(returnData, (uint256));
            } else {
                IERC20(stablecoin).safeTransfer(receiver, stablecoinBalance);
                return (stablecoin, stablecoinBalance, success);
            }
        }

        if (isCall) {
            bytes memory wrappedCallData = abi.encodeWithSelector(
                IGeniusProxyCall.transferTokenAndExecute.selector,
                tokenOut,
                callTarget,
                callData
            );

            (success, ) = address(this).call(wrappedCallData);
        }

        uint256 balance = IERC20(effectiveTokenOut).balanceOf(address(this));

        if (balance > 0)
            IERC20(effectiveTokenOut).safeTransfer(receiver, balance);

        if (stablecoin != effectiveTokenOut) {
            uint256 balanceStable = IERC20(stablecoin).balanceOf(address(this));
            if (balanceStable > 0)
                IERC20(stablecoin).safeTransfer(receiver, balanceStable);
        }
    }

    /**
     * @dev See {IGeniusProxyCall-approveTokenExecuteAndVerify}.
     */
    function approveTokenExecuteAndVerify(
        address token,
        address target,
        bytes calldata data,
        address tokenOut,
        uint256 minAmountOut,
        address expectedTokenReceiver
    ) external payable override onlyCallerOrSelf returns (uint256) {
        uint256 balancePreSwap = IERC20(tokenOut).balanceOf(
            expectedTokenReceiver
        );
        _approveTokenAndExecute(token, target, data);

        uint256 balancePostSwap = IERC20(tokenOut).balanceOf(
            expectedTokenReceiver
        );
        uint256 amountOut = balancePostSwap - balancePreSwap;
        if (amountOut < minAmountOut)
            revert GeniusErrors.InvalidAmountOut(amountOut, minAmountOut);
        else return amountOut;
    }

    /**
     * @dev See {IGeniusProxyCall-approveTokenExecute}.
     */
    function approveTokenExecute(
        address token,
        address target,
        bytes calldata data
    ) public payable override onlyCallerOrSelf {
        _approveTokenAndExecute(token, target, data);
    }

    /**
     * @dev See {IGeniusProxyCall-approveTokensAndExecute}.
     */
    function approveTokensAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data
    ) external payable override onlyCallerOrSelf {
        _approveAddressAndExecute(tokens, target, data, target);
    }

    function approveAddressAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data,
        address toApprove
    ) external payable override onlyCallerOrSelf {
        _approveAddressAndExecute(tokens, target, data, toApprove);
    }

    /**
     * @dev See {IGeniusProxyCall-transferTokenAndExecute}.
     */
    function transferTokenAndExecute(
        address token,
        address target,
        bytes calldata data
    ) external payable onlyCallerOrSelf {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance != 0) {
            IERC20(token).safeTransfer(target, balance);
        }
        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target);
    }

    /**
     * @dev See {IGeniusProxyCall-transferTokensAndExecute}.
     */
    function transferTokensAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data
    ) external payable onlyCallerOrSelf {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();

        uint256 tokensLength = tokens.length;
        for (uint i; i < tokensLength; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));

            if (balance > 0) {
                IERC20(tokens[i]).safeTransfer(target, balance);
            }
        }
        (bool _success, ) = target.call{value: msg.value}(data);
        if (!_success) revert GeniusErrors.ExternalCallFailed(target);
    }

    /**
     * @dev See {IGeniusProxyCall-multiSend}.
     */
    function multiSend(bytes memory transactions) external payable {
        if (address(this) != msg.sender)
            revert GeniusErrors.InvalidCallerMulticall();
        _multiSend(transactions);
    }

    /**
     * @notice Approves multiple tokens for spending by the address to approve,
     * and then executes an arbitrary call.
     *
     * @param tokens The tokens to approve for spending.
     * @param target The target contract to call.
     * @param data The data to pass to the target contract.
     * @param toApprove The address to approve for the swap.
     */
    function _approveAddressAndExecute(
        address[] memory tokens,
        address target,
        bytes calldata data,
        address toApprove
    ) internal {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();
        if (!_isContract(toApprove))
            revert GeniusErrors.ApprovalTargetIsNotContract();

        if (target == address(this)) {
            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target);
        } else {
            uint256 tokensLength = tokens.length;
            for (uint256 i; i < tokensLength; i++) {
                IERC20(tokens[i]).approve(toApprove, type(uint256).max);
            }

            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target);

            for (uint i; i < tokensLength; i++) {
                IERC20(tokens[i]).approve(toApprove, 0);
            }
        }
    }

    /**
     * @notice Approves a target contract to spend the maximum amount of a token,
     * and then executes an arbitrary call.
     *
     * @param token The token to approve for spending.
     * @param target The target contract to call.
     * @param data The data to pass to the target contract.
     */
    function _approveTokenAndExecute(
        address token,
        address target,
        bytes calldata data
    ) internal {
        if (target == address(0)) revert GeniusErrors.NonAddress0();
        if (!_isContract(target)) revert GeniusErrors.TargetIsNotContract();

        if (target == address(this)) {
            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target);
        } else {
            IERC20(token).approve(target, type(uint256).max);

            (bool _success, ) = target.call{value: msg.value}(data);
            if (!_success) revert GeniusErrors.ExternalCallFailed(target);

            IERC20(token).approve(target, 0);
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
        return length > 0;
    }

    /**
     * @dev Fallback function to receive ETH.
     */
    receive() external payable {}
}
