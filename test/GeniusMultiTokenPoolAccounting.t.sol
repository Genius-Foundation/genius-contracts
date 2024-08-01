// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";

import {GeniusMultiTokenPool} from "../src/GeniusMultiTokenPool.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusMultiTokenPoolAccounting is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IEIP712 public permit2 = IEIP712(permit2Address);
    
    // ============ Internal Contracts ============
    GeniusMultiTokenPool public POOL;
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;
    PermitSignature public sigUtils;


    // ============ Variables ============
    uint256 private privateKey;
    uint48 public nonce;

    // ============ Constants ============
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;
    bytes32 public DOMAIN_SEPERATOR;

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

    // ============ Helper Functions ============
    function generatePermitBatchAndSignature(
        address spender,
        address[] memory tokens,
        uint160[] memory amounts
    ) internal returns (IAllowanceTransfer.PermitBatch memory, bytes memory) {
        require(tokens.length == amounts.length, "Tokens and amounts length mismatch");
        require(tokens.length > 0, "At least one token must be provided");

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](tokens.length);
        
        for (uint i = 0; i < tokens.length; i++) {
            permitDetails[i] = IAllowanceTransfer.PermitDetails({
                token: tokens[i],
                amount: amounts[i],
                expiration: 1900000000,
                nonce: nonce
            });
            nonce++;
        }

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: spender,
            sigDeadline: 1900000000
        });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            privateKey,
            DOMAIN_SEPERATOR
        );

        return (permitBatch, signature);
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

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        // Set up addresses
        OWNER = address(0x1);
        ORCHESTRATOR = address(0x3);

        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        TRADER = traderAddress;
        privateKey = traderKey;

        // Deploy mock tokens
        TOKEN1 = new MockERC20("Token1", "TK1", 18);
        TOKEN2 = new MockERC20("Token2", "TK2", 18);
        TOKEN3 = new MockERC20("Token3", "TK3", 18);

        vm.startPrank(OWNER);

        // Deploy contracts
        POOL = new GeniusMultiTokenPool(address(USDC), OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);
        EXECUTOR = new GeniusExecutor(permit2Address, address(POOL), address(VAULT), OWNER);
        DEX_ROUTER = new MockDEXRouter();

        // Initialize pool with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);
        
        POOL.initialize(address(EXECUTOR), address(VAULT), supportedTokens);
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
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);
        vm.stopPrank();

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
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets in VAULT mismatch");
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);
        vm.stopPrank();

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
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(POOL.availStableBalance(), 100 ether, "Available stable balance mismatch");
        assertEq(VAULT.totalAssets(), 0, "Total assets in VAULT mismatch");

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
        deal(address(TOKEN1), address(TRADER), 100 ether);
        deal(address(USDC), address(DEX_ROUTER), 100 ether);

        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.deposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");
        
        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for TOKEN1
        address[] memory tokens = new address[](1);
        tokens[0] = address(TOKEN1);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(100 ether);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TOKEN1),
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        EXECUTOR.tokenSwapAndDeposit(
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER
        );

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 150 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 125 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        vm.stopPrank();

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 150 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 60 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 90 ether, "Minimum stable balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availStableBalance(), 50 ether, "Available stable balance mismatch");

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
        // =================== SETUP ===================
        deal(address(TOKEN1), address(TRADER), 100 ether);
        deal(address(USDC), address(DEX_ROUTER), 100 ether);

        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        // Initial donation
        donateAndAssert(0,  0, 0, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.deposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 110 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 85 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before swap and deposit
        donateAndAssert(100 ether, 110 ether, 85 ether, 25 ether);

        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for TOKEN1
        address[] memory tokens = new address[](1);
        tokens[0] = address(TOKEN1);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(100 ether);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TOKEN1),
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        EXECUTOR.tokenSwapAndDeposit(
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER
        );

        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 170 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 145 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before changing threshold
        donateAndAssert(100 ether, 170 ether, 145 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalStables(), 180 ether, "Total stables mismatch");
        assertEq(POOL.availStableBalance(), 90 ether, "Available stable balance mismatch");
        assertEq(POOL.minStableBalance(), 90 ether, "Minimum stable balance mismatch");

        // Donate before withdrawing
        donateAndAssert(100 ether, 180 ether, 90 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availStableBalance(), 90 ether, "Available stable balance mismatch");

        // Final state logging
        LogEntry[] memory entries = new LogEntry[](5);
        entries[0] = LogEntry("Total Staked Stables", POOL.totalStakedAssets(), 0);
        entries[1] = LogEntry("Total Stables", POOL.totalStables(), 170 ether);
        entries[2] = LogEntry("Available Stable Balance", POOL.availStableBalance(), 170 ether);
        entries[3] = LogEntry("Min Stable Balance", POOL.minStableBalance(), 0);
        entries[4] = LogEntry("Vault Balance", VAULT.totalAssets(), 0);

        logValues("testFullCycleWithDonations Ending balances", entries);

        // Check balances of other supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token != address(USDC)) {
                assertEq(tokenBalances[i].balance, 0, "Non-USDC token balance should be 0");
            } else {
                assertEq(tokenBalances[i].balance, 170 ether, "USDC balance in pool should be 170 ether");
            }
        }
    }

    function testAddLiquiditySwapWithDifferentTokens() public {
        uint256 depositAmount = 100 ether;

        // Check that each token is supported
        assertEq(POOL.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");


        // Deal Tokens to the EXECUTOR to spend
        deal(address(USDC), address(EXECUTOR), depositAmount);
        deal(address(TOKEN1), address(EXECUTOR), depositAmount);
        deal(address(TOKEN2), address(EXECUTOR), depositAmount);
        deal(address(TOKEN3), address(EXECUTOR), depositAmount);

        vm.startPrank(address(EXECUTOR));
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
        vm.deal(address(EXECUTOR), depositAmount); // Ensure TRADER has enough ETH
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
        uint256 depositAmount = 100 ether;

        // Setup
        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        // Check that each token is supported
        assertEq(POOL.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(POOL.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");

        console.log("Native Pool Balance Before Deposit:", address(POOL).balance);

        // Prepare for native ETH deposit
        uint256 initialETHBalance = address(POOL).balance;
        vm.deal(TRADER, depositAmount); // Ensure TRADER has enough ETH
        deal(address(USDC), address(DEX_ROUTER), depositAmount);

        // Create the calldata for the nativeSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapToStables(address)",
            address(USDC)
        );

        vm.prank(TRADER);
        EXECUTOR.nativeSwapAndDeposit{value: depositAmount}(
            address(DEX_ROUTER),
            calldataSwap,
            depositAmount
        );

        assertEq(address(POOL).balance - initialETHBalance, 0, "ETH should not be held in POOL");
        assertEq(USDC.balanceOf(address(POOL)), depositAmount / 2, "USDC balance mismatch after swap");

        // Verify token balances using supportedTokenBalances
        GeniusMultiTokenPool.TokenBalance[] memory tokenBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (tokenBalances[i].token == NATIVE) {
                assertEq(tokenBalances[i].balance, 0, "ETH balance should be 0 in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(USDC)) {
                assertEq(tokenBalances[i].balance, depositAmount, "USDC balance mismatch in supportedTokenBalances");
            }
        }
    }

    function testSwapToStables() public {
        uint256 swapAmount = 100 ether;

        // Setup
        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        // First, add liquidity for a non-USDC token (let's use TOKEN1)
        vm.startPrank(TRADER);
        TOKEN1.approve(address(EXECUTOR), swapAmount);
        TOKEN1.approve(permit2Address, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(POOL), swapAmount);
        deal(address(TOKEN1), address(EXECUTOR), swapAmount);
        POOL.addLiquiditySwap(TRADER, address(TOKEN1), swapAmount);
        deal(address(USDC), address(DEX_ROUTER), swapAmount);
        vm.stopPrank();

        // Log initial state
        LogEntry[] memory initialEntries = new LogEntry[](5);
        initialEntries[0] = LogEntry("Initial TOKEN1 Balance", TOKEN1.balanceOf(address(POOL)), swapAmount);
        initialEntries[1] = LogEntry("Initial USDC Balance", USDC.balanceOf(address(POOL)), 0);
        initialEntries[2] = LogEntry("Initial Total Stables", POOL.totalStables(), 0);
        initialEntries[3] = LogEntry("Initial Available Stable Balance", POOL.availStableBalance(), 0);
        initialEntries[4] = LogEntry("Initial Min Stable Balance", POOL.minStableBalance(), 0);
        logValues("Initial State", initialEntries);

        // Check initial balances
        uint256 initialTotalStables = POOL.totalStables();

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TOKEN1),
            address(USDC)
        );

        // Generate permit details for TOKEN1
        address[] memory tokens = new address[](1);
        tokens[0] = address(TOKEN1);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(swapAmount);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        vm.startPrank(ORCHESTRATOR);
        EXECUTOR.tokenSwapAndDeposit(
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER
        );

        // Log state after swap
        LogEntry[] memory postSwapEntries = new LogEntry[](5);
        postSwapEntries[0] = LogEntry("Post-Swap TOKEN1 Balance", TOKEN1.balanceOf(address(POOL)), 0);
        postSwapEntries[1] = LogEntry("Post-Swap USDC Balance", USDC.balanceOf(address(POOL)), swapAmount);
        postSwapEntries[2] = LogEntry("Post-Swap Total Stables", POOL.totalStables(), swapAmount);
        postSwapEntries[3] = LogEntry("Post-Swap Available Stable Balance", POOL.availStableBalance(), swapAmount);
        postSwapEntries[4] = LogEntry("Post-Swap Min Stable Balance", POOL.minStableBalance(), 0);
        logValues("Post-Swap State", postSwapEntries);

        // Check final balances
        uint256 finalToken1Balance = TOKEN1.balanceOf(address(POOL));
        uint256 finalUSDCBalance = USDC.balanceOf(address(POOL));
        uint256 finalTotalStables = POOL.totalStables();

        // Assertions
        assertEq(finalToken1Balance, 100 ether, "TOKEN1 balance should be 0");
        assertEq(finalUSDCBalance, swapAmount / 2, "USDC balance should increase by swapAmount");
        assertEq(finalTotalStables, initialTotalStables + swapAmount / 2, "Total stables should increase by swapAmount");

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
                assertEq(tokenBalances[i].balance, 100 ether, "TOKEN1 balance should be 100 in supportedTokenBalances");
            } else if (tokenBalances[i].token == address(USDC)) {
                assertEq(tokenBalances[i].balance, swapAmount, "USDC balance mismatch in supportedTokenBalances");
            }
        }

        logValues("Final Token Balances", finalEntries);
    }

}