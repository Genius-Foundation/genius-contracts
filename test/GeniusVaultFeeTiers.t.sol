// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultFeeTiers is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;
    uint256 destChainId = 42;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 43114; // avalanche
    uint16 targetChainId = 42; // destination chain

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public WETH;

    GeniusVault public VAULT;

    GeniusProxyCall public PROXYCALL;
    MockDEXRouter public DEX_ROUTER;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);
        
        // Set a deterministic chainId for testing
        uint256 testChainId = 43114; // Avalanche chain ID
        vm.chainId(testChainId);
        sourceChainId = uint16(testChainId);
        
        console.log("Chain ID set to:", block.chainid);

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        RECEIVER = bytes32(uint256(uint160(TRADER)));
        ORCHESTRATOR = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // The hardcoded tx.origin for forge

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB); // WETH on Avalanche
        PROXYCALL = new GeniusProxyCall(OWNER, new address[](0));
        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);

        vm.startPrank(OWNER, OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            86_000,
            99_000_000,
            101_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));
        DEX_ROUTER = new MockDEXRouter();

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));
        
        // Set up chain configurations
        console.log("Setting up chain configs for destChainId:", destChainId);
        console.log("Current chain ID:", block.chainid);
        
        // Set minimum fee for destination chain
        VAULT.setTargetChainMinFee(address(USDC), destChainId, 1 ether);
        
        // Set decimals for both source and destination chains
        VAULT.setChainStablecoinDecimals(destChainId, 6);
        VAULT.setChainStablecoinDecimals(block.chainid, 6);

        // Set up fee tiers
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 0;        // First tier starts at 0 (smallest orders)
        thresholdAmounts[1] = 100 ether; // 100 USDC
        thresholdAmounts[2] = 500 ether; // 500 USDC
        
        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 30; // 0.3% for smallest orders
        bpsFees[1] = 20; // 0.2% for medium orders
        bpsFees[2] = 10; // 0.1% for large orders
        
        VAULT.setFeeTiers(thresholdAmounts, bpsFees);
        
        // Debug: print chain IDs and stablecoin decimals
        console.log("Block ChainID:", block.chainid);
        console.log("Dest ChainID:", destChainId);
        console.log("Chain stablecoin decimals for current chain:", VAULT.chainStablecoinDecimals(block.chainid));

        vm.stopPrank();

        assertEq(
            VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER),
            true,
            "Owner should be ADMIN"
        );

        vm.startPrank(OWNER);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 10_000 ether);
        deal(address(USDC), ORCHESTRATOR, 10_000 ether);
        deal(address(USDC), address(ORCHESTRATOR), 10_000 ether);
    }

    function testFeeTierConfiguration() public view {
        // Access the fee tiers to verify they were set correctly
        (uint256 threshold0, uint256 bps0) = VAULT.feeTiers(0);
        (uint256 threshold1, uint256 bps1) = VAULT.feeTiers(1);
        (uint256 threshold2, uint256 bps2) = VAULT.feeTiers(2);
        
        assertEq(threshold0, 0, "Threshold 0 should be 0");
        assertEq(bps0, 30, "BPS 0 should be 30");
        
        assertEq(threshold1, 100 ether, "Threshold 1 should be 100 ether");
        assertEq(bps1, 20, "BPS 1 should be 20");
        
        assertEq(threshold2, 500 ether, "Threshold 2 should be 500 ether");
        assertEq(bps2, 10, "BPS 2 should be 10");
    }

    function testFeeTierUpdate() public {
        // Try to update the fee tiers
        vm.startPrank(OWNER);
        
        uint256[] memory newThresholdAmounts = new uint256[](2);
        newThresholdAmounts[0] = 0;        // First tier starts at 0
        newThresholdAmounts[1] = 1000 ether; // 1000 USDC
        
        uint256[] memory newBpsFees = new uint256[](2);
        newBpsFees[0] = 25; // 0.25% for smaller orders
        newBpsFees[1] = 15; // 0.15% for larger orders
        
        VAULT.setFeeTiers(newThresholdAmounts, newBpsFees);
        
        // Verify the updates took effect
        (uint256 threshold0, uint256 bps0) = VAULT.feeTiers(0);
        (uint256 threshold1, uint256 bps1) = VAULT.feeTiers(1);
        
        assertEq(threshold0, 0, "Updated threshold 0 should be 0");
        assertEq(bps0, 25, "Updated BPS 0 should be 25");
        
        assertEq(threshold1, 1000 ether, "Updated threshold 1 should be 1000 ether");
        assertEq(bps1, 15, "Updated BPS 1 should be 15");
        
        // Verify that the length of the array has changed
        vm.expectRevert(); // This will revert because feeTiers(2) now doesn't exist
        VAULT.feeTiers(2);
    }

    function testFeeTierValidation() public {
        vm.startPrank(OWNER);
        
        // Try to set tiers with non-ascending order
        uint256[] memory invalidThresholds = new uint256[](3);
        invalidThresholds[0] = 0;
        invalidThresholds[1] = 200 ether;
        invalidThresholds[2] = 100 ether; // This is less than the previous, which is invalid
        
        uint256[] memory invalidBps = new uint256[](3);
        invalidBps[0] = 30;
        invalidBps[1] = 20;
        invalidBps[2] = 10;
        
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        VAULT.setFeeTiers(invalidThresholds, invalidBps);
        
        // Try to set tiers with invalid BPS (> 10000)
        uint256[] memory validThresholds = new uint256[](2);
        validThresholds[0] = 0;
        validThresholds[1] = 100 ether;
        
        uint256[] memory invalidBpsValues = new uint256[](2);
        invalidBpsValues[0] = 30;
        invalidBpsValues[1] = 11000; // > 10000, which is invalid
        
        vm.expectRevert(GeniusErrors.InvalidPercentage.selector);
        VAULT.setFeeTiers(validThresholds, invalidBpsValues);
        
        // Try to set tiers with mismatched array lengths
        uint256[] memory thresholds = new uint256[](2);
        thresholds[0] = 0;
        thresholds[1] = 100 ether;
        
        uint256[] memory bps = new uint256[](3);
        bps[0] = 30;
        bps[1] = 20;
        bps[2] = 10;
        
        vm.expectRevert(GeniusErrors.ArrayLengthsMismatch.selector);
        VAULT.setFeeTiers(thresholds, bps);
    }

    function testSmallOrderFees() public {
        console.log("Starting testSmallOrderFees");
        console.log("Block ChainID:", block.chainid);
        console.log("Dest ChainID:", destChainId);
        console.log("Chain stablecoin decimals for current chain:", VAULT.chainStablecoinDecimals(block.chainid));
        
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 10_000 ether);
        
        // Create a small order (50 USDC)
        uint256 orderAmount = 50 ether;
        uint256 minFee = 1 ether; // The minimum fee set for the target chain
        uint256 expectedBpsFee = (orderAmount * 30) / 10000; // 0.3% of 50 ether
        uint256 totalExpectedFee = minFee + expectedBpsFee;
        
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: orderAmount,
            seed: keccak256("small_order"),
            srcChainId: uint256(block.chainid),  // Make sure we use the active chain ID
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: totalExpectedFee,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        
        VAULT.createOrder(order);
        
        // Verify the fees collected
        assertEq(
            VAULT.claimableFees(),
            totalExpectedFee,
            "Collected fees should match expected fee for small order"
        );
        
        // Try with an insufficient fee
        uint256 insufficientFee = minFee + expectedBpsFee - 1; // 1 less than required
        
        IGeniusVault.Order memory orderWithInsufficientFee = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: orderAmount,
            seed: keccak256("small_order_insufficient_fee"),
            srcChainId: uint256(block.chainid),  // Make sure we use the active chain ID
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: insufficientFee,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InsufficientFees.selector,
                insufficientFee,
                totalExpectedFee,
                address(USDC)
            )
        );
        VAULT.createOrder(orderWithInsufficientFee);
    }

    function testMediumOrderFees() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 10_000 ether);
        
        // Create a medium order (200 USDC)
        uint256 orderAmount = 200 ether;
        uint256 minFee = 1 ether; // The minimum fee set for the target chain
        uint256 expectedBpsFee = (orderAmount * 20) / 10000; // 0.2% of 200 ether
        uint256 totalExpectedFee = minFee + expectedBpsFee;
        
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: orderAmount,
            seed: keccak256("medium_order"),
            srcChainId: uint256(block.chainid),  // Make sure we use the active chain ID
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: totalExpectedFee,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        
        VAULT.createOrder(order);
        
        // Verify the fees collected
        assertEq(
            VAULT.claimableFees(),
            totalExpectedFee,
            "Collected fees should match expected fee for medium order"
        );
    }

    function testLargeOrderFees() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 10_000 ether);
        
        // Create a large order (800 USDC)
        uint256 orderAmount = 800 ether;
        uint256 minFee = 1 ether; // The minimum fee set for the target chain
        uint256 expectedBpsFee = (orderAmount * 10) / 10000; // 0.1% of 800 ether
        uint256 totalExpectedFee = minFee + expectedBpsFee;
        
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: orderAmount,
            seed: keccak256("large_order"),
            srcChainId: uint256(block.chainid),  // Make sure we use the active chain ID
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: totalExpectedFee,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        
        VAULT.createOrder(order);
        
        // Verify the fees collected
        assertEq(
            VAULT.claimableFees(),
            totalExpectedFee,
            "Collected fees should match expected fee for large order"
        );
    }

    function testNoFeeTiersConfigured() public {
        // Reset fee tiers (delete all tiers)
        vm.startPrank(OWNER);
        
        // Create empty arrays
        uint256[] memory emptyThresholds = new uint256[](0);
        uint256[] memory emptyBps = new uint256[](0);
        
        // Expect revert on setting empty arrays
        vm.expectRevert(GeniusErrors.EmptyArray.selector);
        VAULT.setFeeTiers(emptyThresholds, emptyBps);
        
        // Set a valid but single tier setup
        uint256[] memory singleThreshold = new uint256[](1);
        singleThreshold[0] = 0;
        
        uint256[] memory singleBps = new uint256[](1);
        singleBps[0] = 15; // 0.15% flat fee
        
        VAULT.setFeeTiers(singleThreshold, singleBps);
        
        // Switch to orchestrator for order creation
        vm.stopPrank();
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 10_000 ether);
        
        // Create an order with the single tier fee
        uint256 orderAmount = 500 ether;
        uint256 minFee = 1 ether; // The minimum fee set for the target chain
        uint256 expectedBpsFee = (orderAmount * 15) / 10000; // 0.15% of 500 ether
        uint256 totalExpectedFee = minFee + expectedBpsFee;
        
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: orderAmount,
            seed: keccak256("single_tier_order"),
            srcChainId: uint256(block.chainid),  // Make sure we use the active chain ID
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: totalExpectedFee,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        
        VAULT.createOrder(order);
        
        // Verify the fees collected
        assertEq(
            VAULT.claimableFees(),
            totalExpectedFee,
            "Collected fees should match expected fee with single tier"
        );
    }
}