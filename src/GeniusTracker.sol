// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./access/Orchestrable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract GeniusTracker is Ownable, Orchestrable {

    struct Swap {
        uint96 network;
        bytes32 txHash;
        uint8 status;  
    }

    mapping(bytes32 ipfsHash => Swap) public swaps;

    // Swap statuses
    uint8 public constant STATUS_INIT = 0;
    uint8 public constant STATUS_PENDING = 1;
    uint8 public constant STATUS_SUCCESS = 2;
    uint8 public constant STATUS_FAILED = 3;

    event SwapModified(bytes32 indexed ipfsHash, uint8 oldStatus, uint8 newStatus, bytes32 txHash, uint96 network);
    event SwapRemoved(bytes32 indexed ipfsHash);

    constructor(address initialOwner) Ownable(initialOwner) {}

    function modifySwap(
        bytes32 _ipfsHash,
        bytes32 _txHash,
        uint96 _network,
        uint8 _status
    ) external onlyOrchestrator {
        require(_status <= STATUS_FAILED, "GeniusTracker: Invalid status");

        Swap storage swap = swaps[_ipfsHash];
        uint8 oldStatus = swap.status;

        console.log("oldStatus: %d", oldStatus);

        require(oldStatus != STATUS_SUCCESS, "GeniusTracker: Cannot modify a successful swap");
        require(_status != oldStatus, "GeniusTracker: New status must be different");

        swap.txHash = _txHash;
        swap.network = _network;
        swap.status = _status;

        emit SwapModified(_ipfsHash, oldStatus, _status, _txHash, _network);
    }

    function getSwap(bytes32 _ipfsHash) external view returns (bytes32 txHash, uint96 network, uint8 status) {
        Swap memory swap = swaps[_ipfsHash];
        require(swap.txHash != bytes32(0), "GeniusTracker: Swap does not exist");
        return (swap.txHash, swap.network, swap.status);
    }
}