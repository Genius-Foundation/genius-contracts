// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";
import {GeniusMultiTokenVault} from "../src/GeniusMultiTokenVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

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
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public WETH;
    ERC20 public USDT; // Additional token for multi-token testing

    GeniusMultiTokenVault public VAULT;

    GeniusProxyCall public PROXYCALL;
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
        USDT = ERC20(0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7); // USDT on Avalanche (example)

        PROXYCALL = new GeniusProxyCall();

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
            address(PROXYCALL),
            7_500,
            30,
            300,
            initialTokens
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusMultiTokenVault(address(proxy));
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
        deal(address(WETH), TRADER, 1_000 ether);
        deal(address(USDT), TRADER, 1_000 ether);
    }

    function testAddLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            srcChainId: block.chainid,
            destChainId: 42,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.createOrder(order);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "GeniusVault balance should be 1,000 ether"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0,
            "ORCHESTRATOR balance should be 0"
        );

        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            1 ether,
            "Total unclaimed fees should be 1 ether"
        );
        assertEq(
            VAULT.minLiquidity(),
            1 ether,
            "Needed liquidity should be 1000 ether"
        );
        assertEq(
            VAULT.tokenBalance(address(USDC)),
            1_000 ether,
            "Stablecoin balance should be 1,000 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            999 ether,
            "Available assets should be 0"
        );
    }

    function testAddLiquidityAndRemoveLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));

        // Create an Order struct for removing liquidity
        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: block.chainid, // Use the current chain ID
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.createOrder(order);
        vm.stopPrank();

        assertEq(
            VAULT.availableAssets(),
            999 ether,
            "Available assets should be 999"
        );

        order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: 0, // Use the current chain ID
            destChainId: block.chainid,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 3 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        // Create dummy targets, calldata, and values arrays to call fillOrder

        console.log("Removing liquidity");
        console.log(
            "USDC balance before removing liquidity: ",
            USDC.balanceOf(address(VAULT))
        );
        console.log(
            "USDC available assets before removing liquidity: ",
            VAULT.availableAssets()
        );

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        VAULT.fillOrder(order, address(0), "", address(0), "");

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            3 ether,
            "GeniusVault balance should be 3 ether (only fees left)"
        );
        assertEq(
            USDC.balanceOf(address(ORCHESTRATOR)),
            0 ether,
            "Executor balance should be 999 ether"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            1 ether,
            "Total unclaimed fees should still be 1 ether"
        );
        assertEq(
            VAULT.minLiquidity(),
            1 ether,
            "Minimum liquidity should be 1"
        );
        assertEq(
            VAULT.availableAssets(),
            2 ether,
            "Available assets should be 0"
        );
        assertEq(
            VAULT.tokenBalance(address(USDC)),
            3 ether,
            "Stablecoin balance should be 1 ether"
        );
    }

    function testRemoveTooMuchLiquidity() public {
        vm.startPrank(address(ORCHESTRATOR));

        IGeniusVault.Order memory orderToDeposit = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: block.chainid, // Use the current chain ID
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.createOrder(orderToDeposit);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: destChainId, // Use the current chain ID
            destChainId: block.chainid,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 0,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        // Create calldata to transfer the stablecoin to this contract
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1_000 ether
        );

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InsufficientLiquidity.selector,
                999 ether,
                1_000 ether
            )
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
            VAULT.supportedTokenFees(address(USDC)),
            1 ether,
            "Total unclaimed fees should still be 1 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            999 ether,
            "Available assets should be 999 ether"
        );
        assertEq(
            VAULT.tokenBalance(address(USDC)),
            1_000 ether,
            "Stablecoin balance should be 1,000 ether"
        );
    }

    function testAddLiquidityMultipleTokens() public {
        deal(address(WETH), address(ORCHESTRATOR), 1_000 ether);
        deal(address(USDT), address(ORCHESTRATOR), 1_000 ether);
        deal(address(WETH), address(ORCHESTRATOR), 1_000 ether);

        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 10000 ether);
        WETH.approve(address(VAULT), 10000 ether);
        USDT.approve(address(VAULT), 10000 ether);

        IGeniusVault.Order memory orderUsdc = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: block.chainid, // Use the current chain ID
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        IGeniusVault.Order memory orderUsdt = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: block.chainid, // Use the current chain ID
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(USDT)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        IGeniusVault.Order memory orderWeth = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"),
            srcChainId: block.chainid,
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: VAULT.addressToBytes32(address(WETH)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        VAULT.createOrder(orderUsdc);
        VAULT.createOrder(orderUsdt);
        VAULT.createOrder(orderWeth);

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_000 ether,
            "USDC balance should be 1,000 ether"
        );
        assertEq(
            WETH.balanceOf(address(VAULT)),
            1_000 ether,
            "WETH balance should be 1,000 ether"
        );
        assertEq(
            USDT.balanceOf(address(VAULT)),
            1_000 ether,
            "USDT balance should be 1,000 ether"
        );

        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            1 ether,
            "USDC unclaimed fees should be 1 ether"
        );
        assertEq(
            VAULT.supportedTokenFees(address(WETH)),
            1 ether,
            "WETH unclaimed fees should be 1 ether"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDT)),
            1 ether,
            "USDT unclaimed fees should be 1 ether"
        );
    }
}
