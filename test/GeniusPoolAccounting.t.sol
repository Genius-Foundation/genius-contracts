// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {IStargateRouter} from "../src/interfaces/IStargateRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

contract GeniusPoolAccounting is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    // IStargateRouter public STARGATE = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);
    
    // ============ Internal Contracts ============
    GeniusPool public POOL;
    GeniusVault public VAULT;

    // ============ Constants ============
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;

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

        // Set up addresses
        OWNER = address(0x1);
        TRADER = address(0x2);
        ORCHESTRATOR = address(0x3);

        console.log("Setup - OWNER:", OWNER);
        console.log("Setup - TRADER:", TRADER);
        console.log("Setup - ORCHESTRATOR:", ORCHESTRATOR);

        vm.startPrank(OWNER);
        console.log("Setup - msg.sender after OWNER prank:", msg.sender);

        // Deploy contracts
        IStargateRouter stargate = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);
        ERC20 usdc = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        POOL = new GeniusPool(address(usdc), address(stargate), OWNER);
        VAULT = new GeniusVault(address(usdc), OWNER);

        POOL.initialize(address(VAULT));
        VAULT.initialize(address(POOL));
        
        // Add Orchestrator
        POOL.addOrchestrator(ORCHESTRATOR);
        console.log("Setup - Orchestrator added:", ORCHESTRATOR);
        console.log("Setup - Is orchestrator:", POOL.orchestrator(ORCHESTRATOR));

        vm.stopPrank();

        // Provide USDC to TRADER and ORCHESTRATOR
        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(this), 1_000 ether);
    }


    /**
     * @dev This function is a test function that checks the staked values in the GeniusPoolAccounting contract.
     * It performs the following steps:
     * 1. Starts a prank with the TRADER address.
     * 2. Approves USDC to be spent by the VAULT contract.
     * 3. Deposits 100 USDC into the VAULT contract.
     * 4. Creates an array of LogEntry structs to store the staked values.
     * 5. Calls the logValues function to log the staked values.
     * 6. Asserts the staked values to ensure they match the expected values.
     */
    function testStakedValues() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.deposit(100 ether, TRADER);

        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", VAULT.totalAssets(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 75 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 25 ether);

        logValues("Staked Values", entries);

        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.totalStakedAssets(), VAULT.totalAssets(), "Total staked assets and total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

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
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.totalStakedAssets(), VAULT.totalAssets(), "Total staked assets and total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank(); // Stop acting as TRADER

        // Change the threshold
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        // Log the staked values
        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", VAULT.totalAssets(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 10 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 90 ether);

        logValues("Post Change Values", entries);


        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.totalStakedAssets(), VAULT.totalAssets(), "Total staked assets and total assets mismatch");
        assertEq(POOL.availableAssets(), 10 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");
    }

    function testStakeAndDeposit() public {

        // Start acting as TRADER
        vm.startPrank(TRADER);
        console.log("msg.sender after starting TRADER prank:", msg.sender);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");

        vm.stopPrank();
        
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, 100 ether);

        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", POOL.totalAssets(), 200 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 150 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 50 ether);

        logValues("Post Stake and Deposit Values", entries);
        console.log("balanceOf pool", USDC.balanceOf(address(POOL)));

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 200 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 150 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 50 ether, "Minimum asset balance mismatch");

    }
}