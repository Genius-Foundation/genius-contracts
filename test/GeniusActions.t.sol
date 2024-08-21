// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

contract GeniusActionsTest is Test {
    address public deployer = makeAddr("deployer");
    address public admin = makeAddr("admin");
    address public sentinel = makeAddr("sentinel");
    address public user = makeAddr("user");

    GeniusActions public geniusActions;

    function setUp() public {
        vm.prank(deployer);
        geniusActions = new GeniusActions(admin);
    }

    function testConstructor() public view {
        assertTrue(geniusActions.hasRole(geniusActions.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(geniusActions.hasRole(geniusActions.SENTINEL_ROLE(), admin));
    }

    function testConstructorFailure() public {
        vm.expectRevert("Initial owner cannot be the contract deployer");
        new GeniusActions(address(this));
    }

    function testAddActionWithoutAdmin() public {
        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
    }

    function testAddActionAsAdmin() public {
        vm.prank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertEq(action.ipfsHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
    }

    function testAddActionWithInvalidIpfsHash() public {
        vm.prank(admin);
        vm.expectRevert("incorrect IPFS hash");
        geniusActions.addAction("action1", "invalid");
    }

    function testGetNonexistentAction() public {
        vm.expectRevert("Action does not exist");
        geniusActions.getActionByActionLabel("nonexistent");
    }

    function testAddDuplicateAction() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        vm.expectRevert("Label already exists");
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        vm.stopPrank();
    }

    function testUpdateActionStatusByHash() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        bytes32 actionHash = geniusActions.getActionHashFromIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.updateActionStatusByHash(actionHash, false);
        GeniusActions.Action memory action = geniusActions.getActionByActionHash(actionHash);
        assertFalse(action.active);
        vm.stopPrank();
    }

    function testUpdateActionStatusByLabel() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.updateActionStatusByLabel("action1", false);
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertFalse(action.active);
        vm.stopPrank();
    }

    function testEmergencyDisableActionByLabel() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.emergencyDisableActionByLabel("action1");
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertFalse(action.active);
        vm.stopPrank();
    }

    function testEmergencyDisableActionById() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.emergencyDisableActionById(1);
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertFalse(action.active);
        vm.stopPrank();
    }

    function testEmergencyDisableActionByHash() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        bytes32 actionHash = geniusActions.getActionHashFromIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.emergencyDisableActionByHash(actionHash);
        GeniusActions.Action memory action = geniusActions.getActionByActionHash(actionHash);
        assertFalse(action.active);
        vm.stopPrank();
    }

    function testEmergencyDisableByNonAdmin() public {
        vm.prank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        
        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.emergencyDisableActionByLabel("action1");
    }

    function testUpdateActionIpfsHashByLabel() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.updateActionIpfsHashByLabel("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertEq(action.ipfsHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        vm.stopPrank();
    }

    function testUpdateActionIpfsHashByHash() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        bytes32 oldHash = geniusActions.getActionHashFromIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.updateActionIpfsHashByHash(oldHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        GeniusActions.Action memory action = geniusActions.getActionByActionLabel("action1");
        assertEq(action.ipfsHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        vm.stopPrank();
    }

    function testUpdateNonexistentActionIpfsHash() public {
        vm.prank(admin);
        vm.expectRevert("Action does not exist");
        geniusActions.updateActionIpfsHashByLabel("nonexistent", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
    }

    function testUpdateActionIpfsHashToSameHash() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        bytes32 oldHash = geniusActions.getActionHashFromIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        vm.expectRevert("New IPFS hash is the same as the old one");
        geniusActions.updateActionIpfsHashByHash(oldHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        vm.stopPrank();
    }

    function testGetActiveActions() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.addAction("action2", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        geniusActions.updateActionStatusByLabel("action2", false);
        vm.stopPrank();

        GeniusActions.Action[] memory activeActions = geniusActions.getActiveActions();
        assertEq(activeActions.length, 1);
        assertEq(activeActions[0].label, "action1");
    }

    function testGetInactiveActions() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.addAction("action2", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        geniusActions.updateActionStatusByLabel("action2", false);
        vm.stopPrank();

        GeniusActions.Action[] memory inactiveActions = geniusActions.getInactiveActions();
        assertEq(inactiveActions.length, 1);
        assertEq(inactiveActions[0].label, "action2");
    }

    function testActiveCount() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.addAction("action2", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        geniusActions.updateActionStatusByLabel("action2", false);
        vm.stopPrank();

        assertEq(geniusActions.activeCount(), 1);
    }

    function testComplexScenario() public {
        vm.startPrank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        geniusActions.addAction("action2", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd72");
        geniusActions.addAction("action3", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd73");
        geniusActions.updateActionStatusByLabel("action2", false);

        assertEq(geniusActions.activeCount(), 2);

        geniusActions.emergencyDisableActionByLabel("action1");

        assertEq(geniusActions.activeCount(), 1);

        geniusActions.updateActionStatusByLabel("action2", true);

        assertEq(geniusActions.activeCount(), 2);

        GeniusActions.Action[] memory activeActions = geniusActions.getActiveActions();
        assertEq(activeActions.length, 2);
        assertEq(activeActions[0].label, "action2");
        assertEq(activeActions[1].label, "action3");

        GeniusActions.Action[] memory inactiveActions = geniusActions.getInactiveActions();
        assertEq(inactiveActions.length, 1);
        assertEq(inactiveActions[0].label, "action1");
        vm.stopPrank();
    }

    function testGetActionByIpfsHash() public {
        vm.prank(admin);
        geniusActions.addAction("action1", "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");

        GeniusActions.Action memory action = geniusActions.getActionByIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        assertEq(action.label, "action1");
        assertEq(action.ipfsHash, "QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        assertTrue(action.active);
    }

    function testGetActionHashFromIpfsHash() public view {
        bytes32 expectedHash = 0xd264059aba5c9a50a24fa7a025939025c7f5289aa94b6ffa8f8abe41eeacbb81;
        bytes32 actualHash = geniusActions.getActionHashFromIpfsHash("QmTfCejgo2wTwqnDJs8Lu1pCNeCrCDuE4GAwkna93zdd71");
        assertEq(actualHash, expectedHash);
    }
}