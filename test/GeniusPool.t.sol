// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";


contract GeniusPoolTest is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 106; // avalanche
    uint16 targetChainId = 101; // ethereum

    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address OWNER;
    address TRADER;
    address ORCHESTRATOR;

    ERC20 public USDC;
    IStargateRouter public stargateRouter;

    GeniusPool public geniusPool;
    GeniusVault public geniusVault;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        ORCHESTRATOR = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38; // The hardcoded tx.origin for forge

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche
        stargateRouter = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd); // Stargate Router on Avalanche

        vm.startPrank(OWNER, OWNER);
        geniusPool = new GeniusPool(address(USDC), address(stargateRouter), OWNER);
        geniusVault = new GeniusVault(address(USDC), OWNER);
        vm.stopPrank();

        assertEq(geniusPool.owner(), OWNER, "Owner should be ORCHESTRATOR");

        vm.startPrank(OWNER);
        geniusVault.initialize(address(geniusPool));

        vm.startPrank(OWNER);
        geniusPool.initialize(address(geniusVault));

        geniusPool.addOrchestrator(ORCHESTRATOR);
        geniusPool.addOrchestrator(address(this));
        assertEq(geniusPool.orchestrator(ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
    }

    function testEmergencyLock() public {
        vm.startPrank(OWNER);
        geniusPool.emergencyLock();

        assertEq(geniusPool.isPaused(), 1, "GeniusPool should be paused");

        /**
        * When paused, we should not be able to access any of the functions
        * that require the contract to be unpaused.
        */

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.setRebalanceThreshold(5);
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.addBridgeLiquidity(1_000 ether, targetChainId);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.removeBridgeLiquidity(1 ether, 0.5 ether, targetChainId, sourcePoolId, targetPoolId);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.removeLiquiditySwap(TRADER, 1_000 ether);

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        geniusPool.removeRewardLiquidity(1_000 ether);
    }

    function testEmergencyUnlock() public {
        vm.startPrank(OWNER);
        geniusPool.emergencyLock();
        assertEq(geniusPool.isPaused(), 1, "GeniusPool should be paused");

        vm.startPrank(OWNER);
        geniusPool.emergencyUnlock();
        assertEq(geniusPool.isPaused(), 0, "GeniusPool should be unpaused");
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
        vm.startPrank(OWNER);
        vm.expectRevert();
        geniusPool.initialize(address(geniusVault));
    }

    function testSetRebalanceThreshold() public {
        vm.startPrank(OWNER);
        geniusPool.setRebalanceThreshold(5);

        assertEq(geniusPool.rebalanceThreshold(), 5, "Rebalance threshold should be 5");
    }

    function testAddBridgeLiquidity() public {
        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.addBridgeLiquidity(1_000 ether, targetChainId);

        assertEq(USDC.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(orchestratorBalance, 0, "Orchestrator balance should be 0");
    }

    function testAddLiquiditySwap() public {
        vm.startPrank(TRADER);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be0 ether");
        assertEq(availableAssets, 1_000 ether, "Available assets should be 1,000 ether");
        assertEq(traderBalance, 0, "Orchestrator balance should be 0");
    }

    function testRemoveLiquiditySwap() public {
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        vm.startPrank(ORCHESTRATOR);
        geniusPool.removeLiquiditySwap(TRADER, 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function removeRewardLiquidity() public {
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        vm.startPrank(ORCHESTRATOR);
        geniusPool.removeRewardLiquidity(1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 orchestratorBalance = USDC.balanceOf(ORCHESTRATOR);

        assertEq(totalAssets, 0, "Total assets should be 0 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 0, "Available assets should be 0 ether");
        assertEq(orchestratorBalance, initialOrchestatorBalance + 1_000 ether, "Orchestrator balance should be +1,000 ether");
    }

    function testStakeLiquidity() public {
        vm.expectRevert();
        geniusPool.stakeLiquidity(TRADER, 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, TRADER);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
    }

    function testRemoveStakedLiquidity() public {
        vm.expectRevert();
        geniusPool.stakeLiquidity(TRADER, 1_000 ether);

        assertEq(USDC.balanceOf(address(geniusPool)), 0, "GeniusPool balance should be 0 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, TRADER);

        // Remove staked liquidity (should fail because unstaking is not available through the pool contract)
        vm.startPrank(TRADER);
        vm.expectRevert();
        geniusPool.removeStakedLiquidity(TRADER, 1_000 ether);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        // Remove staked liquidity
        vm.startPrank(TRADER);
        geniusVault.withdraw(1_000 ether, TRADER, TRADER);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
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
        USDC.approve(address(geniusVault), 1_000 ether);
        geniusVault.deposit(1_000 ether, TRADER);

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();
        uint256 traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,000 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");

        deal(address(USDC), TRADER, 1_000 ether);
        vm.startPrank(TRADER);
        USDC.transfer(address(geniusPool), 500 ether);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
        traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,500 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
        assertEq(traderBalance, 500 ether, "Trader balance should be 500 ether");

        vm.startPrank(TRADER);
        USDC.approve(address(geniusVault), 500 ether);
        geniusVault.deposit(500 ether, TRADER);

        totalAssets = geniusPool.totalAssets();
        availableAssets = geniusPool.availableAssets();
        totalStakedAssets = geniusPool.totalStakedAssets();
        traderBalance = USDC.balanceOf(TRADER);

        assertEq(totalAssets, 2000 ether, "Total assets should be 2,000 ether");
        assertEq(totalStakedAssets, 1_500 ether, "Total staked assets should be 1,500 ether");
        assertEq(availableAssets, 1625 ether, "Available assets should be 650 ether");
        assertEq(traderBalance, 0, "Trader balance should be 0 ether");
    }

    function testRemoveBridgeLiquidity() public {
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        // Add bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.addBridgeLiquidity(500 ether, targetChainId);

        assertEq(USDC.balanceOf(address(geniusPool)), 500 ether, "GeniusPool balance should be 1,000 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestatorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        vm.deal(ORCHESTRATOR, 100 ether);

        vm.startPrank(ORCHESTRATOR);
        USDC.approve(address(geniusPool), 1_000 ether);
        geniusPool.removeBridgeLiquidity{value: 20 ether}(
            100 * 1e6,
            0,
            targetChainId,
            sourcePoolId,
            targetPoolId
        );

        assertEq(USDC.balanceOf(address(geniusPool)), 499.9999999999 ether, "GeniusPool balance should be 499.9999999999 ether");
        assertEq(USDC.balanceOf(ORCHESTRATOR), initialOrchestatorBalance - 500 ether, "Orchestrator balance should be -500 ether");

        uint256 totalAssets = geniusPool.totalAssets();
        uint256 availableAssets = geniusPool.availableAssets();
        uint256 totalStakedAssets = geniusPool.totalStakedAssets();

        assertEq(totalAssets, 499.9999999999 ether, "Total assets should be 499.9999999999 ether");
        assertEq(totalStakedAssets, 0, "Total staked assets should be 0 ether");
        assertEq(availableAssets, 499.9999999999 ether, "Available assets should be 499.9999999999 ether");
    }
}