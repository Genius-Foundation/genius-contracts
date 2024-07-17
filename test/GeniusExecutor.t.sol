// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Utils
import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

// Contracts
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

// Interfaces
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAllowanceTransfer, IEIP712 } from "permit2/interfaces/IAllowanceTransfer.sol";

// Mocks
import {TestERC20} from "./mocks/TestERC20.sol";
import {MockSwapTarget} from "./mocks/MockSwapTarget.sol";

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
    address public trader;
    uint256 private privateKey;
    address public coinReceiver;

    address public quoterAddress = 0xd76019A16606FDa4651f636D9751f500Ed776250;
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address payable public routerAddress = payable(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);

    address WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address MEOW = 0x8aD25B0083C9879942A64f00F20a70D3278f6187;

    // External contracts
    TestERC20 public USDC;
    TestERC20 public WETH;

    ERC20 public wavaxContract;
    ERC20 public meowContract;

    MockSwapTarget public ROUTER;

    PermitSignature public sigUtils;
    IEIP712 public permit2;

    // Internal contracts
    GeniusPool public POOL;
    GeniusVault public VAULT;
    GeniusExecutor public EXECUTOR;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        OWNER = makeAddr("owner");
        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        trader = traderAddress;
        privateKey = traderKey;
        coinReceiver = makeAddr("coinReceiver");

        USDC = new TestERC20();
        WETH = new TestERC20();
        ROUTER = new MockSwapTarget();

        wavaxContract = ERC20(WAVAX);
        meowContract = ERC20(MEOW);

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        vm.prank(OWNER);
        POOL = new GeniusPool(
            address(USDC),
            OWNER
        );

        vm.startPrank(OWNER);
        VAULT = new GeniusVault(address(USDC), OWNER);

        EXECUTOR = new GeniusExecutor(
            permit2Address,
            address(POOL),
            address(VAULT),
            OWNER
        );

        POOL.initialize(address(VAULT), address(EXECUTOR));
        vm.stopPrank();

        vm.startPrank(OWNER);
        VAULT.initialize(address(POOL));

        address[] memory routers = new address[](1);
        routers[0] = address(ROUTER);

        EXECUTOR.initialize(routers);
        vm.stopPrank();

        deal(address(wavaxContract), trader, 100 ether);
        deal(address(meowContract), trader, 100 ether);
        deal(address(USDC), trader, 100 ether);

        vm.prank(trader);
        wavaxContract.approve(permit2Address, 100 ether);

        vm.prank(trader);
        meowContract.approve(permit2Address, 100 ether);

        vm.prank(trader);
        USDC.approve(permit2Address, 1_000 ether);

        vm.prank(trader);
        VAULT.approve(permit2Address, 1_000 ether);


    }

    function testAggregateWithoutPermit2() public {

        address holderOne = makeAddr("holderOne");
        address holderTwo = makeAddr("holderTwo");

        USDC.transfer(holderOne, 100 ether);
        USDC.transfer(holderTwo, 100 ether);

        vm.prank(holderOne);
        USDC.approve(address(EXECUTOR), 100 ether);

        vm.prank(holderTwo);
        USDC.approve(address(EXECUTOR), 100 ether);

        address LP = makeAddr("fakeLP");
        WETH.transfer(LP, 100 ether);

        vm.startPrank(LP);
        WETH.approve(address(ROUTER), 100 ether);




        // Create call data for swapExactNATIVEForTokens
        bytes memory mockSwap_one = abi.encodeWithSignature(
            "mockSwap(address tokenIn, uint256 amountIn, address tokenOut, address poolAddress, uint256 amountOut)",
            address(USDC),
            1 ether,
            address(WETH),
            address(LP),
            1 ether
        );

        // Create call data for swapExactNATIVEForTokens
        bytes memory mockSwap_two = abi.encodeWithSignature(
            "mockSwap(address tokenIn, uint256 amountIn, address tokenOut, address poolAddress, uint256 amountOut)",
            address(USDC),
            2 ether,
            address(WETH),
            address(LP),
            2 ether
        );

        // Declare the arrays in memory instead of calldata
        address[] memory targets = new address[](2);
        targets[0] = address(ROUTER);
        targets[1] = address(ROUTER);

        bytes[] memory data = new bytes[](2);
        data[0] = mockSwap_one; 
        data[1] = mockSwap_two;

        uint256[] memory values = new uint256[](2);
        values[0] = 0; 
        values[1] = 0; 

        EXECUTOR.aggregate(
            targets,
            data,
            values
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 3 ether, "Executor should have 3 test tokens");
        assertEq(USDC.balanceOf(holderOne), 99 ether, "Holder One should have 97 test tokens");
        assertEq(USDC.balanceOf(holderTwo), 98 ether, "Holder Two should have 98 test tokens");
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
            privateKey,
            DOMAIN_SEPERATOR
        );

        EXECUTOR.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            trader
        );


        assertEq(wavaxContract.balanceOf(receiverOne), 1 ether, "Receiver One should have 1 WAVAX");
        assertEq(meowContract.balanceOf(receiverTwo), 2 ether, "Receiver Two should have 2 MEOW");
        assertEq(wavaxContract.balanceOf(address(EXECUTOR)), 0, "Executor should have no WAVAX");
        assertEq(meowContract.balanceOf(address(EXECUTOR)), 0, "Executor should have no MEOW");
        assertEq(wavaxContract.balanceOf(trader), 99 ether, "Trader should have 99 WAVAX");
        assertEq(meowContract.balanceOf(trader), 98 ether, "Trader should have 98 MEOW");
    }


    function testTokenSwapAndDeposit() public {
        uint160 transferAmount = 10 ether;  // Define the amount of WAVAX to swap

        // Approve LBRouter to spend WAVAX from GeniusExecutor
        vm.prank(trader);
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
            privateKey,
            DOMAIN_SEPERATOR
        );

        // Perform the swap and deposit via GeniusExecutor
        EXECUTOR.tokenSwapAndDeposit(
            address(ROUTER), // Targeting the LBRouter for the swap
            swapCalldata,
            permitBatch,
            signature,
            trader
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(POOL)), 5 ether, "Executor should have 5 test tokens");
        assertEq(POOL.totalAssets(), 5 ether, "Pool should have 5 test tokens available");
        assertEq(POOL.availableAssets(), 5 ether, "Pool should have 90% of test tokens available");
        assertEq(POOL.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }

    function testNativeSwapAndDeposit() public {
        address target = makeAddr("target");

        USDC.transfer(target, 10 ether);
        vm.prank(target);
        USDC.approve(address(EXECUTOR), 10 ether);

        // Encode a transferFrom call to the target address to the executor contract
        bytes memory transferCalldata = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            target,
            address(EXECUTOR),
            10 ether
        );


        EXECUTOR.nativeSwapAndDeposit(
            address(USDC),
            transferCalldata,
            0
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(POOL)), 10 ether, "Executor should have 10 test tokens");
        assertEq(POOL.totalAssets(), 10 ether, "Pool should have 10 test tokens available");
        assertEq(POOL.availableAssets(), 10 ether, "Pool should have 10 test tokens available");
        assertEq(POOL.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }


    function testMultiSwapAndDeposit() public {
        address holderOne = makeAddr("holderOne");
        address holderTwo = makeAddr("holderTwo");

        // Create the targets, data, and vlues arrays
        address target = address(USDC);
        address[] memory targets = new address[](2);
        targets[0] = target;
        targets[1] = target;

        
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;


        USDC.transfer(trader, 100 ether);
        USDC.transfer(holderOne, 100 ether);
        USDC.transfer(holderTwo, 100 ether);

        vm.prank(trader);
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
            privateKey,
            DOMAIN_SEPERATOR
        );

        address[] memory routers = new address[](1);
        routers[0] = makeAddr("fakeRouter1");

        uint256 traderBalance = USDC.balanceOf(trader);

        vm.prank(trader);
        EXECUTOR.multiSwapAndDeposit(
            targets,
            data,
            values,
            routers,
            permitBatch,
            signature,
            trader
        );

        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 test tokens");
        assertEq(USDC.balanceOf(address(POOL)), 120 ether, "Executor should have 120 test tokens");
        assertEq(USDC.balanceOf(holderOne), 90 ether, "Holder One should have 90 test tokens");
        assertEq(USDC.balanceOf(holderTwo), 90 ether, "Holder Two should have 90 test tokens");
        assertEq(USDC.balanceOf(trader), traderBalance - 100 ether, "Trader should have expected balance");
        assertEq(POOL.totalAssets(), 120 ether, "Pool should have 120 test tokens available");
        assertEq(POOL.availableAssets(), 120 ether, "Pool should have 120 test tokens available");
        assertEq(POOL.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }

    function testDepositToVault() public {
        uint160 depositAmount = 10 ether;

        // Set up initial balances
        deal(address(USDC), trader, 100 ether);
        
        vm.startPrank(trader);
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
            privateKey,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit via GeniusExecutor
        vm.prank(trader);
        EXECUTOR.depositToVault(
            permitBatch,
            signature,
            trader
        );

        // Assert the results
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 USDC");
        assertEq(VAULT.totalAssets(), depositAmount, "Vault should have received the deposit");
        assertEq(VAULT.balanceOf(trader), depositAmount, "Trader should have received vault shares");
        assertEq(USDC.balanceOf(trader), 90 ether, "Trader should have 90 USDC left");
    }

    function testWithdrawFromVault() public {
        uint160 depositAmount = 10 ether;
        uint160 withdrawAmount = 1 ether;

        // First, deposit to the vault
        deal(address(USDC), trader, 100 ether);
        
        vm.startPrank(trader);
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
            privateKey,
            DOMAIN_SEPERATOR
        );

        // Perform the deposit
        vm.startPrank(trader);
        EXECUTOR.depositToVault( depositPermitBatch, depositSignature, trader);
        VAULT.approve(address(EXECUTOR), VAULT.balanceOf(trader));
        
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
            privateKey,
            DOMAIN_SEPERATOR
        );
        vm.stopPrank();

        // Perform the withdrawal via GeniusExecutor
        EXECUTOR.withdrawFromVault(
            withdrawPermitBatch,
            withdrawSignature,
            trader
        );

        // Assert the results
        assertEq(USDC.balanceOf(address(EXECUTOR)), 0, "Executor should have 0 USDC");
        assertEq(USDC.balanceOf(address(POOL)), 9 ether, "Pool should have remaining USDC");
        assertEq(VAULT.balanceOf(trader), 9 ether, "Trader should have remaining vault shares");
        assertEq(USDC.balanceOf(trader), 91 ether, "Trader should have received withdrawn USDC");
    }

}