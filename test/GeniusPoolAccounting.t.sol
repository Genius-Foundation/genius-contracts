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

    // ============ Helper Functions ============
    function donateAndAssert(uint256 expectedTotalStaked, uint256 expectedTotal, uint256 expectedAvailable, uint256 expectedMin) internal {
        USDC.transfer(address(POOL), 10 ether);
        assertEq(POOL.totalStakedAssets(), expectedTotalStaked, "Total staked assets mismatch after donation");
        assertEq(POOL.totalAssets(), expectedTotal, "Total assets mismatch after donation");
        assertEq(POOL.availableAssets(), expectedAvailable, "Available assets mismatch after donation");
        assertEq(POOL.minAssetBalance(), expectedMin, "Minimum asset balance mismatch after donation");
    }

    // ============ Setup ============
    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);

        // Set up addresses
        OWNER = address(0x1);
        TRADER = address(0x2);
        ORCHESTRATOR = address(0x3);

        vm.startPrank(OWNER);

        // Deploy contracts
        IStargateRouter stargate = IStargateRouter(0x45A01E4e04F14f7A4a6702c74187c5F6222033cd);
        ERC20 usdc = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        POOL = new GeniusPool(address(usdc), address(stargate), OWNER);
        VAULT = new GeniusVault(address(usdc), OWNER);

        POOL.initialize(address(VAULT));
        VAULT.initialize(address(POOL));
        
        // Add Orchestrator
        POOL.addOrchestrator(ORCHESTRATOR);

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


    /**
     * @dev This function tests the threshold change functionality of the GeniusPoolAccounting contract.
     * It performs the following steps:
     * 1. Starts acting as a TRADER.
     * 2. Approves USDC to be spent by the vault.
     * 3. Deposits 100 USDC into the vault.
     * 4. Checks the staked value and asserts the expected values.
     * 5. Stops acting as a TRADER.
     * 6. Starts acting as an OWNER.
     * 7. Changes the rebalance threshold to 10.
     * 8. Stops acting as an OWNER.
     * 9. Logs the post-change staked values.
     * 10. Checks the staked value again and asserts the expected values.
     */
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

    /**
     * @dev This function is used to test the stake and deposit functionality.
     * It starts by acting as a TRADER, approves the transfer of USDC tokens to the VAULT contract,
     * and then deposits 100 ether into the VAULT contract.
     * It asserts the expected values for total staked assets, total assets, and available assets.
     * After that, it stops acting as a TRADER, approves the transfer of USDC tokens to the POOL contract,
     * and adds liquidity swap for 100 ether.
     * It creates an array of LogEntry structs to store the post-stake and deposit values,
     * and logs these values using the logValues function.
     * Finally, it asserts the expected values for total staked assets, total assets, available assets,
     * and minimum asset balance.
     */
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
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        LogEntry[] memory entries = new LogEntry[](4);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 100 ether);
        entries[1] = LogEntry("Total Assets", POOL.totalAssets(), 200 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 175 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 25 ether);

        logValues("Post Stake and Deposit Values", entries);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 175 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

    }

    /**
     * @dev This function tests the cycle without threshold change in the GeniusPoolAccounting contract.
     * It performs a series of actions such as depositing assets into the vault, adding liquidity to the pool,
     * withdrawing assets from the vault, and checking the balances of various variables and contracts.
     * It also logs the ending balances of key variables for further analysis.
     */
    function testCycleWithoutThresholdChange() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank();
        
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 175 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Start acting as TRADER
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 100 ether, "Available assets mismatch");

        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Assets", POOL.totalAssets(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 100 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testStakeAndWithdraw Ending balances", entries);

    }

    /**
     * @dev This function tests the full cycle of depositing assets through a vault, adding liquidity to a pool,
     * changing the rebalance threshold, and withdrawing assets from the vault.
     * It performs the following steps:
     * 1. Deposits 100 ether into the vault.
     * 2. Checks the total staked assets, total assets, available assets, and minimum asset balance of the pool.
     * 3. Adds liquidity of 100 ether to the pool.
     * 4. Checks the total staked assets, total assets, available assets, and minimum asset balance of the pool.
     * 5. Changes the rebalance threshold of the pool to 10.
     * 6. Checks the total staked assets, total assets, available assets, and minimum asset balance of the pool.
     * 7. Withdraws 100 ether from the vault.
     * 8. Checks the total staked assets, total assets, available assets, and minimum asset balance of the pool.
     * 9. Logs the ending balances of the pool and vault.
     */
    function testFullCycle() public {

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank();
        
        // =================== ADD LIQUIDITY ===================
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 175 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 110 ether, "#1111 Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 100 ether, "Available assets mismatch");

        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Assets", POOL.totalAssets(), 100 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 100 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testStakeAndWithdraw Ending balances", entries);
    }    

        /**
         * @dev This function tests the full cycle of a GeniusPoolAccounting contract with donations.
         * It performs the following steps:
         * 1. Makes an initial donation.
         * 2. Deposits assets into the vault.
         * 3. Adds liquidity to the pool.
         * 4. Changes the rebalance threshold.
         * 5. Withdraws assets from the vault.
         * 6. Logs the final state of the contract.
         */
        function testFullCycleWithDonations() public {

        // Initial donation
        donateAndAssert(0, 0, 0, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Vault Total assets mismatch");
        assertEq(POOL.totalAssets(), 110 ether, "Pool Total assets mismatch");
        assertEq(POOL.availableAssets(), 85 ether, "#1 Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Donate before adding liquidity
        donateAndAssert(100 ether, 110 ether, 85 ether, 25 ether);

        // =================== ADD LIQUIDITY ===================
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 220 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 195 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Donate before changing threshold
        donateAndAssert(100 ether, 220 ether, 195 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 230 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 140 ether, "$$$$ Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");

        // Donate before withdrawing
        donateAndAssert(100 ether, 230 ether, 140 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 140 ether, "Available assets mismatch");

        // Final state logging
        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Assets", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Assets", POOL.totalAssets(), 140 ether);
        entries[2] = LogEntry("Available Assets", POOL.availableAssets(), 140 ether);
        entries[3] = LogEntry("Min Asset Balance", POOL.minAssetBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testFullCycleWithDonations Ending balances", entries);
    }
}

