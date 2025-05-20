// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {IFeeCollector} from "../src/interfaces/IFeeCollector.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

contract FeeCollectorTest is Test {
    // Test roles
    address public constant ADMIN = address(0x1);
    address public constant DISTRIBUTOR = address(0x2);
    address public constant WORKER = address(0x3);
    address public constant TRADER = address(0x4);
    address public constant RANDOM_USER = address(0x5);

    // Test constants
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether;
    uint256 public constant BASE_PERCENTAGE = 10_000;
    uint256 public constant PROTOCOL_FEE_BPS = 2_000; // 20%
    uint256 public constant LP_FEE_BPS = 5_000; // 50%

    // Destination chain
    uint256 public constant DEST_CHAIN_ID = 42; // Random chain ID for testing

    // Mock ERC20 token (USDC)
    MockERC20 public stablecoin;

    // Test contracts
    FeeCollector public feeCollector;
    GeniusVault public vault;

    // Events to test
    event FeesCollectedFromVault(
        bytes32 indexed orderHash,
        uint256 protocolFee,
        uint256 lpFee,
        uint256 operatorFee
    );
    event ProtocolFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );
    event LPFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );
    event OperatorFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );
    event VaultSet(address vault);
    event ProtocolFeeUpdated(uint256 protocolFee);
    event FeeTiersUpdated(uint256[] thresholdAmounts, uint256[] bpsFees);
    event InsuranceFeeTiersUpdated(
        uint256[] thresholdAmounts,
        uint256[] bpsFees
    );
    event TargetChainMinFeeChanged(uint256 targetChainId, uint256 newMinFee);

    function setUp() public {
        // Deploy stablecoin
        stablecoin = new MockERC20("USD Coin", "USDC", 18);
        stablecoin.mint(ADMIN, INITIAL_SUPPLY);
        stablecoin.mint(TRADER, INITIAL_SUPPLY);
        stablecoin.mint(RANDOM_USER, INITIAL_SUPPLY);

        // Deploy FeeCollector
        FeeCollector implementation = new FeeCollector();

        bytes memory data = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            ADMIN,
            address(stablecoin),
            PROTOCOL_FEE_BPS, // Only passing protocolFee now, lpFee is calculated automatically
            ADMIN,
            DISTRIBUTOR,
            WORKER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        feeCollector = FeeCollector(address(proxy));

        // Set up vault mock (we'll use a real vault for integration testing later)
        vm.startPrank(ADMIN);
        // Create a mock vault address - we use this for testing authorization
        vault = GeniusVault(makeAddr("VAULT"));
        feeCollector.setVault(address(vault));

        // Set up roles
        feeCollector.grantRole(feeCollector.DISTRIBUTOR_ROLE(), DISTRIBUTOR);
        feeCollector.grantRole(feeCollector.WORKER_ROLE(), WORKER);

        // Set up fee tiers
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 100 ether;
        thresholdAmounts[1] = 1000 ether;
        thresholdAmounts[2] = 10000 ether;

        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 50; // 0.5%
        bpsFees[1] = 30; // 0.3%
        bpsFees[2] = 20; // 0.2%

        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);

        // Set up insurance fee tiers
        uint256[] memory insThresholdAmounts = new uint256[](3);
        insThresholdAmounts[0] = 100 ether;
        insThresholdAmounts[1] = 1000 ether;
        insThresholdAmounts[2] = 10000 ether;

        uint256[] memory insBpsFees = new uint256[](3);
        insBpsFees[0] = 30; // 0.3%
        insBpsFees[1] = 20; // 0.2%
        insBpsFees[2] = 10; // 0.1%

        feeCollector.setInsuranceFeeTiers(insThresholdAmounts, insBpsFees);

        // Set up minimum fee for destination chain
        feeCollector.setTargetChainMinFee(DEST_CHAIN_ID, 1 ether);

        vm.stopPrank();
    }

    // INITIALIZATION TESTS

    function testInitialization() public view {
        assertEq(address(feeCollector.stablecoin()), address(stablecoin));

        // Use call to access public variable
        (bool success, bytes memory data) = address(feeCollector).staticcall(
            abi.encodeWithSignature("protocolFee()")
        );
        require(success, "Call failed");
        uint256 protocolFee = abi.decode(data, (uint256));

        assertEq(protocolFee, PROTOCOL_FEE_BPS);
        assertEq(feeCollector.vault(), address(vault));

        // Check roles
        assertTrue(
            feeCollector.hasRole(feeCollector.DEFAULT_ADMIN_ROLE(), ADMIN)
        );
        assertTrue(
            feeCollector.hasRole(feeCollector.DISTRIBUTOR_ROLE(), DISTRIBUTOR)
        );
        assertTrue(feeCollector.hasRole(feeCollector.WORKER_ROLE(), WORKER));

        // Check fee tiers
        (uint256 threshold, uint256 fee) = feeCollector.feeTiers(0);
        assertEq(threshold, 100 ether);
        assertEq(fee, 50);

        (threshold, fee) = feeCollector.feeTiers(1);
        assertEq(threshold, 1000 ether);
        assertEq(fee, 30);

        (threshold, fee) = feeCollector.feeTiers(2);
        assertEq(threshold, 10000 ether);
        assertEq(fee, 20);

        // Check insurance fee tiers
        (threshold, fee) = feeCollector.insuranceFeeTiers(0);
        assertEq(threshold, 100 ether);
        assertEq(fee, 30);

        (threshold, fee) = feeCollector.insuranceFeeTiers(1);
        assertEq(threshold, 1000 ether);
        assertEq(fee, 20);

        (threshold, fee) = feeCollector.insuranceFeeTiers(2);
        assertEq(threshold, 10000 ether);
        assertEq(fee, 10);

        // Check min fee
        assertEq(feeCollector.targetChainMinFee(DEST_CHAIN_ID), 1 ether);
    }

    function test_RevertWhen_InitializeWithZeroAddress() public {
        FeeCollector implementation = new FeeCollector();

        bytes memory data = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            address(0), // Zero address for admin
            address(stablecoin),
            PROTOCOL_FEE_BPS, // Only passing protocolFee now
            ADMIN,
            DISTRIBUTOR,
            WORKER
        );

        vm.expectRevert();
        new ERC1967Proxy(address(implementation), data);
    }

    function test_RevertWhen_InitializeWithZeroStablecoin() public {
        FeeCollector implementation = new FeeCollector();

        bytes memory data = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            ADMIN,
            address(0), // Zero address for stablecoin
            PROTOCOL_FEE_BPS, // Only passing protocolFee now
            ADMIN,
            DISTRIBUTOR,
            WORKER
        );

        vm.expectRevert();
        new ERC1967Proxy(address(implementation), data);
    }

    function test_RevertWhen_InitializeWithInvalidFeePercentages() public {
        FeeCollector implementation = new FeeCollector();

        bytes memory data = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            ADMIN,
            address(stablecoin),
            11_000, // > 100%, which is invalid
            ADMIN,
            DISTRIBUTOR,
            WORKER
        );

        vm.expectRevert();
        new ERC1967Proxy(address(implementation), data);
    }

    // ADMIN FUNCTIONS TESTS

    function testSetVault() public {
        address newVault = makeAddr("NEW_VAULT");

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit VaultSet(newVault);
        feeCollector.setVault(newVault);
        vm.stopPrank();

        assertEq(feeCollector.vault(), newVault);
    }

    function test_RevertWhen_SetVaultNonAdmin() public {
        address newVault = makeAddr("NEW_VAULT");

        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.setVault(newVault);
    }

    function test_RevertWhen_SetVaultZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setVault(address(0));
    }

    function testSetProtocolFee() public {
        uint256 newProtocolFee = 3_000; // 30%

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeeUpdated(newProtocolFee);
        feeCollector.setProtocolFee(newProtocolFee);
        vm.stopPrank();

        // Access internal variables via low-level call
        (bool success, bytes memory data) = address(feeCollector).staticcall(
            abi.encodeWithSignature("protocolFee()")
        );
        require(success, "Call failed");
        uint256 protocolFee = abi.decode(data, (uint256));

        assertEq(protocolFee, newProtocolFee);
    }

    function test_RevertWhen_SetProtocolFeeNonAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.setProtocolFee(3_000);
    }

    function test_RevertWhen_SetProtocolFeeInvalidPercentage() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setProtocolFee(11_000); // > 100%
    }

    function testSetFeeTiers() public {
        uint256[] memory newThresholdAmounts = new uint256[](2);
        newThresholdAmounts[0] = 500 ether;
        newThresholdAmounts[1] = 5000 ether;

        uint256[] memory newBpsFees = new uint256[](2);
        newBpsFees[0] = 40; // 0.4%
        newBpsFees[1] = 25; // 0.25%

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit FeeTiersUpdated(newThresholdAmounts, newBpsFees);
        feeCollector.setFeeTiers(newThresholdAmounts, newBpsFees);
        vm.stopPrank();

        (uint256 threshold, uint256 fee) = feeCollector.feeTiers(0);
        assertEq(threshold, 500 ether);
        assertEq(fee, 40);

        (threshold, fee) = feeCollector.feeTiers(1);
        assertEq(threshold, 5000 ether);
        assertEq(fee, 25);
    }

    function test_RevertWhen_SetFeeTiersNonAdmin() public {
        uint256[] memory thresholdAmounts = new uint256[](2);
        uint256[] memory bpsFees = new uint256[](2);

        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
    }

    function test_RevertWhen_SetFeeTiersEmptyArray() public {
        uint256[] memory thresholdAmounts = new uint256[](0);
        uint256[] memory bpsFees = new uint256[](0);

        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
    }

    function test_RevertWhen_SetFeeTiersArrayLengthMismatch() public {
        uint256[] memory thresholdAmounts = new uint256[](2);
        uint256[] memory bpsFees = new uint256[](3);

        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
    }

    function test_RevertWhen_SetFeeTiersOutOfOrder() public {
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 100 ether;
        thresholdAmounts[1] = 1000 ether;
        thresholdAmounts[2] = 500 ether; // Out of order

        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 50;
        bpsFees[1] = 30;
        bpsFees[2] = 20;

        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
    }

    function test_RevertWhen_SetFeeTiersInvalidPercentage() public {
        uint256[] memory thresholdAmounts = new uint256[](2);
        thresholdAmounts[0] = 100 ether;
        thresholdAmounts[1] = 1000 ether;

        uint256[] memory bpsFees = new uint256[](2);
        bpsFees[0] = 50;
        bpsFees[1] = 12000; // Over 100%

        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
    }

    function testSetInsuranceFeeTiers() public {
        uint256[] memory newThresholdAmounts = new uint256[](2);
        newThresholdAmounts[0] = 500 ether;
        newThresholdAmounts[1] = 5000 ether;

        uint256[] memory newBpsFees = new uint256[](2);
        newBpsFees[0] = 25; // 0.25%
        newBpsFees[1] = 15; // 0.15%

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit InsuranceFeeTiersUpdated(newThresholdAmounts, newBpsFees);
        feeCollector.setInsuranceFeeTiers(newThresholdAmounts, newBpsFees);
        vm.stopPrank();

        (uint256 threshold, uint256 fee) = feeCollector.insuranceFeeTiers(0);
        assertEq(threshold, 500 ether);
        assertEq(fee, 25);

        (threshold, fee) = feeCollector.insuranceFeeTiers(1);
        assertEq(threshold, 5000 ether);
        assertEq(fee, 15);
    }

    function testSetTargetChainMinFee() public {
        uint256 destChainId = 100;
        uint256 minFee = 2 ether;

        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit TargetChainMinFeeChanged(destChainId, minFee);
        feeCollector.setTargetChainMinFee(destChainId, minFee);
        vm.stopPrank();

        assertEq(feeCollector.targetChainMinFee(destChainId), minFee);
    }

    function test_RevertWhen_SetTargetChainMinFeeInvalidChainId() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.setTargetChainMinFee(block.chainid, 1 ether);
    }

    // FEE CALCULATION TESTS

    function testGetOrderFees() public view {
        uint256 orderAmount = 500 ether; // Between first and second tier

        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        // Base fee should be set from targetChainMinFee
        assertEq(fees.baseFee, 1 ether);

        // BPS fee should be from the first tier (0.5% of 500 ether)
        assertEq(fees.bpsFee, (500 ether * 50) / BASE_PERCENTAGE);

        // Insurance fee should be from the first tier (0.3% of 500 ether)
        assertEq(fees.insuranceFee, (500 ether * 30) / BASE_PERCENTAGE);

        // Total fee should be the sum
        assertEq(fees.totalFee, fees.baseFee + fees.bpsFee + fees.insuranceFee);
    }

    function testGetOrderFeesLargeTier() public view {
        uint256 orderAmount = 20000 ether; // Above the highest tier

        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        // Base fee should be set from targetChainMinFee
        assertEq(fees.baseFee, 1 ether);

        // BPS fee should be from the highest tier (0.2% of 20000 ether)
        assertEq(fees.bpsFee, (20000 ether * 20) / BASE_PERCENTAGE);

        // Insurance fee should be from the highest tier (0.1% of 20000 ether)
        assertEq(fees.insuranceFee, (20000 ether * 10) / BASE_PERCENTAGE);

        // Total fee should be the sum
        assertEq(fees.totalFee, fees.baseFee + fees.bpsFee + fees.insuranceFee);
    }

    // FEE COLLECTION TESTS

    function testCollect() public {
        uint256 orderAmount = 500 ether;

        // Calculate expected fee breakdown
        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Expected fee distribution
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee = expectedFees.bpsFee - expectedProtocolFee; // LP fee is remainder
        uint256 expectedOperatorFee = expectedFees.baseFee; // No surplus in this test

        // Simulate vault calling collect
        vm.startPrank(address(vault));
        vm.expectEmit(true, true, true, true);
        emit FeesCollectedFromVault(
            bytes32(0),
            expectedProtocolFee,
            expectedLpFee,
            expectedOperatorFee
        );

        uint256 amountToTransfer = feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee // Exact fee amount
        );
        vm.stopPrank();

        // Verify that the returned amount is correct (total fees minus insurance fees)
        assertEq(
            amountToTransfer,
            expectedFees.totalFee - expectedFees.insuranceFee
        );

        // Verify state changes
        assertEq(feeCollector.protocolFeesCollected(), expectedProtocolFee);
        assertEq(feeCollector.lpFeesCollected(), expectedLpFee);
        assertEq(feeCollector.operatorFeesCollected(), expectedOperatorFee);
    }

    function testCollectWithSurplus() public {
        uint256 orderAmount = 500 ether;

        // Calculate expected fee breakdown
        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Add a surplus to the fee
        uint256 surplus = 0.5 ether;
        uint256 totalFeeWithSurplus = expectedFees.totalFee + surplus;

        // Expected fee distribution
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee = expectedFees.bpsFee - expectedProtocolFee; // LP fee is remainder
        uint256 expectedOperatorFee = expectedFees.baseFee + surplus; // Base fee plus surplus

        // Simulate vault calling collect
        vm.startPrank(address(vault));
        vm.expectEmit(true, true, true, true);
        emit FeesCollectedFromVault(
            bytes32(0),
            expectedProtocolFee,
            expectedLpFee,
            expectedOperatorFee
        );

        uint256 amountToTransfer = feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            totalFeeWithSurplus // Fee amount with surplus
        );
        vm.stopPrank();

        // Verify that the returned amount is correct (total fees with surplus minus insurance fees)
        assertEq(
            amountToTransfer,
            totalFeeWithSurplus - expectedFees.insuranceFee
        );

        // Verify state changes
        assertEq(feeCollector.protocolFeesCollected(), expectedProtocolFee);
        assertEq(feeCollector.lpFeesCollected(), expectedLpFee);
        assertEq(feeCollector.operatorFeesCollected(), expectedOperatorFee);
    }

    function test_RevertWhen_CollectInsufficientFees() public {
        uint256 orderAmount = 500 ether;

        // Calculate expected fee breakdown
        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Use insufficient fee (1 wei less than required)
        uint256 insufficientFee = expectedFees.totalFee - 1;

        // Simulate vault calling collectFromVault with insufficient fee
        vm.prank(address(vault));
        vm.expectRevert();
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            insufficientFee
        );
    }

    function test_RevertWhen_CollectNonVault() public {
        uint256 orderAmount = 500 ether;
        uint256 fee = 10 ether;

        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            fee
        );
    }

    // FEE CLAIMING TESTS

    function testClaimProtocolFees() public {
        // First, add some fees
        uint256 orderAmount = 1000 ether;

        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Simulate vault calling collect
        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee
        );

        // Calculate expected protocol fee
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;

        // Transfer tokens to the fee collector so it can pay out
        stablecoin.mint(address(feeCollector), expectedProtocolFee);

        // Claim protocol fees as admin
        vm.startPrank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit ProtocolFeesClaimed(ADMIN, ADMIN, expectedProtocolFee);

        uint256 claimedAmount = feeCollector.claimProtocolFees();
        vm.stopPrank();

        // Verify claimed amount
        assertEq(claimedAmount, expectedProtocolFee);

        // Verify state changes
        assertEq(feeCollector.protocolFeesClaimed(), expectedProtocolFee);
        assertEq(
            stablecoin.balanceOf(ADMIN),
            INITIAL_SUPPLY + expectedProtocolFee
        );
    }

    function test_RevertWhen_ClaimProtocolFeesNonAdmin() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.claimProtocolFees();
    }

    function test_RevertWhen_ClaimProtocolFeesNoFees() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        feeCollector.claimProtocolFees();
    }

    function testClaimLPFees() public {
        // First, add some fees
        uint256 orderAmount = 1000 ether;

        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Simulate vault calling collect
        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee
        );

        // Calculate expected LP fee
        // LP fee is now the remainder after protocol fee is taken from bpsFee
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee = expectedFees.bpsFee - expectedProtocolFee;

        // Transfer tokens to the fee collector so it can pay out
        stablecoin.mint(address(feeCollector), expectedLpFee);

        // Claim LP fees as distributor
        vm.startPrank(DISTRIBUTOR);
        vm.expectEmit(true, true, true, true);
        emit LPFeesClaimed(DISTRIBUTOR, DISTRIBUTOR, expectedLpFee);

        uint256 claimedAmount = feeCollector.claimLPFees();
        vm.stopPrank();

        // Verify claimed amount
        assertEq(claimedAmount, expectedLpFee);

        // Verify state changes
        assertEq(feeCollector.lpFeesClaimed(), expectedLpFee);
        assertEq(stablecoin.balanceOf(DISTRIBUTOR), expectedLpFee);
    }

    function test_RevertWhen_ClaimLPFeesNonDistributor() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.claimLPFees();
    }

    function testClaimOperatorFees() public {
        // First, add some fees
        uint256 orderAmount = 1000 ether;

        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Simulate vault calling collectFromVault
        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee
        );

        // Calculate expected operator fee (just the base fee in this case)
        uint256 expectedOperatorFee = expectedFees.baseFee;

        // Transfer tokens to the fee collector so it can pay out
        stablecoin.mint(address(feeCollector), expectedOperatorFee);

        // Claim operator fees as worker
        vm.startPrank(WORKER);
        vm.expectEmit(true, true, true, true);
        emit OperatorFeesClaimed(WORKER, WORKER, expectedOperatorFee);

        uint256 claimedAmount = feeCollector.claimOperatorFees();
        vm.stopPrank();

        // Verify claimed amount
        assertEq(claimedAmount, expectedOperatorFee);

        // Verify state changes
        assertEq(feeCollector.operatorFeesClaimed(), expectedOperatorFee);
        assertEq(stablecoin.balanceOf(WORKER), expectedOperatorFee);
    }

    function test_RevertWhen_ClaimOperatorFeesNonWorker() public {
        vm.prank(RANDOM_USER);
        vm.expectRevert();
        feeCollector.claimOperatorFees();
    }

    // VIEW FUNCTION TESTS

    function testClaimableFeeAmounts() public {
        // First, add some fees
        uint256 orderAmount = 1000 ether;

        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Simulate vault calling collect
        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee
        );

        // Calculate expected fees
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee = expectedFees.bpsFee - expectedProtocolFee; // LP fee is remainder
        uint256 expectedOperatorFee = expectedFees.baseFee;

        // Check claimable amounts
        assertEq(feeCollector.claimableProtocolFees(), expectedProtocolFee);
        assertEq(feeCollector.claimableLPFees(), expectedLpFee);
        assertEq(feeCollector.claimableOperatorFees(), expectedOperatorFee);

        // Now claim some fees and check again
        stablecoin.mint(address(feeCollector), expectedProtocolFee);
        vm.prank(ADMIN);
        feeCollector.claimProtocolFees();

        // Protocol fees should be 0, others unchanged
        assertEq(feeCollector.claimableProtocolFees(), 0);
        assertEq(feeCollector.claimableLPFees(), expectedLpFee);
        assertEq(feeCollector.claimableOperatorFees(), expectedOperatorFee);
    }

    // INTEGRATION TEST WITH VAULT

    function testIntegrationWithVault() public {
        // This test requires a real vault instance
        // For simplicity, we'll use vm.mockCall to simulate vault behavior

        uint256 orderAmount = 1000 ether;

        // Get expected fees
        IFeeCollector.FeeBreakdown memory expectedFees = feeCollector
            .getOrderFees(orderAmount, DEST_CHAIN_ID);

        // Simulate a vault collecting fees
        vm.startPrank(address(vault));
        uint256 amountToTransfer = feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            expectedFees.totalFee
        );
        vm.stopPrank();

        // Expected fee distribution
        uint256 expectedProtocolFee = (expectedFees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee = expectedFees.bpsFee - expectedProtocolFee; // LP fee is remainder
        uint256 expectedOperatorFee = expectedFees.baseFee;

        // The vault should transfer amountToTransfer to the fee collector
        stablecoin.mint(address(feeCollector), amountToTransfer);

        // Now verify that the fees can be claimed correctly

        // Admin claims protocol fees
        vm.startPrank(ADMIN);
        stablecoin.balanceOf(ADMIN);
        feeCollector.claimProtocolFees();
        vm.stopPrank();

        // Distributor claims LP fees
        vm.startPrank(DISTRIBUTOR);
        feeCollector.claimLPFees();
        vm.stopPrank();

        // Worker claims operator fees
        vm.startPrank(WORKER);
        feeCollector.claimOperatorFees();
        vm.stopPrank();

        // Check balances after claims
        assertEq(
            stablecoin.balanceOf(ADMIN),
            INITIAL_SUPPLY + expectedProtocolFee
        );
        assertEq(stablecoin.balanceOf(DISTRIBUTOR), expectedLpFee);
        assertEq(stablecoin.balanceOf(WORKER), expectedOperatorFee);

        // Check contract state
        assertEq(feeCollector.protocolFeesCollected(), expectedProtocolFee);
        assertEq(feeCollector.protocolFeesClaimed(), expectedProtocolFee);
        assertEq(feeCollector.lpFeesCollected(), expectedLpFee);
        assertEq(feeCollector.lpFeesClaimed(), expectedLpFee);
        assertEq(feeCollector.operatorFeesCollected(), expectedOperatorFee);
        assertEq(feeCollector.operatorFeesClaimed(), expectedOperatorFee);
    }

    // UPGRADE TESTS

    function testAuthorizeUpgrade() public {
        FeeCollector newImplementation = new FeeCollector();

        // Only admin should be able to upgrade
        vm.startPrank(ADMIN);

        // Use a low-level call to simulate the UUPS upgrade pattern
        (bool success, ) = address(feeCollector).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(newImplementation),
                ""
            )
        );

        assertTrue(success, "Upgrade should succeed");
        vm.stopPrank();
    }

    function test_RevertWhen_AuthorizeUpgradeNonAdmin() public {
        FeeCollector newImplementation = new FeeCollector();

        vm.startPrank(RANDOM_USER);

        // Use a low-level call to simulate the UUPS upgrade pattern
        vm.expectRevert();
        (bool success, ) = address(feeCollector).call(
            abi.encodeWithSignature(
                "upgradeToAndCall(address,bytes)",
                address(newImplementation),
                ""
            )
        );

        vm.stopPrank();
    }

    function testZeroAmountOrder() public {
        uint256 orderAmount = 0;

        vm.prank(address(vault));
        vm.expectRevert(); // Should revert with InvalidAmount or similar
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            1 ether // Some arbitrary fee
        );
    }

    function testVeryLargeAmountOrder() public view {
        uint256 orderAmount = type(uint128).max; // Very large but not max uint256 to avoid overflow

        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        // Verify calculations don't overflow
        assertTrue(fees.bpsFee > 0);
        assertTrue(fees.insuranceFee > 0);
        assertTrue(fees.totalFee > 0);
    }

    function testExactTierBoundaryAmount() public view {
        // Test exactly at a tier boundary (1000 ether is the second tier threshold)
        uint256 orderAmount = 1000 ether;

        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        // Should use the second tier fee (30 bps)
        assertEq(fees.bpsFee, (orderAmount * 30) / BASE_PERCENTAGE);
    }

    function testMultipleCollections() public {
        // First collection
        uint256 orderAmount1 = 500 ether;
        IFeeCollector.FeeBreakdown memory fees1 = feeCollector.getOrderFees(
            orderAmount1,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount1,
            DEST_CHAIN_ID,
            fees1.totalFee
        );

        // Second collection
        uint256 orderAmount2 = 2000 ether;
        IFeeCollector.FeeBreakdown memory fees2 = feeCollector.getOrderFees(
            orderAmount2,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount2,
            DEST_CHAIN_ID,
            fees2.totalFee
        );

        // Calculate expected cumulative fees
        uint256 expectedProtocolFee1 = (fees1.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee1 = fees1.bpsFee - expectedProtocolFee1;

        uint256 expectedProtocolFee2 = (fees2.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 expectedLpFee2 = fees2.bpsFee - expectedProtocolFee2;

        // Check cumulative accounting
        assertEq(
            feeCollector.protocolFeesCollected(),
            expectedProtocolFee1 + expectedProtocolFee2
        );
        assertEq(
            feeCollector.lpFeesCollected(),
            expectedLpFee1 + expectedLpFee2
        );
        assertEq(
            feeCollector.operatorFeesCollected(),
            fees1.baseFee + fees2.baseFee
        );
    }

    function testPartialClaimsWithMoreCollections() public {
        // Set up initial fees
        uint256 orderAmount1 = 1000 ether;
        IFeeCollector.FeeBreakdown memory fees1 = feeCollector.getOrderFees(
            orderAmount1,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount1,
            DEST_CHAIN_ID,
            fees1.totalFee
        );

        // Calculate initial fees
        uint256 protocolFee1 = (fees1.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;

        // Transfer tokens for claims
        stablecoin.mint(address(feeCollector), protocolFee1);

        // Partial claim
        vm.prank(ADMIN);
        feeCollector.claimProtocolFees();

        // More fee collection
        uint256 orderAmount2 = 2000 ether;
        IFeeCollector.FeeBreakdown memory fees2 = feeCollector.getOrderFees(
            orderAmount2,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount2,
            DEST_CHAIN_ID,
            fees2.totalFee
        );

        // Calculate second batch fees
        uint256 protocolFee2 = (fees2.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;

        // Check state
        assertEq(
            feeCollector.protocolFeesCollected(),
            protocolFee1 + protocolFee2
        );
        assertEq(feeCollector.protocolFeesClaimed(), protocolFee1);
        assertEq(feeCollector.claimableProtocolFees(), protocolFee2);
    }

    function testZeroInsuranceFee() public {
        // Set insurance tiers to zero
        uint256[] memory insThresholdAmounts = new uint256[](1);
        insThresholdAmounts[0] = 0;

        uint256[] memory insBpsFees = new uint256[](1);
        insBpsFees[0] = 0; // 0%

        vm.prank(ADMIN);
        feeCollector.setInsuranceFeeTiers(insThresholdAmounts, insBpsFees);

        // Test order with zero insurance fee
        uint256 orderAmount = 1000 ether;
        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        // Insurance fee should be zero
        assertEq(fees.insuranceFee, 0);

        // amountToTransfer should equal total fee
        vm.prank(address(vault));
        uint256 amountToTransfer = feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            fees.totalFee
        );

        assertEq(amountToTransfer, fees.totalFee);
    }

    function testInsuranceFeeIsExcludedFromTransfer() public {
        uint256 orderAmount = 1000 ether;
        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        uint256 amountToTransfer = feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            fees.totalFee
        );

        // Verify amount to transfer excludes insurance fee
        assertEq(amountToTransfer, fees.totalFee - fees.insuranceFee);
    }

    function testRevokeAndReassignRoles() public {
        // Test revoking and reassigning roles
        address newDistributor = makeAddr("NEW_DISTRIBUTOR");

        vm.startPrank(ADMIN);
        feeCollector.revokeRole(feeCollector.DISTRIBUTOR_ROLE(), DISTRIBUTOR);
        feeCollector.grantRole(feeCollector.DISTRIBUTOR_ROLE(), newDistributor);
        feeCollector.setLPFeeReceiver(newDistributor);
        vm.stopPrank();

        // Old distributor should no longer be able to claim
        vm.startPrank(DISTRIBUTOR);
        vm.expectRevert();
        feeCollector.claimLPFees();
        vm.stopPrank();

        // Set up some fees first
        uint256 orderAmount = 1000 ether;
        IFeeCollector.FeeBreakdown memory fees = feeCollector.getOrderFees(
            orderAmount,
            DEST_CHAIN_ID
        );

        vm.prank(address(vault));
        feeCollector.collectFromVault(
            bytes32(0),
            orderAmount,
            DEST_CHAIN_ID,
            fees.totalFee
        );

        // Calculate LP fee
        uint256 protocolFee = (fees.bpsFee * PROTOCOL_FEE_BPS) /
            BASE_PERCENTAGE;
        uint256 lpFee = fees.bpsFee - protocolFee;

        // Mint tokens for claiming
        stablecoin.mint(address(feeCollector), lpFee);

        // New distributor should be able to claim
        vm.startPrank(newDistributor);
        feeCollector.claimLPFees();
        vm.stopPrank();

        // Verify the new distributor got the funds
        assertEq(stablecoin.balanceOf(newDistributor), lpFee);
    }
}
