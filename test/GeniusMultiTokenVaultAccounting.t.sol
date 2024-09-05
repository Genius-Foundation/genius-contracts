// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusMultiTokenVault} from "../src/GeniusMultiTokenVault.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";

import {MockERC20} from "./mocks/MockERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusMultiTokenVaultAccounting is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint16 destChainId = 42;

    uint256 bridgeAmount = 100 ether;

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IEIP712 public permit2 = IEIP712(permit2Address);
    address public feeCollecter = makeAddr("feeCollector");
    
    // ============ Internal Contracts ============
    GeniusMultiTokenVault public VAULT;
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
        USDC.transfer(address(VAULT), 10 ether);
        assertEq(VAULT.totalStakedAssets(), expectedTotalStaked, "Total staked assets mismatch after donation");
        assertEq(VAULT.stablecoinBalance(), expectedTotal, "Total assets mismatch after donation");
        assertEq(VAULT.availableAssets(), expectedAvailable, "Available assets mismatch after donation");
        assertEq(VAULT.minAssetBalance(), expectedMin, "Minimum asset balance mismatch after donation");
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
        DEX_ROUTER = new MockDEXRouter();
        BRIDGE = makeAddr("bridge");

        // Initialize vault with supported tokens
        address[] memory supportedTokens = new address[](4);
        supportedTokens[0] = NATIVE;
        supportedTokens[1] = address(TOKEN1);
        supportedTokens[2] = address(TOKEN2);
        supportedTokens[3] = address(TOKEN3);

        address[] memory bridges = new address[](1);
        bridges[0] = address(DEX_ROUTER);

        address[] memory routers = new address[](1);
        routers[0] = address(DEX_ROUTER);
        
        GeniusMultiTokenVault implementation = new GeniusMultiTokenVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusMultiTokenVault.initialize.selector,
            address(USDC),
            OWNER,
            supportedTokens, 
            bridges, 
            routers
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusMultiTokenVault(address(proxy));
        EXECUTOR = new GeniusExecutor(permit2Address, address(VAULT), OWNER, new address[](0));

        VAULT.setExecutor(address(EXECUTOR));
        
        // Add Orchestrator
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);

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
        VAULT.stakeDeposit(100 ether, TRADER);

        // Check the staked value
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch after deposit");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch after deposit");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch after deposit");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch after deposit");

        vm.stopPrank(); // Stop acting as TRADER
    }

    function testThresholdChange() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.stakeDeposit(100 ether, TRADER);

        // Check the staked value
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets and total assets mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank(); // Stop acting as TRADER

        // Change the threshold
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(10);
        vm.stopPrank();


        // Check the staked value
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 10 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");
    }

    function testStakeAndDeposit() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        
        USDC.approve(address(VAULT), 100 ether);
        VAULT.stakeDeposit(100 ether, TRADER);

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total stables mismatch");
        assertEq(VAULT.rebalanceThreshold(), 75, "Threshold mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available stable balance mismatch");
        vm.stopPrank();
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDC), 100 ether, 42, uint32(block.timestamp + 1000), 1 ether);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 200 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 174 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

        // Test balances of other supported tokens
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) != address(USDC)) {
                assertEq(tokenBalances[i], 0, "Non-USDC token balance should be 0");
            }
        }
    }

    function testCycleWithoutThresholdChange() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.stakeDeposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total assets in VAULT mismatch");
        
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 100 ether);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDC), 100 ether, 42, uint32(block.timestamp + 1000), 1 ether);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 200 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 174 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total assets in VAULT mismatch");
        assertEq(VAULT.supportedTokenReservedFees(address(USDC)), 1 ether, "USDC reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "USDC fees mismatch");

        // Start acting as TRADER again
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.availableAssets(), 99 ether, "Available stable balance mismatch");
        assertEq(VAULT.totalStakedAssets(), 0, "Total assets in VAULT mismatch");

        // Check balances of other supported tokens
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) != address(USDC)) {
                assertEq(tokenBalances[i], 0, "Non-USDC token balance should be 0");
            }
        }
    }

    function testFullCycle() public {
        // =================== DEPOSIT THROUGH VAULT ===================
        deal(address(TOKEN1), address(TRADER), 100 ether);
        deal(address(USDC), address(DEX_ROUTER), 100 ether);

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE() ,ORCHESTRATOR);
        vm.stopPrank();

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        
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
            keccak256("order"),
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER,
            destChainId,
            uint32(block.timestamp + 1000),
            1 ether
        );

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 124 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.supportedTokenReservedFees(address(USDC)), 1 ether, "USDC reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "USDC fees mismatch");

        vm.stopPrank();

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 59 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum stable balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Vault total assets mismatch");
        assertEq(VAULT.availableAssets(), 49 ether, "Available stable balance mismatch");

        vm.stopPrank();

        // Check balances of other supported tokens
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) != address(USDC)) {
                assertEq(tokenBalances[i], 0, "Non-USDC token balance should be 0");
            } else {
                assertEq(tokenBalances[i], 100 ether, "USDC balance in vault should be 100 ether");
            }
        }
    }

    function testFullCycleWithDonations() public {
        
        // =================== SETUP ===================
        deal(address(TOKEN1), address(TRADER), 100 ether);
        deal(address(USDC), address(DEX_ROUTER), 100 ether);

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Initial donation
        donateAndAssert(0, 10 ether, 10 ether, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 110 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 85 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");

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
            keccak256("order"),
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER,
            destChainId,
            uint32(block.timestamp + 1000),
            1 ether
        );

        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 170 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 144 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum stable balance mismatch");
        assertEq(VAULT.supportedTokenReservedFees(address(USDC)), 1 ether, "USDC reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "USDC fees mismatch");

        // Donate before changing threshold
        donateAndAssert(100 ether, 180 ether, 154 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked stables mismatch");
        assertEq(VAULT.stablecoinBalance(), 180 ether, "Total stables mismatch");
        assertEq(VAULT.availableAssets(), 89 ether, "Available stable balance mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum stable balance mismatch");

        // Donate before withdrawing
        donateAndAssert(100 ether, 190 ether, 99 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked stables does not equal 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Vault total assets mismatch");
        assertEq(VAULT.availableAssets(), 89 ether, "Available stable balance mismatch");

        // Check balances of other supported tokens
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) != address(USDC)) {
                assertEq(tokenBalances[i], 0, "Non-USDC token balance should be 0");
            } else {
                assertEq(tokenBalances[i], 170 ether, "USDC balance in vault should be 170 ether");
            }
        }
    }

    function testAddLiquiditySwapWithDifferentTokens() public {

        // Check that each token is supported
        assertEq(VAULT.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");


        // Deal Tokens to the EXECUTOR to spend
        deal(address(USDC), address(EXECUTOR), bridgeAmount);
        deal(address(TOKEN1), address(EXECUTOR), bridgeAmount);
        deal(address(TOKEN2), address(EXECUTOR), bridgeAmount);
        deal(address(TOKEN3), address(EXECUTOR), bridgeAmount);

        vm.startPrank(address(EXECUTOR));
        // Test USDC deposit
        USDC.approve(address(VAULT), bridgeAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(USDC), bridgeAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        assertEq(VAULT.stablecoinBalance(), bridgeAmount, "USDC deposit failed");
        assertEq(USDC.balanceOf(address(VAULT)), bridgeAmount, "USDC balance mismatch");

        assertEq(VAULT.supportedTokenReservedFees(address(USDC)), 1 ether, "USDC reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "USDC fees mismatch");

        // Test TOKEN1 deposit
        TOKEN1.approve(address(VAULT), bridgeAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(TOKEN1), bridgeAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        assertEq(TOKEN1.balanceOf(address(VAULT)), bridgeAmount, "TOKEN1 balance mismatch");

        assertEq(VAULT.supportedTokenReservedFees(address(TOKEN1)), 1 ether, "TOKEN1 reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(TOKEN1)), 0, "TOKEN1 fees mismatch");

        // Test TOKEN2 deposit
        TOKEN2.approve(address(VAULT), bridgeAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(TOKEN2), bridgeAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        assertEq(TOKEN2.balanceOf(address(VAULT)), bridgeAmount, "TOKEN2 balance mismatch");

        assertEq(VAULT.supportedTokenReservedFees(address(TOKEN2)), 1 ether, "TOKEN2 reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(TOKEN2)), 0, "TOKEN2 fees mismatch");

        // Test TOKEN3 deposit
        TOKEN3.approve(address(VAULT), bridgeAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(TOKEN3), bridgeAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        assertEq(TOKEN3.balanceOf(address(VAULT)), bridgeAmount, "TOKEN3 balance mismatch");

        assertEq(VAULT.supportedTokenReservedFees(address(TOKEN3)), 1 ether, "TOKEN3 reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(TOKEN3)), 0, "TOKEN3 fees mismatch");

        // Test native ETH deposit
        uint256 initialETHBalance = address(VAULT).balance;
        vm.deal(address(EXECUTOR), bridgeAmount); // Ensure TRADER has enough ETH
        VAULT.addLiquiditySwap{value: bridgeAmount}(keccak256("order"), TRADER, NATIVE, bridgeAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        assertEq(address(VAULT).balance - initialETHBalance, bridgeAmount, "ETH deposit failed");

        assertEq(VAULT.supportedTokenReservedFees(NATIVE), 1 ether, "NATIVE reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(NATIVE), 0, "NATIVE fees mismatch");

        // Verify token balances using supportedTokensBalances
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            address token = VAULT.supportedTokensIndex(i);
            if (token == address(USDC)) {
                assertEq(tokenBalances[i], bridgeAmount, "USDC balance mismatch in supportedTokensBalances");
            } else if (token == address(TOKEN1)) {
                assertEq(tokenBalances[i], bridgeAmount, "TOKEN1 balance mismatch in supportedTokensBalances");
            } else if (token == address(TOKEN2)) {
                assertEq(tokenBalances[i], bridgeAmount, "TOKEN2 balance mismatch in supportedTokensBalances");
            } else if (token == address(TOKEN3)) {
                assertEq(tokenBalances[i], bridgeAmount, "TOKEN3 balance mismatch in supportedTokensBalances");
            } else if (token == NATIVE) {
                assertEq(tokenBalances[i], bridgeAmount, "ETH balance mismatch in supportedTokensBalances");
            }
        }

        vm.stopPrank();
    }

    function testNativeLiquiditySwap() public {
        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Check that each token is supported
        assertEq(VAULT.isTokenSupported(NATIVE), true, "NATIVE token not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN1)), true, "TOKEN1 not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN2)), true, "TOKEN2 not supported");
        assertEq(VAULT.isTokenSupported(address(TOKEN3)), true, "TOKEN3 not supported");

        // Prepare for native ETH deposit
        uint256 initialETHBalance = address(VAULT).balance;
        vm.deal(TRADER, bridgeAmount); // Ensure TRADER has enough ETH
        deal(address(USDC), address(DEX_ROUTER), bridgeAmount);

        // Create the calldata for the nativeSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapToStables(address)",
            address(USDC)
        );

        vm.prank(TRADER);
        EXECUTOR.nativeSwapAndDeposit{value: bridgeAmount}(
            keccak256("order"),
            address(DEX_ROUTER),
            calldataSwap,
            bridgeAmount,
            destChainId,
            uint32(block.timestamp + 1000),
            1 ether
        );

        assertEq(address(VAULT).balance - initialETHBalance, 0, "ETH should not be held in VAULT");
        assertEq(USDC.balanceOf(address(VAULT)), 50 ether, "USDC balance mismatch after swap");
        assertEq(VAULT.supportedTokenReservedFees(address(USDC)), 1 ether, "NATIVE reserved fees mismatch");
        assertEq(VAULT.supportedTokenFees(address(USDC)), 0, "NATIVE fees mismatch");

        // Verify token balances using supportedTokensBalances
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            address token = VAULT.supportedTokensIndex(i);
            if (token == NATIVE) {
                assertEq(tokenBalances[i], 0, "ETH balance should be 0 in supportedTokensBalances");
            } else if (token == address(USDC)) {
                assertEq(tokenBalances[i], bridgeAmount, "USDC balance mismatch in supportedTokensBalances");
            }
        }
    }

    function testSwapToStables() public {
        uint256 swapAmount = 100 ether;

        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // First, add liquidity for a non-USDC token (let's use TOKEN1)
        vm.startPrank(TRADER);
        TOKEN1.approve(address(EXECUTOR), swapAmount);
        TOKEN1.approve(permit2Address, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(VAULT), swapAmount);
        deal(address(TOKEN1), address(EXECUTOR), swapAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(TOKEN1), swapAmount, 42, uint32(block.timestamp + 1000), 1 ether);
        deal(address(USDC), address(DEX_ROUTER), swapAmount);
        vm.stopPrank();

        // Check initial balances
        uint256 initialTotalStables = VAULT.stablecoinBalance();

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
            keccak256("order"),
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER,
            42,
            uint32(block.timestamp + 1000),
            1 ether
        );

        // Assertions
        assertEq(TOKEN1.balanceOf(address(VAULT)), 100 ether, "TOKEN1 balance should be 0");
        assertEq(USDC.balanceOf(address(VAULT)), (swapAmount / 2), "USDC balance should increase by swapAmount");
        assertEq(VAULT.stablecoinBalance(), initialTotalStables + (swapAmount / 2), "Total stables should increase by swapAmount");

        // Verify token balances using supportedTokensBalances
        uint256[] memory tokenBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < tokenBalances.length; i++) {
            address token = VAULT.supportedTokensIndex(i);

            if (token == address(TOKEN1)) {
                assertEq(tokenBalances[i], 100 ether, "TOKEN1 balance should be 100 in supportedTokensBalances");
            } else if (token == address(USDC)) {
                assertEq(tokenBalances[i], swapAmount, "USDC balance mismatch in supportedTokensBalances");
            }
        }
    }

    function testSwapToStablesErrors() public {
        uint256 swapAmount = 100 ether;

        // Setup
        vm.startPrank(OWNER, OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Add liquidity for a non-USDC token (let's use TOKEN1)
        vm.startPrank(TRADER);
        TOKEN1.approve(address(EXECUTOR), swapAmount);
        TOKEN1.approve(permit2Address, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(VAULT), swapAmount);
        deal(address(TOKEN1), address(EXECUTOR), swapAmount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(TOKEN1), swapAmount, 42, uint32(block.timestamp + 1000), 1 ether);
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
        VAULT.pause();
        vm.stopPrank();

        assertEq(VAULT.paused(), true, "Contract should be paused");

        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        VAULT.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataSwap);
        vm.stopPrank();

        vm.startPrank(OWNER);
        VAULT.unpause();
        vm.stopPrank();


        vm.startPrank(ORCHESTRATOR);
        // Test InvalidAmount error
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        VAULT.swapToStables(address(TOKEN1), 0, address(DEX_ROUTER), calldataSwap);

        // Test InvalidToken error
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(0xdeadbeef)));
        VAULT.swapToStables(address(0xdeadbeef), swapAmount, address(DEX_ROUTER), calldataSwap);

        // Test InsufficientBalance error
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InsufficientBalance.selector, address(TOKEN1), swapAmount * 2, swapAmount));
        VAULT.swapToStables(address(TOKEN1), swapAmount * 2, address(DEX_ROUTER), calldataSwap);

        bytes memory calldataNoSwap = abi.encodeWithSignature(
                "swapWithNoEffect(address,address)",
                address(TOKEN1),
                address(USDC)
            );

        vm.expectRevert(GeniusErrors.InvalidDelta.selector);
        VAULT.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataNoSwap);

        // Test ExternalCallFailed error
        bytes memory calldataSwapFail = abi.encodeWithSignature(
            "nonExistentFunction()"
        );
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.ExternalCallFailed.selector, address(DEX_ROUTER), 0));
        VAULT.swapToStables(address(TOKEN1), swapAmount, address(DEX_ROUTER), calldataSwapFail);
         
        vm.stopPrank();
    }


    function testAddBridgeLiquidity() public {

        // Setup: Fund the ORCHESTRATOR with USDC
        deal(address(USDC), ORCHESTRATOR, bridgeAmount);
        uint256[] memory initialBalances = VAULT.supportedTokensBalances();

        // Perform addBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), bridgeAmount);
        vm.stopPrank();

        // Assert total stables increased correctly
        assertEq(VAULT.stablecoinBalance(), 0 + bridgeAmount, "Total stables should increase by bridge amount");

        // Assert available stable balance increased
        assertEq(VAULT.availableAssets(), 0 + bridgeAmount, "Available stable balance should increase by bridge amount");

        // Assert min stable balance remains unchanged
        assertEq(VAULT.minAssetBalance(), 0, "Minimum stable balance should remain unchanged");

        // Assert balances for all supported tokens
        uint256[] memory finalBalances = VAULT.supportedTokensBalances();
        assertEq(finalBalances.length, initialBalances.length, "Number of supported tokens should remain the same");

        for (uint i = 0; i < finalBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) == address(USDC)) {
                assertEq(finalBalances[i], initialBalances[i] + bridgeAmount, "USDC balance should increase by bridge amount");
            } else {
                assertEq(finalBalances[i], initialBalances[i], "Non-USDC token balances should remain unchanged");
            }
        }

        // Verify USDC transfer
        assertEq(USDC.balanceOf(address(VAULT)), initialBalances[0] + bridgeAmount, "USDC balance in vault should increase by bridge amount");
    }

    function testRemoveBridgeLiquidity() public {
        uint16 testChainId = 1; // Example chain ID

        // Setup: Add liquidity to the vault
        deal(address(USDC), address(DEX_ROUTER), bridgeAmount);
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), bridgeAmount);

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

        vm.startPrank(address(VAULT));
        USDC.approve(address(DEX_ROUTER), bridgeAmount);
        vm.stopPrank();

        // Perform removeBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        VAULT.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);
        vm.stopPrank();

        // Assert state changes
        assertEq(VAULT.stablecoinBalance(), 0, "Total stables should decrease");
        assertEq(USDC.balanceOf(address(VAULT)),  0, "VAULT USDC balance should decrease");

        // Test with zero amount (should revert)
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        VAULT.removeBridgeLiquidity(0, testChainId, targets, values, data);

        // Test when vault is paused
        vm.prank(OWNER);
        VAULT.pause();
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        VAULT.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);
        vm.prank(OWNER);
        VAULT.unpause();

        // Test when called by non-orchestrator
        vm.prank(TRADER);
        vm.expectRevert();
        VAULT.removeBridgeLiquidity(bridgeAmount, testChainId, targets, values, data);

        // Test when trying to remove more than available balance
        vm.prank(ORCHESTRATOR);
        vm.expectRevert();
        VAULT.removeBridgeLiquidity(1 ether, testChainId, targets, values, data);
    }


    function testAddBridgeLiquidityWithDonations() public {
        // Setup: Fund the ORCHESTRATOR with USDC
        deal(address(USDC), ORCHESTRATOR, bridgeAmount);
        
        uint256[] memory initialBalances = VAULT.supportedTokensBalances();

        // Perform addBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        USDC.transfer(address(VAULT), bridgeAmount);
        vm.stopPrank();

        // Assert total stables increased correctly
        assertEq(
            VAULT.stablecoinBalance(),
            0 + bridgeAmount,
            "Total stables should increase by bridge amount"
        );

        // Assert available stable balance increased
        assertEq(
            VAULT.availableAssets(),
            0 + bridgeAmount,
            "Available stable balance should increase by bridge amount"
        );

        // Assert min stable balance remains unchanged
        assertEq(
            VAULT.minAssetBalance(),
            0,
            "Minimum stable balance should remain unchanged"
        );

        // Assert balances for all supported tokens
        uint256[] memory finalBalances = VAULT.supportedTokensBalances();
        assertEq(
            finalBalances.length,
            initialBalances.length,
            "Number of supported tokens should remain the same"
        );

        for (uint i = 0; i < finalBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) == address(USDC)) {

                assertEq(
                    finalBalances[i],
                    initialBalances[i] + bridgeAmount,
                    "USDC balance should increase by bridge amount"
                );

            } else {

                assertEq(
                    finalBalances[i],
                    initialBalances[i],
                    "Non-USDC token balances should remain unchanged"
                );

            }
        }

        // Verify USDC transfer
        assertEq(
            USDC.balanceOf(address(VAULT)),
            initialBalances[0] + bridgeAmount,
            "USDC balance in vault should increase by bridge amount"
        );

        // Additional Step: Simulate a donation to the vault


        // Manually reconcile the balances due to donation
        donateAndAssert(
            VAULT.totalStakedAssets(), 
            VAULT.stablecoinBalance() + 10 ether, // Account for the 10 ether donation
            VAULT.availableAssets() +  10 ether, // Account for the 10 ether donation
            VAULT.minAssetBalance()
        );

        // Assert the balances have been updated correctly to include the donation
        uint256[] memory postDonationBalances = VAULT.supportedTokensBalances();
        for (uint i = 0; i < postDonationBalances.length; i++) {
            if (VAULT.supportedTokensIndex(i) == address(USDC)) {
                
                assertEq(
                    postDonationBalances[i],
                    finalBalances[i] + 10 ether,
                    "USDC balance should include donation amount"
                );

            } else {

                assertEq(
                    postDonationBalances[i],
                    finalBalances[i],
                    "Non-USDC token balances should remain unchanged"
                );

            }
        }

        // Verify USDC balance in the vault contract
        assertEq(
            USDC.balanceOf(address(VAULT)),
            initialBalances[0] + bridgeAmount + 10 ether,
            "USDC balance in vault should include donation amount"
        );
    }


    /**
     * @dev Tests the manageToken function
     */
    function testManageToken() public {
        // Setup: Deploy a new test token
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);

        // Initial checks
        assertFalse(VAULT.isTokenSupported(address(newToken)), "New token should not be supported initially");
        uint256 initialSupportedTokensCount = VAULT.supportedTokensCount();

        // Test adding a new token
        vm.prank(OWNER);
        VAULT.manageToken(address(newToken), true);

        assertTrue(VAULT.isTokenSupported(address(newToken)), "New token should now be supported");
        assertEq(VAULT.supportedTokensCount(), initialSupportedTokensCount + 1, "Supported tokens count should increase");

        // Test adding a duplicate token (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DuplicateToken.selector, address(newToken)));
        VAULT.manageToken(address(newToken), true);

        // Test removing the token
        vm.prank(OWNER);
        VAULT.manageToken(address(newToken), false);

        assertFalse(VAULT.isTokenSupported(address(newToken)), "New token should no longer be supported");
        assertEq(VAULT.supportedTokensCount(), initialSupportedTokensCount, "Supported tokens count should be back to initial value");

        // Test removing a token that's not supported (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(newToken)));
        VAULT.manageToken(address(newToken), false);

        // Test removing a token with non-zero balance (should revert)
        // First, add the token back and simulate some balance
        vm.prank(OWNER);
        VAULT.manageToken(address(newToken), true);

        deal(address(newToken), address(EXECUTOR), 100 ether);
        vm.startPrank(address(EXECUTOR));
        newToken.approve(address(VAULT), 100 ether);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(newToken), 100 ether, 42, uint32(block.timestamp + 1000), 1 ether);

        vm.startPrank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.RemainingBalance.selector, 100 ether));
        VAULT.manageToken(address(newToken), false);

        // Test managing STABLECOIN (should revert)
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidToken.selector, address(USDC)));
        VAULT.manageToken(address(USDC), false);

        // Test calling from non-owner address (should revert)
        vm.startPrank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector));
        VAULT.manageToken(address(newToken), false);
    }

    function testManageBridge() public {
        address newBridge = makeAddr("newBridge");

        // Initial check
        assertEq(VAULT.supportedBridges(newBridge), 0, "Bridge should not be supported initially");

        // Test authorizing a new bridge
        vm.prank(OWNER);
        VAULT.manageBridge(newBridge, true);
        assertEq(VAULT.supportedBridges(newBridge), 1, "Bridge should be supported after authorization");

        // Test authorizing an already authorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, newBridge));
        VAULT.manageBridge(newBridge, true);

        // Test unauthorizing the bridge
        vm.prank(OWNER);
        VAULT.manageBridge(newBridge, false);
        assertEq(VAULT.supportedBridges(newBridge), 0, "Bridge should not be supported after unauthorized");

        // Test unauthorizing an already unauthorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidTarget.selector, newBridge));
        VAULT.manageBridge(newBridge, false);

        // Test calling from non-owner address (should revert)
        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector));
        VAULT.manageBridge(newBridge, true);

        // Test with address(0) as bridge address
        vm.prank(OWNER);
        VAULT.manageBridge(address(0), true);
        assertEq(VAULT.supportedBridges(address(0)), 1, "Zero address should be allowed as a bridge");

        vm.prank(OWNER);
        VAULT.manageBridge(address(0), false);
        assertEq(VAULT.supportedBridges(address(0)), 0, "Zero address should be removable as a bridge");

        // Test multiple authorizations and unauthorizations
        address[] memory bridges = new address[](3);
        bridges[0] = makeAddr("bridge1");
        bridges[1] = makeAddr("bridge2");
        bridges[2] = makeAddr("bridge3");

        vm.startPrank(OWNER);
        for (uint i = 0; i < bridges.length; i++) {
            VAULT.manageBridge(bridges[i], true);
            assertEq(VAULT.supportedBridges(bridges[i]), 1, "Bridge should be supported after authorization");
        }

        for (uint i = 0; i < bridges.length; i++) {
            VAULT.manageBridge(bridges[i], false);
            assertEq(VAULT.supportedBridges(bridges[i]), 0, "Bridge should not be supported after unauthorized");
        }
        vm.stopPrank();
    }

    function testManageRouter() public {
        MockDEXRouter UNAUTHORIZED_ROUTER = new MockDEXRouter();
        address unRouter = address(UNAUTHORIZED_ROUTER);

        // Initial check
        assertEq(VAULT.supportedRouters(unRouter), 0, "Router should not be supported initially");

        // Test authorizing a new router
        vm.prank(OWNER);
        VAULT.manageRouter(unRouter, true);
        assertEq(VAULT.supportedRouters(unRouter), 1, "Router should be supported after authorization");

        // Test authorizing an already authorized router (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.DuplicateRouter.selector, unRouter));
        VAULT.manageRouter(unRouter, true);

        // Test unauthorizing the router
        vm.prank(OWNER);
        VAULT.manageRouter(unRouter, false);
        assertEq(VAULT.supportedRouters(unRouter), 0, "Router should not be supported after unauthorized");

        // Test unauthorizing an already unauthorized router (should revert)
        vm.prank(OWNER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.InvalidRouter.selector, unRouter));
        VAULT.manageRouter(unRouter, false);

        // Test calling from non-owner address (should revert)
        vm.prank(TRADER);
        vm.expectRevert(abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector));
        VAULT.manageRouter(unRouter, true);

        // Test with address(0) as router address
        vm.prank(OWNER);
        VAULT.manageRouter(address(0), true);
        assertEq(VAULT.supportedRouters(address(0)), 1, "Zero address should be allowed as a router");

        vm.prank(OWNER);
        VAULT.manageRouter(address(0), false);
        assertEq(VAULT.supportedRouters(address(0)), 0, "Zero address should be removable as a router");

        // Test multiple authorizations and unauthorizations
        address[] memory routers = new address[](3);
        routers[0] = makeAddr("router1");
        routers[1] = makeAddr("router2");
        routers[2] = makeAddr("router3");

        vm.startPrank(OWNER);
        for (uint i = 0; i < routers.length; i++) {
            VAULT.manageRouter(routers[i], true);
            assertEq(VAULT.supportedRouters(routers[i]), 1, "Router should be supported after authorization");
        }

        for (uint i = 0; i < routers.length; i++) {
            VAULT.manageRouter(routers[i], false);
            assertEq(VAULT.supportedRouters(routers[i]), 0, "Router should not be supported after unauthorized");
        }
        vm.stopPrank();

        // Test interaction with swapToStables function
        MockERC20 mockToken = new MockERC20("Mock Token", "MTK", 18);
        uint256 amount = 100 ether;
        deal(address(USDC), address(DEX_ROUTER), amount);
        bytes memory data = abi.encodeWithSignature("swapToStables(address)", address(USDC));

        // Add mockToken as a supported token
        vm.prank(OWNER);
        VAULT.manageToken(address(mockToken), true);

        // Attempt to swap with an unauthorized router (should revert)
        vm.prank(ORCHESTRATOR);
        deal(address(mockToken), address(EXECUTOR), amount);
        vm.expectRevert(); // The exact error will depend on how swapToStables is implemented
        VAULT.swapToStables(address(mockToken), amount, address(UNAUTHORIZED_ROUTER), data);

        vm.prank(OWNER);
        VAULT.manageRouter(unRouter, true);

        deal(address(mockToken), ORCHESTRATOR, amount);
        deal(address(USDC), address(UNAUTHORIZED_ROUTER), amount);
        vm.startPrank(address(EXECUTOR));
        mockToken.approve(address(VAULT), amount);
        VAULT.addLiquiditySwap(keccak256("order"), TRADER, address(mockToken), amount, 42, uint32(block.timestamp + 1000), 1 ether);



        amount = 100 ether;
        deal(address(USDC), address(DEX_ROUTER), amount);
        data = abi.encodeWithSignature("swapERC20ToStables(address,address)", address(mockToken), address(USDC));


        vm.startPrank(ORCHESTRATOR);
        VAULT.swapToStables(address(mockToken), amount, address(DEX_ROUTER), data);
    }

}