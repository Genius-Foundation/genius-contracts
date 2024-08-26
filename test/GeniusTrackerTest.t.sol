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
        uint256 network = 1;
        bytes1 status = tracker.STATUS_PENDING();

        tracker.modifySwap(ipfsHash, txHash, network, status);

        (bytes32 retrievedTxHash, uint256 retrievedNetwork, bytes1 retrievedStatus) = tracker.getSwap(ipfsHash);
        assertEq(retrievedTxHash, txHash);
        assertEq(retrievedNetwork, network);
        assertEq(retrievedStatus, status);

        vm.stopPrank();
    }

    function testModifyExistingSwap() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint256 network = 1;
        bytes1 status = tracker.STATUS_PENDING();

        tracker.modifySwap(ipfsHash, txHash, network, status);

        bytes1 newStatus = tracker.STATUS_FAILED();
        tracker.modifySwap(ipfsHash, txHash, network, newStatus);

        (,, bytes1 retrievedStatus) = tracker.getSwap(ipfsHash);
        assertEq(retrievedStatus, newStatus);

        vm.stopPrank();
    }

    function testCannotModifySuccessfulSwap() public {
        vm.startPrank(orchestrator);

        bytes32 ipfsHash = keccak256("swap1");
        bytes32 txHash = keccak256("txHash1");
        uint256 network = 1;

        console.log("Creating PENDING swap");
        tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_PENDING());
        
        (,, bytes1 currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_PENDING(), "Swap should be in PENDING status");
        console.log("Swap status after creation:", uint8(currentStatus));
        
        console.log("Modifying to SUCCESS");
        tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_SUCCESS());
        
        (,, currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_SUCCESS(), "Swap should be in SUCCESS status");
        console.log("Swap status after modification to SUCCESS:", uint8(currentStatus));

        console.log("Attempting to modify SUCCESS to FAILED");
        vm.expectRevert("GeniusTracker: Cannot modify a successful swap");
        tracker.modifySwap(ipfsHash, txHash, network, tracker.STATUS_FAILED());

        (,, currentStatus) = tracker.getSwap(ipfsHash);
        assertEq(currentStatus, tracker.STATUS_SUCCESS(), "Swap should still be in SUCCESS status");
        console.log("Final swap status:", uint8(currentStatus));

        vm.stopPrank();
    }

    // function testMaxSwapsLimit() public {
    //     vm.startPrank(orchestrator);

    //     for (uint i = 0; i < 500; i++) {
    //         bytes32 ipfsHash = keccak256(abi.encodePacked("swap", uint256(i)));
    //         bytes32 txHash = keccak256(abi.encodePacked("txHash", uint256(i)));
    //         tracker.modifySwap(ipfsHash, txHash, i % 256, tracker.STATUS_PENDING());
    //     }

    //     assertEq(tracker.getSwapCount(), 500);

    //     bytes32 newIpfsHash = keccak256(abi.encodePacked("swap", uint256(500)));
    //     bytes32 newTxHash = keccak256(abi.encodePacked("txHash", uint256(500)));
        
    //     vm.expectRevert("GeniusTracker: Maximum number of swaps reached");
    //     tracker.modifySwap(newIpfsHash, newTxHash, 500 % 256, tracker.STATUS_PENDING());

    //     vm.stopPrank();
    // }

    function testGetOldestAndNewestSwap() public {
        vm.startPrank(orchestrator);

        for (uint i = 0; i < 3; i++) {
            bytes32 ipfsHash = keccak256(abi.encodePacked("swap", uint256(i)));
            bytes32 txHash = keccak256(abi.encodePacked("txHash", uint256(i)));
            tracker.modifySwap(ipfsHash, txHash, i, tracker.STATUS_PENDING());
        }

        bytes32 oldestSwapHash = tracker.getOldestSwap();
        bytes32 newestSwapHash = tracker.getNewestSwap();

        assertEq(oldestSwapHash, keccak256(abi.encodePacked("swap", uint256(0))));
        assertEq(newestSwapHash, keccak256(abi.encodePacked("swap", uint256(2))));

        vm.stopPrank();
    }
}