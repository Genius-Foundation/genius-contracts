// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";


contract GeniusPoolTest is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 106; // avalanche
    uint16 targetChainId = 101; // ethereum

    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address owner;
    address trader;
    address orchestrator;

    ERC20 public usdc;
    IStargateRouter public stargateRouter;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        owner = makeAddr("owner");
        trader = makeAddr("trader");
        orchestrator = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // The hardcoded tx.origin for forge

        usdc = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche
        stargateRouter = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd); // Stargate Router on Avalanche

        vm.startPrank(owner);
        geniusPool = new GeniusPool(address(usdc), address(stargateRouter), owner);
        geniusVault = new GeniusVault(address(usdc), owner);

        assertEq(geniusPool.owner(), owner, "Owner should be orchestrator");

        vm.startPrank(orchestrator);
        geniusVault.initialize(address(geniusPool));

        vm.startPrank(owner);
        geniusPool.initialize(address(geniusVault));

        geniusPool.addOrchestrator(orchestrator);
        assertEq(geniusPool.orchestrator(orchestrator), true);

        deal(address(usdc), trader, 1_000 ether);
        deal(address(usdc), orchestrator, 1_000 ether);
    }

    function testGetLayerZeroFee() public view {
        (
            uint256 layerZeroFee,
        ) = geniusPool.layerZeroFee(101, 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38);

        console.log("Layer Zero Fee: ", layerZeroFee);
        // console.log("lzTxParams: ", lzTxParams);

        assertEq(layerZeroFee, 0, "Layer Zero Fee should be 0");
    }

    function testRevertWhenAlreadyInitialized() public {
        vm.startPrank(owner);
        vm.expectRevert();
        geniusPool.initialize(address(geniusVault));
    }

    function testSetRebalanceThreshold() public {
        vm.startPrank(owner);
        geniusPool.setRebalanceThreshold(5);

        assertEq(geniusPool.rebalanceThreshold(), 5, "Rebalance threshold should be 5");
    }

    function testAddBridgeLiquidity() public {
        vm.startPrank(orchestrator);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.addBridgeLiquidity(1_000 ether, targetChainId);

        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = usdc.balanceOf(orchestrator);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(orchestratorBalance, 0, "Orchestrator balance should be 0");
    }

    function testAddLiquiditySwap() public {
        vm.startPrank(trader);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = usdc.balanceOf(trader);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(traderBalance, 0, "Orchestrator balance should be 0");
    }

    function testRemoveLiquiditySwap() public {
        uint256 initialOrchestatorBalance = usdc.balanceOf(orchestrator);

        vm.startPrank(trader);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        vm.startPrank(orchestrator);
        geniusPool.removeLiquiditySwap(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = usdc.balanceOf(orchestrator);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function removeRewardLiquidity() public {
        uint256 initialOrchestatorBalance = usdc.balanceOf(orchestrator);

        vm.startPrank(trader);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        vm.startPrank(orchestrator);
        geniusPool.removeRewardLiquidity(1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = usdc.balanceOf(orchestrator);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function testStakeLiquidity() public {
        vm.expectRevert();
        geniusPool.stakeLiquidity(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, trader);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 100 ether, "Available assets should be 100 ether");
    }

    function testRemoveStakedLiquidity() public {
        vm.expectRevert();
        geniusPool.stakeLiquidity(trader, 1_000 ether);

        assertEq(usdc.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, trader);

        // Remove staked liquidity (should fail because unstaking is not available through the pool contract)
        vm.startPrank(trader);
        vm.expectRevert();
        geniusPool.removeStakedLiquidity(trader, 1_000 ether);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = usdc.balanceOf(trader);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 100 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        // Remove staked liquidity
        vm.startPrank(trader);
        geniusVault.withdraw(1_000 ether, trader, trader);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
        traderBalance = usdc.balanceOf(trader);

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

        vm.startPrank(trader);
        usdc.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, trader);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = usdc.balanceOf(trader);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 100 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        deal(address(usdc), trader, 1_000 ether);
        vm.startPrank(trader);
        usdc.transfer(address(geniusPool), 500 ether);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
        traderBalance = usdc.balanceOf(trader);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,500 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 100 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 500 ether, "Trader balance should be 500 ether");

        vm.startPrank(trader);
        usdc.approve(address(geniusVault), 500 ether);
        geniusVault.deposit(500 ether, trader);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
        traderBalance = usdc.balanceOf(trader);

        assertEq(totalAssets, 2000 ether, "Total assets should be 2,000 ether");
        assertEq(totalStakedAssets, 1_500 ether, "Total staked assets should be 1,500 ether");
        assertEq(availableAssets, 650 ether, "Available assets should be 650 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");
    }

    function testRemoveBridgeLiquidity() public {
        uint256 initialOrchestatorBalance = usdc.balanceOf(orchestrator);

        // Add bridge liquidity
        vm.startPrank(orchestrator);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.addBridgeLiquidity(500 ether, targetChainId);

        assertEq(usdc.balanceOf(address(geniusPool)), 500 ether, "GeniusPool balance should be 1,000 ether");
        assertEq(usdc.balanceOf(orchestrator), initialOrchestatorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        vm.deal(orchestrator, 100 ether);

        vm.startPrank(orchestrator);
        usdc.approve(address(geniusPool), 1_000 ether);
        geniusPool.removeBridgeLiquidity{value: 20 ether}(
            100 * 1e6,
            0,
            targetChainId,
            sourcePoolId,
            targetPoolId
        );

        assertEq(usdc.balanceOf(address(geniusPool)), 499.9999999999 ether, "GeniusPool balance should be 499.9999999999 ether");
        assertEq(usdc.balanceOf(orchestrator), initialOrchestatorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        assertEq(totalAssets, 499.9999999999 ether, "Total assets should be 499.9999999999 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 499.9999999999 ether, "Available assets should be 499.9999999999 ether");
    }
}