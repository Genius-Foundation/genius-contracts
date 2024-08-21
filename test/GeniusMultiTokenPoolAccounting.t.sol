// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";

import {GeniusMultiTokenPool} from "../src/GeniusMultiTokenPool.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {Orchestrable, Ownable} from "../src/access/Orchestrable.sol";

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
    address public BRIDGE;
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

    function donateAndAssert(uint256 expectedTotalStaked, uint256 expectedTotal, uint256 expectedAvailable, uint256 expectedMin) internal {
        USDC.transfer(address(POOL), 10 ether);
        assertEq(POOL.totalStakedAssets(), expectedTotalStaked, "Total staked assets mismatch after donation");
        assertEq(POOL.totalAssets(), expectedTotal, "Total assets mismatch after donation");
        assertEq(POOL.availableAssets(), expectedAvailable, "Available assets mismatch after donation");
        assertEq(POOL.minAssetBalance(), expectedMin, "Minimum asset balance mismatch after donation");
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
        BRIDGE = makeAddr("bridge");

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
        
        VAULT.initialize(address(POOL));
        POOL.initialize(
            address(EXECUTOR),
            address(VAULT),
            supportedTokens,
            bridges,
            routers
        );
        
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

        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch after deposit");
        assertEq(POOL.totalAssets(), 100 ether, "Total assets mismatch after deposit");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch after deposit");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch after deposit");

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
        assertEq(POOL.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets and total assets mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank(); // Stop acting as TRADER

        // Change the threshold
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();


        // Check the staked value
        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(POOL.totalAssets(), 100 ether, "Total assets mismatch");
        assertEq(POOL.availableAssets(), 10 ether, "Available assets mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");
    }

    function testStakeAndDeposit() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.deposit(100 ether, TRADER);

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        vm.stopPrank();
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 175 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

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
        assertEq(POOL.totalAssets(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets in VAULT mismatch");
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(USDC), 100 ether);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 200 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 175 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalAssets(), 100 ether, "Total assets in VAULT mismatch");

        // Start acting as TRADER again
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(POOL.availableAssets(), 100 ether, "Available stable balance mismatch");
        assertEq(VAULT.totalAssets(), 0, "Total assets in VAULT mismatch");

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
        assertEq(POOL.totalAssets(), 100 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 75 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        
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
        assertEq(POOL.totalAssets(), 150 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 125 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

        vm.stopPrank();

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 150 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 60 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum stable balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availableAssets(), 50 ether, "Available stable balance mismatch");

        vm.stopPrank();

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
        donateAndAssert(0, 10 ether, 10 ether, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.deposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 110 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 85 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before swap and deposit
        donateAndAssert(100 ether, 120 ether, 95 ether, 25 ether);

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
        assertEq(POOL.totalAssets(), 170 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 145 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

        // Donate before changing threshold
        donateAndAssert(100 ether, 180 ether, 155 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        POOL.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(POOL.totalAssets(), 180 ether, "Total stables mismatch");
        assertEq(POOL.availableAssets(), 90 ether, "Available stable balance mismatch");
        assertEq(POOL.minAssetBalance(), 90 ether, "Minimum stable balance mismatch");

        // Donate before withdrawing
        donateAndAssert(100 ether, 190 ether, 100 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.withdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(POOL.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalAssets(), 0, "Vault total assets mismatch");
        assertEq(POOL.availableAssets(), 90 ether, "Available stable balance mismatch");

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
        assertEq(POOL.totalAssets(), depositAmount, "USDC deposit failed");
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

        // Check initial balances
        uint256 initialTotalStables = POOL.totalAssets();

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

        // Assertions
        assertEq(TOKEN1.balanceOf(address(POOL)), 100 ether, "TOKEN1 balance should be 0");
        assertEq(USDC.balanceOf(address(POOL)), swapAmount / 2, "USDC balance should increase by swapAmount");
        assertEq(POOL.totalAssets(), initialTotalStables + swapAmount / 2, "Total stables should increase by swapAmount");

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
    }

    function testSwapToStablesErrors() public {
        uint256 swapAmount = 100 ether;

        // Setup
        vm.startPrank(OWNER);
        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        EXECUTOR.initialize(routers);
        EXECUTOR.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        // Add liquidity for a non-USDC token (let's use TOKEN1)
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

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TOKEN1),
            address(USDC)
        );

        vm.startPrank(OWNER);
        // Test Paused error
        POOL.emergencyLock();
        vm.stopPrank();

        assertEq(POOL.paused(), true, "Contract should be paused");

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        POOL.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataSwap);
        vm.stopPrank();

        vm.startPrank(OWNER);
        POOL.emergencyUnlock();

        // Test NotInitialized error
        GeniusMultiTokenPool uninitializedPool = new GeniusMultiTokenPool(address(USDC), OWNER);
        // Add the orchestrator as an orchestrator
        uninitializedPool.addOrchestrator(ORCHESTRATOR);
        vm.stopPrank();

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(GeniusErrors.NotInitialized.selector);
        uninitializedPool.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataSwap);

        // Test InvalidAmount error
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        POOL.swapToStables(address(TOKEN1), 0, address(DEX_ROUTER), calldataSwap);

        // Test InvalidToken error
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(0xdeadbeef)));
        POOL.swapToStables(address(0xdeadbeef), swapAmount, address(DEX_ROUTER), calldataSwap);

        // Test InsufficientBalance error
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InsufficientBalance.selector, address(TOKEN1), swapAmount * 2, swapAmount));
        POOL.swapToStables(address(TOKEN1), swapAmount * 2, address(DEX_ROUTER), calldataSwap);

        bytes memory calldataNoSwap = abi.encodeWithSignature(
                "swapWithNoEffect(address,address)",
                address(TOKEN1),
                address(USDC)
            );

        vm.expectRevert(GeniusErrors.InvalidDelta.selector);
        POOL.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataNoSwap);

        // Test ExternalCallFailed error
        bytes memory calldataSwapFail = abi.encodeWithSignature(
            "nonExistentFunction()"
        );
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.ExternalCallFailed.selector, address(DEX_ROUTER), 0));
        POOL.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataSwapFail);
         
        vm.stopPrank();
    }


    function testAddBridgeLiquidity() public {
        uint256 bridgeAmount = 100 ether;
        uint16 testChainId = 1; // Example chain ID

        // Setup: Fund the ORCHESTRATOR with USDC
        deal(address(USDC), ORCHESTRATOR, bridgeAmount);

        // Record initial balances
        uint256 initialTotalStables = POOL.totalAssets();
        uint256 initialavailableAssets = POOL.availableAssets();
        uint256 initialminAssetBalance = POOL.minAssetBalance();
        
        GeniusMultiTokenPool.TokenBalance[] memory initialBalances = POOL.supportedTokenBalances();

        // Perform addBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), bridgeAmount);
        vm.stopPrank();

        // Assert total stables increased correctly
        assertEq(POOL.totalAssets(), initialTotalStables + bridgeAmount, "Total stables should increase by bridge amount");

        // Assert available stable balance increased
        assertEq(POOL.availableAssets(), initialavailableAssets + bridgeAmount, "Available stable balance should increase by bridge amount");

        // Assert min stable balance remains unchanged
        assertEq(POOL.minAssetBalance(), initialminAssetBalance, "Minimum stable balance should remain unchanged");

        // Assert balances for all supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory finalBalances = POOL.supportedTokenBalances();
        assertEq(finalBalances.length, initialBalances.length, "Number of supported tokens should remain the same");

        for (uint i = 0; i < finalBalances.length; i++) {
            if (finalBalances[i].token == address(USDC)) {
                assertEq(finalBalances[i].balance, initialBalances[i].balance + bridgeAmount, "USDC balance should increase by bridge amount");
            } else {
                assertEq(finalBalances[i].balance, initialBalances[i].balance, "Non-USDC token balances should remain unchanged");
            }
        }

        // Verify USDC transfer
        assertEq(USDC.balanceOf(address(POOL)), initialBalances[0].balance + bridgeAmount, "USDC balance in pool should increase by bridge amount");
    }

    function testRemoveBridgeLiquidity() public {
        uint256 bridgeAmount = 100 ether;
        uint16 testChainId = 1; // Example chain ID

        // Setup: Add liquidity to the pool
        deal(address(USDC), address(DEX_ROUTER), bridgeAmount);
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), bridgeAmount);

        // Prepare for removal
        uint256 initialTotalStables = POOL.totalAssets();
        uint256 initialPoolUSDCBalance = USDC.balanceOf(address(POOL));

        // Prepare mock data for external calls
        address[] memory targets = new address[](1);
        targets[0] = address(DEX_ROUTER);
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        bytes[] memory data = new bytes[](1);
        // call swapERC20ToStables
        data[0] = abi.encodeWithSignature(
            "bridge(address,uint256)",
            address(USDC),
            bridgeAmount
        );

        vm.startPrank(address(POOL));
        USDC.approve(address(DEX_ROUTER), bridgeAmount);
        vm.stopPrank();

        // Perform removeBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        POOL.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);
        vm.stopPrank();

        // Assert state changes
        assertEq(POOL.totalAssets(), initialTotalStables - bridgeAmount, "Total stables should decrease");
        assertEq(USDC.balanceOf(address(POOL)), initialPoolUSDCBalance - bridgeAmount, "POOL USDC balance should decrease");

        // Test with zero amount (should revert)
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        POOL.removeBridgeLiquidity(0, testChainId, targets, values, data);

        // Test when pool is paused
        vm.prank(OWNER);
        POOL.emergencyLock();
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        POOL.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);
        vm.prank(OWNER);
        POOL.emergencyUnlock();

        // Test when called by non-orchestrator
        vm.prank(TRADER);
        vm.expectRevert();
        POOL.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);

        // Test when trying to remove more than available balance
        vm.prank(ORCHESTRATOR);
        vm.expectRevert();
        POOL.removeBridgeLiquidity(initialTotalStables + 1 ether, testChainId, targets, values, data);
    }


    function testAddBridgeLiquidityWithDonations() public {
        uint256 bridgeAmount = 100 ether;
        uint16 testChainId = 1; // Example chain ID

        // Setup: Fund the ORCHESTRATOR with USDC
        deal(address(USDC), ORCHESTRATOR, bridgeAmount);

        // Record initial balances
        uint256 initialTotalStables = POOL.totalAssets();
        uint256 initialavailableAssets = POOL.availableAssets();
        uint256 initialminAssetBalance = POOL.minAssetBalance();
        
        GeniusMultiTokenPool.TokenBalance[] memory initialBalances = POOL.supportedTokenBalances();

        // Perform addBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(POOL), bridgeAmount);
        vm.stopPrank();

        // Assert total stables increased correctly
        assertEq(
            POOL.totalAssets(),
            initialTotalStables + bridgeAmount,
            "Total stables should increase by bridge amount"
        );

        // Assert available stable balance increased
        assertEq(
            POOL.availableAssets(),
            initialavailableAssets + bridgeAmount,
            "Available stable balance should increase by bridge amount"
        );

        // Assert min stable balance remains unchanged
        assertEq(
            POOL.minAssetBalance(),
            initialminAssetBalance,
            "Minimum stable balance should remain unchanged"
        );

        // Assert balances for all supported tokens
        GeniusMultiTokenPool.TokenBalance[] memory finalBalances = POOL.supportedTokenBalances();
        assertEq(
            finalBalances.length,
            initialBalances.length,
            "Number of supported tokens should remain the same"
        );

        for (uint i = 0; i < finalBalances.length; i++) {
            if (finalBalances[i].token == address(USDC)) {

                assertEq(
                    finalBalances[i].balance,
                    initialBalances[i].balance + bridgeAmount,
                    "USDC balance should increase by bridge amount"
                );

            } else {

                assertEq(
                    finalBalances[i].balance,
                    initialBalances[i].balance,
                    "Non-USDC token balances should remain unchanged"
                );

            }
        }

        // Verify USDC transfer
        assertEq(
            USDC.balanceOf(address(POOL)),
            initialBalances[0].balance + bridgeAmount,
            "USDC balance in pool should increase by bridge amount"
        );

        // Additional Step: Simulate a donation to the pool


        // Manually reconcile the balances due to donation
        donateAndAssert(
            POOL.totalStakedAssets(), 
            POOL.totalAssets() + 10 ether, // Account for the 10 ether donation
            POOL.availableAssets() +  10 ether, // Account for the 10 ether donation
            POOL.minAssetBalance()
        );

        // Assert the balances have been updated correctly to include the donation
        GeniusMultiTokenPool.TokenBalance[] memory postDonationBalances = POOL.supportedTokenBalances();
        for (uint i = 0; i < postDonationBalances.length; i++) {
            if (postDonationBalances[i].token == address(USDC)) {
                
                assertEq(
                    postDonationBalances[i].balance,
                    finalBalances[i].balance + 10 ether,
                    "USDC balance should include donation amount"
                );

            } else {

                assertEq(
                    postDonationBalances[i].balance,
                    finalBalances[i].balance,
                    "Non-USDC token balances should remain unchanged"
                );

            }
        }

        // Verify USDC balance in the pool contract
        assertEq(
            USDC.balanceOf(address(POOL)),
            initialBalances[0].balance + bridgeAmount + 10 ether,
            "USDC balance in pool should include donation amount"
        );
    }


    /**
     * @dev Tests the manageToken function
     */
    function testManageToken() public {
        // Setup: Deploy a new test token
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);

        // Initial checks
        assertFalse(POOL.isTokenSupported(address(newToken)), "New token should not be supported initially");
        uint256 initialSupportedTokensCount = POOL.supportedTokensCount();

        // Test adding a new token
        vm.prank(OWNER);
        POOL.manageToken(address(newToken), true);

        assertTrue(POOL.isTokenSupported(address(newToken)), "New token should now be supported");
        assertEq(POOL.supportedTokensCount(), initialSupportedTokensCount + 1, "Supported tokens count should increase");

        // Test adding a duplicate token (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DuplicateToken.selector, address(newToken)));
        POOL.manageToken(address(newToken), true);

        // Test removing the token
        vm.prank(OWNER);
        POOL.manageToken(address(newToken), false);

        assertFalse(POOL.isTokenSupported(address(newToken)), "New token should no longer be supported");
        assertEq(POOL.supportedTokensCount(), initialSupportedTokensCount, "Supported tokens count should be back to initial value");

        // Test removing a token that's not supported (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(newToken)));
        POOL.manageToken(address(newToken), false);

        // Test removing a token with non-zero balance (should revert)
        // First, add the token back and simulate some balance
        vm.prank(OWNER);
        POOL.manageToken(address(newToken), true);

        deal(address(newToken), address(EXECUTOR), 100 ether);
        vm.startPrank(address(EXECUTOR));
        newToken.approve(address(POOL), 100 ether);
        POOL.addLiquiditySwap(TRADER, address(newToken), 100 ether);

        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.RemainingBalance.selector, 100 ether));
        POOL.manageToken(address(newToken), false);

        // Test managing STABLECOIN (should revert)
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(USDC)));
        POOL.manageToken(address(USDC), false);

        // Test calling from non-owner address (should revert)
        vm.startPrank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, TRADER));
        POOL.manageToken(address(newToken), false);
    }

    function testManageBridge() public {
        address newBridge = makeAddr("newBridge");

        // Initial check
        assertEq(POOL.supportedBridges(newBridge), 0, "Bridge should not be supported initially");

        // Test authorizing a new bridge
        vm.prank(OWNER);
        POOL.manageBridge(newBridge, true);
        assertEq(POOL.supportedBridges(newBridge), 1, "Bridge should be supported after authorization");

        // Test authorizing an already authorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, newBridge));
        POOL.manageBridge(newBridge, true);

        // Test unauthorizing the bridge
        vm.prank(OWNER);
        POOL.manageBridge(newBridge, false);
        assertEq(POOL.supportedBridges(newBridge), 0, "Bridge should not be supported after unauthorized");

        // Test unauthorizing an already unauthorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, newBridge));
        POOL.manageBridge(newBridge, false);

        // Test calling from non-owner address (should revert)
        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, TRADER));
        POOL.manageBridge(newBridge, true);

        // Test with address(0) as bridge address
        vm.prank(OWNER);
        POOL.manageBridge(address(0), true);
        assertEq(POOL.supportedBridges(address(0)), 1, "Zero address should be allowed as a bridge");

        vm.prank(OWNER);
        POOL.manageBridge(address(0), false);
        assertEq(POOL.supportedBridges(address(0)), 0, "Zero address should be removable as a bridge");

        // Test multiple authorizations and unauthorizations
        address[] memory bridges = new address[](3);
        bridges[0] = makeAddr("bridge1");
        bridges[1] = makeAddr("bridge2");
        bridges[2] = makeAddr("bridge3");

        vm.startPrank(OWNER);
        for (uint i = 0; i < bridges.length; i++) {
            POOL.manageBridge(bridges[i], true);
            assertEq(POOL.supportedBridges(bridges[i]), 1, "Bridge should be supported after authorization");
        }

        for (uint i = 0; i < bridges.length; i++) {
            POOL.manageBridge(bridges[i], false);
            assertEq(POOL.supportedBridges(bridges[i]), 0, "Bridge should not be supported after unauthorized");
        }
        vm.stopPrank();
    }

    function testManageRouter() public {
        MockDEXRouter UNAUTHORIZED_ROUTER = new MockDEXRouter();
        address unRouter = address(UNAUTHORIZED_ROUTER);

        // Initial check
        assertEq(POOL.supportedRouters(unRouter), 0, "Router should not be supported initially");

        // Test authorizing a new router
        vm.prank(OWNER);
        POOL.manageRouter(unRouter, true);
        assertEq(POOL.supportedRouters(unRouter), 1, "Router should be supported after authorization");

        // Test authorizing an already authorized router (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DuplicateRouter.selector, unRouter));
        POOL.manageRouter(unRouter, true);

        // Test unauthorizing the router
        vm.prank(OWNER);
        POOL.manageRouter(unRouter, false);
        assertEq(POOL.supportedRouters(unRouter), 0, "Router should not be supported after unauthorized");

        // Test unauthorizing an already unauthorized router (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidRouter.selector, unRouter));
        POOL.manageRouter(unRouter, false);

        // Test calling from non-owner address (should revert)
        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, TRADER));
        POOL.manageRouter(unRouter, true);

        // Test with address(0) as router address
        vm.prank(OWNER);
        POOL.manageRouter(address(0), true);
        assertEq(POOL.supportedRouters(address(0)), 1, "Zero address should be allowed as a router");

        vm.prank(OWNER);
        POOL.manageRouter(address(0), false);
        assertEq(POOL.supportedRouters(address(0)), 0, "Zero address should be removable as a router");

        // Test multiple authorizations and unauthorizations
        address[] memory routers = new address[](3);
        routers[0] = makeAddr("router1");
        routers[1] = makeAddr("router2");
        routers[2] = makeAddr("router3");

        vm.startPrank(OWNER);
        for (uint i = 0; i < routers.length; i++) {
            POOL.manageRouter(routers[i], true);
            assertEq(POOL.supportedRouters(routers[i]), 1, "Router should be supported after authorization");
        }

        for (uint i = 0; i < routers.length; i++) {
            POOL.manageRouter(routers[i], false);
            assertEq(POOL.supportedRouters(routers[i]), 0, "Router should not be supported after unauthorized");
        }
        vm.stopPrank();

        // Test interaction with swapToStables function
        MockERC20 mockToken = new MockERC20("Mock Token", "MTK", 18);
        uint256 amount = 100 ether;
        deal(address(USDC), address(DEX_ROUTER), amount);
        bytes memory data = abi.encodeWithSignature("swapToStables(address)", address(USDC));

        // Add mockToken as a supported token
        vm.prank(OWNER);
        POOL.manageToken(address(mockToken), true);

        // Attempt to swap with an unauthorized router (should revert)
        vm.prank(ORCHESTRATOR);
        console.log("MAN WHAT THE HELL");
        deal(address(mockToken), address(EXECUTOR), amount);
        vm.expectRevert(); // The exact error will depend on how swapToStables is implemented
        POOL.swapToStables(address(mockToken), amount, address(UNAUTHORIZED_ROUTER), data);
        console.log("BOOMBACLOT");

        vm.prank(OWNER);
        POOL.manageRouter(unRouter, true);

        deal(address(mockToken), ORCHESTRATOR, amount);
        deal(address(USDC), address(UNAUTHORIZED_ROUTER), amount);
        vm.startPrank(address(EXECUTOR));
        mockToken.approve(address(POOL), amount);
        POOL.addLiquiditySwap(TRADER, address(mockToken), amount);



        amount = 100 ether;
        deal(address(USDC), address(DEX_ROUTER), amount);
        data = abi.encodeWithSignature("swapERC20ToStables(address,address)", address(mockToken), address(USDC));


        vm.startPrank(ORCHESTRATOR);
        console.log("Mock Token balance in POOL before swap: ", mockToken.balanceOf(address(POOL)));
        POOL.swapToStables(address(mockToken), amount, address(DEX_ROUTER), data);
    }

}