// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";


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

    function testSetRebalanceThresholdWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();

        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        POOL.setRebalanceThreshold(5);
        vm.stopPrank();

    }

    function testAddBridgeLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        POOL.addBridgeLiquidity(1_000 ether, targetChainId);
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
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        POOL.removeBridgeLiquidity(0.5 ether, targetChainId, tokens, amounts, data);
        vm.stopPrank();
    }

    function testAddLiquiditySwapWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);
    }

    function testRemoveLiquiditySwapWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
        POOL.removeLiquiditySwap(TRADER, 1_000 ether);
    }

    function testRemoveRewardLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        POOL.emergencyLock();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.Paused.selector));
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
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addBridgeLiquidity(1_000 ether, targetChainId);

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
            1 ether
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
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

        assertEq(USDC.balanceOf(address(POOL)), 1_000 ether, "GeniusPool balance should be 1,000 ether");

        POOL.removeLiquiditySwap(TRADER, 1_000 ether);

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
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 1_000 ether);

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

        assertEq(totalAssets, 1_000 ether, "Total assets should be 1,500 ether");
        assertEq(totalStakedAssets, 1_000 ether, "Total staked assets should be 1,000 ether");
        assertEq(availableAssets, 750 ether, "Available assets should be 100 ether");
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
        USDC.approve(address(POOL), 1_000 ether);
        POOL.addBridgeLiquidity(500 ether, targetChainId);

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
}