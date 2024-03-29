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
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "ipfsHash1");
    }

    function test_returns_mapped_value() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "ipfsHash1");
    }

    function test_no_value_for_nonexistant_action() public {
        vm.prank(owner);
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "");
    }

    function test_duplicate_action() public {
        vm.prank(owner);
        geniusActions.addAction("action1", "ipfsHash1");
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "ipfsHash1");

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
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "ipfsHash1");

        vm.prank(owner);
        geniusActions.removeAction("action1");
        assertEq(geniusActions.actionTypeToIpfsHash("action1"), "");
    }

    function test_nonexistant_action_removal() public {
        vm.prank(owner);
        vm.expectRevert();
        geniusActions.removeAction("action1");
    }

}
