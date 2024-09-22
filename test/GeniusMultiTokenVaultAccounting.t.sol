// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusMultiTokenVault} from "../src/GeniusMultiTokenVault.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusErrors} from "../src/libs/GeniusErrors.sol";
import {IGeniusVault} from "../src/interfaces/IGeniusVault.sol";

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
    bytes32 public RECEIVER;

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
        require(
            tokens.length == amounts.length,
            "Tokens and amounts length mismatch"
        );
        require(tokens.length > 0, "At least one token must be provided");

        IAllowanceTransfer.PermitDetails[]
            memory permitDetails = new IAllowanceTransfer.PermitDetails[](
                tokens.length
            );

        for (uint i = 0; i < tokens.length; i++) {
            permitDetails[i] = IAllowanceTransfer.PermitDetails({
                token: tokens[i],
                amount: amounts[i],
                expiration: 1900000000,
                nonce: nonce
            });
            nonce++;
        }

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer
            .PermitBatch({
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

    function donateAndAssert(
        uint256 expectedTotalStaked,
        uint256 expectedTotal,
        uint256 expectedAvailable,
        uint256 expectedMin
    ) internal {
        USDC.transfer(address(VAULT), 10 ether);
        assertEq(
            VAULT.totalStakedAssets(),
            expectedTotalStaked,
            "Total staked assets mismatch after donation"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            expectedTotal,
            "Total assets mismatch after donation"
        );
        assertEq(
            VAULT.availableAssets(),
            expectedAvailable,
            "Available assets mismatch after donation"
        );
        assertEq(
            VAULT.minLiquidity(),
            expectedMin,
            "Minimum asset balance mismatch after donation"
        );
    }

    function _getTokenSymbol(
        address token
    ) internal view returns (string memory) {
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
        RECEIVER = bytes32(uint256(uint160(TRADER)));
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
            supportedTokens
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusMultiTokenVault(address(proxy));
        EXECUTOR = new GeniusExecutor(
            permit2Address,
            address(VAULT),
            OWNER,
            new address[](0)
        );

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
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked assets mismatch after deposit"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            100 ether,
            "Total assets mismatch after deposit"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available assets mismatch after deposit"
        );
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum asset balance mismatch after deposit"
        );

        vm.stopPrank(); // Stop acting as TRADER
    }

    function testThresholdChange() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.stakeDeposit(100 ether, TRADER);

        // Check the staked value
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked assets mismatch"
        );
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked assets and total assets mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available assets mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum asset balance mismatch"
        );

        vm.stopPrank(); // Stop acting as TRADER

        // Change the threshold
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(1_000);
        vm.stopPrank();

        // Check the staked value
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked assets mismatch"
        );
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(
            VAULT.availableAssets(),
            10 ether,
            "Available assets mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            90 ether,
            "Minimum asset balance mismatch"
        );
    }

    function testStakeAndDeposit() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);

        USDC.approve(address(VAULT), 100 ether);
        VAULT.stakeDeposit(100 ether, TRADER);

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            100 ether,
            "Total stables mismatch"
        );
        assertEq(VAULT.rebalanceThreshold(), 7_500, "Threshold mismatch");
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum stable balance mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 101 ether);
        USDC.approve(address(VAULT), 101 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(USDC),
            100 ether,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            201 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            126 ether,
            "Minimum stable balance mismatch"
        );
    }

    function testCycleWithoutThresholdChange() public {
        // Start acting as TRADER
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        VAULT.stakeDeposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            100 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum stable balance mismatch"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total assets in VAULT mismatch"
        );

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 101 ether);
        USDC.approve(address(VAULT), 101 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(USDC),
            100 ether,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            201 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            126 ether,
            "Minimum stable balance mismatch"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total assets in VAULT mismatch"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            0,
            "USDC fees mismatch"
        );

        // Start acting as TRADER again
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked stables does not equal 0"
        );
        assertEq(
            VAULT.availableAssets(),
            0 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total assets in VAULT mismatch"
        );
    }

    function testFullCycle() public {
        // =================== DEPOSIT THROUGH VAULT ===================
        deal(address(TOKEN1), address(TRADER), 100 ether);
        deal(address(USDC), address(DEX_ROUTER), 100 ether);

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), 100 ether);
        USDC.approve(permit2Address, type(uint256).max);
        TOKEN1.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(100 ether, TRADER);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            100 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum stable balance mismatch"
        );

        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for TOKEN1
        address[] memory tokens = new address[](1);
        tokens[0] = address(TOKEN1);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(100 ether);

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(address(EXECUTOR), tokens, amounts);

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
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            150 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            75 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            75 ether,
            "Minimum stable balance mismatch"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            0,
            "USDC fees mismatch"
        );

        vm.stopPrank();

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(1_000);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            150 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            10 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            140 ether,
            "Minimum stable balance mismatch"
        );

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);

        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked stables does not equal 0"
        );
        assertEq(VAULT.totalStakedAssets(), 0, "Vault total assets mismatch");
        assertEq(
            VAULT.availableAssets(),
            0 ether,
            "Available stable balance mismatch"
        );

        vm.stopPrank();

        assertEq(
            VAULT.stablecoinBalance(),
            50 ether,
            "USDC balance in vault should be 50 ether"
        );
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

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            110 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            85 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            25 ether,
            "Minimum stable balance mismatch"
        );

        // Donate before swap and deposit
        donateAndAssert(100 ether, 120 ether, 95 ether, 25 ether);

        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for TOKEN1
        address[] memory tokens = new address[](1);
        tokens[0] = address(TOKEN1);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(100 ether);

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(address(EXECUTOR), tokens, amounts);

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
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );

        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            170 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            95 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            75 ether,
            "Minimum stable balance mismatch"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            0,
            "USDC fees mismatch"
        );

        // Donate before changing threshold
        donateAndAssert(100 ether, 180 ether, 105 ether, 75 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(1_000);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            100 ether,
            "Total staked stables mismatch"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            180 ether,
            "Total stables mismatch"
        );
        assertEq(
            VAULT.availableAssets(),
            40 ether,
            "Available stable balance mismatch"
        );
        assertEq(
            VAULT.minLiquidity(),
            140 ether,
            "Minimum stable balance mismatch"
        );

        // Donate before withdrawing
        donateAndAssert(100 ether, 190 ether, 50 ether, 140 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(100 ether, TRADER, TRADER);
        vm.stopPrank();

        assertEq(
            VAULT.totalStakedAssets(),
            0,
            "Total staked stables does not equal 0"
        );
        assertEq(VAULT.totalStakedAssets(), 0, "Vault total assets mismatch");
        assertEq(
            VAULT.availableAssets(),
            40 ether,
            "Available stable balance mismatch"
        );

        assertEq(
            VAULT.stablecoinBalance(),
            90 ether,
            "USDC balance in vault should be 90 ether"
        );
    }

    function testAddLiquiditySwapWithDifferentTokens() public {
        // Check that each token is supported
        assertEq(
            VAULT.isTokenSupported(NATIVE),
            true,
            "NATIVE token not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN1)),
            true,
            "TOKEN1 not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN2)),
            true,
            "TOKEN2 not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN3)),
            true,
            "TOKEN3 not supported"
        );

        // Deal Tokens to the EXECUTOR to spend
        deal(address(USDC), address(EXECUTOR), bridgeAmount + 1 ether);
        deal(address(TOKEN1), address(EXECUTOR), bridgeAmount + 1 ether);
        deal(address(TOKEN2), address(EXECUTOR), bridgeAmount + 1 ether);
        deal(address(TOKEN3), address(EXECUTOR), bridgeAmount + 1 ether);

        vm.startPrank(address(EXECUTOR));
        // Test USDC deposit
        USDC.approve(address(VAULT), bridgeAmount + 1 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(USDC),
            bridgeAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        assertEq(
            VAULT.stablecoinBalance(),
            bridgeAmount + 1 ether,
            "USDC deposit failed"
        );
        assertEq(
            USDC.balanceOf(address(VAULT)),
            bridgeAmount + 1 ether,
            "USDC balance mismatch"
        );

        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            0,
            "USDC fees mismatch"
        );

        // Test TOKEN1 deposit
        TOKEN1.approve(address(VAULT), bridgeAmount + 1 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(TOKEN1),
            bridgeAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );

        assertEq(
            TOKEN1.balanceOf(address(VAULT)),
            bridgeAmount + 1 ether,
            "TOKEN1 balance mismatch"
        );
        assertEq(
            VAULT.supportedTokenFees(address(TOKEN1)),
            0,
            "TOKEN1 fees mismatch"
        );

        // Test TOKEN2 deposit
        TOKEN2.approve(address(VAULT), bridgeAmount + 1 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(TOKEN2),
            bridgeAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        assertEq(
            TOKEN2.balanceOf(address(VAULT)),
            bridgeAmount + 1 ether,
            "TOKEN2 balance mismatch"
        );

        assertEq(
            VAULT.supportedTokenFees(address(TOKEN2)),
            0,
            "TOKEN2 fees mismatch"
        );

        // Test TOKEN3 deposit
        TOKEN3.approve(address(VAULT), bridgeAmount + 1 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(TOKEN3),
            bridgeAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        assertEq(
            TOKEN3.balanceOf(address(VAULT)),
            bridgeAmount + 1 ether,
            "TOKEN3 balance mismatch"
        );

        assertEq(
            VAULT.supportedTokenFees(address(TOKEN3)),
            0,
            "TOKEN3 fees mismatch"
        );

        // Test native ETH deposit
        uint256 initialETHBalance = address(VAULT).balance;
        vm.deal(address(EXECUTOR), bridgeAmount + 1 ether); // Ensure TRADER has enough ETH
        VAULT.addLiquiditySwap{value: bridgeAmount + 1 ether}(
            keccak256("order"),
            TRADER,
            NATIVE,
            bridgeAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        assertEq(
            address(VAULT).balance - initialETHBalance,
            bridgeAmount + 1 ether,
            "ETH deposit failed"
        );

        assertEq(VAULT.supportedTokenFees(NATIVE), 0, "NATIVE fees mismatch");

        assertEq(
            VAULT.stablecoinBalance(),
            bridgeAmount + 1 ether,
            "USDC balance mismatch in supportedTokensBalances"
        );
        assertEq(
            VAULT.tokenBalance(address(TOKEN1)),
            bridgeAmount + 1 ether,
            "TOKEN1 balance mismatch in supportedTokensBalances"
        );
        assertEq(
            VAULT.tokenBalance(address(TOKEN2)),
            bridgeAmount + 1 ether,
            "TOKEN2 balance mismatch in supportedTokensBalances"
        );
        assertEq(
            VAULT.tokenBalance(address(TOKEN3)),
            bridgeAmount + 1 ether,
            "TOKEN3 balance mismatch in supportedTokensBalances"
        );
        assertEq(
            VAULT.tokenBalance(NATIVE),
            bridgeAmount + 1 ether,
            "ETH balance mismatch in supportedTokensBalances"
        );

        vm.stopPrank();
    }

    function testNativeLiquiditySwap() public {
        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Check that each token is supported
        assertEq(
            VAULT.isTokenSupported(NATIVE),
            true,
            "NATIVE token not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN1)),
            true,
            "TOKEN1 not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN2)),
            true,
            "TOKEN2 not supported"
        );
        assertEq(
            VAULT.isTokenSupported(address(TOKEN3)),
            true,
            "TOKEN3 not supported"
        );

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
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );

        assertEq(
            address(VAULT).balance - initialETHBalance,
            0,
            "ETH should not be held in VAULT"
        );
        assertEq(
            USDC.balanceOf(address(VAULT)),
            50 ether,
            "USDC balance mismatch after swap"
        );
        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            0,
            "NATIVE fees mismatch"
        );

        assertEq(
            VAULT.tokenBalance(NATIVE),
            0,
            "ETH balance should be 0 in supportedTokensBalances"
        );
        assertEq(
            VAULT.tokenBalance(address(USDC)),
            bridgeAmount / 2,
            "USDC balance mismatch in supportedTokensBalances"
        );
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
        TOKEN1.approve(address(EXECUTOR), swapAmount + 1 ether);
        TOKEN1.approve(permit2Address, type(uint256).max);
        vm.stopPrank();

        vm.startPrank(address(EXECUTOR));
        TOKEN1.approve(address(VAULT), swapAmount + 1 ether);
        deal(address(TOKEN1), address(EXECUTOR), swapAmount + 1 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(TOKEN1),
            swapAmount,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
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

        (
            IAllowanceTransfer.PermitBatch memory permitBatch,
            bytes memory signature
        ) = generatePermitBatchAndSignature(address(EXECUTOR), tokens, amounts);

        vm.startPrank(ORCHESTRATOR);
        EXECUTOR.tokenSwapAndDeposit(
            keccak256("order"),
            address(DEX_ROUTER),
            calldataSwap,
            permitBatch,
            signature,
            TRADER,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );

        // Assertions
        assertEq(
            TOKEN1.balanceOf(address(VAULT)),
            101 ether,
            "TOKEN1 balance should be 101"
        );
        assertEq(
            USDC.balanceOf(address(VAULT)),
            (swapAmount / 2),
            "USDC balance should increase by swapAmount"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            initialTotalStables + (swapAmount / 2),
            "Total stables should increase by swapAmount"
        );

        assertEq(
            VAULT.tokenBalance(address(TOKEN1)),
            101 ether,
            "TOKEN1 balance should be 100 in supportedTokensBalances"
        );

        assertEq(
            VAULT.stablecoinBalance(),
            swapAmount / 2,
            "USDC balance mismatch in supportedTokensBalances"
        );
    }

    function testRemoveLiquiditySwapNoTargetsMultiToken() public {
        // Setup initial state
        deal(address(USDC), address(VAULT), 1_001 ether);
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1_001 ether,
            "GeniusMultiTokenVault initial USDC balance should be 1,000 ether"
        );

        // Create the order
        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: TRADER,
            srcChainId: 42,
            destChainId: uint16(block.chainid),
            fillDeadline: uint32(block.timestamp + 200),
            tokenIn: address(USDC),
            fee: 1 ether,
            receiver: RECEIVER
        });

        // Empty arrays for targets, values, and calldatas
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory calldatas = new bytes[](0);

        uint256 balanceTraderBefore = USDC.balanceOf(TRADER);

        // Execute removeLiquiditySwap
        vm.startPrank(ORCHESTRATOR);
        VAULT.removeLiquiditySwap(order, targets, values, calldatas);

        // Assertions
        assertEq(
            USDC.balanceOf(address(VAULT)),
            1 ether,
            "GeniusMultiTokenVault USDC balance should be 1 ether after removal"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            1 ether,
            "Total stablecoin balance should be 1 ether"
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
            1000 ether,
            "Trader balance should increase by 1000 ether"
        );

        vm.stopPrank();
    }

    function testRevertOrderNoTargetsMultiToken() public {
        // Setup initial state
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_004 ether);
        USDC.approve(address(VAULT), 1_004 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(USDC),
            1_000 ether,
            destChainId,
            uint32(block.timestamp + 100),
            4 ether,
            RECEIVER
        );
        vm.stopPrank();

        IGeniusVault.Order memory order = IGeniusVault.Order({
            seed: keccak256("order"),
            amountIn: 1_000 ether,
            trader: TRADER,
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: uint32(block.timestamp + 100),
            tokenIn: address(USDC),
            fee: 4 ether
        });

        // Advance time past the fillDeadline
        vm.warp(block.timestamp + 200);

        uint256 prevTraderBalance = USDC.balanceOf(TRADER);
        uint256 prevVaultBalance = USDC.balanceOf(address(VAULT));

        // Empty arrays for targets, values, and data
        address[] memory targets = new address[](0);
        uint256[] memory values = new uint256[](0);
        bytes[] memory data = new bytes[](0);

        vm.startPrank(ORCHESTRATOR);
        VAULT.revertOrder(order, targets, values, data);
        vm.stopPrank();

        uint256 postTraderBalance = USDC.balanceOf(TRADER);
        uint256 postVaultBalance = USDC.balanceOf(address(VAULT));

        uint256 expectedRefund = 1002 ether; // 1000 + 2 (50% of fees)

        assertEq(
            VAULT.supportedTokenFees(address(USDC)),
            2 ether,
            "Supported token fees for USDC should be 2 ether"
        );
        assertEq(
            VAULT.stablecoinBalance(),
            2 ether,
            "Vault stablecoin balance should be 2 ether"
        );
        assertEq(
            postTraderBalance - prevTraderBalance,
            expectedRefund,
            "Trader should receive refunded amount"
        );
        assertEq(
            prevVaultBalance - postVaultBalance,
            expectedRefund,
            "Vault balance should decrease by refunded amount"
        );
        assertEq(
            VAULT.supportedTokenReserves(address(USDC)),
            0,
            "Supported token reserves for USDC should be 0"
        );

        bytes32 orderHash = VAULT.orderHash(order);
        assertEq(
            uint256(VAULT.orderStatus(orderHash)),
            uint256(IGeniusVault.OrderStatus.Reverted),
            "Order status should be Reverted"
        );
    }

    function testRemoveBridgeLiquidity() public {
        uint16 testChainId = 1; // Example chain ID

        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        vm.stopPrank();

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

        vm.startPrank(address(EXECUTOR));
        USDC.approve(address(DEX_ROUTER), bridgeAmount);
        vm.stopPrank();

        // Perform removeBridgeLiquidity
        vm.startPrank(ORCHESTRATOR);
        VAULT.removeBridgeLiquidity(
            address(USDC),
            bridgeAmount,
            testChainId,
            targets,
            values,
            data
        );
        vm.stopPrank();

        // Assert state changes
        assertEq(VAULT.stablecoinBalance(), 0, "Total stables should decrease");
        assertEq(
            USDC.balanceOf(address(VAULT)),
            0,
            "VAULT USDC balance should decrease"
        );

        // Test with zero amount (should revert)
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(GeniusErrors.InvalidAmount.selector);
        VAULT.removeBridgeLiquidity(
            address(USDC),
            0,
            testChainId,
            targets,
            values,
            data
        );

        // Test when vault is paused
        vm.prank(OWNER);
        VAULT.pause();
        vm.prank(ORCHESTRATOR);
        vm.expectRevert(Pausable.EnforcedPause.selector);
        VAULT.removeBridgeLiquidity(
            address(USDC),
            bridgeAmount,
            testChainId,
            targets,
            values,
            data
        );
        vm.prank(OWNER);
        VAULT.unpause();

        // Test when called by non-orchestrator
        vm.prank(TRADER);
        vm.expectRevert();
        VAULT.removeBridgeLiquidity(
            address(USDC),
            bridgeAmount,
            testChainId,
            targets,
            values,
            data
        );

        // Test when trying to remove more than available balance
        vm.prank(ORCHESTRATOR);
        vm.expectRevert();
        VAULT.removeBridgeLiquidity(
            address(USDC),
            1 ether,
            testChainId,
            targets,
            values,
            data
        );
    }

    /**
     * @dev Tests the manageToken function
     */
    function testManageToken() public {
        // Setup: Deploy a new test token
        MockERC20 newToken = new MockERC20("New Token", "NTK", 18);

        // Initial checks
        assertFalse(
            VAULT.isTokenSupported(address(newToken)),
            "New token should not be supported initially"
        );

        // Test adding a new token
        vm.prank(OWNER);
        VAULT.setTokenSupported(address(newToken), true);

        assertTrue(
            VAULT.isTokenSupported(address(newToken)),
            "New token should now be supported"
        );

        // Test removing the token
        vm.prank(OWNER);
        VAULT.setTokenSupported(address(newToken), false);

        assertFalse(
            VAULT.isTokenSupported(address(newToken)),
            "New token should no longer be supported"
        );

        // Test removing a token with non-zero balance (should revert)
        // First, add the token back and simulate some balance
        vm.prank(OWNER);
        VAULT.setTokenSupported(address(newToken), true);

        deal(address(newToken), address(EXECUTOR), 101 ether);
        vm.startPrank(address(EXECUTOR));
        newToken.approve(address(VAULT), 101 ether);
        VAULT.addLiquiditySwap(
            keccak256("order"),
            TRADER,
            address(newToken),
            100 ether,
            42,
            uint32(block.timestamp + 200),
            1 ether,
            RECEIVER
        );
        vm.stopPrank();

        // Test managing STABLECOIN (should revert)
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidToken.selector,
                address(USDC)
            )
        );
        VAULT.setTokenSupported(address(USDC), false);
        vm.stopPrank();

        // Test calling from non-owner address (should revert)
        vm.startPrank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector)
        );
        VAULT.setTokenSupported(address(newToken), false);
    }

    function testManageBridge() public {
        address newBridge = makeAddr("newBridge");

        // Initial check
        assertEq(
            VAULT.supportedBridges(newBridge),
            0,
            "Bridge should not be supported initially"
        );

        // Test authorizing a new bridge
        vm.prank(OWNER);
        VAULT.manageBridge(newBridge, true);
        assertEq(
            VAULT.supportedBridges(newBridge),
            1,
            "Bridge should be supported after authorization"
        );

        // Test authorizing an already authorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidTarget.selector,
                newBridge
            )
        );
        VAULT.manageBridge(newBridge, true);

        // Test unauthorizing the bridge
        vm.prank(OWNER);
        VAULT.manageBridge(newBridge, false);
        assertEq(
            VAULT.supportedBridges(newBridge),
            0,
            "Bridge should not be supported after unauthorized"
        );

        // Test unauthorizing an already unauthorized bridge (should revert)
        vm.prank(OWNER);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.InvalidTarget.selector,
                newBridge
            )
        );
        VAULT.manageBridge(newBridge, false);

        // Test calling from non-owner address (should revert)
        vm.prank(TRADER);
        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.IsNotAdmin.selector)
        );
        VAULT.manageBridge(newBridge, true);

        // Test with address(0) as bridge address
        vm.prank(OWNER);
        VAULT.manageBridge(address(0), true);
        assertEq(
            VAULT.supportedBridges(address(0)),
            1,
            "Zero address should be allowed as a bridge"
        );

        vm.prank(OWNER);
        VAULT.manageBridge(address(0), false);
        assertEq(
            VAULT.supportedBridges(address(0)),
            0,
            "Zero address should be removable as a bridge"
        );

        // Test multiple authorizations and unauthorizations
        address[] memory bridges = new address[](3);
        bridges[0] = makeAddr("bridge1");
        bridges[1] = makeAddr("bridge2");
        bridges[2] = makeAddr("bridge3");

        vm.startPrank(OWNER);
        for (uint i = 0; i < bridges.length; i++) {
            VAULT.manageBridge(bridges[i], true);
            assertEq(
                VAULT.supportedBridges(bridges[i]),
                1,
                "Bridge should be supported after authorization"
            );
        }

        for (uint i = 0; i < bridges.length; i++) {
            VAULT.manageBridge(bridges[i], false);
            assertEq(
                VAULT.supportedBridges(bridges[i]),
                0,
                "Bridge should not be supported after unauthorized"
            );
        }
        vm.stopPrank();
    }

    // Add these test functions to the GeniusMultiTokenVaultAccounting contract

    function testCannotAddOrderWithDeadlineAboveMaxOrderTime() public {
        uint32 currentTimestamp = uint32(block.timestamp);
        uint32 invalidDeadline = currentTimestamp +
            uint32(VAULT.maxOrderTime()) +
            1;

        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_000 ether);
        USDC.approve(address(VAULT), 1_000 ether);

        vm.expectRevert(
            abi.encodeWithSelector(GeniusErrors.InvalidDeadline.selector)
        );
        VAULT.addLiquiditySwap(
            keccak256("invalidDeadlineOrder"),
            TRADER,
            address(USDC),
            1_000 ether,
            destChainId,
            invalidDeadline,
            1 ether,
            RECEIVER
        );
        vm.stopPrank();
    }

    function testCannotRevertOrderBeforeRevertBuffer() public {
        // First, add a valid order
        vm.startPrank(address(EXECUTOR));
        deal(address(USDC), address(EXECUTOR), 1_003 ether);
        USDC.approve(address(VAULT), 1_003 ether);
        uint32 validDeadline = uint32(block.timestamp + 100);
        VAULT.addLiquiditySwap(
            keccak256("orderToRevert"),
            TRADER,
            address(USDC),
            1_000 ether,
            destChainId,
            validDeadline,
            3 ether,
            RECEIVER
        );
        vm.stopPrank();

        // Create the order struct
        IGeniusVault.Order memory orderToRevert = IGeniusVault.Order({
            seed: keccak256("orderToRevert"),
            amountIn: 1_000 ether,
            trader: TRADER,
            receiver: RECEIVER,
            srcChainId: uint16(block.chainid),
            destChainId: destChainId,
            fillDeadline: validDeadline,
            tokenIn: address(USDC),
            fee: 3 ether
        });

        // Prepare revert parameters
        address[] memory targets = new address[](1);
        bytes[] memory calldatas = new bytes[](1);
        uint256[] memory values = new uint256[](1);

        targets[0] = address(USDC);
        calldatas[0] = abi.encodeWithSelector(
            USDC.transfer.selector,
            address(this),
            997 ether
        );
        values[0] = 0;

        // Advance time to just after the deadline but before the revert buffer
        vm.warp(validDeadline + 1);

        // Attempt to revert the order
        vm.startPrank(ORCHESTRATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                GeniusErrors.DeadlineNotPassed.selector,
                validDeadline + VAULT.orderRevertBuffer()
            )
        );
        VAULT.revertOrder(orderToRevert, targets, values, calldatas);
        vm.stopPrank();
    }
}
