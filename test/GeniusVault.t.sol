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
import {GeniusProxyCall} from "../src/GeniusProxyCall.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusVaultTest is Test {
    uint256 destChainId = 42;

    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint256 sourceChainId = block.chainid; // avalanche
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
    GeniusProxyCall public PROXYCALL;
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

        badOrder = IGeniusVault.Order({
            seed: keccak256(abi.encodePacked("badOrder")),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 43, // Wrong source chain
            destChainId: destChainId,
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
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

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
        VAULT.setTargetChainMinFee(address(USDC), destChainId, 1 ether);

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

        bytes memory data = abi.encodeWithSignature(
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
        VAULT.rebalanceLiquidity(0.5 ether, destChainId, address(USDC), data);
        vm.stopPrank();
    }

    function testcreateOrderWhenPaused() public {
        vm.startPrank(OWNER);
        VAULT.pause();
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        VAULT.createOrder(order);
    }

    function testcreateOrderWhenNoApprove() public {
        vm.startPrank(address(ORCHESTRATOR));
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        VAULT.createOrder(order);
    }

    function testcreateOrderWhenNoBalance() public {
        vm.startPrank(address(TRADER));
        USDC.transfer(address(ORCHESTRATOR), 1 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        VAULT.createOrder(order);
    }

    function testfillOrderWhenPaused() public {
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
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        vm.expectRevert(
            abi.encodeWithSelector(Pausable.EnforcedPause.selector)
        );
        // Create calldata to transfer the stablecoin to this contract
        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            1001 ether
        );

        VAULT.fillOrder(order, address(USDC), data, address(0), "");
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
        VAULT.initialize(address(USDC), OWNER, address(PROXYCALL), 7_500);
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

    function testfillOrder() public {
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
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 997 ether,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            999 ether
        );

        vm.startPrank(address(ORCHESTRATOR));
        VAULT.fillOrder(order, address(USDC), data, address(0), "");

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

    function testfillOrderNoTargets() public {
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
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            receiver: RECEIVER,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });

        uint256 balanceTraderBefore = USDC.balanceOf(TRADER);

        // Execute fillOrder
        vm.startPrank(address(ORCHESTRATOR));
        VAULT.fillOrder(order, address(0), "", address(0), "");

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
        VAULT.rebalanceLiquidity(
            amountToRemove,
            destChainId,
            address(USDC),
            stableTransferData
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

    function testOrderCreation() public {
        vm.startPrank(address(ORCHESTRATOR));
        deal(address(USDC), address(ORCHESTRATOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);
        VAULT.createOrder(order);

        bytes32 orderHash = VAULT.orderHash(order);

        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Created),
            "Order status should be Created"
        );
    }

    function testfillOrderOrderFulfillment() public {
        vm.startPrank(ORCHESTRATOR);
        deal(address(USDC), address(VAULT), 1_000 ether);

        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        bytes memory data = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            999 ether
        );

        VAULT.fillOrder(order, address(USDC), data, address(0), "");

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Filled),
            "Order status should be Filled"
        );
    }

    function testcreateOrderWithZeroAmount() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 0,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidAmount.selector)
        );
        VAULT.createOrder(order);
    }

    function testcreateOrderWithInvalidToken() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(WETH)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: bytes32(uint256(1))
        });
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidTokenIn.selector)
        );

        VAULT.createOrder(order);
    }

    function testcreateOrderWithSameChainId() public {
        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
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

        VAULT.createOrder(order);
    }

    function testCreateOrderWithTargetChainIdOrTokenNotSupported() public {
        vm.startPrank(OWNER);
        VAULT.setTargetChainMinFee(address(USDC), destChainId, 0);
        vm.stopPrank();

        vm.startPrank(address(ORCHESTRATOR));
        order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1000 ether,
            trader: VAULT.addressToBytes32(TRADER),
            receiver: RECEIVER,
            srcChainId: block.chainid,
            destChainId: destChainId,
            tokenIn: VAULT.addressToBytes32(address(USDC)),
            fee: 1 ether,
            minAmountOut: 0,
            tokenOut: VAULT.addressToBytes32(address(USDC))
        });

        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.TokenOrTargetChainNotSupported.selector
            )
        );

        VAULT.createOrder(order);
    }
}
