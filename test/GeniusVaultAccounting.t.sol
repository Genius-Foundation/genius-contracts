// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAllowanceTransfer, IEIP712} from "permit2/interfaces/IAllowanceTransfer.sol";
import {PermitSignature} from "./utils/SigUtils.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GeniusVault} from "../src/GeniusVault.sol";
import {GeniusExecutor} from "../src/GeniusExecutor.sol";

import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

contract GeniusVaultAccounting is Test {
    // ============ Network ============
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");

    uint32 destChainId = 42;
    uint256 depositAmount = 100 ether;

    // ============ External Contracts ============
    ERC20 public USDC = ERC20(0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
    ERC20 public TEST_TOKEN;
    
    // ============ Internal Contracts ============
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;
    MockDEXRouter public DEX_ROUTER;

    // ============ Constants ============
    address public PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address public feeCollecter = makeAddr("feeCollector");
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;

        // Add new variables for Permit2
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    IEIP712 public permit2 = IEIP712(permit2Address);
    PermitSignature public sigUtils;
    uint256 private privateKey;
    uint48 public nonce;
    bytes32 public DOMAIN_SEPERATOR;

    // Add new function for generating Permit2 batch and signature
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

    // ============ Helper Functions ============
    function donateAndAssert(uint256 expectedTotalStaked, uint256 expectedTotal, uint256 expectedAvailable, uint256 expectedMin) internal {
        USDC.transfer(address(VAULT), 10 ether);
        assertEq(VAULT.totalStakedAssets(), expectedTotalStaked, "Total staked assets mismatch after donation");
        assertEq(VAULT.stablecoinBalance(), expectedTotal, "Total assets mismatch after donation");
        assertEq(VAULT.availableAssets(), expectedAvailable, "Available assets mismatch after donation");
        assertEq(VAULT.minAssetBalance(), expectedMin, "Minimum asset balance mismatch after donation");
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
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));
        EXECUTOR = new GeniusExecutor(PERMIT2, address(VAULT), OWNER, new address[](0));
        DEX_ROUTER = new MockDEXRouter();
        

        VAULT.setExecutor(address(EXECUTOR));

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        TRADER = traderAddress;
        privateKey = traderKey;
        
        // Add Orchestrator
        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);

        vm.stopPrank();

        // Provide USDC to TRADER and ORCHESTRATOR
        deal(address(USDC), TRADER, 1_000 ether);
        deal(address(USDC), ORCHESTRATOR, 1_000 ether);
        deal(address(USDC), address(this), 1_000 ether);
    }


    /**
     * @dev This function is a test function that checks the staked values in the GeniusVaultAccounting contract.
     * It performs the following steps:
     * 1. Starts a prank with the TRADER address.
     * 2. Approves USDC to be spent by the VAULT contract.
     * 3. Deposits 100 USDC into the VAULT contract.
     * 5. Calls the logValues function to log the staked values.
     * 6. Asserts the staked values to ensure they match the expected values.
     */
    function testStakedValues() public {
        vm.startPrank(TRADER);

        // Approve USDC to be spent by the vault
        USDC.approve(address(VAULT), 1_000 ether);

        // Deposit 100 USDC into the vault
        VAULT.stakeDeposit(100 ether, TRADER);

        // Check the staked value
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(VAULT.totalStakedAssets(), VAULT.stablecoinBalance(), "Total staked assets and total assets mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank(); // Stop acting as TRADER
    }


    /**
     * @dev This function tests the threshold change functionality of the GeniusVaultAccounting contract.
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
        VAULT.stakeDeposit(100 ether, TRADER);

        // Check the staked value
        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 100 ether, "Total assets mismatch");
        assertEq(VAULT.totalStakedAssets(), VAULT.stablecoinBalance(), "Total staked assets and total assets mismatch");
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
        assertEq(VAULT.totalStakedAssets(), VAULT.stablecoinBalance(), "Total staked assets and total assets mismatch");
        assertEq(VAULT.availableAssets(), 10 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");
    }

    /**
     * @dev This function is used to test the stake and deposit functionality.
     * It starts by acting as a TRADER, approves the transfer of USDC tokens to the VAULT contract,
     * and then deposits 100 ether into the VAULT contract.
     * It asserts the expected values for total staked assets, total assets, and available assets.
     * After that, it stops acting as a TRADER, approves the transfer of USDC tokens to the VAULT contract,
     * and adds liquidity swap for 100 ether.
     * and logs these values using the logValues function.
     * Finally, it asserts the expected values for total staked assets, total assets, available assets,
     * and minimum asset balance.
     */
    function testStakeAndDeposit() public {

        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Start acting as TRADER
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), depositAmount);
        USDC.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(depositAmount, TRADER);

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), depositAmount, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        vm.stopPrank();

        // Swap and deposit using EXECUTOR
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for USDC
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(depositAmount);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TEST_TOKEN),  // Using testToken as the input token
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        deal(address(USDC), address(DEX_ROUTER), depositAmount);
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

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 124 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");
    }

    /**
     * @dev This function tests the cycle without threshold change in the GeniusVaultAccounting contract.
     * It performs a series of actions such as depositing assets into the vault, adding liquidity to the vault,
     * withdrawing assets from the vault, and checking the balances of various variables and contracts.
     * It also logs the ending balances of key variables for further analysis.
     */
    function testCycleWithoutThresholdChange() public {
        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Start acting as TRADER
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), depositAmount);
        USDC.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(depositAmount, TRADER);

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");
        vm.stopPrank();

        // Swap and deposit using EXECUTOR
        vm.startPrank(ORCHESTRATOR);
        
        // Generate permit details for USDC
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(depositAmount);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TEST_TOKEN),  // Using testToken as the input token
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        // deal(address(testToken), address(EXECUTOR), depositAmount);
        deal(address(USDC), address(DEX_ROUTER), depositAmount);
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

        assertEq(VAULT.totalStakedAssets(), 100 ether, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 124 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Start acting as TRADER
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(depositAmount, TRADER, TRADER);

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 49 ether, "Available assets mismatch");

        vm.stopPrank();
    }

    /**
     * @dev This function tests the full cycle of depositing assets through a vault, adding liquidity to a vault,
     * changing the rebalance threshold, and withdrawing assets from the vault.
     * It performs the following steps:
     * 1. Deposits 100 ether into the vault.
     * 2. Checks the total staked assets, total assets, available assets, and minimum asset balance of the vault.
     * 3. Adds liquidity of 100 ether to the vault.
     * 4. Checks the total staked assets, total assets, available assets, and minimum asset balance of the vault.
     * 5. Changes the rebalance threshold of the vault to 10.
     * 6. Checks the total staked assets, total assets, available assets, and minimum asset balance of the vault.
     * 7. Withdraws 100 ether from the vault.
     * 8. Checks the total staked assets, total assets, available assets, and minimum asset balance of the vault.
     * 9. Logs the ending balances of the vault and vault.
     */
    function testFullCycle() public {

        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), depositAmount);
        USDC.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(depositAmount, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 75 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for USDC
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(depositAmount);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TEST_TOKEN),  // Using testToken as the input token
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        deal(address(USDC), address(DEX_ROUTER), depositAmount);
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

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 124 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 150 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 59 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(depositAmount, TRADER, TRADER);

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 49 ether, "Available assets mismatch");

        vm.stopPrank();
    } 

        /**
         * @dev This function tests the full cycle of a GeniusVaultAccounting contract with donations.
         * It performs the following steps:
         * 1. Makes an initial donation.
         * 2. Deposits assets into the vault.
         * 3. Adds liquidity to the vault.
         * 4. Changes the rebalance threshold.
         * 5. Withdraws assets from the vault.
         * 6. Logs the final state of the contract.
         */
    function testFullCycleWithDonations() public {

        // Setup
        vm.startPrank(OWNER);
        EXECUTOR.setAllowedTarget(address(DEX_ROUTER), true);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        vm.stopPrank();

        // Initial donation
        donateAndAssert(0, 10 ether, 10 ether, 0);

        // =================== DEPOSIT THROUGH VAULT ===================
        vm.startPrank(TRADER);
        USDC.approve(address(VAULT), depositAmount);
        USDC.approve(permit2Address, type(uint256).max);
        VAULT.stakeDeposit(depositAmount, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.totalStakedAssets(), depositAmount, "Vault Total assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 110 ether, "Vault Total assets mismatch");
        assertEq(VAULT.availableAssets(), 85 ether, "#1 Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Donate +10 before adding liquidity
        donateAndAssert(100 ether, 120 ether, 95 ether, 25 ether);

        // =================== SWAP AND DEPOSIT ===================
        vm.startPrank(ORCHESTRATOR);

        // Generate permit details for USDC
        address[] memory tokens = new address[](1);
        tokens[0] = address(USDC);

        uint160[] memory amounts = new uint160[](1);
        amounts[0] = uint160(depositAmount);

        (IAllowanceTransfer.PermitBatch memory permitBatch, bytes memory signature) = generatePermitBatchAndSignature(
            address(EXECUTOR),
            tokens,
            amounts
        );

        // Create the calldata for the tokenSwapAndDeposit function
        bytes memory calldataSwap = abi.encodeWithSignature(
            "swapERC20ToStables(address,address)",
            address(TEST_TOKEN),  // Using testToken as the input token
            address(USDC)
        );

        // Execute the tokenSwapAndDeposit function
        deal(address(USDC), address(DEX_ROUTER), depositAmount);
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

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 170 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 144 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 25 ether, "Minimum asset balance mismatch");

        // Donate + 10 before changing threshold
        donateAndAssert(100 ether, 180 ether, 154 ether, 25 ether);

        // =================== CHANGE THRESHOLD ===================
        vm.startPrank(OWNER);
        VAULT.setRebalanceThreshold(10);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), depositAmount, "Total staked assets mismatch");
        assertEq(VAULT.stablecoinBalance(), 180 ether, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 89 ether, "Available assets mismatch");
        assertEq(VAULT.minAssetBalance(), 90 ether, "Minimum asset balance mismatch");

        // Donate +10 before withdrawing
        donateAndAssert(100 ether, 190 ether, 99 ether, 90 ether);

        // =================== WITHDRAW FROM VAULT ===================
        vm.startPrank(TRADER);
        VAULT.stakeWithdraw(depositAmount, TRADER, TRADER);
        vm.stopPrank();

        assertEq(VAULT.totalStakedAssets(), 0, "Total staked assets does not equal 0");
        assertEq(VAULT.totalStakedAssets(), 0, "Total assets mismatch");
        assertEq(VAULT.availableAssets(), 89 ether, "Available assets mismatch");
    }
}

