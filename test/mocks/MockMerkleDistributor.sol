// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {IMerkleDistributor} from "../../src/interfaces/IMerkleDistributor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockMerkleDistributor
 * @notice Mock implementation of IMerkleDistributor for testing
 */
contract MockMerkleDistributor is IMerkleDistributor {
    mapping(address => uint256) public rewards;
    
    function submitRewards(address token, uint256 amount) external override {
        rewards[token] += amount;
        // Transfer tokens from msg.sender to this contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);
    }
    
    // Implement other interface functions with default behavior
    function merkleRoot() external pure override returns (bytes32) {
        return bytes32(0);
    }
    
    function lastMerkleUpdateBlockNumber() external pure override returns (uint256) {
        return 0;
    }
    
    function lastRewardsUpdateBlockNumber() external pure override returns (uint256) {
        return 0;
    }
    
    function oracleCount() external pure override returns (uint256) {
        return 0;
    }
    
    function claimedBitMap(bytes32, uint256) external pure override returns (uint256) {
        return 0;
    }
    
    function pause() external override {
        // Mock implementation - do nothing
    }
    
    function unpause() external override {
        // Mock implementation - do nothing
    }
    
    function addOracle(address) external override {
        // Mock implementation - do nothing
    }
    
    function removeOracle(address) external override {
        // Mock implementation - do nothing
    }
    
    function isMerkleRootVoting() external pure override returns (bool) {
        return false;
    }
    
    function setMerkleRoot(bytes32, string calldata, bytes[] calldata) external override {
        // Mock implementation - do nothing
    }
    
    function isClaimed(uint256) external pure override returns (bool) {
        return false;
    }
    
    function claim(
        uint256,
        address,
        address[] calldata,
        uint256[] calldata,
        bytes32[] calldata
    ) external override {
        // Mock implementation - do nothing
    }
} 