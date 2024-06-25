// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {GeniusMultiTokenPool} from "../src/GeniusMultiTokenPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";

contract GeniusMultiTokenPoolAccounting is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    
    // ============ Internal Contracts ============
    GeniusMultiTokenPool public POOL;
    GeniusVault public VAULT;

    // ============ Constants ============
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;

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

    // ============ Helper Functions ============
    function donateAndAssert(uint256 expectedTotalStaked, uint256 expectedTotal, uint256 expectedAvailable, uint256 expectedMin) internal {
        USDC.transfer(address(POOL), 10 ether);
        assertEq(POOL.totalStakedAssets(), expectedTotalStaked, "Total staked assets mismatch after donation");
        assertEq(POOL.totalStables(), expectedTotal, "Total assets mismatch after donation");
        assertEq(POOL.availStableBalance(), expectedAvailable, "Available assets mismatch after donation");
        assertEq(POOL.minStableBalance(), expectedMin, "Minimum asset balance mismatch after donation");
    }

    function _getTokenSymbol(address token) internal view returns (string memory) {
        if (token == address(TOKEN1)) return "TOKEN1";
        if (token == address(USDC)) return "USDC";
        if (token == address(TOKEN2)) return "TOKEN2";
        if (token == address(TOKEN3)) return "TOKEN3";
        return "ETH";
    }

    // ============ Setup ============
    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);

        // Set up addresses
        OWNER = address(0x1);
        TRADER = address(0x2);
        ORCHESTRATOR = address(0x3);

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        vm.startPrank(OWNER);

        // Deploy contracts
        POOL = new GeniusMultiTokenPool(address(USDC), OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);

        // Initialize pool with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);
        
        POOL.initialize(address(VAULT), supportedTokens);
        VAULT.initialize(address(POOL));
        
        // Add Orchestrator
        POOL.addOrchestrator(ORCHESTRATOR);

        vm.stopPrank();

        // Provide tokens to TRADER and ORCHESTRATOR
        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(this), 1_000 ether);
        deal(address(TOKEN1), TRADER, 1_000 ether);
        deal(address(TOKEN2), TRADER, 1_000 ether);
        deal(address(TOKEN3), TRADER, 1_000 ether);
        deal(TRADER, 1000 ether); // Provide ETH
    }

    function testStakedValues() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.deposit(100 ether, TRADER);

        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", POOL.totalStables(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availStableBalance(), 75 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minStableBalance(), 25 ether);

        logValues("Staked Values", entries);

        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch after deposit");
        assertEq(POOL.totalStables(), 100 ether, "Total assets mismatch after deposit");
        assertEq(POOL.availStableBalance(), 75 ether, "Available assets mismatch after deposit");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum asset balance mismatch after deposit");

        vm.stopPrank(); // Stop acting as TRADER
    }

    function testThresholdChange() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.deposit(100 ether, TRADER);

        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total assets mismatch");
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets and total assets mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank(); // Stop acting as TRADER

        // Change the threshold
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        // Log the staked values
        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", POOL.totalStables(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availStableBalance(), 10 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minStableBalance(), 90 ether);

        logValues("Post Change Values", entries);


        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total assets mismatch");
        assertEq(POOL.availStableBalance(), 10 ether, "Available assets mismatch");
        assertEq(POOL.minStableBalance(), 90 ether, "Minimum asset balance mismatch");
    }

    function testStakeAndDeposit() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        console.log("msg.sender after starting TRADER prank:", msg.sender);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        vm.stopPrank();
        
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Stables", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Stables", POOL.totalStables(), 200 ether);
        entries[2] = LogEntry("Available Stable Balance", POOL.availStableBalance(), 175 ether);
        entries[3] = LogEntry("Min Stable Balance", POOL.minStableBalance(), 25 ether);

        logValues("Post Stake and Deposit Values", entries);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 175 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // Test balances of other supported tokens
        (GeniusMultiTokenPool.TokenBalance[] memory tokenBalances) = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token != address(USDC)) {
                assertEq(tokenBalances[i].balance, 0, "Non-USDC token balance should be 0");
            }
        }
    }

    function testCycleWithoutThresholdChange() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets in VAULT mismatch");
        vm.stopPrank();
        
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 175 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets in VAULT mismatch");

        console.log("Total Staked Stables:", POOL.totalStakedAssets());
        console.log("Total Stables:", POOL.totalStables());
        console.log("Available Stable Balance:", POOL.availStableBalance());
        console.log("Min Stable Balance:", POOL.minStableBalance());
        console.log("USDC Balance of POOL:",  VAULT.totalAssets());
        console.log("USDC Balance of VAULT:", USDC.balanceOf(address(VAULT)));
        console.log("USDC Balance of TRADER:", USDC.balanceOf(TRADER));

        // Start acting as TRADER again
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(POOL.availStableBalance(), 100 ether, "Available stable balance mismatch");
        assertEq(VAULT.totalAssets(), 0, "Total assets in VAULT mismatch");

        vm.stopPrank();

        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Stables", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Stables", POOL.totalStables(), 100 ether);
        entries[2] = LogEntry("Available Stable Balance", POOL.availStableBalance(), 100 ether);
        entries[3] = LogEntry("Min Stable Balance", POOL.minStableBalance(), 0);

        logValues("testCycleWithoutThresholdChange Ending balances", entries);

        // Check balances of other supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token != address(USDC)) {
                assertEq(tokenBalances[i].balance, 0, "Non-USDC token balance should be 0");
            }
        }
    }

    function testFullCycle() public {
        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        vm.stopPrank();
        
        // =================== ADD LIQUIDITY ===================
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 175 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 110 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 90 ether, "Minimum stable balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availStableBalance(), 100 ether, "Available stable balance mismatch");

        vm.stopPrank();

        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Stables", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Stables", POOL.totalStables(), 100 ether);
        entries[2] = LogEntry("Available Stable Balance", POOL.availStableBalance(), 100 ether);
        entries[3] = LogEntry("Min Stable Balance", POOL.minStableBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testFullCycle Ending balances", entries);

        // Check balances of other supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token != address(USDC)) {
                assertEq(tokenBalances[i].balance, 0, "Non-USDC token balance should be 0");
            } else {
                assertEq(tokenBalances[i].balance, 100 ether, "USDC balance in pool should be 100 ether");
            }
        }
    }

    function testFullCycleWithDonations() public {
        // Initial donation
        donateAndAssert(0, 0, 0, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Vault Total assets mismatch");
        assertEq(POOL.totalStables(), 110 ether, "Pool Total stables mismatch");
        assertEq(POOL.availStableBalance(), 85 ether, "#1 Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before adding liquidity
        donateAndAssert(100 ether, 110 ether, 85 ether, 25 ether);

        // =================== ADD LIQUIDITY ===================
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 220 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 195 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before changing threshold
        donateAndAssert(100 ether, 220 ether, 195 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 230 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 140 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 90 ether, "Minimum stable balance mismatch");

        // Donate before withdrawing
        donateAndAssert(100 ether, 230 ether, 140 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availStableBalance(), 140 ether, "Available stable balance mismatch");

        // Final state logging
        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Stables", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Stables", POOL.totalStables(), 140 ether);
        entries[2] = LogEntry("Available Stable Balance", POOL.availStableBalance(), 140 ether);
        entries[3] = LogEntry("Min Stable Balance", POOL.minStableBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testFullCycleWithDonations Ending balances", entries);

        // Check balances of other supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token != address(USDC)) {
                assertEq(tokenBalances[i].balance, 0, "Non-USDC token balance should be 0");
            } else {
                assertEq(tokenBalances[i].balance, 140 ether, "USDC balance in pool should be 140 ether");
            }
        }
    }

    function testAddLiquiditySwapWithDifferentTokens() public {
        vm.startPrank(TRADER);
        uint256 depositAmount = 100 ether;

        // Check that each token is supported
        assertEq(POOL.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");

        // Test USDC deposit
        USDC.approve(address(POOL), depositAmount);
        POOL.addLiquiditySwap(TRADER, address(USDC), depositAmount);
        assertEq(POOL.totalStables(), depositAmount, "USDC deposit failed");
        assertEq(USDC.balanceOf(address(POOL)), depositAmount, "USDC balance mismatch");

        // Test TOKEN1 deposit
        TOKEN1.approve(address(POOL), depositAmount);
        POOL.addLiquiditySwap(TRADER, address(TOKEN1), depositAmount);
        assertEq(TOKEN1.balanceOf(address(POOL)), depositAmount, "TOKEN1 balance mismatch");

        // Test TOKEN2 deposit
        TOKEN2.approve(address(POOL), depositAmount);
        POOL.addLiquiditySwap(TRADER, address(TOKEN2), depositAmount);
        assertEq(TOKEN2.balanceOf(address(POOL)), depositAmount, "TOKEN2 balance mismatch");

        // Test TOKEN3 deposit
        TOKEN3.approve(address(POOL), depositAmount);
        POOL.addLiquiditySwap(TRADER, address(TOKEN3), depositAmount);
        assertEq(TOKEN3.balanceOf(address(POOL)), depositAmount, "TOKEN3 balance mismatch");

        // Test native ETH deposit
        uint256 initialETHBalance = address(POOL).balance;
        vm.deal(TRADER, depositAmount); // Ensure TRADER has enough ETH
        POOL.addLiquiditySwap{value: depositAmount}(TRADER, NATIVE, depositAmount);
        assertEq(address(POOL).balance - initialETHBalance, depositAmount, "ETH deposit failed");

        // Verify token balances using supportedTokenBalances
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token == address(USDC)) {
                assertEq(tokenBalances[i].balance, depositAmount, "USDC balance mismatch in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(TOKEN1)) {
                assertEq(tokenBalances[i].balance, depositAmount, "TOKEN1 balance mismatch in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(TOKEN2)) {
                assertEq(tokenBalances[i].balance, depositAmount, "TOKEN2 balance mismatch in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(TOKEN3)) {
                assertEq(tokenBalances[i].balance, depositAmount, "TOKEN3 balance mismatch in supportedTokenBalances");
            } else if (tokenBalances[i].token == NATIVE) {
                assertEq(tokenBalances[i].balance, depositAmount, "ETH balance mismatch in supportedTokenBalances");
            }
        }

        vm.stopPrank();
    }

    function testNativeLiquiditySwap() public {
        vm.startPrank(TRADER);
        uint256 depositAmount = 100 ether;

        // Check that each token is supported
        assertEq(POOL.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");

        console.log("Native Pool Balance Before Deposit:", address(POOL).balance);

        // Test native ETH deposit
        uint256 initialETHBalance = address(POOL).balance;
        vm.deal(TRADER, depositAmount); // Ensure TRADER has enough ETH
        POOL.addLiquiditySwap{value: depositAmount}(TRADER, NATIVE, depositAmount);
        assertEq(address(POOL).balance - initialETHBalance, depositAmount, "ETH deposit failed");

        console.log("Native Pool Balance After Deposit:", address(POOL).balance);

        // Verify token balances using supportedTokenBalances
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token == NATIVE) {
                assertEq(tokenBalances[i].balance, depositAmount, "ETH balance mismatch in supportedTokenBalances");
            }
        }

        vm.stopPrank();
    }

    function testSwapToStables() public {
        uint256 swapAmount = 100 ether;

        // First, add liquidity for a non-USDC token (let's use TOKEN1)
        vm.startPrank(TRADER);
        TOKEN1.approve(address(POOL), swapAmount);
        POOL.addLiquiditySwap(TRADER, address(TOKEN1), swapAmount);
        deal(address(USDC), TRADER, swapAmount);
        vm.stopPrank();

        // Log initial state
        LogEntry[] memory initialEntries = new LogEntry[](5);
        initialEntries[0] = LogEntry("Initial TOKEN1 Balance", TOKEN1.balanceOf(address(POOL)), 0);
        initialEntries[1] = LogEntry("Initial USDC Balance", USDC.balanceOf(address(POOL)), 0);
        initialEntries[2] = LogEntry("Initial Total Stables", POOL.totalStables(), 0);
        initialEntries[3] = LogEntry("Initial Available Stable Balance", POOL.availStableBalance(), 0);
        initialEntries[4] = LogEntry("Initial Min Stable Balance", POOL.minStableBalance(), 0);
        logValues("Initial State", initialEntries);

        // Check initial balances
        uint256 initialToken1Balance = TOKEN1.balanceOf(address(POOL));
        uint256 initialUSDCBalance = USDC.balanceOf(address(POOL));
        uint256 initialTotalStables = POOL.totalStables();

        // Create a mock swap target contract
        MockSwapTarget mockSwapTarget = new MockSwapTarget();

        // Transfer USDC into the mockSwapTarget to simulate the swap result
        deal(address(USDC), address(mockSwapTarget), 1_000 ether);

        // Log state after setting up mock swap target
        LogEntry[] memory setupEntries = new LogEntry[](1);
        setupEntries[0] = LogEntry("MockSwapTarget USDC Balance", USDC.balanceOf(address(mockSwapTarget)), 0);
        logValues("After Mock Setup", setupEntries);

        // Prepare calldata for the mock swap
        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(TOKEN1),
            swapAmount,
            address(USDC),
            address(POOL),
            swapAmount
        );

        vm.startPrank(TRADER);
        TOKEN1.approve(address(mockSwapTarget), swapAmount);
        USDC.approve(address(mockSwapTarget), swapAmount);
        vm.stopPrank();

        // Log state before swap
        LogEntry[] memory preSwapEntries = new LogEntry[](3);
        preSwapEntries[0] = LogEntry("Pre-Swap TOKEN1 Balance", TOKEN1.balanceOf(address(POOL)), 100 ether);
        preSwapEntries[1] = LogEntry("Pre-Swap USDC Balance", USDC.balanceOf(address(POOL)), 0);
        preSwapEntries[2] = LogEntry("Pre-Swap Total Stables", POOL.totalStables(), 0);
        logValues("Pre-Swap State", preSwapEntries);

        vm.prank(ORCHESTRATOR, ORCHESTRATOR);
        POOL.swapToStables(address(TOKEN1), swapAmount, address(mockSwapTarget), swapCalldata);

        // Log state after swap
        LogEntry[] memory postSwapEntries = new LogEntry[](5);
        postSwapEntries[0] = LogEntry("Post-Swap TOKEN1 Balance", TOKEN1.balanceOf(address(POOL)), 0);
        postSwapEntries[1] = LogEntry("Post-Swap USDC Balance", USDC.balanceOf(address(POOL)), 100 ether);
        postSwapEntries[2] = LogEntry("Post-Swap Total Stables", POOL.totalStables(), 100 ether);
        postSwapEntries[3] = LogEntry("Post-Swap Available Stable Balance", POOL.availStableBalance(), 100 ether);
        postSwapEntries[4] = LogEntry("Post-Swap Min Stable Balance", POOL.minStableBalance(), 0);
        logValues("Post-Swap State", postSwapEntries);

        // Check final balances
        uint256 finalToken1Balance = TOKEN1.balanceOf(address(POOL));
        uint256 finalUSDCBalance = USDC.balanceOf(address(POOL));
        uint256 finalTotalStables = POOL.totalStables();

        // Assertions
        assertEq(finalToken1Balance, initialToken1Balance - swapAmount, "TOKEN1 balance should decrease");
        assertEq(finalUSDCBalance, initialUSDCBalance + swapAmount, "USDC balance should increase");
        assertEq(finalTotalStables, initialTotalStables + swapAmount, "Total stables should increase");

        // Verify token balances using supportedTokenBalances
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        LogEntry[] memory finalEntries = new LogEntry[](tokenBalances.length);
        for (uint i = 0; i < tokenBalances.length; i++) {
            finalEntries[i] = LogEntry(
                string(abi.encodePacked("Final Balance of ", _getTokenSymbol(tokenBalances[i].token))),
                tokenBalances[i].balance,
                0
            );
            if (tokenBalances[i].token == address(TOKEN1)) {
                assertEq(tokenBalances[i].balance, finalToken1Balance, "TOKEN1 balance mismatch in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(USDC)) {
                assertEq(tokenBalances[i].balance, finalUSDCBalance, "USDC balance mismatch in supportedTokenBalances");
            }
        }

        logValues("Final Token Balances", finalEntries);
    }

}