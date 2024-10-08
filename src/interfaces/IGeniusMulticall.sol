// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IGeniusMulticall {
    function aggregate(
        address[] calldata targets,
        bytes[] calldata data
    ) external;

    function aggregateWithValues(
        address[] calldata targets,
        bytes[] calldata data,
        uint256[] calldata values
    ) external payable;
}
