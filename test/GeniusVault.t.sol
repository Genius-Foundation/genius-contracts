// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import { IGeniusVault } from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";


contract GeniusVaultTest is Test {
    uint16 destChainId = 42;

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

    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;

    IGeniusVault.Order public badOrder = IGeniusVault.Order({
        amountIn: 1_000 ether,
        orderId: 0,
        trader: TRADER,
        srcChainId: 43, // Wrong source chain
        destChainId: destChainId,
        fillDeadline: uint32(block.timestamp + 1000),
        tokenIn: address(USDC),
        fee: 1 ether
    });

    IGeniusVault.Order public order = IGeniusVault.Order({
        amountIn: 1_000 ether,
        orderId: 0,
        trader: TRADER,
        srcChainId: uint16(block.chainid),
        destChainId: destChainId,
        fillDeadline: uint32(block.timestamp + 1000),
        tokenIn: address(USDC),
        fee: 1 ether
    });

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
        VAULT = new GeniusVault(address(USDC), OWNER);
        EXECUTOR = new GeniusExecutor(PERMIT2, address(VAULT), OWNER);
        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER), true, "Owner should be ORCHESTRATOR");

        vm.startPrank(OWNER);
        VAULT.initialize(address(EXECUTOR));

        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), address(this));
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
        VAULT.removeBridgeLiquidity(0.5 ether, targetChainId, tokens, amounts, data);
        vm.stopPrank();
    }

    function testAddLiquiditySwapWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);
    }

    function testAddLiquiditySwapWhenNoApprove() public {

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);
    }

    function testAddLiquiditySwapWhenNoBalance() public {
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 1_000 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);
    }

    function testRemoveLiquiditySwapWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        IGeniusVault.Order memory order = 
            IGeniusVault.Order({
                amountIn: 1_000 ether,
                orderId: 1,
                trader: TRADER,
                srcChainId: uint16(block.chainid),
                destChainId: destChainId,
                fillDeadline: uint32(block.timestamp + 1000),
                tokenIn: address(USDC),
                fee: 1 ether
            });
        
        VAULT.removeLiquiditySwap(order);
    }

    function testRemoveRewardLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        VAULT.removeRewardLiquidity(1_000 ether);
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
        VAULT.initialize(address(EXECUTOR));
    }

    function testSetRebalanceThreshold() public {
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(5);

        assertEq(VAULT.rebalanceThreshold(), 5, "Rebalance threshold should be 5");
    }

    function testAddBridgeLiquidity() public {
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), 1_000 ether);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");

        uint256 totalAssets = VAULT.stablecoinBalance();
        uint256 availableAssets = VAULT.availableAssets();
        uint256 totalStakedAssets = VAULT.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(orchestratorBalance, 0, "Orchestrator balance should be 0");
    }

    function testAddLiquiditySwapNative() public {
        
        deal(address(USDC), address(DEX_ROUTER), 1_000 ether);
        bytes memory swapData = abi.encodeWithSelector(
            MockDEXRouter.swapToStables.selector,
            address(USDC)
        );

        vm.startPrank(address(TRADER));
        vm.deal(address(TRADER), 2 ether);
        EXECUTOR.nativeSwapAndDeposit{value: 2 ether}(
            address(DEX_ROUTER),
            swapData,
            2 ether,
            destChainId,
            uint32(block.timestamp + 1000),
            1 ether
        );

        assertEq(USDC.balanceOf(address(VAULT)), 500 ether, "GeniusVault balance should be 500 ether");
        assertEq(VAULT.stablecoinBalance(), 500 ether, "Total assets should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 500 ether, "Total available assets should be 0 ether");
        assertEq( VAULT.totalStakedAssets(), 0, "Total staked assets should be 0 ether");
        assertEq(USDC.balanceOf(TRADER), 1000 ether, "Orchestrator balance should be unchanged");
    }

    function testRemoveLiquiditySwap() public {

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(VAULT), 1_000 ether);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");

        IGeniusVault.Order memory order = 
            IGeniusVault.Order({
                amountIn: 1_000 ether,
                orderId: VAULT.totalOrders(),
                trader: TRADER,
                srcChainId: 42,
                destChainId: uint16(block.chainid),
                fillDeadline: uint32(block.timestamp + 1000),
                tokenIn: address(USDC),
                fee: 1 ether
            });

        VAULT.removeLiquiditySwap(order);

        assertEq(USDC.balanceOf(address(VAULT)), 0, "GeniusVault balance should be 0 ether");
        assertEq(VAULT.stablecoinBalance(), 0, "Total assets should be 0 ether");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should be 0 ether");
        assertEq( VAULT.availableAssets(), 0, "Available assets should be 0 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), 1_000 ether, "Orchestrator balance should be 1000 ether");
    }

    function removeRewardLiquidity() public {
        
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");

        vm.startPrank(ORCHESTRATOR);
        VAULT.removeRewardLiquidity(1_000 ether);

        assertEq(USDC.balanceOf(address(VAULT)), 0, "GeniusVault balance should be 0 ether");

        assertEq(VAULT.stablecoinBalance(), 0, "Total assets should be 0 ether");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should be 0 ether");
        assertEq(VAULT.availableAssets(), 0, "Available assets should be 0 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function testStakeLiquidity() public {
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        assertEq(VAULT.stablecoinBalance(), 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(VAULT.totalStakedAssets(), 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 750 ether, "Available assets should be 100 ether");
    }

    function testRemoveStakedLiquidity() public {
        assertEq(USDC.balanceOf(address(VAULT)), 0, "GeniusVault balance should be 0 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        assertEq(VAULT.stablecoinBalance(), 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(VAULT.totalStakedAssets(), 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 750 ether, "Available assets should be 100 ether");
        assertEq(USDC.balanceOf(TRADER), 0, "Trader balance should be 0 ether");

        // Remove staked liquidity
        vm.startPrank(TRADER);
        VAULT.withdraw(1_000 ether, TRADER, TRADER);

        assertEq(VAULT.stablecoinBalance(), 0, "Total assets should be 0 ether");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should be 0 ether");
        assertEq( VAULT.availableAssets(), 0, "Available assets should be 0 ether");
        assertEq(USDC.balanceOf(TRADER), 1_000 ether, "Trader balance should be 1,000 ether");
    }

    function testDonatedBalance() public {
        /**
         * Donated balances are balances that are transferred into the pool contract
         * but are done so directly without going through a contract function.
         */

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.deposit(1_000 ether, TRADER);

        assertEq(VAULT.stablecoinBalance(), 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(VAULT.totalStakedAssets(), 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 750 ether, "Available assets should be 100 ether");
        assertEq(USDC.balanceOf(TRADER), 0, "Trader balance should be 0 ether");

        deal(address(USDC), TRADER, 1_000 ether);
        vm.startPrank(TRADER);
        USDC.transfer(address(VAULT), 500 ether);

        assertEq(VAULT.stablecoinBalance(), 1_500 ether, "Total assets should be 1,500 ether");
        assertEq(VAULT.totalStakedAssets(), 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 1250 ether, "Available assets should be 100 ether");
        assertEq(USDC.balanceOf(TRADER), 500 ether, "Trader balance should be 500 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 500 ether);
        VAULT.deposit(500 ether, TRADER);

        assertEq(VAULT.stablecoinBalance(), 2000 ether, "Total assets should be 2,000 ether");
        assertEq(VAULT.totalStakedAssets(), 1_500 ether, "Total staked assets should be 1,500 ether");
        assertEq(VAULT.availableAssets(), 1625 ether, "Available assets should be 650 ether");
        assertEq(USDC.balanceOf(TRADER), 0, "Trader balance should be 0 ether");
    }

    function testRemoveBridgeLiquidity() public {
        uint256 initialOrchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        // Add bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), 500 ether);

        assertEq(USDC.balanceOf(address(VAULT)), 500 ether, "GeniusVault balance should be 500 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestratorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        vm.deal(ORCHESTRATOR, 100 ether);

        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(VAULT), 1_000 ether);

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

        VAULT.removeBridgeLiquidity(amountToRemove, targetChainId, targets, values, data);

        assertEq(USDC.balanceOf(address(VAULT)), 400 ether, "GeniusVault balance should be 400 ether");
        assertEq(USDC.balanceOf(randomAddress), amountToRemove, "Random address should receive 100 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestratorBalance - 500 ether, "Orchestrator balance should remain unchanged");

        assertEq(VAULT.stablecoinBalance(), 400 ether, "Total assets should be 400 ether");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should be 0 ether");
        assertEq(VAULT.availableAssets(), 400 ether, "Available assets should be 400 ether");
    }

    function testAddLiquiditySwapOrderCreation() public {
        

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 _fillDeadline = uint32(block.timestamp + 1000);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, _fillDeadline, 1 ether);

        assertEq(VAULT.totalOrders(), 1, "Total orders should be 1");

        IGeniusVault.Order memory _order_ = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: _fillDeadline,
            tokenIn: address(USDC),
            fee: 1 ether
        });

        bytes32 orderHash = VAULT.orderHash(_order_);
        uint8 status = uint8(VAULT.orderStatus(orderHash));

        console.log("Order Status: %d", status);
        assertEq(uint256(VAULT.orderStatus(orderHash)), uint256(IGeniusVault.OrderStatus.Created), "Order status should be Created");
    }

    function testRemoveLiquiditySwapOrderFulfillment() public {

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        VAULT.removeLiquiditySwap(order);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(uint256(VAULT.orderStatus(orderHash)), uint256(IGeniusVault.OrderStatus.Filled), "Order status should be Filled");
    }

    function testSetOrderAsFilled() public {
        

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(order);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(uint256(VAULT.orderStatus(orderHash)), uint256(IGeniusVault.OrderStatus.Filled), "Order status should be Filled");
    }

    function testRevertOrder() public {

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 100), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: address(USDC),
            fee: 1 ether
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

        VAULT.revertOrder(order, targets, data, values);

        uint256 postBalance = USDC.balanceOf(TRADER);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(uint256(VAULT.orderStatus(orderHash)), uint256(IGeniusVault.OrderStatus.Reverted), "Order status should be Reverted");
        assertEq(postBalance - prevBalance, 1_000 ether, "Trader should receive refunded amount");
    }

    function testCannotRevertOrderBeforeDeadline() public {
        

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        vm.startPrank(ORCHESTRATOR);
        
        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        bytes[] memory data = new bytes[](1);
        data[0] = abi.encodeWithSelector(USDC.transfer.selector, TRADER, 1_000 ether);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlineNotPassed.selector, uint32(block.timestamp + 1000)));
        VAULT.revertOrder(order, targets, data, values);
    }

    function testAddLiquiditySwapWithZeroAmount() public {
        

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector));
        VAULT.addLiquiditySwap(TRADER, address(USDC), 0, destChainId, uint32(block.timestamp + 1000), 1 ether);
    }

    function testAddLiquiditySwapWithInvalidToken() public {
        

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(WETH)));
        VAULT.addLiquiditySwap(TRADER, address(WETH), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);
    }

    function testAddLiquiditySwapWithSameChainId() public {
        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidDestChainId.selector, uint16(block.chainid)));
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, uint16(block.chainid), uint32(block.timestamp + 1000), 1 ether);
    }

    function testAddLiquiditySwapWithPastDeadline() public {
        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlinePassed.selector, uint32(block.timestamp - 1)));
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp - 1), 1 ether);
    }

    function testRemoveLiquiditySwapAfterDeadline() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DeadlinePassed.selector, uint32(block.timestamp + 100)));
        VAULT.removeLiquiditySwap(order);
    }

    function testSetOrderAsFilledWithWrongSourceChain() public {
        

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        VAULT.setOrderAsFilled(badOrder);
    }

    function testSetOrderAsFilledTwice() public {

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(order);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        VAULT.setOrderAsFilled(order);
    }

    function testRevertOrderWithWrongSourceChain() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether);

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
        VAULT.revertOrder(badOrder, targets, data, values);
    }

    function testRevertOrderWithIncorrectRefundAmount() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 100), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: address(USDC),
            fee: 1 ether
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
        VAULT.revertOrder(order, targets, data, values);
    }

    function testRevertOrderTwice() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 100), 1 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            amountIn: 1_000 ether,
            orderId: 0,
            trader: TRADER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: address(USDC),
            fee: 1 ether
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

        VAULT.revertOrder(order, targets, data, values);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector));
        VAULT.revertOrder(order, targets, data, values);
    }
}