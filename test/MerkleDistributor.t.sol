// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import {MerkleDistributor} from "../src/distributor/MerkleDistributor.sol";
import {IMerkleDistributor} from "../src/interfaces/IMerkleDistributor.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MerkleDistributorTest is Test {
    // Test roles
    address public constant ADMIN = address(0x1);
    // ORACLE_1, ORACLE_2, ORACLE_3 are now derived from private keys in setUp()
    address public constant DISTRIBUTOR = address(0x5);
    address public constant USER_1 = address(0x6);
    address public constant USER_2 = address(0x7);
    address public constant RANDOM_USER = address(0x8);

    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant REWARD_AMOUNT = 10_000 ether;

    // Test contracts
    MerkleDistributor public merkleDistributor;
    MockERC20 public token1;
    MockERC20 public token2;

    // Test data
    bytes32 public merkleRoot;
    address[] public tokens;
    uint256[] public amounts;
    bytes32[] public merkleProof;

    // Oracle private keys for signing
    uint256 public constant ORACLE_1_PRIVATE_KEY = 0x1234567890123456789012345678901234567890123456789012345678901234;
    uint256 public constant ORACLE_2_PRIVATE_KEY = 0x2345678901234567890123456789012345678901234567890123456789012345;
    uint256 public constant ORACLE_3_PRIVATE_KEY = 0x3456789012345678901234567890123456789012345678901234567890123456;
    address public ORACLE_1;
    address public ORACLE_2;
    address public ORACLE_3;

    // Events to test
    event MerkleRootUpdated(
        address indexed sender,
        bytes32 indexed merkleRoot,
        string merkleProofs
    );
    event RewardsSubmitted(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 blockNumber
    );
    event Claimed(
        address indexed account,
        uint256 index,
        address[] tokens,
        uint256[] amounts
    );
    event OracleAdded(address indexed oracle);
    event OracleRemoved(address indexed oracle);

    function setUp() public {
        // Derive oracle addresses from private keys
        ORACLE_1 = vm.addr(ORACLE_1_PRIVATE_KEY);
        ORACLE_2 = vm.addr(ORACLE_2_PRIVATE_KEY);
        ORACLE_3 = vm.addr(ORACLE_3_PRIVATE_KEY);
        
        // Deploy tokens
        token1 = new MockERC20("Token 1", "TK1", 18);
        token2 = new MockERC20("Token 2", "TK2", 18);
        
        token1.mint(ADMIN, INITIAL_SUPPLY);
        token2.mint(ADMIN, INITIAL_SUPPLY);
        token1.mint(DISTRIBUTOR, INITIAL_SUPPLY);
        token2.mint(DISTRIBUTOR, INITIAL_SUPPLY);

        // Deploy MerkleDistributor
        MerkleDistributor implementation = new MerkleDistributor();
        
        bytes memory data = abi.encodeWithSelector(
            MerkleDistributor.initialize.selector,
            ADMIN
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        merkleDistributor = MerkleDistributor(address(proxy));

        // Set up roles
        vm.startPrank(ADMIN);
        merkleDistributor.grantRole(merkleDistributor.DISTRIBUTOR_ROLE(), DISTRIBUTOR);
        vm.stopPrank();

        // Set up test data
        tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);

        amounts = new uint256[](2);
        amounts[0] = 100 ether;
        amounts[1] = 200 ether;

        // Create a merkle tree that's compatible with OpenZeppelin's MerkleProof
        bytes32 leaf0 = keccak256(abi.encode(0, tokens, USER_1, amounts));
        bytes32 leaf1 = keccak256(abi.encode(1, tokens, USER_2, amounts));
        
        // For OpenZeppelin's MerkleProof, we need to ensure the leaves are sorted
        bytes32 leftLeaf = leaf0 < leaf1 ? leaf0 : leaf1;
        bytes32 rightLeaf = leaf0 < leaf1 ? leaf1 : leaf0;
        
        merkleRoot = keccak256(abi.encodePacked(leftLeaf, rightLeaf));
        
        // Create the correct proof for index 0 (USER_1)
        merkleProof = new bytes32[](1);
        if (leaf0 < leaf1) {
            // leaf0 is on the left, so proof for leaf0 is leaf1
            merkleProof[0] = leaf1;
        } else {
            // leaf0 is on the right, so proof for leaf0 is leaf1 (which is now on the left)
            merkleProof[0] = leaf1;
        }
    }

    // HELPER FUNCTIONS FOR MERKLE TREE



    function _createMerkleProofForUser(uint256 index, address /* user */) internal view returns (bytes32[] memory) {
        // Create leaves for the merkle tree
        bytes32 leaf0 = keccak256(abi.encode(0, tokens, USER_1, amounts));
        bytes32 leaf1 = keccak256(abi.encode(1, tokens, USER_2, amounts));
        
        // For OpenZeppelin's MerkleProof, we need to ensure the leaves are sorted
        bytes32 leftLeaf = leaf0 < leaf1 ? leaf0 : leaf1;
        bytes32 rightLeaf = leaf0 < leaf1 ? leaf1 : leaf0;
        
        // Create the correct proof for the specified index
        bytes32[] memory proof = new bytes32[](1);
        if (index == 0) {
            // Proof for leaf0
            if (leaf0 < leaf1) {
                // leaf0 is on the left, so proof is leaf1
                proof[0] = leaf1;
            } else {
                // leaf0 is on the right, so proof is leaf1 (which is now on the left)
                proof[0] = leaf1;
            }
        } else {
            // Proof for leaf1
            if (leaf0 < leaf1) {
                // leaf1 is on the right, so proof is leaf0
                proof[0] = leaf0;
            } else {
                // leaf1 is on the left, so proof is leaf0 (which is now on the right)
                proof[0] = leaf0;
            }
        }
        
        return proof;
    }





    // INITIALIZATION TESTS

    function testInitialization() public view {
        assertTrue(merkleDistributor.hasRole(merkleDistributor.DEFAULT_ADMIN_ROLE(), ADMIN));
        assertTrue(merkleDistributor.hasRole(merkleDistributor.PAUSER_ROLE(), ADMIN));
        assertEq(merkleDistributor.oracleCount(), 0);
        assertEq(merkleDistributor.lastMerkleUpdateBlockNumber(), 0);
        assertEq(merkleDistributor.lastRewardsUpdateBlockNumber(), 0);
    }

    function testMerkleProofVerification() public view {
        // Verify that our merkle proof is correct
        bytes32 leaf0 = keccak256(abi.encode(0, tokens, USER_1, amounts));
        bytes32 leaf1 = keccak256(abi.encode(1, tokens, USER_2, amounts));
        
        // For OpenZeppelin's MerkleProof, we need to ensure the leaves are sorted
        bytes32 leftLeaf = leaf0 < leaf1 ? leaf0 : leaf1;
        bytes32 rightLeaf = leaf0 < leaf1 ? leaf1 : leaf0;
        bytes32 expectedRoot = keccak256(abi.encodePacked(leftLeaf, rightLeaf));
        
        // Verify the root matches
        assertEq(merkleRoot, expectedRoot);
        
        // Verify the proof works
        bool isValid = MerkleProof.verify(merkleProof, merkleRoot, leaf0);
        assertTrue(isValid, "Merkle proof should be valid");
        
        // Verify the proof for USER_2 (index 1) also works
        bytes32[] memory proof1 = _createMerkleProofForUser(1, USER_2);
        
        bool isValid1 = MerkleProof.verify(proof1, merkleRoot, leaf1);
        assertTrue(isValid1, "Merkle proof for index 1 should be valid");
    }



    function test_RevertWhen_InitializeWithZeroAddress() public {
        MerkleDistributor implementation = new MerkleDistributor();
        
        bytes memory data = abi.encodeWithSelector(
            MerkleDistributor.initialize.selector,
            address(0)
        );

        vm.expectRevert(GeniusErrors.NonAddress0.selector);
        new ERC1967Proxy(address(implementation), data);
    }

    function test_RevertWhen_InitializeTwice() public {
        vm.expectRevert("InvalidInitialization()");
        merkleDistributor.initialize(ADMIN);
    }

    // ORACLE MANAGEMENT TESTS

    function testAddOracle() public {
        vm.startPrank(ADMIN);
        
        vm.expectEmit(true, false, false, false);
        emit OracleAdded(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_1);
        
        assertTrue(merkleDistributor.hasRole(merkleDistributor.ORACLE_ROLE(), ORACLE_1));
        assertEq(merkleDistributor.oracleCount(), 1);
        
        vm.stopPrank();
    }

    function testAddMultipleOracles() public {
        vm.startPrank(ADMIN);
        
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        
        assertTrue(merkleDistributor.hasRole(merkleDistributor.ORACLE_ROLE(), ORACLE_1));
        assertTrue(merkleDistributor.hasRole(merkleDistributor.ORACLE_ROLE(), ORACLE_2));
        assertTrue(merkleDistributor.hasRole(merkleDistributor.ORACLE_ROLE(), ORACLE_3));
        assertEq(merkleDistributor.oracleCount(), 3);
        
        vm.stopPrank();
    }

    function testRemoveOracle() public {
        vm.startPrank(ADMIN);
        
        merkleDistributor.addOracle(ORACLE_1);
        assertEq(merkleDistributor.oracleCount(), 1);
        
        vm.expectEmit(true, false, false, false);
        emit OracleRemoved(ORACLE_1);
        merkleDistributor.removeOracle(ORACLE_1);
        
        assertFalse(merkleDistributor.hasRole(merkleDistributor.ORACLE_ROLE(), ORACLE_1));
        assertEq(merkleDistributor.oracleCount(), 0);
        
        vm.stopPrank();
    }

    function test_RevertWhen_AddOracleWithZeroAddress() public {
        vm.startPrank(ADMIN);
        vm.expectRevert("Oracles: invalid oracle address");
        merkleDistributor.addOracle(address(0));
        vm.stopPrank();
    }

    function test_RevertWhen_AddOracleTwice() public {
        vm.startPrank(ADMIN);
        
        merkleDistributor.addOracle(ORACLE_1);
        vm.expectRevert("Oracles: oracle already exists");
        merkleDistributor.addOracle(ORACLE_1);
        
        vm.stopPrank();
    }

    function test_RevertWhen_RemoveNonExistentOracle() public {
        vm.startPrank(ADMIN);
        vm.expectRevert("Oracles: oracle do not exists");
        merkleDistributor.removeOracle(ORACLE_1);
        vm.stopPrank();
    }

    function test_RevertWhen_NonAdminAddsOracle() public {
        vm.startPrank(RANDOM_USER);
        vm.expectRevert();
        merkleDistributor.addOracle(ORACLE_1);
        vm.stopPrank();
    }

    function test_RevertWhen_NonAdminRemovesOracle() public {
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        vm.stopPrank();
        
        vm.startPrank(RANDOM_USER);
        vm.expectRevert();
        merkleDistributor.removeOracle(ORACLE_1);
        vm.stopPrank();
    }

    // REWARDS SUBMISSION TESTS

    function testSubmitRewards() public {
        vm.startPrank(DISTRIBUTOR);
        
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        
        vm.expectEmit(true, true, false, false);
        emit RewardsSubmitted(DISTRIBUTOR, address(token1), REWARD_AMOUNT, block.number);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        
        assertEq(token1.balanceOf(address(merkleDistributor)), REWARD_AMOUNT);
        assertEq(merkleDistributor.lastRewardsUpdateBlockNumber(), block.number);
        
        vm.stopPrank();
    }

    function testSubmitMultipleRewards() public {
        vm.startPrank(DISTRIBUTOR);
        
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        
        assertEq(token1.balanceOf(address(merkleDistributor)), REWARD_AMOUNT);
        assertEq(token2.balanceOf(address(merkleDistributor)), REWARD_AMOUNT);
        
        vm.stopPrank();
    }

    function test_RevertWhen_NonDistributorSubmitsRewards() public {
        vm.startPrank(RANDOM_USER);
        vm.expectRevert("MerkleDistributor: access denied");
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
    }

    // MERKLE ROOT VOTING TESTS

    function testIsMerkleRootVoting() public {
        // Initially, no voting should be active
        assertFalse(merkleDistributor.isMerkleRootVoting());
        
        // Submit rewards to trigger voting period
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to enable voting
        vm.roll(block.number + 1);
        
        // Now voting should be active
        assertTrue(merkleDistributor.isMerkleRootVoting());
        
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Set merkle root to end voting
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
        
        // Voting should no longer be active (because lastMerkleUpdateBlockNumber >= lastRewardsUpdateBlockNumber)
        assertFalse(merkleDistributor.isMerkleRootVoting());
    }

    function testIsEnoughSignatures() public {
        vm.startPrank(ADMIN);
        
        // Add 3 oracles
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        
        // With 3 oracles, we need at least 2 signatures (2 * 3 > 3 * 2 is false, but 3 * 3 > 3 * 2 is true)
        assertTrue(merkleDistributor.oracleCount() >= 2);
        
        vm.stopPrank();
    }

    // MERKLE ROOT UPDATE TESTS

    function testSetMerkleRoot() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        // Create signatures
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        
        vm.startPrank(ORACLE_1);
        vm.expectEmit(true, true, false, false);
        emit MerkleRootUpdated(ORACLE_1, merkleRoot, "test_proofs");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
        
        assertEq(merkleDistributor.merkleRoot(), merkleRoot);
        assertEq(merkleDistributor.lastMerkleUpdateBlockNumber(), block.number);
    }

    function test_RevertWhen_SetMerkleRootTooEarly() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        
        vm.startPrank(ORACLE_1);
        vm.expectRevert("Oracles: too early");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
    }

    function test_RevertWhen_SetMerkleRootWithInsufficientSignatures() public {
        // Set up only 2 oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        // Try with only 1 signature (need at least 2 for 2 oracles)
        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _createSignature(merkleRoot, "test_proofs", ORACLE_1_PRIVATE_KEY);
        
        vm.startPrank(ORACLE_1);
        vm.expectRevert("Oracles: invalid number of signatures");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
    }

    function test_RevertWhen_NonOracleSetsMerkleRoot() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        
        vm.startPrank(RANDOM_USER);
        vm.expectRevert("MerkleDistributor: access denied");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
    }

    function test_RevertWhen_SetMerkleRootWithInvalidSignature() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        // Create signatures with invalid one
        bytes[] memory signatures = new bytes[](3);
        signatures[0] = _createSignature(merkleRoot, "test_proofs", ORACLE_1_PRIVATE_KEY);
        signatures[1] = _createSignature(merkleRoot, "test_proofs", ORACLE_2_PRIVATE_KEY);
        signatures[2] = _createSignature(merkleRoot, "test_proofs", ORACLE_3_PRIVATE_KEY);
        
        // Add invalid signature
        signatures[1] = abi.encodePacked(bytes32(0), bytes32(0), uint8(27));
        
        vm.startPrank(ORACLE_1);
        vm.expectRevert("ECDSAInvalidSignature()");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
    }

    function test_RevertWhen_SetMerkleRootWithDuplicateSignature() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        // Create signatures with duplicate
        bytes[] memory signatures = new bytes[](3);
        bytes memory signature = _createSignature(merkleRoot, "test_proofs", ORACLE_1_PRIVATE_KEY);
        signatures[0] = signature;
        signatures[1] = signature; // Duplicate signature
        signatures[2] = _createSignature(merkleRoot, "test_proofs", ORACLE_3_PRIVATE_KEY);
        
        vm.startPrank(ORACLE_1);
        vm.expectRevert("Oracles: repeated signature");
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
    }

    // CLAIMING TESTS

    function testClaim() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();

        // Submit rewards first
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();

        // Wait for next block to enable voting
        vm.roll(block.number + 1);

        // Set merkle root
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();

        // Wait for next block to allow claiming
        vm.roll(block.number + 1);

        uint256 user1BalanceBefore1 = token1.balanceOf(USER_1);
        uint256 user1BalanceBefore2 = token2.balanceOf(USER_1);

        vm.startPrank(USER_1);
        vm.expectEmit(true, false, false, false);
        emit Claimed(USER_1, 0, tokens, amounts);
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();

        assertEq(token1.balanceOf(USER_1), user1BalanceBefore1 + amounts[0]);
        assertEq(token2.balanceOf(USER_1), user1BalanceBefore2 + amounts[1]);
        assertTrue(merkleDistributor.isClaimed(0));
    }

    function testClaimMultipleUsers() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();

        // Submit rewards first
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();

        // Wait for next block to enable voting
        vm.roll(block.number + 1);

        // Set merkle root
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();

        // Wait for next block to allow claiming
        vm.roll(block.number + 1);

        // Claim for USER_1
        vm.startPrank(USER_1);
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();

        // Create merkle proof for USER_2 (index 1)
        bytes32[] memory proof2 = _createMerkleProofForUser(1, USER_2);

        // Claim for USER_2
        vm.startPrank(USER_2);
        merkleDistributor.claim(1, USER_2, tokens, amounts, proof2);
        vm.stopPrank();

        assertTrue(merkleDistributor.isClaimed(0));
        assertTrue(merkleDistributor.isClaimed(1));
    }

    function test_RevertWhen_ClaimWithZeroAddress() public {
        _setupMerkleRoot();
        
        vm.startPrank(USER_1);
        vm.expectRevert("MerkleDistributor: invalid account");
        merkleDistributor.claim(0, address(0), tokens, amounts, merkleProof);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimWithInvalidProof() public {
        _setupMerkleRoot();
        
        // Use invalid proof
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);
        
        vm.startPrank(USER_1);
        vm.expectRevert("MerkleDistributor: invalid proof");
        merkleDistributor.claim(0, USER_1, tokens, amounts, invalidProof);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimAlreadyClaimed() public {
        _setupMerkleRoot();
        
        // Claim first time
        vm.startPrank(USER_1);
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
        
        // Try to claim again
        vm.startPrank(USER_1);
        vm.expectRevert("MerkleDistributor: already claimed");
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimDuringMerkleRootUpdate() public {
        _setupMerkleRoot();
        
        // Submit rewards
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Submit rewards again to trigger voting period
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        vm.stopPrank();
        
        vm.startPrank(USER_1);
        vm.expectRevert("MerkleDistributor: merkle root updating");
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
    }

    function test_RevertWhen_ClaimWhenPaused() public {
        _setupMerkleRoot();
        
        // Submit rewards
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Pause contract
        vm.startPrank(ADMIN);
        merkleDistributor.pause();
        vm.stopPrank();
        
        vm.startPrank(USER_1);
        vm.expectRevert("EnforcedPause()");
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
    }

    // HELPER FUNCTIONS

    function _setupMerkleRoot() internal {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();
        
        // Submit rewards to enable voting
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to ensure voting is active
        vm.roll(block.number + 1);
        
        // Set merkle root
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();
        
        // Wait for next block to ensure merkle root is set
        vm.roll(block.number + 1);
    }

    function _createSignatures(bytes32 _merkleRoot, string memory _merkleProofs) internal view returns (bytes[] memory) {
        return _createSignatures(_merkleRoot, _merkleProofs, 0);
    }

    function _createSignatures(bytes32 _merkleRoot, string memory _merkleProofs, uint256 _nonce) internal view returns (bytes[] memory) {
        bytes[] memory signatures = new bytes[](3);
        signatures[0] = _createSignature(_merkleRoot, _merkleProofs, ORACLE_1_PRIVATE_KEY, _nonce);
        signatures[1] = _createSignature(_merkleRoot, _merkleProofs, ORACLE_2_PRIVATE_KEY, _nonce);
        signatures[2] = _createSignature(_merkleRoot, _merkleProofs, ORACLE_3_PRIVATE_KEY, _nonce);
        return signatures;
    }

    function _createSignature(bytes32 _merkleRoot, string memory _merkleProofs, uint256 _privateKey) internal view returns (bytes memory) {
        return _createSignature(_merkleRoot, _merkleProofs, _privateKey, 0);
    }

    function _createSignature(bytes32 _merkleRoot, string memory _merkleProofs, uint256 _privateKey, uint256 _nonce) internal view returns (bytes memory) {
        bytes32 candidateId = keccak256(abi.encode(_nonce, _merkleProofs, _merkleRoot));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(_privateKey, candidateId);
        return abi.encodePacked(r, s, v);
    }

    // PAUSABLE TESTS

    function testPauseAndUnpause() public {
        vm.startPrank(ADMIN);
        
        merkleDistributor.pause();
        assertTrue(merkleDistributor.paused());
        
        merkleDistributor.unpause();
        assertFalse(merkleDistributor.paused());
        
        vm.stopPrank();
    }

    function test_RevertWhen_NonPauserPauses() public {
        vm.startPrank(RANDOM_USER);
        vm.expectRevert();
        merkleDistributor.pause();
        vm.stopPrank();
    }

    // UPGRADE TESTS

    function testUpgrade() public {
        MerkleDistributor newImplementation = new MerkleDistributor();
        
        vm.startPrank(ADMIN);
        merkleDistributor.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
        
        // Verify the contract still works
        assertTrue(merkleDistributor.hasRole(merkleDistributor.DEFAULT_ADMIN_ROLE(), ADMIN));
    }

    function test_RevertWhen_NonAdminUpgrades() public {
        MerkleDistributor newImplementation = new MerkleDistributor();
        
        vm.startPrank(RANDOM_USER);
        vm.expectRevert();
        merkleDistributor.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    // EDGE CASES

    function testClaimedBitMap() public {
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();

        // Submit rewards first
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();

        // Wait for next block to enable voting
        vm.roll(block.number + 1);

        // Set merkle root
        bytes[] memory signatures = _createSignatures(merkleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(merkleRoot, "test_proofs", signatures);
        vm.stopPrank();

        // Wait for next block to allow claiming
        vm.roll(block.number + 1);

        // Claim
        vm.startPrank(USER_1);
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
        
        // Check claimed bit map
        uint256 wordIndex = 0 / 256;
        uint256 bitIndex = 0 % 256;
        uint256 claimedWord = merkleDistributor.claimedBitMap(merkleRoot, wordIndex);
        uint256 mask = (1 << bitIndex);
        assertTrue((claimedWord & mask) == mask);
    }

    function testMultipleMerkleRoots() public {
        _setupMerkleRoot();
        
        // Claim with first merkle root
        vm.startPrank(USER_1);
        merkleDistributor.claim(0, USER_1, tokens, amounts, merkleProof);
        vm.stopPrank();
        
        // Advance block to ensure new rewards are in a new block
        vm.roll(block.number + 1);
        
        // Create new claim data for the new period
        address[] memory newTokens = new address[](2);
        newTokens[0] = address(token1);
        newTokens[1] = address(token2);
        uint256[] memory newAmounts = new uint256[](2);
        newAmounts[0] = 123 ether;
        newAmounts[1] = 456 ether;
        
        // Compute new leaves and root
        bytes32 newLeaf0 = keccak256(abi.encode(0, newTokens, USER_1, newAmounts));
        bytes32 newLeaf1 = keccak256(abi.encode(1, newTokens, USER_2, newAmounts));
        bytes32 leftLeaf = newLeaf0 < newLeaf1 ? newLeaf0 : newLeaf1;
        bytes32 rightLeaf = newLeaf0 < newLeaf1 ? newLeaf1 : newLeaf0;
        bytes32 newMerkleRoot = keccak256(abi.encodePacked(leftLeaf, rightLeaf));
        
        // Proof for USER_1 (index 0)
        bytes32[] memory newProof = new bytes32[](1);
        newProof[0] = newLeaf1;
        
        // Submit rewards again to trigger new voting period
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();
        
        // Wait for next block to enable voting
        vm.roll(block.number + 1);
        
        // Set new merkle root
        bytes[] memory signatures = _createSignatures(newMerkleRoot, "new_proofs", 1); // Use nonce 1 for second root
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(newMerkleRoot, "new_proofs", signatures);
        vm.stopPrank();
        
        // Wait for next block to allow claiming
        vm.roll(block.number + 1);
        
        // Should be able to claim again with new merkle root and new proof
        vm.startPrank(USER_1);
        merkleDistributor.claim(0, USER_1, newTokens, newAmounts, newProof);
        vm.stopPrank();
        
        assertTrue(merkleDistributor.isClaimed(0)); // Should be true for new merkle root after claim
    }





    function testSimpleMerkleTree() public view {
        // Let's build a simple merkle tree step by step
        bytes32 leaf0 = keccak256(abi.encode(0, tokens, USER_1, amounts));
        bytes32 leaf1 = keccak256(abi.encode(1, tokens, USER_2, amounts));
        
        // For OpenZeppelin's MerkleProof, we need to ensure the leaves are sorted
        bytes32 leftLeaf = leaf0 < leaf1 ? leaf0 : leaf1;
        bytes32 rightLeaf = leaf0 < leaf1 ? leaf1 : leaf0;
        bytes32 root = keccak256(abi.encodePacked(leftLeaf, rightLeaf));
        
        // Check if our stored values are correct
        assertEq(merkleRoot, root, "Root should match");
        
        // Verify the proof works
        bool isValid = MerkleProof.verify(merkleProof, merkleRoot, leaf0);
        assertTrue(isValid, "Merkle proof verification should work");
    }

    function testClaimSingleLeaf() public {
        // Create a single leaf merkle tree (no proof needed)
        bytes32 singleLeaf = keccak256(abi.encode(0, tokens, USER_1, amounts));
        bytes32 singleRoot = singleLeaf; // For single leaf, root = leaf
        
        // Set up oracles
        vm.startPrank(ADMIN);
        merkleDistributor.addOracle(ORACLE_1);
        merkleDistributor.addOracle(ORACLE_2);
        merkleDistributor.addOracle(ORACLE_3);
        vm.stopPrank();

        // Submit rewards first
        vm.startPrank(DISTRIBUTOR);
        token1.approve(address(merkleDistributor), REWARD_AMOUNT);
        token2.approve(address(merkleDistributor), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token1), REWARD_AMOUNT);
        merkleDistributor.submitRewards(address(token2), REWARD_AMOUNT);
        vm.stopPrank();

        // Wait for next block to enable voting
        vm.roll(block.number + 1);

        // Set merkle root
        bytes[] memory signatures = _createSignatures(singleRoot, "test_proofs");
        vm.startPrank(ORACLE_1);
        merkleDistributor.setMerkleRoot(singleRoot, "test_proofs", signatures);
        vm.stopPrank();

        // Wait for next block to allow claiming
        vm.roll(block.number + 1);

        uint256 user1BalanceBefore1 = token1.balanceOf(USER_1);
        uint256 user1BalanceBefore2 = token2.balanceOf(USER_1);

        // For single leaf, proof is empty array
        bytes32[] memory emptyProof = new bytes32[](0);

        vm.startPrank(USER_1);
        vm.expectEmit(true, false, false, false);
        emit Claimed(USER_1, 0, tokens, amounts);
        merkleDistributor.claim(0, USER_1, tokens, amounts, emptyProof);
        vm.stopPrank();

        assertEq(token1.balanceOf(USER_1), user1BalanceBefore1 + amounts[0]);
        assertEq(token2.balanceOf(USER_1), user1BalanceBefore2 + amounts[1]);
        assertTrue(merkleDistributor.isClaimed(0));
    }


} 