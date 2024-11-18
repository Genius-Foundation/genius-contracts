// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {AggregatorV3Interface} from "../../src/interfaces/AggregatorV3Interface.sol";

contract MockV3Aggregator is AggregatorV3Interface {
    uint8 public constant DECIMALS = 8;
    int256 private _price;
    uint256 private _timestamp;
    uint80 private _roundId;

    constructor(int256 initialPrice) {
        _price = initialPrice;
        _timestamp = block.timestamp;
        _roundId = 1;
    }

    function decimals() external pure override returns (uint8) {
        return DECIMALS;
    }

    function description() external pure override returns (string memory) {
        return "Mock V3 Aggregator";
    }

    function version() external pure override returns (uint256) {
        return 1;
    }

    function getRoundData(uint80 _id)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_id, _price, block.timestamp, _timestamp, _id);
    }

    function latestRoundData()
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (_roundId, _price, block.timestamp, _timestamp, _roundId);
    }

    // Function to update the price (only for testing)
    function updatePrice(int256 newPrice) external {
        _price = newPrice;
        _timestamp = block.timestamp;
        _roundId++;
    }

    // Function to set a stale timestamp (only for testing)
    function setStaleTimestamp(uint256 timestamp) external {
        _timestamp = timestamp;
    }

    // Function to set roundId (only for testing)
    function setRoundId(uint80 roundId) external {
        _roundId = roundId;
    }
}