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

contract GeniusPoolTransferVerificationTest is Test {
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

    function testWrongTranferAmountOnRemoveBridgeLiquidity() public {
        // Add initial liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), 500 ether);
        vm.stopPrank();

        // Prepare removal of bridge liquidity
        vm.startPrank(ORCHESTRATOR);
        address[] memory targets = new address[](1);
        targets[0] = address(USDC);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        address recipient = makeAddr("recipient");
        uint256 amountToRemove = 400 ether;
        uint256 wrongTransferAmount = 500 ether;

        bytes memory transferData = abi.encodeWithSelector(
            USDC.transfer.selector,
            recipient,
            wrongTransferAmount
        );

        bytes[] memory data = new bytes[](1);
        data[0] = transferData;

        vm.expectRevert();
        POOL.removeBridgeLiquidity(amountToRemove, targetChainId, targets, values, data);
        vm.stopPrank();
    }

    function testWrongTransferOnRemoveBridgeLiquidityMULTIPOOL() public {
        uint256 initialLiquidity = 500 ether;
        uint256 amountToRemove = 400 ether;
        uint256 wrongTransferAmount = 500 ether;

        // Add initial liquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(MULTIPOOL), initialLiquidity);
        vm.stopPrank();

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
            wrongTransferAmount
        );

        bytes[] memory data = new bytes[](1);
        data[0] = transferData;

        vm.expectRevert();
        MULTIPOOL.removeBridgeLiquidity(amountToRemove, targetChainId, targets, values, data);
        vm.stopPrank();
    }
}