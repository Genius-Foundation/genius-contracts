// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import { IAllowanceTransfer, IEIP712 } from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GeniusMultiTokenPool} from "../src/GeniusMultiTokenPool.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";

/**
 * @title MultiTokenPoolExecutorInteractions
 * @dev This contract tests the various functions and
 *      interactions between the GeniusMultiTokenPool and the
 *      GeniusExecutor contracts.
 */
contract MultiTokenPoolExecutorInteractions is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    // ============ Mocks ============
    MockSwapTarget public ROUTER;

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    IEIP712 PERMIT2 = IEIP712(0x000000000022D473030F116dDEE9F6B43aC78BA3);

    // ============ Internal Contracts ============
    GeniusVault public VAULT;
    GeniusMultiTokenPool public MULTI_POOL;
    GeniusExecutor public EXECUTOR;
    PermitSignature public SIG_UTILS;

    // ============ Constants ============
    bytes32 public DOMAIN_SEPERATOR;
    uint160 AMOUNT = 10 ether; 

    // ============ Accounts ============
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;
    address public BRIDGE;

    // ============ Private Key ============
    uint256 P_KEY;

    // ============ Supported Tokens ============
    address public constant NATIVE = address(0);
    ERC20 public TOKEN1;
    ERC20 public TOKEN2;
    ERC20 public TOKEN3;

    // ============ Logging ============
    struct LogEntry {
        string name;
        uint256 actual;
        uint256 expected;
    }

    function logValues(string memory title, LogEntry[] memory entries) internal view {
        console.log("--- ", title, " ---");
        for (uint i = 0; i < entries.length; i++) {
            console.log(entries[i].name);
            console.log("  Actual:  ", entries[i].actual);
            console.log("  Expected:", entries[i].expected);
            console.log(""); // Empty line for better readability between entries
        }
        console.log(""); // Empty line at the end
    }

    // ============ Setup ============
    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        DOMAIN_SEPERATOR = PERMIT2.DOMAIN_SEPARATOR();
        SIG_UTILS = new PermitSignature();

        // Set up addresses
        OWNER = address(0x1);
        ORCHESTRATOR = address(0x3);
        BRIDGE = address(0x4);

        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        TRADER = traderAddress;
        P_KEY = traderKey;

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        vm.startPrank(OWNER);

        // Deploy contracts
        MULTI_POOL = new GeniusMultiTokenPool(address(USDC), OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);
        EXECUTOR = new GeniusExecutor(address(PERMIT2), address(MULTI_POOL), OWNER);
        ROUTER = new MockSwapTarget();

        // Initialize pool with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);

        address[] memory routers = new address[](1);
        routers[0] = address(ROUTER);

        address[] memory bridges = new address[](1);
        bridges[0] = BRIDGE;
        
        MULTI_POOL.initialize(address(EXECUTOR), address(VAULT), supportedTokens, bridges, routers);
        VAULT.initialize(address(MULTI_POOL));
        EXECUTOR.initialize(routers);
        
        // Add Orchestrator
        MULTI_POOL.grantRole(MULTI_POOL.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);

        vm.stopPrank();

        // Provide tokens to TRADER and ORCHESTRATOR
        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(this), 1_000 ether);
        deal(address(TOKEN1), TRADER, 1_000 ether);
        deal(address(TOKEN2), TRADER, 1_000 ether);
        deal(address(TOKEN3), TRADER, 1_000 ether);
        deal(address(USDC), address(ROUTER), 100 ether);
        deal(TRADER, 1000 ether); // Provide ETH

        // Approve tokens for MULTI_POOL
        vm.startPrank(TRADER);
        TOKEN1.approve(address(PERMIT2), 1_000 ether);
        TOKEN2.approve(address(PERMIT2), 1_000 ether);

        TOKEN1.approve(address(ROUTER), AMOUNT / 2);
        TOKEN2.approve(address(ROUTER), AMOUNT / 2);
        vm.stopPrank();
    }


    function testTokenSwapAndDeposit() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN1),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );

        // Set up permit details for WAVAX
        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN1),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });



        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory signature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the swap and deposit via GeniusExecutor
        vm.prank(ORCHESTRATOR);
        EXECUTOR.tokenSwapAndDeposit(
            address(ROUTER),
            swapCalldata,
            permitBatch,
            signature,
            TRADER,
            destChainId,
            fillDeadline
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "EXECUTOR should have 0 test tokens");
        assertEq(USDC.balanceOf(address(MULTI_POOL)), 5 ether, "MULTI_POOL should have 5 test tokens");
        assertEq(MULTI_POOL.totalAssets(), 5 ether, "MULTI_POOL should have 5 test tokens available");
        assertEq(MULTI_POOL.availableAssets(), 5 ether, "MULTI_POOL should have 90% of test tokens available");
        assertEq(MULTI_POOL.totalStakedAssets(), 0, "MULTI_POOL should have 0 test tokens staked");

    }

    function testMultiSwapAndDeposit() public {
        // Set up permit details for WAVAX
        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](2);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN1),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });

        permitDetails[1] = IAllowanceTransfer.PermitDetails({
            token: address(TOKEN2),
            amount: AMOUNT,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory signature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN1),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );
        data[1] = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN2),
            AMOUNT,
            address(USDC),
            address(EXECUTOR),
            AMOUNT / 2
        );

        address[] memory targets = new address[](2);
        targets[0] = address(ROUTER);
        targets[1] = address(ROUTER);

        uint256[]memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;

        address[] memory routers = new address[](2);
        routers[0] = address(ROUTER);
        routers[1] = address(ROUTER);

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(ROUTER), AMOUNT);
        TOKEN2.approve(address(ROUTER), AMOUNT);
        vm.stopPrank();

        // Perform the swap and deposit via GeniusExecutor
        EXECUTOR.multiSwapAndDeposit(
            targets,
            data,
            values,
            permitBatch,
            signature,
            TRADER,
            42,
            uint32(block.timestamp + 1000)
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "EXECUTOR should have 0 test tokens");
        assertEq(USDC.balanceOf(address(MULTI_POOL)), 10 ether, "MULTI_POOL should have 10 test tokens");
        assertEq(MULTI_POOL.totalAssets(), 10 ether, "MULTI_POOL should have 10 test tokens available");
        assertEq(MULTI_POOL.availableAssets(), 10 ether, "MULTI_POOL should have 90% of test tokens available");
        assertEq(MULTI_POOL.totalStakedAssets(), 0, "MULTI_POOL should have 0 test tokens staked ");
    }

    function testNativeSwapAndDeposit() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);
        uint256 initialBalance = TRADER.balance;
        uint256 swapAmount = 1 ether;

        // Prepare swap calldata
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            NATIVE,
            swapAmount,
            address(USDC),
            address(EXECUTOR),
            swapAmount / 2 
        );

        // Perform the native swap and deposit via GeniusExecutor
        vm.prank(TRADER);
        EXECUTOR.nativeSwapAndDeposit{value: swapAmount}(
            address(ROUTER),
            swapCalldata,
            swapAmount,
            destChainId,
            fillDeadline
        );

        // Prepare log entries for assertion checks
        LogEntry[] memory entries = new LogEntry[](6);
        entries[0] = LogEntry("EXECUTOR USDC balance", USDC.balanceOf(address(EXECUTOR)), 0);
        entries[1] = LogEntry("MULTI_POOL USDC balance", USDC.balanceOf(address(MULTI_POOL)), swapAmount / 2);
        entries[2] = LogEntry("MULTI_POOL totalAssets", MULTI_POOL.totalAssets(), swapAmount / 2);
        entries[3] = LogEntry("MULTI_POOL availableAssets", MULTI_POOL.availableAssets(), swapAmount / 2);
        entries[4] = LogEntry("MULTI_POOL totalStakedAssets", MULTI_POOL.totalStakedAssets(), 0);
        entries[5] = LogEntry("TRADER ETH balance change", initialBalance - TRADER.balance, swapAmount);

        // Log and assert all values
        logValues("Native Swap and Deposit Test Results", entries);

        for (uint i = 0; i < entries.length; i++) {
            assertEq(entries[i].actual, entries[i].expected, string(abi.encodePacked("Assertion failed for: ", entries[i].name)));
        }
    }

    function testDepositToVault() public {
        uint160 depositAmount = 10 ether;

        // Set up initial balances
        deal(address(USDC), TRADER, 100 ether);
        
        vm.startPrank(TRADER);
        USDC.approve(address(PERMIT2), 100 ether);
        USDC.approve(address(EXECUTOR), 100 ether);
        vm.stopPrank();

        // Set up permit details for USDC
        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: depositAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory signature = SIG_UTILS.getPermitBatchSignature(
            permitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit via GeniusExecutor
        vm.prank(ORCHESTRATOR);
        EXECUTOR.depositToVault(
            permitBatch,
            signature,
            TRADER
        );

        // Prepare log entries for assertion checks
        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("EXECUTOR USDC balance", USDC.balanceOf(address(EXECUTOR)), 0);
        entries[1] = LogEntry("VAULT total assets", VAULT.totalAssets(), depositAmount);
        entries[2] = LogEntry("TRADER vault share balance", VAULT.balanceOf(TRADER), depositAmount);
        entries[3] = LogEntry("TRADER USDC balance", USDC.balanceOf(TRADER), 90 ether);

        // Log and assert all values
        logValues("Deposit To Vault Test Results", entries);

        for (uint i = 0; i < entries.length; i++) {
            assertEq(entries[i].actual, entries[i].expected, string(abi.encodePacked("Assertion failed for: ", entries[i].name)));
        }
    }

    function testWithdrawFromVault() public {
        uint160 depositAmount = 10 ether;
        uint160 withdrawAmount = 1 ether;
        
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(address(PERMIT2), 100 ether);
        USDC.approve(address(EXECUTOR), 100 ether);
        VAULT.approve(address(PERMIT2), 100 ether);
        vm.stopPrank();

        // Set up permit details for deposit
        IAllowanceTransfer.PermitDetails[] memory depositPermitDetails = new IAllowanceTransfer.PermitDetails[](1);
        depositPermitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: depositAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory depositPermitBatch = IAllowanceTransfer.PermitBatch({
            details: depositPermitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory depositSignature = SIG_UTILS.getPermitBatchSignature(
            depositPermitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit
        vm.startPrank(ORCHESTRATOR);
        console.log("msg.sender", msg.sender);
        EXECUTOR.depositToVault(depositPermitBatch, depositSignature, TRADER);
        console.log("deposit successful");
        vm.startPrank(TRADER);
        VAULT.approve(address(EXECUTOR), VAULT.balanceOf(TRADER));
        vm.stopPrank();
        
        // Now set up the withdrawal
        // Set up permit details for withdrawal (vault shares)
        IAllowanceTransfer.PermitDetails[] memory withdrawPermitDetails = new IAllowanceTransfer.PermitDetails[](1);
        withdrawPermitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(VAULT),
            amount: withdrawAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory withdrawPermitBatch = IAllowanceTransfer.PermitBatch({
            details: withdrawPermitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory withdrawSignature = SIG_UTILS.getPermitBatchSignature(
            withdrawPermitBatch,
            P_KEY,
            DOMAIN_SEPERATOR
        );
        vm.stopPrank();



        vm.startPrank(ORCHESTRATOR);
        // Perform the withdrawal via GeniusExecutor
        EXECUTOR.withdrawFromVault(
            withdrawPermitBatch,
            withdrawSignature,
            TRADER
        );
        vm.stopPrank(); 

        // Prepare log entries for assertion checks
        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("EXECUTOR USDC balance", USDC.balanceOf(address(EXECUTOR)), 0);
        entries[1] = LogEntry("MULTI_POOL USDC balance", USDC.balanceOf(address(MULTI_POOL)), 9 ether);
        entries[2] = LogEntry("VAULT total assets", VAULT.totalAssets(), 9 ether);
        entries[3] = LogEntry("TRADER vault share balance", VAULT.balanceOf(TRADER), 9 ether);
        entries[4] = LogEntry("TRADER USDC balance", USDC.balanceOf(TRADER), 991 ether);

        // Log and assert all values
        logValues("Withdraw From Vault Test Results", entries);

        for (uint i = 0; i < entries.length; i++) {
            assertEq(entries[i].actual, entries[i].expected, string(abi.encodePacked("Assertion failed for: ", entries[i].name)));
        }
    }
}