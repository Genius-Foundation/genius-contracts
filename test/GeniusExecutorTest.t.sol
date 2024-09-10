// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Utils
import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

// Contracts
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

// Interfaces
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAllowanceTransfer, IEIP712 } from "permit2/interfaces/IAllowanceTransfer.sol";

// Mocks
import {TestERC20} from "./mocks/TestERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockDEXRouter} from "./mocks/MockDEXRouter.sol";

/**
 * @title GeniusExecutorTest
 * @dev A contract for testing the GeniusExecutor contract.
 *
 * Note while the executor is meant to be used for batching swaps, within the tests we simply
 *      use transfers to simulate the swap functionality, as all functions are extremely generalized,
 *      and the swap functionality is not the main focus of the tests.
 *
 *      Must use --via-ir flag when running tests to avoid stack too deep error.
 */
contract GeniusExecutorTest is Test {
    // Setup the fork for the Avalanche network
    uint256 avalanche;
    string private rpc = vm.envString("AVALANCHE_RPC_URL");
    bytes32 public DOMAIN_SEPERATOR;

    // All of the addresses used in the tests
    address public OWNER;
    address public TRADER;
    address public ORCHESTRATOR;
    uint256 private PRIVATE_KEY;
    address public RECEIVER;

    address public quoterAddress = 0xd76019A16606FDa4651f636D9751f500Ed776250;
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address payable public routerAddress = payable(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);
    address public feeCollector = makeAddr("feeCollector");

    address WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address MEOW = 0x8aD25B0083C9879942A64f00F20a70D3278f6187;

    address holderOne = makeAddr("holderOne");
    address holderTwo = makeAddr("holderTwo");

    // External contracts
    TestERC20 public USDC;
    TestERC20 public WETH;

    ERC20 public wavaxContract;
    ERC20 public meowContract;

    MockSwapTarget public ROUTER;

    PermitSignature public sigUtils;
    IEIP712 public permit2;

    // Internal contracts
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("owner");
        (address traderAddress, uint256 traderKey) = makeAddrAndKey("TRADER");
        TRADER = traderAddress;
        PRIVATE_KEY = traderKey;
        RECEIVER = makeAddr("RECEIVER");
        ORCHESTRATOR = makeAddr("orchestrator");

        USDC = new TestERC20();
        WETH = new TestERC20();
        ROUTER = new MockSwapTarget();

        wavaxContract = ERC20(WAVAX);
        meowContract = ERC20(MEOW);

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        vm.prank(OWNER);
        GeniusVault implementation = new GeniusVault();

        bytes memory data = abi.encodeWithSelector(
            GeniusVault.initialize.selector,
            address(USDC),
            OWNER
        );

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), data);

        VAULT = GeniusVault(address(proxy));

        vm.startPrank(OWNER);

        EXECUTOR = new GeniusExecutor(
            permit2Address,
            address(VAULT),
            OWNER,
            new address[](0)
        );

        VAULT.setExecutor(address(EXECUTOR));

        EXECUTOR.setAllowedTarget(address(EXECUTOR), true);
        vm.stopPrank();

        vm.startPrank(OWNER);

        VAULT.grantRole(VAULT.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.grantRole(EXECUTOR.ORCHESTRATOR_ROLE(), ORCHESTRATOR);
        EXECUTOR.setAllowedTarget(address(ROUTER), true);
        vm.stopPrank();

        deal(address(wavaxContract), TRADER, 100 ether);
        deal(address(meowContract), TRADER, 100 ether);
        deal(address(USDC), TRADER, 100 ether);

        vm.prank(TRADER);
        wavaxContract.approve(permit2Address, 100 ether);

        vm.prank(TRADER);
        meowContract.approve(permit2Address, 100 ether);

        vm.prank(TRADER);
        USDC.approve(permit2Address, 1_000 ether);

        vm.prank(TRADER);
        VAULT.approve(permit2Address, 1_000 ether);


    }

    function testAggregateWithoutPermit2() public {
        USDC.transfer(holderOne, 100 ether);
        USDC.transfer(holderTwo, 100 ether);

        // !!!! NEVER DO THIS ON DEPLOYED CODE
        vm.prank(holderOne);
        USDC.approve(address(EXECUTOR), 100 ether);

        vm.prank(holderTwo);
        USDC.approve(address(EXECUTOR), 100 ether);

        // Set up MockDEXRouter
        MockDEXRouter mockRouter = new MockDEXRouter();
        
        // Add MockDEXRouter to the list of approved routers
        vm.prank(OWNER);
        EXECUTOR.setAllowedTarget(address(mockRouter), true);

        // Approve MockDEXRouter to spend USDC on behalf of EXECUTOR
        vm.prank(address(EXECUTOR));
        USDC.approve(address(mockRouter), type(uint256).max);

        // Create call data for swaps
        bytes memory swap_one = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            1 ether
        );

        bytes memory swap_two = abi.encodeWithSignature(
            "swap(address,address,uint256)",
            address(USDC),
            address(WETH),
            2 ether
        );

        // Declare the arrays in memory
        address[] memory targets = new address[](2);
        targets[0] = address(mockRouter);
        targets[1] = address(mockRouter);

        bytes[] memory data = new bytes[](2);
        data[0] = swap_one; 
        data[1] = swap_two;

        uint256[] memory values = new uint256[](2);
        values[0] = 0; 
        values[1] = 0; 

        EXECUTOR.aggregate(
            targets,
            data,
            values
        );

        // Check balances
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 USDC");
        assertEq(USDC.balanceOf(holderOne), 100 ether, "Holder One should still have 100 USDC");
        assertEq(USDC.balanceOf(holderTwo), 100 ether, "Holder Two should still have 100 USDC");

        // Verify that the mock swaps occurred
        address mockWETHAddress = mockRouter.mockTokens(address(WETH));
        assertEq(mockWETHAddress != address(0), true, "Mock WETH token should have been created");
        assertEq(MockERC20(mockWETHAddress).balanceOf(address(EXECUTOR)), mockRouter.MINT_AMOUNT() * 2, "Executor should have received mock WETH");

        // Verify that the MockDEXRouter didn't receive any USDC
        assertEq(USDC.balanceOf(address(mockRouter)), 0, "MockDEXRouter should not have received any USDC");

        // Verify that the correct amount of mock WETH was minted
        assertEq(MockERC20(mockWETHAddress).totalSupply(), mockRouter.MINT_AMOUNT() * 2, "Total supply of mock WETH should be MINT_AMOUNT * 2");
    }

    function testAggregateWithPermit2() public {

        address receiverOne = makeAddr("fakeReceiverOne");
        address receiverTwo = makeAddr("fakeReceiverTwo");

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_one = abi.encodeWithSignature(
            "transfer(address,uint256)",
            receiverOne,
            1 ether
        );

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_two = abi.encodeWithSignature(
            "transfer(address,uint256)",
            receiverTwo,
            2 ether
        );

        // Declare the arrays in memory instead of calldata
        address[] memory targets = new address[](2);
        targets[0] = address(WAVAX);
        targets[1] = address(MEOW);

        bytes[] memory data = new bytes[](2);
        data[0] = transferCalldata_one; 
        data[1] = transferCalldata_two; 

        uint256[] memory values = new uint256[](2);
        values[0] = 0; 
        values[1] = 0; 

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](2);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: WAVAX,
            amount: 1 ether,
            expiration: 1900000000,
            nonce: 0
        });

        permitDetails[1] = IAllowanceTransfer.PermitDetails({
            token: MEOW,
            amount: 2 ether,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        EXECUTOR.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            TRADER
        );


        assertEq(wavaxContract.balanceOf(receiverOne), 1 ether, "Receiver One should have 1 WAVAX");
        assertEq(meowContract.balanceOf(receiverTwo), 2 ether, "Receiver Two should have 2 MEOW");
        assertEq(wavaxContract.balanceOf(address(EXECUTOR)), 0, "Executor should have no WAVAX");
        assertEq(meowContract.balanceOf(address(EXECUTOR)), 0, "Executor should have no MEOW");
        assertEq(wavaxContract.balanceOf(TRADER), 99 ether, "Trader should have 99 WAVAX");
        assertEq(meowContract.balanceOf(TRADER), 98 ether, "Trader should have 98 MEOW");
    }


    function testTokenSwapAndDeposit() public {
        uint32 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        uint160 transferAmount = 10 ether;  // Define the amount of WAVAX to swap

        // Approve LBRouter to spend WAVAX from GeniusExecutor
        vm.prank(TRADER);
        USDC.approve(address(permit2), transferAmount);
        USDC.approve(address(EXECUTOR), transferAmount);
        USDC.transfer(address(ROUTER), transferAmount);

        bytes memory swapCalldata = abi.encodeWithSelector(
            MockSwapTarget.mockSwap.selector,
            address(wavaxContract),
            transferAmount,
            address(USDC),
            address(EXECUTOR),
            transferAmount / 2
        );

        // Set up permit details for WAVAX
        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(wavaxContract),
            amount: transferAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the swap and deposit via GeniusExecutor
        vm.startPrank(ORCHESTRATOR);
        EXECUTOR.tokenSwapAndDeposit(
            keccak256("order"),
            address(ROUTER), // Targeting the LBRouter for the swap
            swapCalldata,
            permitBatch,
            signature,
            TRADER,
            destChainId,
            fillDeadline,
            1 ether
        );
        vm.stopPrank();

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(VAULT)), 5 ether, "Executor should have 4 test tokens");
        assertEq(VAULT.stablecoinBalance(), 5 ether, "Vault should have 4 test tokens available");
        assertEq(VAULT.availableAssets(), 0 ether, "Vault should have 0% of test tokens available");
        assertEq(VAULT.reservedAssets(), 5 ether, "Vault should have 100% of tokens reserved");
        assertEq(VAULT.totalStakedAssets(), 0, "Vault should have 0 test tokens staked");
    }

    function testNativeSwapAndDeposit() public {
        uint16 destChainId = 42;
        uint32 fillDeadline = uint32(block.timestamp + 1000);

        vm.startPrank(OWNER);
        MockDEXRouter dexRouter = new MockDEXRouter();
        EXECUTOR.setAllowedTarget(address(dexRouter), true);
        deal(address(USDC), address(dexRouter), 100 ether);
        vm.deal(address(this), 1 ether);
        vm.stopPrank();

        bytes memory swapData = abi.encodeWithSelector(
            MockDEXRouter.swapToStables.selector,
            address(USDC)
        );

        EXECUTOR.nativeSwapAndDeposit{value: 1 ether}(
            keccak256("order"),
            address(dexRouter),
            swapData,
            1 ether,
            destChainId,
            fillDeadline,
            1 ether
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(VAULT)), 50 ether, "Executor should have 10 test tokens");
        assertEq(VAULT.stablecoinBalance(), 50 ether, "Vault should have 10 test tokens available");
        assertEq(VAULT.availableAssets(), 0 ether, "Vault should have 0 test tokens available");
        assertEq(VAULT.reservedAssets(), 50 ether, "Vault should have 0 test tokens staked");
        assertEq(VAULT.totalStakedAssets(), 0, "Vault should have 0 test tokens staked");
    }


    function testMultiSwapAndDeposit() public {

        // Create the targets, data, and vlues arrays
        address target = address(USDC);
        address[] memory targets = new address[](2);
        targets[0] = target;
        targets[1] = target;

        
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;


        USDC.transfer(TRADER, 100 ether);
        USDC.transfer(holderOne, 100 ether);
        USDC.transfer(holderTwo, 100 ether);

        vm.prank(TRADER);
        USDC.approve(address(permit2), 100 ether);

        vm.prank(holderOne);
        USDC.approve(address(permit2), 100 ether);
        vm.prank(holderOne);
        USDC.approve(address(EXECUTOR), 100 ether);

        vm.prank(holderTwo);
        USDC.approve(address(permit2), 100 ether);
        vm.prank(holderTwo);
        USDC.approve(address(EXECUTOR), 100 ether);

        // Encode a transferFrom call to the target address to the executor contract
        bytes memory transferCalldata_one = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderOne,
            address(EXECUTOR),
            10 ether
        );

        bytes memory transferCalldata_two = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderTwo,
            address(EXECUTOR),
            10 ether
        );

        bytes[] memory data = new bytes[](2);
        data[0] = transferCalldata_one;
        data[1] = transferCalldata_two;

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(USDC),
            amount: 100 ether,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(EXECUTOR),
            sigDeadline: 1900000000
        });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        address[] memory routers = new address[](1);
        routers[0] = makeAddr("fakeRouter1");

        uint256 traderBalance = USDC.balanceOf(TRADER);

        vm.prank(TRADER);
        EXECUTOR.multiSwapAndDeposit(
            keccak256("order"),
            targets,
            data,
            values,
            permitBatch,
            signature,
            TRADER,
            42,
            uint32(block.timestamp + 1000),
            1 ether
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(VAULT)), 120 ether, "Executor should have 120 test tokens");
        assertEq(USDC.balanceOf(holderOne), 90 ether, "Holder One should have 90 test tokens");
        assertEq(USDC.balanceOf(holderTwo), 90 ether, "Holder Two should have 90 test tokens");
        assertEq(USDC.balanceOf(TRADER), traderBalance - 100 ether, "Trader should have expected balance");
        assertEq(VAULT.stablecoinBalance(), 120 ether, "Vault should have 120 test tokens available");
        assertEq(VAULT.availableAssets(), 0 ether, "Vault should have 120 test tokens available");
        assertEq(VAULT.totalStakedAssets(), 0, "Vault should have 0 test tokens staked");
        assertEq(VAULT.reservedAssets(), 120 ether, "Vault should have 0 test tokens reserved");
    }

    function testDepositToVault() public {
        uint160 depositAmount = 10 ether;

        // Set up initial balances
        deal(address(USDC), TRADER, 100 ether);
        
        vm.startPrank(TRADER);
        USDC.approve(address(permit2), 100 ether);
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

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit via GeniusExecutor
        vm.prank(ORCHESTRATOR);
        EXECUTOR.depositToVault(
            permitBatch,
            signature,
            TRADER
        );

        // Assert the results
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 USDC");
        assertEq(VAULT.stablecoinBalance(), depositAmount, "Vault should have received the deposit");
        assertEq(VAULT.balanceOf(TRADER), depositAmount, "Trader should have received vault shares");
        assertEq(USDC.balanceOf(TRADER), 90 ether, "Trader should have 90 USDC left");
    }

    function testWithdrawFromVault() public {
        uint160 depositAmount = 10 ether;
        uint160 withdrawAmount = 1 ether;

        // First, deposit to the vault
        deal(address(USDC), TRADER, 100 ether);
        
        vm.startPrank(TRADER);
        USDC.approve(address(permit2), 100 ether);
        USDC.approve(address(EXECUTOR), 100 ether);
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

        bytes memory depositSignature = sigUtils.getPermitBatchSignature(
            depositPermitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit
        vm.startPrank(ORCHESTRATOR);
        EXECUTOR.depositToVault( depositPermitBatch, depositSignature, TRADER);
        VAULT.approve(address(EXECUTOR), VAULT.balanceOf(TRADER));
        
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

        bytes memory withdrawSignature = sigUtils.getPermitBatchSignature(
            withdrawPermitBatch,
            PRIVATE_KEY,
            DOMAIN_SEPERATOR
        );

        // Perform the withdrawal via GeniusExecutor

        EXECUTOR.withdrawFromVault(
            withdrawPermitBatch,
            withdrawSignature,
            TRADER
        );
        vm.stopPrank();

        // Assert the results
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 USDC");
        assertEq(USDC.balanceOf(address(VAULT)), 9 ether, "Vault should have remaining USDC");
        assertEq(VAULT.balanceOf(TRADER), 9 ether, "Trader should have remaining vault shares");
        assertEq(USDC.balanceOf(TRADER), 91 ether, "Trader should have received withdrawn USDC");
    }

}