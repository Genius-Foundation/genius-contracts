// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusMultiTokenPool} from "../src/GeniusMultiTokenPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";

contract GeniusPoolDOSTest is Test {
    uint256 avalanche;
    uint16 constant targetChainId = 42;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    address OWNER;
    address TRADER;
    address ORCHESTRATOR;
    address public BRIDGE;
    address PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    address public constant NATIVE = address(0);
    ERC20 public TOKEN1;
    ERC20 public TOKEN2;
    ERC20 public TOKEN3;

    ERC20 public USDC;
    GeniusPool public POOL;
    GeniusMultiTokenPool public MULTIPOOL;
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E); // USDC on Avalanche

        OWNER = makeAddr("OWNER");
        TRADER = makeAddr("TRADER");
        ORCHESTRATOR = makeAddr("ORCHESTRATOR");

        DEX_ROUTER = new MockDEXRouter();
        BRIDGE = makeAddr("BRIDGE");

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        // Initialize pool with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);

        address[] memory bridges = new address[](1);
        bridges[0] = address(DEX_ROUTER);

        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);

        vm.startPrank(OWNER);
        POOL = new GeniusPool(address(USDC), OWNER);
        MULTIPOOL = new GeniusMultiTokenPool(address(USDC), OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);
        EXECUTOR = new GeniusExecutor(PERMIT2, address(POOL), address(VAULT), OWNER);

        VAULT.initialize(address(POOL));
        POOL.initialize(address(VAULT), address(EXECUTOR));
        MULTIPOOL.initialize(
            address(EXECUTOR),
            address(VAULT),
            supportedTokens,
            bridges,
            routers
        );
        POOL.addOrchestrator(ORCHESTRATOR);
        MULTIPOOL.addOrchestrator(ORCHESTRATOR);

        vm.stopPrank();

        deal(address(USDC), ORCHESTRATOR, 1000 ether);
    }

    function testDOSAttackOnRemoveBridgeLiquidity() public {
        // Add initial liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), 500 ether);
        vm.stopPrank();

        // Simulate a donation to the pool
        deal(address(USDC), address(POOL), 600 ether);

        // Prepare removal of bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        address recipient = makeAddr("recipient");
        uint256 amountToRemove = 500 ether;

        bytes memory transferData = abi.encodeWithSelector(
            USDC.transfer.selector,
            recipient,
            amountToRemove
        );

        bytes[] memory data = new bytes[](1);
        data[0] = transferData;

        // This should not revert
        POOL.removeBridgeLiquidity(amountToRemove, targetChainId, targets, values, data);

        vm.stopPrank();

        // Verify that the funds have been transferred
        assertEq(USDC.balanceOf(recipient), amountToRemove);
    }

    function testDOSAttackOnRemoveBridgeLiquidityMULTIPOOL() public {
    uint256 initialLiquidity = 500 ether;
    uint256 donationAmount = 100 ether;
    uint256 removalAmount = 500 ether;

    // Add initial liquidity
    vm.startPrank(ORCHESTRATOR);
    USDC.transfer(address(MULTIPOOL), initialLiquidity);
    vm.stopPrank();

    // Record initial state
    uint256 initialtotalAssets = MULTIPOOL.totalAssets();
    uint256 initialavailableAssets = MULTIPOOL.availableAssets();

    // Simulate a donation to the pool
    deal(address(USDC), address(MULTIPOOL), initialLiquidity + donationAmount);

    // Prepare removal of bridge liquidity
    vm.startPrank(OWNER);
    // Ensure the USDC token is a valid target for bridge operations
    MULTIPOOL.manageBridge(address(USDC), true);
    vm.stopPrank();

    vm.startPrank(ORCHESTRATOR);
    address[] memory targets = new address[](1);
    targets[0] = address(USDC);

    uint256[] memory values = new uint256[](1);
    values[0] = 0;

    address recipient = makeAddr("recipient");

    bytes memory transferData = abi.encodeWithSelector(
        USDC.transfer.selector,
        recipient,
        removalAmount
    );

    bytes[] memory data = new bytes[](1);
    data[0] = transferData;

    // This should now succeed
    MULTIPOOL.removeBridgeLiquidity(removalAmount, targetChainId, targets, values, data);

    vm.stopPrank();

    // Verify that the funds have been transferred
    assertEq(USDC.balanceOf(recipient), removalAmount, "Recipient should receive the removed amount");

    // Verify the state changes in the pool
    assertEq(MULTIPOOL.totalAssets(), initialtotalAssets + donationAmount - removalAmount, "Total stables should be updated correctly");
    assertEq(MULTIPOOL.availableAssets(), initialavailableAssets + donationAmount - removalAmount, "Available stable balance should be updated correctly");

    // Try to remove more than the available balance (should revert)
    vm.startPrank(ORCHESTRATOR);
    uint256 excessiveAmount = MULTIPOOL.availableAssets() + 1 ether;
    vm.expectRevert();
    MULTIPOOL.removeBridgeLiquidity(excessiveAmount, targetChainId, targets, values, data);
    vm.stopPrank();

    // Verify that the total balance matches the contract's actual balance
    assertEq(USDC.balanceOf(address(MULTIPOOL)), MULTIPOOL.totalAssets(), "Contract balance should match totalAssets");
    }
}