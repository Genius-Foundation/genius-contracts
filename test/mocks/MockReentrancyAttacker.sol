// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";

contract MockReentrancyAttacker {
    GeniusExecutor public EXECUTOR;

    constructor(address payable _executor) {
        EXECUTOR = GeniusExecutor(_executor);
    }

    function attack() external {
        // Attempt to call back into the EXECUTOR
        address[] memory targets = new address[](1);
        targets[0] = address(this);
        
        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature("dummy()");
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        EXECUTOR.aggregate(targets, data, values);
    }

    function dummy() external pure {}
}