// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

contract GeniusActionsTest is Test {
    address public owner = makeAddr("Any Random String as Private Key");

    GeniusActions public geniusActions = new GeniusActions(owner);

    function testConstructor() view public {
        assertEq(geniusActions.owner(), owner);
    }

    function testAddActionWithoutOwner() public {
       vm.expectRevert();
       geniusActions.addAction("action1", "ipfsHash1");
    }

    function testAddActionAsOwner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
    }

    function testReturnsCorrectValue() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
    }

    function testExpectRevertNonexistentAction() public {
        vm.expectRevert();
        geniusActions.getAction("action1");
    }

    function testExpectRevertOnDuplicateAction() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        vm.expectRevert();
        geniusActions.addAction("action1", "ipfsHash1");
    }

    function testRemoveActionWithoutOwner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");

        vm.expectRevert();
        geniusActions.removeAction("action1");
    }

    function testRemoveActionAsOwner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        vm.prank(owner);
        geniusActions.removeAction("action1"); 
        vm.expectRevert();
        geniusActions.getAction("action1");
    }

    function testRemoveNonexistentAction() public {
        vm.prank(owner);
        vm.expectRevert();
        geniusActions.removeAction("action1");
    }

    function testExpectDeployerNotToBeOwner() public {
        vm.prank(address(this));
        vm.expectRevert();
        GeniusActions secondContract = new GeniusActions(address(this));

        vm.expectRevert();
        vm.prank(address(this));
        secondContract.addAction("action1", "ipfsHash1");
    }

    function testGetActions() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getActiveActionName(0), "action1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
        vm.expectRevert();
        geniusActions.getInactiveActionName(0);
    }

    function testGetInactiveActions() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getActiveActionName(0), "action1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        vm.prank(owner);
        geniusActions.removeAction("action1");
        assertEq(geniusActions.getInactiveActionName(0), "action1");
        assertEq(geniusActions.getInactiveAction("action1"), "ipfsHash1");
        vm.expectRevert();
        geniusActions.getActiveActionName(0);
    }

    function testInactiveActions() public {
        // Add the action
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getActiveActionName(0), "action1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        // Remove the action
        vm.prank(owner);
        geniusActions.removeAction("action1");
        vm.expectRevert();
        geniusActions.getAction("action1");

        vm.expectRevert();
        geniusActions.getActiveActionName(0);

        // Check if the action is inactive
        vm.expectRevert();
        geniusActions.activeActionNames();
        string[] memory inactiveActions = geniusActions.inactiveActionNames();
        assertEq(inactiveActions.length, 1);
    }
}
