// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultOrders is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint256 sourceChainId = block.chainid; // ethereum
    uint256 targetChainId = 42;

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public TOKEN1;

    GeniusVault public VAULT;
    FeeCollector public FEE_COLLECTOR;

    GeniusProxyCall public PROXYCALL;
    MockDEXRouter public DEX_ROUTER;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        RECEIVER = bytes32(uint256(uint160(TRADER)));
        ORCHESTRATOR = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // The hardcoded tx.origin for forge

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche
        TOKEN1 = new MockERC20("Token1", "TK1", 18);

        // Deploy proxy call implementation and proxy
        GeniusProxyCall proxyCallImpl = new GeniusProxyCall();
        bytes memory proxyCallInitData = abi.encodeWithSelector(
            GeniusProxyCall.initialize.selector,
            OWNER,
            new address[](0)
        );
        ERC1967Proxy proxyCallProxy = new ERC1967Proxy(
            address(proxyCallImpl),
            proxyCallInitData
        );
        PROXYCALL = GeniusProxyCall(payable(address(proxyCallProxy)));

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

        // Deploy FeeCollector
        FeeCollector feeCollectorImplementation = new FeeCollector();

        bytes memory feeCollectorData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            OWNER,
            address(USDC),
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
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 0;
        thresholdAmounts[1] = 100 ether;
        thresholdAmounts[2] = 500 ether;

        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 30; // 0.3%
        bpsFees[1] = 20; // 0.2%
        bpsFees[2] = 10; // 0.1%

        FEE_COLLECTOR.setFeeTiers(thresholdAmounts, bpsFees);

        // Set up insurance fee tiers
        uint256[] memory insThresholdAmounts = new uint256[](3);
        insThresholdAmounts[0] = 0;
        insThresholdAmounts[1] = 100 ether;
        insThresholdAmounts[2] = 500 ether;

        uint256[] memory insBpsFees = new uint256[](3);
        insBpsFees[0] = 30; // 0.3%
        insBpsFees[1] = 20; // 0.2%
        insBpsFees[2] = 10; // 0.1%

        FEE_COLLECTOR.setInsuranceFeeTiers(insThresholdAmounts, insBpsFees);

        // Set min fee in FeeCollector
        FEE_COLLECTOR.setTargetChainMinFee(targetChainId, 10000);

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));

        DEX_ROUTER = new MockDEXRouter();
        VAULT.setChainStablecoinDecimals(targetChainId, 6);

        vm.stopPrank();

        assertEq(
            VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER),
            true,
            "Owner should be ORCHESTRATOR"
        );

        vm.startPrank(OWNER);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(ORCHESTRATOR), 1_000 ether);
        deal(address(TOKEN1), address(DEX_ROUTER), 100_000_000 ether);
        deal(address(USDC), address(VAULT), 1_000 ether);
    }

    function testFillOrder() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: targetChainId,
            destChainId: block.chainid,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 50_000_000 ether,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        vm.startPrank(address(ORCHESTRATOR));

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(TOKEN1),
            order.amountIn - order.fee,
            TRADER
        );

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");
        vm.stopPrank();

        bytes32 hash = VAULT.orderHash(order);
        assertEq(uint(VAULT.orderStatus(hash)), 2, "Order should be filled");

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
        assertEq(
            USDC.balanceOf(address(DEX_ROUTER)),
            999 ether,
            "Executor balance should be 999 USDC"
        );
        assertEq(
            VAULT.availableAssets(),
            1 ether,
            "Available Stablecoin balance should be 1"
        );
        assertEq(
            TOKEN1.balanceOf(TRADER),
            order.minAmountOut,
            "Trader should receive the correct amount"
        );
    }

    function testFillOrderShouldTransferUsdcIfAmountOutTooSmall() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: targetChainId, // Use the current chain ID
            destChainId: block.chainid,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 51_000_000 ether,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(TOKEN1),
            order.amountIn - order.fee,
            TRADER
        );

        uint256 balanceBefore = USDC.balanceOf(TRADER);

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );

        assertEq(
            USDC.balanceOf(TRADER) - balanceBefore,
            999 ether,
            "Executor balance should be 999 USDC"
        );
    }

    function testFillOrderFromVaultWithLowerDecimals() public {
        vm.startPrank(address(OWNER));
        VAULT.setChainStablecoinDecimals(targetChainId, 3);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000_000);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000_000,
            seed: keccak256("order"),
            srcChainId: targetChainId,
            destChainId: block.chainid,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1_000,
            minAmountOut: 50_000_000,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        vm.startPrank(address(ORCHESTRATOR));
        uint256 balanceBefore = USDC.balanceOf(TRADER);

        VAULT.fillOrder(order, address(0), "", address(0), "");
        vm.stopPrank();

        bytes32 hash = VAULT.orderHash(order);
        assertEq(uint(VAULT.orderStatus(hash)), 2, "Order should be filled");

        // Add assertions to check the state after removing liquidity
        assertEq(
            balanceBefore - USDC.balanceOf(address(VAULT)),
            999_000_000,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
    }

    function testFillOrderFromVaultWithHigherDecimals() public {
        vm.startPrank(address(OWNER));
        VAULT.setChainStablecoinDecimals(targetChainId, 18);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: targetChainId,
            destChainId: block.chainid,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 50_000_000 ether,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        vm.startPrank(address(ORCHESTRATOR));

        uint256 balanceBefore = USDC.balanceOf(TRADER);
        VAULT.fillOrder(order, address(0), "", address(0), "");
        vm.stopPrank();

        bytes32 hash = VAULT.orderHash(order);
        assertEq(uint(VAULT.orderStatus(hash)), 2, "Order should be filled");

        // Add assertions to check the state after removing liquidity
        assertEq(
            balanceBefore - USDC.balanceOf(address(VAULT)),
            999_000_000,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
    }
}
