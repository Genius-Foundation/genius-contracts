// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

contract GeniusActionsTest is Test {
    address public owner = makeAddr("Any Random String as Private Key");

    GeniusActions public geniusActions = new GeniusActions(owner);

    function test_constructor() view public {
        assertEq(geniusActions.owner(), owner);
    }

    function test_action_addtion_without_owner() public {
       vm.expectRevert();
       geniusActions.addAction("action1", "ipfsHash1");
    }

    function test_action_addition_with_owner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
    }

    function test_returns_mapped_value() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
    }

    function test_no_value_for_nonexistant_action() public {
        vm.expectRevert();
        geniusActions.getAction("action1");
    }

    function test_duplicate_action() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        vm.expectRevert();
        geniusActions.addAction("action1", "ipfsHash1");
    }

    function test_action_removal_without_owner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");

        vm.expectRevert();
        geniusActions.removeAction("action1");
    }

    function test_action_removal_with_owner() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");

        vm.prank(owner);
        console.log("Action added");
        geniusActions.removeAction("action1");
        console.log("Action removed");  
        vm.expectRevert();
        geniusActions.getAction("action1");
    }

    function test_nonexistant_action_removal() public {
        vm.prank(owner);
        vm.expectRevert();
        geniusActions.removeAction("action1");
    }

    function test_deployer_cannot_be_owner() public {
        vm.prank(address(this));
        vm.expectRevert();
        GeniusActions secondContract = new GeniusActions(address(this));

        vm.expectRevert();
        vm.prank(address(this));
        secondContract.addAction("action1", "ipfsHash1");
    }

    function test_get_action_names() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.getActiveActionName(0), "action1");
        assertEq(geniusActions.getAction("action1"), "ipfsHash1");
        vm.expectRevert();
        geniusActions.getInactiveActionName(0);
    }

    function test_get_inactive_action_names() public {
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

    function test_inactive_action() public {
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
