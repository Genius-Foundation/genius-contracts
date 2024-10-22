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
import {MockERC20} from "./mocks/MockERC20.sol";

contract GeniusVaultOrders is Test {
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 sourceChainId = 1; // ethereum
    uint16 targetChainId = 43114; // current

    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    bytes32 RECEIVER;

    ERC20 public USDC;
    ERC20 public TOKEN1;

    GeniusVault public VAULT;

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
        TOKEN1 = new MockERC20("Token1", "TK1", 18);

        PROXYCALL = new GeniusProxyCall(OWNER, new address[](0));

        vm.startPrank(OWNER, OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER,
            address(PROXYCALL),
            7_500,
            30,
            300
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));

        PROXYCALL.grantRole(PROXYCALL.CALLER_ROLE(), address(VAULT));

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
        deal(address(TOKEN1), address(DEX_ROUTER), 100_000_000 ether);
        deal(address(USDC), address(VAULT), 1_000 ether);
    }

    function testRemoveLiquiditySwap() public {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 timestamp = uint32(block.timestamp + 200);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: sourceChainId, // Use the current chain ID
            destChainId: targetChainId,
            fillDeadline: timestamp,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 50_000_000 ether,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(TOKEN1),
            order.amountIn - order.fee,
            TRADER
        );

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");
        vm.stopPrank();

        bytes32 hash = VAULT.orderHash(order);
        assertEq(uint(VAULT.orderStatus(hash)), 2, "Order should be filled");

        // Add assertions to check the state after removing liquidity
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );
        assertEq(
            USDC.balanceOf(address(DEX_ROUTER)),
            999 ether,
            "Executor balance should be 999 USDC"
        );
        assertEq(
            VAULT.unclaimedFees(),
            0 ether,
            "Total unclaimed fees should be 0 ether"
        );
        assertEq(
            VAULT.availableAssets(),
            1 ether,
            "Available Stablecoin balance should be 1"
        );
        assertEq(
            TOKEN1.balanceOf(TRADER),
            order.minAmountOut,
            "Trader should receive the correct amount"
        );
    }

    function testRemoveLiquiditySwapShouldTransferUsdcIfAmountOutTooSmall()
        public
    {
        vm.startPrank(address(ORCHESTRATOR));
        USDC.approve(address(VAULT), 1_000 ether);
        uint32 timestamp = uint32(block.timestamp + 200);

        IGeniusVault.Order memory order = IGeniusVault.Order({
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            amountIn: 1_000 ether,
            seed: keccak256("order"), // This should be the correct order ID
            srcChainId: sourceChainId, // Use the current chain ID
            destChainId: targetChainId,
            fillDeadline: timestamp,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 51_000_000 ether,
            tokenOut: VAULT.addressToBytes32(address(TOKEN1))
        });

        // Remove liquidity
        vm.startPrank(address(ORCHESTRATOR));

        bytes memory data = abi.encodeWithSelector(
            DEX_ROUTER.swapTo.selector,
            address(USDC),
            address(TOKEN1),
            order.amountIn - order.fee,
            TRADER
        );

        uint256 balanceBefore = USDC.balanceOf(TRADER);

        VAULT.fillOrder(order, address(DEX_ROUTER), data, address(0), "");
        vm.stopPrank();

        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusVault balance should be 1 ether (only fees left)"
        );

        assertEq(
            USDC.balanceOf(TRADER) - balanceBefore,
            999 ether,
            "Executor balance should be 999 USDC"
        );
    }
}
