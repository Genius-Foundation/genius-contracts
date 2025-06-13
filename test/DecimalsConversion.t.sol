// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DecimalConversionProtectionTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;

    uint256 sourceChainId = block.chainid; // Current chain - 18 decimals
    uint256 targetChainId = 42; // Target chain - 6 decimals

    address OWNER;
    address TRADER;

    MockERC20 public USDC_18_DECIMALS; // Mock USDC with 18 decimals
    GeniusVault public VAULT;
    FeeCollector public FEE_COLLECTOR;

    function setUp() public {
        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");

        // Create a mock USDC with 18 decimals (instead of the usual 6)
        USDC_18_DECIMALS = new MockERC20("USDC", "USDC", 18);

        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);

        vm.startPrank(OWNER, OWNER);

        // Deploy GeniusVault
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC_18_DECIMALS),
            OWNER,
            address(0), // multicall not needed for this test
            7_500,
            address(MOCK_PRICE_FEED),
            86_000,
            99_000_000,
            101_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);
        VAULT = GeniusVault(address(proxy));

        // Deploy FeeCollector
        FeeCollector feeCollectorImplementation = new FeeCollector();

        bytes memory feeCollectorData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            OWNER,
            address(USDC_18_DECIMALS),
            2000, // 20% to protocol
            OWNER,
            OWNER,
            OWNER
        );

        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImplementation),
            feeCollectorData
        );

        FEE_COLLECTOR = FeeCollector(address(feeCollectorProxy));

        // Set FeeCollector in vault
        VAULT.setFeeCollector(address(FEE_COLLECTOR));

        // Set vault in FeeCollector
        FEE_COLLECTOR.setVault(address(VAULT));

        // Set up fee tiers in FeeCollector
        uint256[] memory thresholdAmounts = new uint256[](1);
        thresholdAmounts[0] = 0;

        uint256[] memory bpsFees = new uint256[](1);
        bpsFees[0] = 10; // 0.1%

        FEE_COLLECTOR.setFeeTiers(thresholdAmounts, bpsFees);
        FEE_COLLECTOR.setInsuranceFeeTiers(thresholdAmounts, bpsFees);

        // Set min fee to 0.1$ (100000 with 6 decimals)
        FEE_COLLECTOR.setTargetChainMinFee(targetChainId, 100000);

        // IMPORTANT: Set chain decimals
        // Target chain has 6 decimals (standard USDC)
        VAULT.setChainStablecoinDecimals(targetChainId, 6);

        vm.stopPrank();

        // Give trader some tokens
        deal(address(USDC_18_DECIMALS), TRADER, 1 ether);
    }

    function testCreateOrderRevertsWhenAmountMinusFeeRoundsToZero() public {
        vm.startPrank(TRADER);
        USDC_18_DECIMALS.approve(address(VAULT), type(uint256).max);

        // Create an order where amountIn - fee would round to 0 after decimal conversion
        // Using an amount just above the minimum fee
        uint256 amountIn = 1000000000000100; // 0.0010000000001 with 18 decimals
        uint256 fee = 1000000000000000; // 0.001 with 18 decimals (minimum fee)

        // amountIn - fee = 100 wei = 0.0000000000001 with 18 decimals
        // This would convert to 0 with 6 decimals

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: VAULT.addressToBytes32(TRADER),
            amountIn: amountIn,
            seed: keccak256("order"),
            srcChainId: sourceChainId,
            destChainId: targetChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC_18_DECIMALS)),
            fee: fee,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_18_DECIMALS))
        });

        // This should revert with InvalidAmount
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        VAULT.createOrder(order);

        vm.stopPrank();
    }

    function testCreateOrderSucceedsWhenAmountSufficientForDecimalConversion()
        public
    {
        vm.startPrank(TRADER);
        USDC_18_DECIMALS.approve(address(VAULT), type(uint256).max);

        // Create an order with sufficient amount that survives decimal conversion
        // 0.01 tokens = 10000000000000000 wei with 18 decimals
        // This converts cleanly to 10000 with 6 decimals (0.01 USDC)
        uint256 amountIn = 10000000000000000; // 0.01 with 18 decimals
        uint256 fee = 1000000000000000; // 0.001 with 18 decimals

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: VAULT.addressToBytes32(TRADER),
            amountIn: amountIn,
            seed: keccak256("order"),
            srcChainId: sourceChainId,
            destChainId: targetChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC_18_DECIMALS)),
            fee: fee,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC_18_DECIMALS))
        });

        // This should succeed
        VAULT.createOrder(order);

        // Verify order was created
        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint(VAULT.orderStatus(orderHash)),
            1,
            "Order should be created"
        );

        vm.stopPrank();
    }
}
