// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract GeniusVaultTest is Test {
    int256 public constant INITIAL_STABLECOIN_PRICE = 100_000_000;
    MockV3Aggregator public MOCK_PRICE_FEED;
    uint256 destChainId = 42;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint256 sourceChainId = block.chainid; // avalanche
    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    uint256 TRADER_PK;
    address ORCHESTRATOR;
    uint256 ORCHESTRATOR_PK;
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public WETH;

    GeniusVault public VAULT;
    GeniusProxyCall public PROXYCALL;
    MockDEXRouter public DEX_ROUTER;

    IGeniusVault.Order public badOrder;

    IGeniusVault.Order public order;

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);

        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("OWNER");
        (TRADER, TRADER_PK) = makeAddrAndKey("TRADER");
        RECEIVER = bytes32(uint256(uint160(TRADER)));
        (ORCHESTRATOR, ORCHESTRATOR_PK) = makeAddrAndKey("ORCHESTRATOR");

        MOCK_PRICE_FEED = new MockV3Aggregator(INITIAL_STABLECOIN_PRICE);

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);

        PROXYCALL = new GeniusProxyCall(OWNER, new address[](0));

        vm.startPrank(OWNER, OWNER);

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            98_000_000,
            102_000_000,
            1000 ether
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));

        badOrder = IGeniusVault.Order({
            seed: keccak256(abi.encodePacked("badOrder")),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 43, // Wrong source chain
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        order = IGeniusVault.Order({
            seed: keccak256(abi.encodePacked("order")),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(
            VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER),
            true,
            "Owner should be ORCHESTRATOR"
        );

        vm.startPrank(OWNER);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        VAULT.setTargetChainMinFee(address(USDC), destChainId, 1 ether);

        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
    }

    function testEmergencyLock() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        assertEq(VAULT.paused(), true, "GeniusVault should be paused");
        vm.stopPrank();
    }

    function testRemoveBridgeLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();

        bytes memory data = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            1_000 ether
        );
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.rebalanceLiquidity(0.5 ether, destChainId, address(USDC), data);
        vm.stopPrank();
    }

    function testDecimals() public view {
        assertEq(USDC.decimals(), 6, "USDC should have 6 decimals");
    }

    function testcreateOrderWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.createOrder(order);
    }

    function testcreateOrderWhenNoApprove() public {
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        VAULT.createOrder(order);
    }

    function testcreateOrderWhenNoBalance() public {
        vm.startPrank(address(TRADER));
        USDC.transfer(address(ORCHESTRATOR), 1 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        VAULT.createOrder(order);
    }

    function testfillOrderWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        // Create calldata to transfer the stablecoin to this contract
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1001 ether
        );

        VAULT.fillOrder(order, address(USDC), data, address(0), "");
    }

    function testEmergencyUnlock() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        assertEq(VAULT.paused(), true, "GeniusVault should be paused");

        vm.startPrank(OWNER);
        VAULT.unpause();
        assertEq(VAULT.paused(), false, "GeniusVault should be unpaused");
    }

    function testRevertWhenAlreadyInitialized() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        VAULT.initialize(
            address(USDC),
            OWNER,
            address(PROXYCALL),
            7_500,
            address(MOCK_PRICE_FEED),
            99_000_000,
            101_000_000,
            1000 ether
        );
    }

    function testSetRebalanceThreshold() public {
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(5);

        assertEq(
            VAULT.rebalanceThreshold(),
            5,
            "Rebalance threshold should be 5"
        );
    }

    function testfillOrder() public {
        deal(address(USDC), address(VAULT), 1_000 ether);
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 997 ether,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            999 ether
        );

        vm.startPrank(address(ORCHESTRATOR));
        VAULT.fillOrder(order, address(USDC), data, address(0), "");

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1 ether,
            "Total assets should be 1 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should be 0 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            1 ether,
            "Available assets should be 1 ether"
        );
        assertEq(
            USDC.balanceOf(ORCHESTRATOR),
            1000 ether,
            "Orchestrator balance should be 1000 ether"
        );
    }

    function testfillOrderNoTargets() public {
        // Setup initial state
        deal(address(USDC), address(VAULT), 1_000 ether);
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault initial balance should be 1,000 ether"
        );

        // Create the order
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        uint256 balanceTraderBefore = USDC.balanceOf(TRADER);

        // Execute fillOrder
        vm.startPrank(address(ORCHESTRATOR));
        VAULT.fillOrder(order, address(0), "", address(0), "");

        // Assertions
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether after removal"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1 ether,
            "Total assets should be 1 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0 ether,
            "Total staked assets should be 0 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            1 ether,
            "Available assets should be 1 ether"
        );
        assertEq(
            USDC.balanceOf(TRADER) - balanceTraderBefore,
            999 ether,
            "Receiver balance should be 999 ether (amountIn - fee)"
        );

        vm.stopPrank();
    }

    function testStakeLiquidity() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.stakeDeposit(1_000 ether, TRADER);

        assertEq(
            VAULT.stablecoinBalance(),
            1_000 ether,
            "Total assets should be 1,000 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            1_000 ether,
            "Total staked assets should be 1,000 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            750 ether,
            "Available assets should be 100 ether"
        );
    }

    function testRemoveStakedLiquidity() public {
        assertEq(
            USDC.balanceOf(address(VAULT)),
            0,
            "GeniusVault balance should be 0 ether"
        );

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.stakeDeposit(1_000 ether, TRADER);

        assertEq(
            VAULT.stablecoinBalance(),
            1_000 ether,
            "Total assets should be 1,000 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            1_000 ether,
            "Total staked assets should be 1,000 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            750 ether,
            "Available assets should be 100 ether"
        );
        assertEq(USDC.balanceOf(TRADER), 0, "Trader balance should be 0 ether");

        // Remove staked liquidity
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(1_000 ether, TRADER, TRADER);

        assertEq(
            VAULT.stablecoinBalance(),
            0,
            "Total assets should be 0 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should be 0 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            0,
            "Available assets should be 0 ether"
        );
        assertEq(
            USDC.balanceOf(TRADER),
            1_000 ether,
            "Trader balance should be 1,000 ether"
        );
    }

    function testRemoveBridgeLiquidity() public {
        uint256 initialOrchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        // Add bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), 500 ether);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            500 ether,
            "GeniusVault balance should be 500 ether"
        );
        assertEq(
            USDC.balanceOf(ORCHESTRATOR),
            initialOrchestratorBalance - 500 ether,
            "Orchestrator balance should be -500 ether"
        );

        vm.deal(ORCHESTRATOR, 100 ether);

        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(VAULT), 1_000 ether);

        // Create erc20 transfer calldata
        address randomAddress = makeAddr("pretendBridge");

        // Amount to remove
        uint256 amountToRemove = 100 ether;

        // Create erc20 transfer calldata
        bytes memory stableTransferData = abi.encodeWithSelector(
            USDC.transfer.selector,
            randomAddress,
            amountToRemove
        );
        VAULT.rebalanceLiquidity(
            amountToRemove,
            destChainId,
            address(USDC),
            stableTransferData
        );

        assertEq(
            USDC.balanceOf(address(VAULT)),
            400 ether,
            "GeniusVault balance should be 400 ether"
        );
        assertEq(
            USDC.balanceOf(randomAddress),
            amountToRemove,
            "Random address should receive 100 ether"
        );
        assertEq(
            USDC.balanceOf(ORCHESTRATOR),
            initialOrchestratorBalance - 500 ether,
            "Orchestrator balance should remain unchanged"
        );

        assertEq(
            VAULT.stablecoinBalance(),
            400 ether,
            "Total assets should be 400 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should be 0 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            400 ether,
            "Available assets should be 400 ether"
        );
    }

    function testOrderCreation() public {
        vm.startPrank(address(ORCHESTRATOR));
        deal(address(USDC), address(ORCHESTRATOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.createOrder(order);

        bytes32 orderHash = VAULT.orderHash(order);

        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Created),
            "Order status should be Created"
        );
    }

    function testfillOrderSwap() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 500 ether,
            tokenOut: VAULT.addressToBytes32(address(WETH))
        });

        deal(address(WETH), address(DEX_ROUTER), 1_000 ether);

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            order.amountIn - order.fee,
            TRADER
        );

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
        assertEq(
            WETH.balanceOf(address(TRADER)),
            500 ether,
            "Balance this should be 500 Weth"
        );
    }

    function testfillOrderSwapToWrongReceiver() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 500 ether,
            tokenOut: VAULT.addressToBytes32(address(WETH))
        });

        deal(address(WETH), address(DEX_ROUTER), 1_000 ether);

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            order.amountIn - order.fee,
            address(this)
        );

        uint256 balanceBefore = USDC.balanceOf(TRADER);

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
        assertEq(
            WETH.balanceOf(address(TRADER)),
            0 ether,
            "Balance receiver should be 0 Weth"
        );
        assertEq(
            WETH.balanceOf(address(this)),
            0 ether,
            "Balance this should be 0 Weth"
        );
        assertEq(
            USDC.balanceOf(address(TRADER)) - balanceBefore,
            999 ether,
            "Balance receiver should be 999 usdc"
        );
    }

    function testfillOrderSwapUnderMinAmountOut() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 501 ether,
            tokenOut: VAULT.addressToBytes32(address(WETH))
        });

        deal(address(WETH), address(DEX_ROUTER), 1_000 ether);

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            order.amountIn - order.fee,
            TRADER
        );

        uint256 balanceBefore = USDC.balanceOf(TRADER);

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
        assertEq(
            WETH.balanceOf(address(TRADER)),
            0 ether,
            "Balance this should be 0 Weth"
        );
        assertEq(
            USDC.balanceOf(address(TRADER)) - balanceBefore,
            999 ether,
            "Balance this should be 999 usdc"
        );
    }

    function testfillOrderArbitraryCallWrongSeed() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            999 ether
        );

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidSeed.selector)
        );
        VAULT.fillOrder(order, address(0), "", address(USDC), data);
    }

    function testfillOrderArbitraryCall() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        deal(address(WETH), address(DEX_ROUTER), 1_000 ether);

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(WETH),
            999 ether,
            0x7b4991A80BA0319599485DFFC496B687b0e9Ac70
        );

        order = IGeniusVault.Order({
            seed: bytes32(
                abi.encodePacked(
                    bytes16(
                        keccak256(
                            abi.encodePacked(
                                address(DEX_ROUTER),
                                keccak256(data)
                            )
                        )
                    ),
                    bytes16(0)
                )
            ),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        uint256 balanceBefore = WETH.balanceOf(
            0x7b4991A80BA0319599485DFFC496B687b0e9Ac70
        );

        VAULT.fillOrder(order, address(0), "", address(DEX_ROUTER), data);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
    }

    function testcreateOrderWithZeroAmount() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 0,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.createOrder(order);
    }

    function testcreateOrderWithAmountAboveMax() public {
        deal(address(USDC), TRADER, 1_000 ether);
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1001 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.createOrder(order);
    }

    function testcreateOrderWithInvalidToken() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(WETH)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidTokenIn.selector)
        );

        VAULT.createOrder(order);
    }

    function testcreateOrderWithSameChainId() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidDestChainId.selector,
                uint16(block.chainid)
            )
        );

        VAULT.createOrder(order);
    }

    function testCreateOrderWithTargetChainIdOrTokenNotSupported() public {
        vm.startPrank(OWNER);
        VAULT.setTargetChainMinFee(address(USDC), destChainId, 0);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.TokenOrTargetChainNotSupported.selector
            )
        );

        VAULT.createOrder(order);
    }

    function testPriceChecksOnCreateOrder() public {
        deal(address(USDC), TRADER, 5_000 ether);

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 5_000 ether);

        // Test with normal price (1.00 USD)
        VAULT.createOrder(order);

        // Test with price too high (1.03 USD)
        MOCK_PRICE_FEED.updatePrice(103_000_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.PriceOutOfBounds.selector,
                103_000_000
            )
        );
        VAULT.createOrder(order);

        // Test with price too low (0.97 USD)
        MOCK_PRICE_FEED.updatePrice(97_000_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.PriceOutOfBounds.selector,
                97_000_000
            )
        );
        VAULT.createOrder(order);

        vm.stopPrank();
    }

    function testPriceFeedFailure() public {
        deal(address(USDC), TRADER, 5_000 ether);

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 5_000 ether);

        // Set invalid price
        MOCK_PRICE_FEED.updatePrice(-1);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.PriceOutOfBounds.selector, -1)
        );
        VAULT.createOrder(order);

        vm.stopPrank();
    }

    function testPriceFeedAdminUpdates() public {
        deal(address(USDC), TRADER, 5_000 ether);

        // Deploy new mock price feed
        MockV3Aggregator newPriceFeed = new MockV3Aggregator(
            INITIAL_STABLECOIN_PRICE
        );

        // Only admin should be able to update price feed
        vm.startPrank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector)
        );
        VAULT.setPriceFeed(address(newPriceFeed));
        vm.stopPrank();

        // Admin can update price feed
        vm.startPrank(OWNER);
        VAULT.setPriceFeed(address(newPriceFeed));
        assertEq(address(VAULT.stablecoinPriceFeed()), address(newPriceFeed));
        vm.stopPrank();

        // Verify new price feed is working
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 5_000 ether);
        VAULT.createOrder(order);

        // Update price on new feed
        newPriceFeed.updatePrice(103_000_000);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.PriceOutOfBounds.selector,
                103_000_000
            )
        );
        VAULT.createOrder(order);
        vm.stopPrank();
    }

    function testEdgeCasePrices() public {
        deal(address(USDC), TRADER, 5_000 ether);
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 5_000 ether);

        // Test exact bounds
        MOCK_PRICE_FEED.updatePrice(98_000_000); // 0.98 - should work
        VAULT.createOrder(order);

        order.seed = keccak256("order1");

        MOCK_PRICE_FEED.updatePrice(102_000_000); // 1.02 - should work
        VAULT.createOrder(order);

        // Test just outside bounds
        MOCK_PRICE_FEED.updatePrice(97_999_999); // Just below 0.98
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.PriceOutOfBounds.selector,
                97_999_999
            )
        );
        VAULT.createOrder(order);

        MOCK_PRICE_FEED.updatePrice(102_000_001); // Just above 1.02
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.PriceOutOfBounds.selector,
                102_000_001
            )
        );
        order.seed = keccak256("order2");
        VAULT.createOrder(order);

        vm.stopPrank();
    }

    function testRevertOrder() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), order.amountIn);
        VAULT.createOrder(order);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        bytes32 orderHash = VAULT.orderHash(order);

        // Generate orchestrator signature
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ORCHESTRATOR_PK,
            revertDigest
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        // Should successfully revert the order
        VAULT.revertOrder(order, signature);

        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Reverted),
            "Order status should be Reverted"
        );

        // Verify USDC was returned to trader (minus fee)
        assertEq(
            USDC.balanceOf(TRADER),
            999 ether, // amountIn - fee
            "Trader should receive amountIn minus fee"
        );

        vm.stopPrank();
    }

    function testRevertOrderWhenPaused() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), order.amountIn);
        VAULT.createOrder(order);
        vm.stopPrank();

        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ORCHESTRATOR_PK,
            revertDigest
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.revertOrder(order, signature);
    }

    function testRevertOrderInvalidStatus() public {
        vm.startPrank(address(ORCHESTRATOR));

        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ORCHESTRATOR_PK,
            revertDigest
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector)
        );
        VAULT.revertOrder(order, signature);

        vm.stopPrank();
    }

    function testRevertOrderInvalidSignature() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), order.amountIn);
        VAULT.createOrder(order);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));

        // Generate invalid signature using different private key
        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TRADER_PK, revertDigest); // Using trader's key instead
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidSignature.selector)
        );
        VAULT.revertOrder(order, invalidSignature);

        vm.stopPrank();
    }

    function testRevertOrderInsufficientLiquidity() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), order.amountIn);
        VAULT.createOrder(order);
        vm.stopPrank();

        // Create order
        vm.startPrank(address(ORCHESTRATOR));

        // Drain vault's liquidity
        deal(address(USDC), address(VAULT), 0);

        bytes32 orderHash = VAULT.orderHash(order);
        bytes32 revertDigest = _revertOrderDigest(orderHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            ORCHESTRATOR_PK,
            revertDigest
        );
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InsufficientLiquidity.selector,
                0,
                999 ether
            )
        );
        VAULT.revertOrder(order, signature);

        vm.stopPrank();
    }

    function _revertOrderDigest(
        bytes32 _orderHash
    ) internal pure returns (bytes32) {
        return
            keccak256(abi.encodePacked("PREFIX_CANCEL_ORDER_HASH", _orderHash));
    }
}
