// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/console.sol";
import "./access/Orchestrable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GeniusTracker is Ownable, Orchestrable {

    struct Swap {
        bytes32 txHash;
        uint256 network;
        bytes1 status;
    }

    mapping(bytes32 => Swap) public swaps;
    bytes32[] public swapQueue;
    uint256 public constant MAX_SWAPS = 500;

    // Swap statuses
    bytes1 public constant STATUS_PENDING = 0x00;
    bytes1 public constant STATUS_SUCCESS = 0x01;
    bytes1 public constant STATUS_FAILED = 0x02;

    event SwapCreated(bytes32 indexed ipfsHash, bytes32 txHash, uint256 network, bytes1 status);
    event SwapModified(bytes32 indexed ipfsHash, bytes1 oldStatus, bytes1 newStatus);
    event SwapRemoved(bytes32 indexed ipfsHash);

    constructor(address initialOwner) Ownable(initialOwner) {}

function modifySwap(
    bytes32 _ipfsHash,
    bytes32 _txHash,
    uint256 _network,
    bytes1 _status
) external onlyOrchestrator {
    require(_status == STATUS_PENDING || _status == STATUS_SUCCESS || _status == STATUS_FAILED, "GeniusTracker: Invalid status");

    Swap storage swap = swaps[_ipfsHash];

    console.log("Modifying swap with ipfsHash:", uint256(uint160(bytes20(_ipfsHash))));
    console.log("Current swap status:", uint8(swap.status));
    console.log("New status:", uint8(_status));

    if (swap.txHash == bytes32(0)) {
        console.log("Creating new swap");
        require(swapQueue.length < MAX_SWAPS, "GeniusTracker: Maximum number of swaps reached");
        
        swap.txHash = _txHash;
        swap.network = _network;
        swap.status = _status;
        swapQueue.push(_ipfsHash);

        emit SwapCreated(_ipfsHash, _txHash, _network, _status);
    } else {
        console.log("Modifying existing swap");
        require(swap.status != STATUS_SUCCESS, "GeniusTracker: Cannot modify a successful swap");
        require(_status != swap.status, "GeniusTracker: New status must be different from current status");

        bytes1 oldStatus = swap.status;
        swap.txHash = _txHash;
        swap.network = _network;
        swap.status = _status;

        emit SwapModified(_ipfsHash, oldStatus, _status);
    }

    console.log("Swap status after modification:", uint8(swap.status));
}

    function getSwap(bytes32 _ipfsHash) external view returns (bytes32 txHash, uint256 network, bytes1 status) {
        Swap memory swap = swaps[_ipfsHash];
        require(swap.txHash != bytes32(0), "GeniusTracker: Swap does not exist");
        return (swap.txHash, swap.network, swap.status);
    }

    function getSwapCount() external view returns (uint256) {
        return swapQueue.length;
    }

    function getOldestSwap() external view returns (bytes32) {
        require(swapQueue.length > 0, "GeniusTracker: No swaps exist");
        return swapQueue[0];
    }

    function getNewestSwap() external view returns (bytes32) {
        require(swapQueue.length > 0, "GeniusTracker: No swaps exist");
        return swapQueue[swapQueue.length - 1];
    }
}