// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {IGeniusPool} from "../src/interfaces/IGeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";


contract GeniusPoolTest is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 106; // avalanche
    uint16 targetChainId = 101; // ethereum

    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;

    ERC20 public USDC;
    ERC20 public WETH;

    GeniusPool public POOL;
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        ORCHESTRATOR = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // The hardcoded tx.origin for forge

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB); // WETH on Avalanche

        vm.startPrank(OWNER, OWNER);
        POOL = new GeniusPool(address(USDC), OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);
        EXECUTOR = new GeniusExecutor(PERMIT2, address(POOL), address(VAULT), OWNER);
        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(POOL.owner(), OWNER, "Owner should be ORCHESTRATOR");

        vm.startPrank(OWNER);
        VAULT.initialize(address(POOL));

        vm.startPrank(OWNER);
        POOL.initialize(address(VAULT), address(EXECUTOR));

        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);

        POOL.addOrchestrator(ORCHESTRATOR);
        POOL.addOrchestrator(address(this));
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        EXECUTOR.addOrchestrator(address(this));
        assertEq(POOL.orchestrator(ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
    }

    function testEmergencyLock() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        assertEq(POOL.paused(), true, "GeniusPool should be paused");
        vm.stopPrank();
    }

    function testRemoveBridgeLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();

        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1_000 ether;

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            1_000 ether
        );
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        POOL.removeBridgeLiquidity(0.5 ether, targetChainId, tokens, amounts, data);
        vm.stopPrank();
    }

    function testAddLiquiditySwapWhenPaused() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);
    }

    function testRemoveLiquiditySwapWhenPaused() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        IGeniusPool.Order memory order = 
            IGeniusPool.Order({
                amountIn: 1_000 ether,
                orderId: 1,
                trader: TRADER,
                srcChainId: uint16(block.chainid),
                destChainId: destChainId,
                fillDeadline: fillDeadline,
                tokenIn: address(USDC)
            });
        
        POOL.removeLiquiditySwap(order);
    }

    function testRemoveRewardLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        POOL.removeRewardLiquidity(1_000 ether);
    }

    function testEmergencyUnlock() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        assertEq(POOL.paused(), true, "GeniusPool should be paused");

        vm.startPrank(OWNER);
        POOL.emergencyUnlock();
        assertEq(POOL.paused(), false, "GeniusPool should be unpaused");
    }

    function testRevertWhenAlreadyInitialized() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        POOL.initialize(address(VAULT), address(EXECUTOR));
    }

    function testSetRebalanceThreshold() public {
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(5);

        assertEq(POOL.rebalanceThreshold(), 5, "Rebalance threshold should be 5");
    }

    function testAddBridgeLiquidity() public {
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), 1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(orchestratorBalance, 0, "Orchestrator balance should be 0");
    }

    function testAddLiquiditySwapNative() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);
        deal(address(USDC), address(DEX_ROUTER), 1_000 ether);
        bytes memory swapData = abi.encodeWithSelector(
            MockDEXRouter.swapToStables.selector,
            address(USDC)
        );

        vm.startPrank(address(TRADER));
        vm.deal(address(TRADER), 2 ether);
        EXECUTOR.nativeSwapAndDeposit{value: 1 ether}(
            address(DEX_ROUTER),
            swapData,
            1 ether,
            destChainId,
            fillDeadline
        );

        assertEq(USDC.balanceOf(address(POOL)), 500 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 500 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 500 ether, "Available assets should be 1,000 ether");
        assertEq(traderBalance, 1000 ether, "Orchestrator balance should be unchanged");
    }

    function testRemoveLiquiditySwap() public {
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(POOL), 1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        IGeniusPool.Order memory order = 
            IGeniusPool.Order({
                amountIn: 1_000 ether,
                orderId: POOL.totalOrders(),
                trader: TRADER,
                srcChainId: 42,
                destChainId: uint16(block.chainid),
                fillDeadline: fillDeadline,
                tokenIn: address(USDC)
            });

        POOL.removeLiquiditySwap(order);

        assertEq(USDC.balanceOf(address(POOL)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, 1_000 ether, "Orchestrator balance should be 1000 ether");
    }

    function removeRewardLiquidity() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        assertEq(USDC.balanceOf(address(POOL)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        vm.startPrank(ORCHESTRATOR);
        POOL.removeRewardLiquidity(1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function testStakeLiquidity() public {
        vm.expectRevert();
        POOL.stakeLiquidity(TRADER, 1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
    }

    function testRemoveStakedLiquidity() public {
        vm.expectRevert();
        POOL.stakeLiquidity(TRADER, 1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        // Remove staked liquidity (should fail because unstaking is not available through the pool contract)
        vm.startPrank(TRADER);
        vm.expectRevert();
        POOL.removeStakedLiquidity(TRADER, 1_000 ether);

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        // Remove staked liquidity
        vm.startPrank(TRADER);
        VAULT.withdraw(1_000 ether, TRADER, TRADER);

        totalAssets = POOL.totalAssets();
        availableAssets = POOL.availableAssets();
        totalStakedAssets = POOL.totalStakedAssets();
        traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(traderBalance, 1_000 ether, "Trader balance should be 1,000 ether");
    }

    function testDonatedBalance() public {
        /**
         * Donated balances are balances that are transferred into the pool contract
         * but are done so directly without going through a contract function.
         */

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        deal(address(USDC), TRADER, 1_000 ether);
        vm.startPrank(TRADER);
        USDC.transfer(address(POOL), 500 ether);

        totalAssets = POOL.totalAssets();
        availableAssets = POOL.availableAssets();
        totalStakedAssets = POOL.totalStakedAssets();
        traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_500 ether, "Total assets should be 1,500 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 1250 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 500 ether, "Trader balance should be 500 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 500 ether);
        VAULT.deposit(500 ether, TRADER);

        totalAssets = POOL.totalAssets();
        availableAssets = POOL.availableAssets();
        totalStakedAssets = POOL.totalStakedAssets();
        traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 2000 ether, "Total assets should be 2,000 ether");
        assertEq(totalStakedAssets, 1_500 ether, "Total staked assets should be 1,500 ether");
        assertEq(availableAssets, 1625 ether, "Available assets should be 650 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");
    }

    function testRemoveBridgeLiquidity() public {
        uint256 initialOrchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        // Add bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), 500 ether);

        assertEq(USDC.balanceOf(address(POOL)), 500 ether, "GeniusPool balance should be 500 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestratorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        vm.deal(ORCHESTRATOR, 100 ether);

        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(POOL), 1_000 ether);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

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

        bytes[] memory data = new bytes[](1);
        data[0] = stableTransferData;

        POOL.removeBridgeLiquidity(amountToRemove, targetChainId, targets, values, data);

        assertEq(USDC.balanceOf(address(POOL)), 400 ether, "GeniusPool balance should be 400 ether");
        assertEq(USDC.balanceOf(randomAddress), amountToRemove, "Random address should receive 100 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestratorBalance - 500 ether, "Orchestrator balance should remain unchanged");

        uint256 totalAssets = POOL.totalAssets();
        uint256 availableAssets = POOL.availableAssets();
        uint256 totalStakedAssets = POOL.totalStakedAssets();

        assertEq(totalAssets, 400 ether, "Total assets should be 400 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 400 ether, "Available assets should be 400 ether");
    }

    function testAddLiquiditySwapOrderCreation() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        assertEq(POOL.totalOrders(), 1, "Total orders should be 1");

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        bytes32 orderHash = POOL.orderHash(order);
        assertEq(uint256(POOL.orderStatus(orderHash)), uint256(IGeniusPool.OrderStatus.Created), "Order status should be Created");
    }

    function testRemoveLiquiditySwapOrderFulfillment() public {
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(POOL), 1_000 ether);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        POOL.removeLiquiditySwap(order);

        bytes32 orderHash = POOL.orderHash(order);
        assertEq(uint256(POOL.orderStatus(orderHash)), uint256(IGeniusPool.OrderStatus.Filled), "Order status should be Filled");
    }

    function testSetOrderAsFilled() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        vm.startPrank(ORCHESTRATOR);
        POOL.setOrderAsFilled(order);

        bytes32 orderHash = POOL.orderHash(order);
        assertEq(uint256(POOL.orderStatus(orderHash)), uint256(IGeniusPool.OrderStatus.Filled), "Order status should be Filled");
    }

    function testRevertOrder() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 100);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.startPrank(ORCHESTRATOR);
        
        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 1_000 ether);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        uint256 prevBalance = USDC.balanceOf(TRADER);

        POOL.revertOrder(order, targets, data, values);

        uint256 postBalance = USDC.balanceOf(TRADER);

        bytes32 orderHash = POOL.orderHash(order);
        assertEq(uint256(POOL.orderStatus(orderHash)), uint256(IGeniusPool.OrderStatus.Reverted), "Order status should be Reverted");
        assertEq(postBalance - prevBalance, 1_000 ether, "Trader should receive refunded amount");
    }

    function testCannotRevertOrderBeforeDeadline() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        vm.startPrank(ORCHESTRATOR);
        
        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 1_000 ether);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlineNotPassed.selector, fillDeadline));
        POOL.revertOrder(order, targets, data, values);
    }

    function testAddLiquiditySwapWithZeroAmount() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector));
        POOL.addLiquiditySwap(TRADER, address(USDC), 0, destChainId, fillDeadline);
    }

    function testAddLiquiditySwapWithInvalidToken() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(WETH)));
        POOL.addLiquiditySwap(TRADER, address(WETH), 1_000 ether, destChainId, fillDeadline);
    }

    function testAddLiquiditySwapWithSameChainId() public {
        uint16 destChainId = uint16(block.chainid);
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidDestChainId.selector, destChainId));
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);
    }

    function testAddLiquiditySwapWithPastDeadline() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp - 1);

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlinePassed.selector, fillDeadline));
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);
    }

    function testRemoveLiquiditySwapAfterDeadline() public {
        uint32 fillDeadline = uint32(block.timestamp + 100);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(POOL), 1_000 ether);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlinePassed.selector, fillDeadline));
        POOL.removeLiquiditySwap(order);
    }

    function testSetOrderAsFilledWithWrongSourceChain() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 43, // Wrong source chain
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        POOL.setOrderAsFilled(order);
    }

    function testSetOrderAsFilledTwice() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        vm.startPrank(ORCHESTRATOR);
        POOL.setOrderAsFilled(order);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        POOL.setOrderAsFilled(order);
    }

    function testRevertOrderWithWrongSourceChain() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 100);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 43, // Wrong source chain
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.startPrank(ORCHESTRATOR);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 1_000 ether);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        POOL.revertOrder(order, targets, data, values);
    }

    function testRevertOrderWithIncorrectRefundAmount() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 100);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.startPrank(ORCHESTRATOR);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 900 ether); // Incorrect refund amount

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidDelta.selector));
        POOL.revertOrder(order, targets, data, values);
    }

    function testRevertOrderTwice() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 100);

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, fillDeadline);

        IGeniusPool.Order memory order = IGeniusPool.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: fillDeadline,
            tokenIn: address(USDC)
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.startPrank(ORCHESTRATOR);

        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 1_000 ether);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        POOL.revertOrder(order, targets, data, values);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        POOL.revertOrder(order, targets, data, values);
    }
}