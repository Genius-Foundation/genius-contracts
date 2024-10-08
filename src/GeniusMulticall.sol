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
        for (uint i; i < targets.length; i++) {
            (bool _success, ) = targets[i].call{value: values[i]}(data[i]);
            if (!_success)
                revert GeniusErrors.ExternalCallFailed(targets[i], i);
        }
    }

    receive() external payable {
        revert("Native tokens not accepted directly");
    }
}
