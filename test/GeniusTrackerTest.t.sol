// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/GeniusTracker.sol";

contract GeniusTrackerTest is Test {
    GeniusTracker public tracker;
    address public owner;
    address public orchestrator;

    function setUp() public {
        owner = address(this);
        orchestrator = address(0x1);
        tracker = new GeniusTracker(owner);
        tracker.addOrchestrator(orchestrator);
    }

    function testModifySwap() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint96 network = 1;
        uint8 status = tracker.STATUS_PENDING();

        tracker.modifySwap(ipfsHash, txHash, network, status);

        (bytes32 retrievedTxHash, uint96 retrievedNetwork, uint8 retrievedStatus) = tracker.getSwap(ipfsHash);
        assertEq(retrievedTxHash, txHash);
        assertEq(retrievedNetwork, network);
        assertEq(retrievedStatus, status);

        vm.stopPrank();
    }

    function testModifyExistingSwap() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint96 network = 1;
        uint8 status = tracker.STATUS_PENDING();

        tracker.modifySwap(ipfsHash, txHash, network, status);

        uint8 newStatus = tracker.STATUS_FAILED();
        tracker.modifySwap(ipfsHash, txHash, network, newStatus);

        (,, uint8 retrievedStatus) = tracker.getSwap(ipfsHash);
        assertEq(retrievedStatus, newStatus);

        vm.stopPrank();
    }

    function testCannotModifySuccessfulSwap() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint96 network = 1;

        tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_PENDING());
        
        (,, uint8 currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_PENDING(), "Swap should be in PENDING status");
        
        tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_SUCCESS());
        
        (,, currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_SUCCESS(), "Swap should be in SUCCESS status");

        vm.expectRevert("GeniusTracker: Cannot modify a successful swap");
        try tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_FAILED()) {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "GeniusTracker: Cannot modify a successful swap", "Unexpected revert reason");
        }

        (,, currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_SUCCESS(), "Swap should still be in SUCCESS status");

        vm.stopPrank();
    }

    function testCannotSetSameStatus() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint96 network = 1;
        uint8 status = tracker.STATUS_PENDING();

        tracker.modifySwap(ipfsHash, txHash, network, status);

        vm.expectRevert("GeniusTracker: New status must be different");
        tracker.modifySwap(ipfsHash, txHash, network, status);

        vm.stopPrank();
    }

    function testInvalidStatus() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint96 network = 1;
        uint8 invalidStatus = 4; // Invalid status

        vm.expectRevert("GeniusTracker: Invalid status");
        tracker.modifySwap(ipfsHash, txHash, network, invalidStatus);

        vm.stopPrank();
    }

    function testGetNonExistentSwap() public {
        bytes32 nonExistentIpfsHash = keccak256("nonexistent");

        vm.expectRevert("GeniusTracker: Swap does not exist");
        tracker.getSwap(nonExistentIpfsHash);
    }
}