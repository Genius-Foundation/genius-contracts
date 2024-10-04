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
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusVaultTest is Test {
    uint256 destChainId = 42;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint256 sourceChainId = 106; // avalanche
    uint256 targetChainId = 101; // ethereum

    uint256 sourcePoolId = 1;
    uint256 targetPoolId = 1;

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public WETH;

    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;

    IGeniusVault.Order public badOrder;

    IGeniusVault.Order public order;

    function setUp() public {
        avalanche = vm.createFork(rpc);

        vm.selectFork(avalanche);

        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        RECEIVER = bytes32(uint256(uint160(TRADER)));
        ORCHESTRATOR = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB);

        vm.startPrank(OWNER, OWNER);

        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));

        badOrder = IGeniusVault.Order({
            seed: keccak256(abi.encodePacked("badOrder")),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 43, // Wrong source chain
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
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
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        EXECUTOR = new GeniusExecutor(
            PERMIT2,
            address(VAULT),
            OWNER,
            new address[](0)
        );

        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(
            VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER),
            true,
            "Owner should be ORCHESTRATOR"
        );

        vm.startPrank(OWNER);
        VAULT.setExecutor(address(EXECUTOR));

        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);

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
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.removeBridgeLiquidity(
            0.5 ether,
            targetChainId,
            tokens,
            amounts,
            data
        );
        vm.stopPrank();
    }

    function testAddLiquiditySwapWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.addLiquiditySwap(order);
    }

    function testAddLiquiditySwapWhenNoApprove() public {
        vm.startPrank(address(EXECUTOR));
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        VAULT.addLiquiditySwap(order);
    }

    function testAddLiquiditySwapWhenNoBalance() public {
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 1_000 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        VAULT.addLiquiditySwap(order);
    }

    function testRemoveLiquiditySwapWhenPaused() public {
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
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1001 ether
        );
        // Value is 0
        values[0] = 0;

        VAULT.removeLiquiditySwap(order, targets, values, calldatas);
    }

    function testRemoveRewardLiquidityWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
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
        VAULT.initialize(address(USDC), OWNER);
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

    function testAddLiquiditySwapNative() public {
        deal(address(USDC), address(DEX_ROUTER), 1_000 ether);
        bytes memory swapData = abi.encodeWithSelector(
            MockDEXRouter.swapToStables.selector,
            address(USDC)
        );

        vm.startPrank(address(TRADER));
        vm.deal(address(TRADER), 2 ether);
        EXECUTOR.nativeSwapAndDeposit{value: 2 ether}(
            keccak256("order"),
            address(DEX_ROUTER),
            swapData,
            2 ether,
            destChainId,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER,
            0,
            bytes32(uint256(1))
        );

        assertEq(
            VAULT.stablecoinBalance(),
            500 ether,
            "Total assets should be 500 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            0 ether,
            "Total available assets should be 0 ether"
        );
        assertEq(
            VAULT.reservedAssets(),
            500 ether,
            "Total reserved assets should be 500 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should be 0 ether"
        );
        assertEq(
            USDC.balanceOf(TRADER),
            1000 ether,
            "Orchestrator balance should be unchanged"
        );
    }

    function testRemoveLiquiditySwap() public {
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
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        // Value is 0
        values[0] = 0;

        vm.startPrank(address(ORCHESTRATOR));
        VAULT.removeLiquiditySwap(order, targets, values, calldatas);

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

    function testRemoveLiquiditySwapNoTargets() public {
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
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        // Empty arrays for targets, values, and calldatas
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        uint256 balanceTraderBefore = USDC.balanceOf(TRADER);

        // Execute removeLiquiditySwap
        vm.startPrank(address(ORCHESTRATOR));
        VAULT.removeLiquiditySwap(order, targets, values, calldatas);

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

    function removeRewardLiquidity() public {
        uint256 initialOrchestatorBalance = USDC.balanceOf(ORCHESTRATOR);

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );

        vm.startPrank(ORCHESTRATOR);
        VAULT.removeRewardLiquidity(1_000 ether);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            0,
            "GeniusVault balance should be 0 ether"
        );

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
            USDC.balanceOf(ORCHESTRATOR),
            initialOrchestatorBalance + 1_000 ether,
            "Orchestrator balance should be +1,000 ether"
        );
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

        VAULT.removeBridgeLiquidity(
            amountToRemove,
            targetChainId,
            targets,
            values,
            data
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

    function testAddLiquiditySwapOrderCreation() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);

        bytes32 orderHash = VAULT.orderHash(order);

        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Created),
            "Order status should be Created"
        );
    }

    function testRemoveLiquiditySwapOrderFulfillment() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            999 ether
        );
        // Value is 0
        values[0] = 0;

        VAULT.removeLiquiditySwap(order, targets, values, calldatas);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
    }

    function testSetOrderAsFilled() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);

        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(order);

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
    }

    function testRevertOrder() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 5 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);
        vm.stopPrank();

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        uint256 prevBalance = USDC.balanceOf(address(this));
        uint256 prevVaultBalance = USDC.balanceOf(address(VAULT));

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        // Value is 0
        values[0] = 0;

        vm.startPrank(address(ORCHESTRATOR));
        VAULT.revertOrder(order, targets, values, calldatas);
        vm.stopPrank();

        uint256 postBalance = USDC.balanceOf(address(this));
        uint256 postVaultBalance = USDC.balanceOf(address(VAULT));

        assertEq(
            VAULT.unclaimedFees(),
            2 ether,
            "Unclaimed fees should be 2 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            2 ether,
            "Vault balance should be 2 ether"
        );
        assertEq(
            postBalance - prevBalance,
            997 ether,
            "Executor should receive refunded amount"
        );
        assertEq(
            prevVaultBalance - postVaultBalance,
            998 ether,
            "Vault balance should decrease by refunded amount"
        );

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Reverted),
            "Order status should be Reverted"
        );
    }

    function testRevertOrderNoTargets() public {
        // Setup initial state
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 5 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);
        vm.stopPrank();

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        uint256 prevTraderBalance = USDC.balanceOf(TRADER);
        uint256 prevVaultBalance = USDC.balanceOf(address(VAULT));

        // Empty arrays for targets, values, and data
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory data = new bytes[](0);

        vm.startPrank(address(ORCHESTRATOR));
        VAULT.revertOrder(order, targets, values, data);
        vm.stopPrank();

        uint256 postTraderBalance = USDC.balanceOf(TRADER);
        uint256 postVaultBalance = USDC.balanceOf(address(VAULT));

        uint256 expectedRefund = 998 ether; // 1000 - 2

        assertEq(
            VAULT.unclaimedFees(),
            2 ether,
            "Unclaimed fees should be 5 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            2 ether,
            "Vault balance should be 5 ether"
        );
        assertEq(
            postTraderBalance - prevTraderBalance,
            expectedRefund,
            "Trader should receive refunded amount"
        );
        assertEq(
            prevVaultBalance - postVaultBalance,
            expectedRefund,
            "Vault balance should decrease by refunded amount"
        );

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Reverted),
            "Order status should be Reverted"
        );
    }

    function testCannotRevertOrderBeforeDeadline() public {
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        vm.startPrank(address(EXECUTOR));

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(order);
        vm.stopPrank();

        address[] memory targets = new address[](2);
        bytes[] memory calldatas = new bytes[](2);
        uint256[] memory values = new uint256[](2);

        // Target is USDC
        targets[0] = address(USDC);
        // Create calldata to approve this contract to spend the user's USDC
        calldatas[0] = abi.encodeWithSelector(
            USDC.approve.selector,
            address(this),
            10000 ether
        );
        // Value is 0
        values[0] = 0;

        // Target is USDC
        targets[1] = address(USDC);
        // Create calldata to transfer the USDC to this contract
        calldatas[1] = abi.encodeWithSelector(
            USDC.transferFrom.selector,
            msg.sender,
            address(this),
            10000 ether
        );
        // Value is 0
        values[1] = 0;

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlineNotPassed.selector,
                order.fillDeadline + VAULT.orderRevertBuffer()
            )
        );
        VAULT.revertOrder(order, targets, values, calldatas);
    }

    function testAddLiquiditySwapWithZeroAmount() public {
        vm.startPrank(address(EXECUTOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 0,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.addLiquiditySwap(order);
    }

    function testAddLiquiditySwapWithInvalidToken() public {
        vm.startPrank(address(EXECUTOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(WETH)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidTokenIn.selector)
        );

        VAULT.addLiquiditySwap(order);
    }

    function testAddLiquiditySwapWithSameChainId() public {
        vm.startPrank(address(EXECUTOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
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

        VAULT.addLiquiditySwap(order);
    }

    function testAddLiquiditySwapWithPastDeadline() public {
        vm.startPrank(address(EXECUTOR));

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            fillDeadline: block.timestamp - 1,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidDeadline.selector)
        );

        VAULT.addLiquiditySwap(order);
    }

    function testRemoveLiquiditySwapAfterDeadline() public {
        vm.startPrank(address(ORCHESTRATOR));
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint32(block.chainid),
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        // Value is 0
        values[0] = 0;

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlinePassed.selector,
                uint32(block.timestamp + 100)
            )
        );
        VAULT.removeLiquiditySwap(order, targets, values, calldatas);
    }

    function testSetOrderAsFilledWithWrongSourceChain() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            receiver: RECEIVER,
            trader: VAULT.addressToBytes32(TRADER),
            srcChainId: block.chainid,
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.addLiquiditySwap(order);

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector)
        );
        VAULT.setOrderAsFilled(badOrder);
    }

    function testSetOrderAsFilledTwice() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.addLiquiditySwap(order);

        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(order);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector)
        );
        VAULT.setOrderAsFilled(order);
    }

    function testRevertOrderTwice() public {
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 3 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.addLiquiditySwap(order);
        vm.stopPrank();

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        // Value is 0
        values[0] = 0;

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);
        vm.startPrank(ORCHESTRATOR);
        VAULT.revertOrder(order, targets, values, calldatas);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidOrderStatus.selector)
        );
        VAULT.revertOrder(order, targets, values, calldatas);
        vm.stopPrank();
    }

    function testCannotAddOrderWithDeadlineAboveMaxOrderTime() public {
        uint32 currentTimestamp = uint32(block.timestamp);
        uint32 invalidDeadline = currentTimestamp +
            uint32(VAULT.maxOrderTime()) +
            1;

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("invalidDeadlineOrder"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: invalidDeadline,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidDeadline.selector)
        );

        VAULT.addLiquiditySwap(order);
        vm.stopPrank();
    }

    function testCannotRevertOrderBeforeRevertBuffer() public {
        // First, add a valid order
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 validDeadline = uint32(block.timestamp + 100);

        IGeniusVault.Order memory orderToRevert = IGeniusVault.Order({
            seed: keccak256("orderToRevert"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: validDeadline,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 3 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.addLiquiditySwap(orderToRevert);
        vm.stopPrank();

        // Prepare revert parameters
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(USDC);
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        values[0] = 0;

        // Advance time to just after the deadline but before the revert buffer
        vm.warp(validDeadline + 1);

        // Attempt to revert the order
        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlineNotPassed.selector,
                validDeadline + VAULT.orderRevertBuffer()
            )
        );
        VAULT.revertOrder(orderToRevert, targets, values, calldatas);
        vm.stopPrank();
    }
}
