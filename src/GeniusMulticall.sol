// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusErrors} from "./libs/GeniusErrors.sol";
import {IGeniusMulticall} from "./interfaces/IGeniusMulticall.sol";

/**
 * @title GeniusMulticall
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusMulticall contract allows for the aggregation of multiple calls
 *         in a single transaction.
 */
contract GeniusMulticall is IGeniusMulticall {
    /**
     * @dev See {IGeniusMulticall-aggregate}.
     */
    function aggregate(
        address[] calldata targets,
        bytes[] calldata data
    ) external override {
        if (targets.length == 0) revert GeniusErrors.EmptyArray();
        if (targets.length != data.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        for (uint i; i < targets.length; i++) {
            (bool _success, ) = targets[i].call(data[i]);
            if (!_success)
                revert GeniusErrors.ExternalCallFailed(targets[i], i);
        }
    }

    function aggregateWithValues(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable override {
        if (targets.length == 0) revert GeniusErrors.EmptyArray();
        if (targets.length != data.length || data.length != values.length)
            revert GeniusErrors.ArrayLengthsMismatch();
        if (msg.value != _sum(values))
            revert GeniusErrors.InvalidNativeAmount();

        for (uint i; i < targets.length; i++) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success)
                revert GeniusErrors.ExternalCallFailed(targets[i], i);
        }
    }

    /**
     * @dev Sums the amounts in an array.
     * @param amounts The array of amounts to be summed.
     */
    function _sum(
        uint256[] calldata amounts
    ) internal pure returns (uint256 total) {
        for (uint i; i < amounts.length; i++) {
            total += amounts[i];
        }
    }

    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}
