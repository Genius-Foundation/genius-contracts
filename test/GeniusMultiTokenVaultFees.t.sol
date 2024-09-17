// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusMultiTokenVault} from "../src/GeniusMultiTokenVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusMultiTokenVaultFees is Test {
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
    ERC20 public USDT; // Additional token for multi-token testing

    GeniusMultiTokenVault public VAULT;
    
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
        USDT = ERC20(0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7); // USDT on Avalanche (example)

        vm.startPrank(OWNER, OWNER);
        GeniusMultiTokenVault implementation = new GeniusMultiTokenVault();

        address[] memory initialTokens = new address[](2);
        initialTokens[0] = address(WETH);
        initialTokens[1] = address(USDT);

        address[] memory initialBridges = new address[](1);
        initialBridges[0] = makeAddr("BRIDGE");

        address[] memory initialRouters = new address[](1);
        initialRouters[0] = makeAddr("ROUTER");

        bytes memory data = abi.encodeWithSelector(
            GeniusMultiTokenVault.initialize.selector,
            address(USDC),
            OWNER,
            initialTokens,
            initialBridges,
            initialRouters
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusMultiTokenVault(address(proxy));
        EXECUTOR = new GeniusExecutor(PERMIT2, address(VAULT), OWNER, new address[](0));
        DEX_ROUTER = new MockDEXRouter();

        vm.stopPrank();

        assertEq(VAULT.hasRole(VAULT.DEFAULT_ADMIN_ROLE(), OWNER), true, "Owner should be ORCHESTRATOR");

        vm.startPrank(OWNER);
        VAULT.setExecutor(address(EXECUTOR));

        vm.startPrank(OWNER);
        VAULT.manageRouter(address(DEX_ROUTER), true);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), address(this));
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), address(this));
        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        deal(address(WETH), TRADER, 1_000 ether);
        deal(address(USDT), TRADER, 1_000 ether);
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
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether, RECEIVER);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor balance should be 0");

        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "Total unclaimed fees should be 1 ether");
        assertEq(VAULT.minLiquidity(), 1000 ether, "Needed liquidity should be 1000 ether");
        assertEq(VAULT.tokenBalance(address(USDC)), 1_000 ether, "Stablecoin balance should be 1,000 ether");
        assertEq(VAULT.availableAssets(), 0 ether, "Available assets should be 0");
        assertEq(VAULT.supportedTokenReserves(address(USDC)), 1000 ether, "Token reserve should be 1000 tokens");


    }

    function testAddLiquidityAndRemoveLiquidity() public {
        vm.startPrank(address(EXECUTOR));

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: TRADER,
            receiver: RECEIVER,
            amountIn: 1000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: uint16(block.chainid), // Use the current chain ID
            destChainId: 42,
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 1 ether
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            order.trader,
            order.tokenIn,
            order.amountIn,
            order.destChainId,
            order.fillDeadline,
            order.fee,
            order.receiver
        );
        vm.stopPrank();

        assertEq(VAULT.supportedTokenReserves(address(USDC)), 1000 ether, "Token reserve should be 1000 tokens");
        assertEq(VAULT.availableAssets(), 0 ether, "Available assets should be 0");

                // Set the order as filled
        vm.startPrank(ORCHESTRATOR);
        VAULT.setOrderAsFilled(order);
        vm.stopPrank(); 

        order = IGeniusVault.Order({
            trader: TRADER,
            receiver: RECEIVER,
            amountIn: 1000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 42, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 1000),
            tokenIn: address(USDC),
            fee: 3 ether
        });

        // Create dummy targets, calldata, and values arrays to call removeLiquiditySwap
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(USDC.transfer.selector, address(this), 997 ether);
        // Value is 0
        values[0] = 0;

        console.log("Removing liquidity");
        console.log("USDC balance before removing liquidity: ", USDC.balanceOf(address(VAULT)));
        console.log("USDC available assets before removing liquidity: ", VAULT.availableAssets());

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        VAULT.removeLiquiditySwap(
            order,
            targets,
            values,
            calldatas
        );

        // Add assertions to check the state after removing liquidity
        assertEq(USDC.balanceOf(address(VAULT)), 3 ether, "GeniusVault balance should be 3 ether (only fees left)");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0 ether, "Executor balance should be 999 ether");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 1 ether, "Total unclaimed fees should still be 1 ether");
        assertEq(VAULT.minLiquidity(), 1 ether, "Minimum liquidity should be 1");
        assertEq(VAULT.availableAssets(), 2 ether, "Available assets should be 0");
        assertEq(VAULT.tokenBalance(address(USDC)), 3 ether, "Stablecoin balance should be 1 ether");
        assertEq(VAULT.supportedTokenReserves(address(USDC)), 0 ether, "Token reserve should be 0 tokens");
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

        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        // Target is stablecoin
        targets[0] = address(USDC);
        // Create calldata to transfer the stablecoin to this contract
        calldatas[0] = abi.encodeWithSelector(USDC.transfer.selector, address(this), 1001 ether);
        // Value is 0
        values[0] = 0;

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InsufficientLiquidity.selector, 0 ether, 1000 ether));
        VAULT.removeLiquiditySwap(
            order,
            targets,
            values,
            calldatas
        );

        // Add assertions to check the state after removing liquidity
        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "GeniusVault balance should be 1,000 ether");
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor balance should be 0");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "Total unclaimed fees should still be 1 ether");
        assertEq(VAULT.availableAssets(), 0 ether, "Available assets should be 0 ether");
        assertEq(VAULT.tokenBalance(address(USDC)), 1_000 ether, "Stablecoin balance should be 1,000 ether");
    }

    function testAddLiquidityMultipleTokens() public {
        deal(address(WETH), address(EXECUTOR), 1_000 ether);
        deal(address(USDT), address(EXECUTOR), 1_000 ether);
        deal(address(WETH), address(EXECUTOR), 1_000 ether);
        
        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(VAULT), 10000 ether);
        WETH.approve(address(VAULT), 10000 ether);
        USDT.approve(address(VAULT), 10000 ether);

        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDC), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether, RECEIVER);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(WETH), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether, RECEIVER);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDT), 1_000 ether, destChainId, uint32(block.timestamp + 1000), 1 ether, RECEIVER);

        assertEq(USDC.balanceOf(address(VAULT)), 1_000 ether, "USDC balance should be 1,000 ether");
        assertEq(WETH.balanceOf(address(VAULT)), 1_000 ether, "WETH balance should be 1,000 ether");
        assertEq(USDT.balanceOf(address(VAULT)), 1_000 ether, "USDT balance should be 1,000 ether");

        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "USDC unclaimed fees should be 1 ether");
        assertEq(VAULT.supportedTokenFees(address(WETH)), 0, "WETH unclaimed fees should be 1 ether");
        assertEq(VAULT.supportedTokenFees(address(USDT)), 0, "USDT unclaimed fees should be 1 ether");

        assertEq(VAULT.supportedTokenReserves(address(USDC)), 1_000 ether, "USDC reserve should be 1000 tokens");
        assertEq(VAULT.supportedTokenReserves(address(WETH)), 1_000 ether, "WETH reserve should be 1,000 ether");
        assertEq(VAULT.supportedTokenReserves(address(USDT)), 1_000 ether, "USDT reserve should be 1,000 ether");
    }
}
