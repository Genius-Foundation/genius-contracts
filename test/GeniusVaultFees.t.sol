// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

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
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public WETH;

    GeniusVault public VAULT;

    GeniusProxyCall public MULTICALL;
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
        WETH = ERC20(0x49D5c2BdFfac6CE2BFdB6640F4F80f226bc10bAB); // WETH on Avalanche
        MULTICALL = new GeniusProxyCall();

        vm.startPrank(OWNER, OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER,
            address(MULTICALL),
            7_500,
            30,
            300
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));
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
        assertEq(VAULT.hasRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR), true);

        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(ORCHESTRATOR), 1_000 ether);
    }

    function testAddLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: block.chainid,
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.createOrder(order);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0,
            "Executor balance should be 0"
        );

        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should be 0"
        );
        assertEq(
            VAULT.unclaimedFees(),
            1 ether,
            "Total unclaimed fees should be 0 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1_000 ether,
            "Stablecoin balance should be 1,000 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            999 ether,
            "Available Stablecoin balance should be 999 ether"
        );
    }

    function testAddLiquidityAndRemoveLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 timestamp = uint32(block.timestamp + 200);

        IGeniusVault.Order memory orderToFill = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 43114, // Use the current chain ID
            destChainId: 1,
            fillDeadline: timestamp,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        VAULT.createOrder(orderToFill);

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 0 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InsufficientLiquidity.selector,
                999 ether,
                1_000 ether
            )
        );

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1_000 ether
        );

        VAULT.fillOrder(order, address(USDC), data, address(0), "");

        order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        data = abi.encodeWithSelector(
            USDC.transfer.selector,
            TRADER,
            999 ether
        );
        VAULT.fillOrder(order, address(USDC), data, address(0), "");
        vm.stopPrank();

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0 ether,
            "Executor balance should be 0 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should still be 0"
        );
        assertEq(
            VAULT.unclaimedFees(),
            1 ether,
            "Total unclaimed fees should still be 1 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1 ether,
            "Stablecoin balance should be 2 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            0 ether,
            "Available Stablecoin balance should be 0"
        );
    }

    function testAddLiquidityAndRemoveLiquidityWithoutExternalCall() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 timestamp = uint32(block.timestamp + 200);

        IGeniusVault.Order memory orderToFill = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 43114, // Use the current chain ID
            destChainId: 1,
            fillDeadline: timestamp,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.createOrder(orderToFill);

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 0 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InsufficientLiquidity.selector,
                999 ether,
                1000 ether
            )
        );

        VAULT.fillOrder(order, address(0), "", address(0), "");

        order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        VAULT.fillOrder(order, address(0), "", address(0), "");
        vm.stopPrank();

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0 ether,
            "Executor balance should be 0 ether"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should still be 0"
        );
        assertEq(
            VAULT.unclaimedFees(),
            1 ether,
            "Total unclaimed fees should still be 0 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1 ether,
            "Stablecoin balance should be 1 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            0 ether,
            "Available Stablecoin balance should be 0"
        );
    }

    function testRemoveTooMuchLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);

        uint32 timestamp = uint32(block.timestamp + 200);
        IGeniusVault.Order memory orderToFill = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 43114, // Use the current chain ID
            destChainId: 1,
            fillDeadline: timestamp,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.createOrder(orderToFill);
        vm.stopPrank();

        // Set the order as filled
        vm.startPrank(ORCHESTRATOR);

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 1, // Use the current chain ID
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.ExternalCallFailed.selector,
                address(USDC),
                0
            )
        );

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1000 ether
        );

        VAULT.fillOrder(order, address(USDC), data, address(0), "");

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0,
            "Executor balance should be 0"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked assets should still be 0"
        );
        assertEq(
            VAULT.unclaimedFees(),
            1 ether,
            "Total unclaimed fees should still be 1 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1_000 ether,
            "Stablecoin balance should be 1,000 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            999 ether,
            "Available Stablecoin balance should be 0 ether"
        );
    }
}
