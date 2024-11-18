// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

contract GeniusActionsTest is Test {
    address public deployer = makeAddr("deployer");
    address public admin = makeAddr("admin");
    address public sentinel = makeAddr("sentinel");
    address public user = makeAddr("user");
    address public orchestrator1 = makeAddr("orchestrator1");
    address public orchestrator2 = makeAddr("orchestrator2");

    GeniusActions public geniusActions;

    function setUp() public {
        vm.prank(deployer);
        geniusActions = new GeniusActions(admin);
    }

    function testConstructor() public view {
        assertTrue(geniusActions.hasRole(geniusActions.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(geniusActions.hasRole(geniusActions.SENTINEL_ROLE(), admin));
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

    function testSetOrchestratorAuthorized() public {
        vm.prank(admin);
        geniusActions.setOrchestratorAuthorized(orchestrator1, true);
        
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator1));
    }

    function testSetOrchestratorAuthorizedByNonAdmin() public {
        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.setOrchestratorAuthorized(orchestrator1, true);
    }

    function testSetBatchOrchestratorAuthorized() public {
        address[] memory orchestrators = new address[](2);
        orchestrators[0] = orchestrator1;
        orchestrators[1] = orchestrator2;

        vm.prank(admin);
        geniusActions.setBatchOrchestratorAuthorized(orchestrators, true);

        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator1));
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator2));
    }

    function testSetBatchOrchestratorAuthorizedByNonAdmin() public {
        address[] memory orchestrators = new address[](2);
        orchestrators[0] = orchestrator1;
        orchestrators[1] = orchestrator2;

        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.setBatchOrchestratorAuthorized(orchestrators, true);
    }

    function testIsAuthorizedOrchestratorFalse() public view {
        assertFalse(geniusActions.isAuthorizedOrchestrator(orchestrator1));
    }

    function testEmergencyDisableOrchestrator() public {
        vm.startPrank(admin);
        geniusActions.setOrchestratorAuthorized(orchestrator1, true);
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator1));

        geniusActions.grantRole(geniusActions.SENTINEL_ROLE(), sentinel);
        vm.stopPrank();

        vm.prank(sentinel);
        geniusActions.emergencyDisableOrchestrator(orchestrator1);

        assertFalse(geniusActions.isAuthorizedOrchestrator(orchestrator1));
    }

    function testEmergencyDisableOrchestratorByNonSentinel() public {
        vm.prank(admin);
        geniusActions.setOrchestratorAuthorized(orchestrator1, true);

        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.emergencyDisableOrchestrator(orchestrator1);
    }

    function testComplexOrchestratorScenario() public {
        vm.startPrank(admin);
        
        // Set up orchestrators
        address[] memory orchestrators = new address[](3);
        orchestrators[0] = orchestrator1;
        orchestrators[1] = orchestrator2;
        orchestrators[2] = user;
        geniusActions.setBatchOrchestratorAuthorized(orchestrators, true);

        // Verify all are authorized
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator1));
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator2));
        assertTrue(geniusActions.isAuthorizedOrchestrator(user));

        // Disable one orchestrator
        geniusActions.setOrchestratorAuthorized(user, false);

        // Verify the disabled orchestrator
        assertFalse(geniusActions.isAuthorizedOrchestrator(user));

        // Set up sentinel
        geniusActions.grantRole(geniusActions.SENTINEL_ROLE(), sentinel);
        vm.stopPrank();

        // Emergency disable by sentinel
        vm.prank(sentinel);
        geniusActions.emergencyDisableOrchestrator(orchestrator1);

        // Verify the emergency disabled orchestrator
        assertFalse(geniusActions.isAuthorizedOrchestrator(orchestrator1));

        // Verify the still active orchestrator
        assertTrue(geniusActions.isAuthorizedOrchestrator(orchestrator2));
    }

    function testSetCommitHashAuthorized() public {
        bytes32 commitHash = keccak256("test commit hash");
        
        vm.prank(admin);
        geniusActions.setCommitHashAuthorized(commitHash, true);

        assertTrue(geniusActions.isAuthorizedCommitHash(commitHash));
    }

    function testSetCommitHashAuthorizedByNonAdmin() public {
        bytes32 commitHash = keccak256("test commit hash");
        
        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.setCommitHashAuthorized(commitHash, true);
    }

    function testSetBatchCommitHashAuthorized() public {
        bytes32[] memory commitHashes = new bytes32[](2);
        commitHashes[0] = keccak256("test commit hash 1");
        commitHashes[1] = keccak256("test commit hash 2");

        vm.prank(admin);
        geniusActions.setBatchCommitHashAuthorized(commitHashes, true);

        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[0]));
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[1]));
    }

    function testSetBatchCommitHashAuthorizedByNonAdmin() public {
        bytes32[] memory commitHashes = new bytes32[](2);
        commitHashes[0] = keccak256("test commit hash 1");
        commitHashes[1] = keccak256("test commit hash 2");

        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.setBatchCommitHashAuthorized(commitHashes, true);
    }

    function testIsAuthorizedCommitHashFalse() public view {
        bytes32 commitHash = keccak256("test commit hash");
        assertFalse(geniusActions.isAuthorizedCommitHash(commitHash));
    }

    function testEmergencyDisableCommitHash() public {
        bytes32 commitHash = keccak256("test commit hash");
        
        vm.startPrank(admin);
        geniusActions.setCommitHashAuthorized(commitHash, true);
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHash));

        geniusActions.grantRole(geniusActions.SENTINEL_ROLE(), sentinel);
        vm.stopPrank();

        vm.prank(sentinel);
        geniusActions.emergencyDisableCommitHash(commitHash);

        assertFalse(geniusActions.isAuthorizedCommitHash(commitHash));
    }

    function testEmergencyDisableCommitHashByNonSentinel() public {
        bytes32 commitHash = keccak256("test commit hash");
        
        vm.prank(admin);
        geniusActions.setCommitHashAuthorized(commitHash, true);

        vm.prank(user);
        vm.expectRevert("OwnablePausable: access denied");
        geniusActions.emergencyDisableCommitHash(commitHash);
    }

    function testComplexCommitHashScenario() public {
        vm.startPrank(admin);

        // Set up commit hashes
        bytes32[] memory commitHashes = new bytes32[](3);
        commitHashes[0] = keccak256("test commit hash 1");
        commitHashes[1] = keccak256("test commit hash 2");
        commitHashes[2] = keccak256("test commit hash 3");
        geniusActions.setBatchCommitHashAuthorized(commitHashes, true);

        // Verify all are authorized
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[0]));
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[1]));
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[2]));

        // Disable one commit hash
        geniusActions.setCommitHashAuthorized(commitHashes[2], false);

        // Verify the disabled commit hash
        assertFalse(geniusActions.isAuthorizedCommitHash(commitHashes[2]));

        // Set up sentinel
        geniusActions.grantRole(geniusActions.SENTINEL_ROLE(), sentinel);
        vm.stopPrank();

        // Emergency disable by sentinel
        vm.prank(sentinel);
        geniusActions.emergencyDisableCommitHash(commitHashes[0]);

        // Verify the emergency disabled commit hash
        assertFalse(geniusActions.isAuthorizedCommitHash(commitHashes[0]));

        // Verify the still active commit hash
        assertTrue(geniusActions.isAuthorizedCommitHash(commitHashes[1]));
    }
}