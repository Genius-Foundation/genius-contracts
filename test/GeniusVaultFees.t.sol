// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { IGeniusVault } from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";


contract GeniusVaultFees is Test {
    uint32 destChainId = 42;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 106; // avalanche
    uint16 targetChainId = 101; // ethereum

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    bytes32 RECEIVER = keccak256("Bh265EkhNxAQA4rS3ey2QT2yJkE8ZS6QqSvrZTMdm8p7");

    ERC20 public USDC;
    ERC20 public WETH;

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
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));
        EXECUTOR = new GeniusExecutor(PERMIT2, address(VAULT), OWNER, new address[](0));
        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER), true, "Owner should be ORCHESTRATOR");

        vm.startPrank(OWNER);
        VAULT.setExecutor(address(EXECUTOR));

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), address(this));
        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
    }

    function testSetFee() public {
        assertEq(VAULT.crosschainFee(), 30, "Fee should be 30 bps");

        vm.startPrank(OWNER);
        VAULT.setCrosschainFee(10);

        assertEq(VAULT.crosschainFee(), 10, "Fee should be 10 bps");
    }

    function testAddLiquidity() public {
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(keccak256("order") ,TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether, RECEIVER);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor balance should be 0");

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should be 0");
        assertEq(VAULT.unclaimedFees(), 0, "Total unclaimed fees should be 0 ether");
        assertEq(VAULT.stablecoinBalance(), 1_000 ether, "Stablecoin balance should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 0 ether, "Available Stablecoin balance should be 999 ether");
        assertEq(VAULT.reservedAssets(), 1_000 ether, "Reserved Stablecoin balance should be 0 ether");
    }

    function testAddLiquidityAndRemoveLiquidity() public {
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 timestamp = uint32(block.timestamp + 1000);

        IGeniusVault.Order memory orderToFill = IGeniusVault.Order({
            trader: TRADER,
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 43114, // Use the current chain ID
            destChainId: 1,
            fillDeadline: timestamp,
            tokenIn: address(USDC),
            fee: 1 ether
        });


        VAULT.addLiquiditySwap(
            keccak256("order"),
            orderToFill.trader,
            orderToFill.tokenIn,
            orderToFill.amountIn,
            orderToFill.destChainId,
            orderToFill.fillDeadline,
            orderToFill.fee,
            orderToFill.receiver
        );

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: TRADER,
            receiver: RECEIVER,
            amountIn: 999 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        // Remove liquidity
        vm.startPrank(address(EXECUTOR));
        // encode with selector
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InsufficientLiquidity.selector, 0 ether, 999 ether));
        VAULT.removeLiquiditySwap(order);
        vm.stopPrank();

        // Set the order as filled
        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(orderToFill);
        bytes32 hash = VAULT.orderHash(orderToFill);
        assertEq(uint(VAULT.orderStatus(hash)), 2, "Order should be filled");
        vm.stopPrank();

        // Remove liquidity
        vm.startPrank(address(EXECUTOR));
        VAULT.removeLiquiditySwap(order);

        // Add assertions to check the state after removing liquidity
        assertEq(USDC.balanceOf(address(VAULT)), 1 ether, "GeniusVault balance should be 1 ether (only fees left)");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 999 ether, "Executor balance should be 999 ether");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should still be 0");
        assertEq(VAULT.unclaimedFees(), 1 ether, "Total unclaimed fees should still be 0 ether");
        assertEq(VAULT.stablecoinBalance(), 1 ether, "Stablecoin balance should be 1 ether");
        assertEq(VAULT.availableAssets(), 0, "Available Stablecoin balance should be 0");
        assertEq(VAULT.reservedAssets(), 0 ether, "Reserved Stablecoin balance should be 0 ether");
    }

    function testRemoveTooMuchLiquidity() public {
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(USDC),
            1_000 ether,
            destChainId,
            uint32(block.timestamp + 1000),
            1 ether,
            RECEIVER
        );

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: TRADER,
            receiver: RECEIVER,
            amountIn: 1_001 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        // Remove liquidity
        vm.startPrank(address(EXECUTOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InsufficientLiquidity.selector, 0 ether, 1001 ether));
        VAULT.removeLiquiditySwap(order);

        // Add assertions to check the state after removing liquidity
        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor balance should be 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets should still be 0");
        assertEq(VAULT.unclaimedFees(), 0, "Total unclaimed fees should still be 0");
        assertEq(VAULT.stablecoinBalance(), 1_000 ether, "Stablecoin balance should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 0 ether, "Available Stablecoin balance should be 0 ether");
        assertEq(VAULT.reservedAssets(), 1_000 ether, "Reserved Stablecoin balance should be 0 ether");
    }
}