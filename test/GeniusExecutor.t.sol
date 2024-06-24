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
    address public owner;
    address public trader;
    uint256 private privateKey;
    address public coinReceiver;

    address public quoterAddress = 0xd76019A16606FDa4651f636D9751f500Ed776250;
    address public permit2Address = 0x000000000022D473030F116dDEE9F6B43aC78BA3;
    address payable public routerAddress = payable(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);

    address wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
    address meow = 0x8aD25B0083C9879942A64f00F20a70D3278f6187;

    // External contracts
    TestERC20 public testERC20;

    ERC20 public wavaxContract;
    ERC20 public meowContract;

    PermitSignature public sigUtils;
    IEIP712 public permit2;

    // Internal contracts
    GeniusPool public geniusPool;
    GeniusExecutor public geniusExecutor;
    GeniusVault public geniusVault;

    function setUp() public {
        avalanche = vm.createFork(rpc);
        vm.selectFork(avalanche);
        assertEq(vm.activeFork(), avalanche);

        owner = makeAddr("owner");
        (address traderAddress, uint256 traderKey) = makeAddrAndKey("trader");
        trader = traderAddress;
        privateKey = traderKey;
        coinReceiver = makeAddr("coinReceiver");

        testERC20 = new TestERC20();

        wavaxContract = ERC20(wavax);
        meowContract = ERC20(meow);

        permit2 = IEIP712(permit2Address);
        DOMAIN_SEPERATOR = permit2.DOMAIN_SEPARATOR();
        sigUtils = new PermitSignature();

        vm.prank(owner);
        geniusPool = new GeniusPool(
            address(testERC20),
            0x000000000022D473030F116dDEE9F6B43aC78BA3,
            owner
        );

        vm.prank(owner);
        geniusVault = new GeniusVault(address(testERC20), owner);

        vm.prank(owner);
        geniusPool.initialize(address(geniusVault));

        geniusExecutor = new GeniusExecutor(
            permit2Address,
            address(geniusPool),
            address(geniusVault)
        );

        deal(address(wavaxContract), trader, 100 ether);
        deal(address(meowContract), trader, 100 ether);
        deal(address(testERC20), trader, 100 ether);

        vm.prank(trader);
        wavaxContract.approve(permit2Address, 100 ether);

        vm.prank(trader);
        meowContract.approve(permit2Address, 100 ether);
    }

    function testAggregateWithoutPermit2() public {

        address holderOne = makeAddr("holderOne");
        address holderTwo = makeAddr("holderTwo");

        testERC20.transfer(holderOne, 100 ether);
        testERC20.transfer(holderTwo, 100 ether);

        vm.prank(holderOne);
        testERC20.approve(address(geniusExecutor), 100 ether);

        vm.prank(holderTwo);
        testERC20.approve(address(geniusExecutor), 100 ether);

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_one = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderOne,
            address(geniusExecutor),
            1 ether
        );

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_two = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderTwo,
            address(geniusExecutor),
            2 ether
        );

        // Declare the arrays in memory instead of calldata
        address[] memory targets = new address[](2);
        targets[0] = address(testERC20);
        targets[1] = address(testERC20);

        bytes[] memory data = new bytes[](2);
        data[0] = transferCalldata_one; 
        data[1] = transferCalldata_two; 

        uint256[] memory values = new uint256[](2);
        values[0] = 0; 
        values[1] = 0; 

        geniusExecutor.aggregate(
            targets,
            data,
            values
        );

        assertEq(testERC20.balanceOf(address(geniusExecutor)), 3 ether, "Executor should have 3 test tokens");
        assertEq(testERC20.balanceOf(holderOne), 99 ether, "Holder One should have 97 test tokens");
        assertEq(testERC20.balanceOf(holderTwo), 98 ether, "Holder Two should have 98 test tokens");
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
        targets[0] = address(wavax);
        targets[1] = address(meow);

        bytes[] memory data = new bytes[](2);
        data[0] = transferCalldata_one; 
        data[1] = transferCalldata_two; 

        uint256[] memory values = new uint256[](2);
        values[0] = 0; 
        values[1] = 0; 

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](2);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: wavax,
            amount: 1 ether,
            expiration: 1900000000,
            nonce: 0
        });

        permitDetails[1] = IAllowanceTransfer.PermitDetails({
            token: meow,
            amount: 2 ether,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(geniusExecutor),
            sigDeadline: 1900000000
        });

        bytes memory permitSignature = sigUtils.getPermitBatchSignature(
            permitBatch,
            privateKey,
            DOMAIN_SEPERATOR
        );

        geniusExecutor.aggregateWithPermit2(
            targets,
            data,
            values,
            permitBatch,
            permitSignature,
            trader
        );


        assertEq(wavaxContract.balanceOf(receiverOne), 1 ether, "Receiver One should have 1 wavax");
        assertEq(meowContract.balanceOf(receiverTwo), 2 ether, "Receiver Two should have 2 meow");
        assertEq(wavaxContract.balanceOf(address(geniusExecutor)), 0, "Executor should have no wavax");
        assertEq(meowContract.balanceOf(address(geniusExecutor)), 0, "Executor should have no meow");
        assertEq(wavaxContract.balanceOf(trader), 99 ether, "Trader should have 99 wavax");
        assertEq(meowContract.balanceOf(trader), 98 ether, "Trader should have 98 meow");
    }


    function testTokenSwapAndDeposit() public {
        uint160 transferAmount = 10 ether;  // Define the amount of wavax to swap

        // Approve LBRouter to spend wavax from GeniusExecutor
        vm.prank(trader);
        testERC20.approve(address(permit2), transferAmount);

        address dummyReceiver = makeAddr("dummyReceiver");
        bytes memory transferCalldata = abi.encodeWithSignature(
            "transfer(address,uint256)",
            dummyReceiver,
            5 ether
        );

        // Set up permit details for wavax
        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(testERC20),
            amount: transferAmount,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(geniusExecutor),
            sigDeadline: 1900000000
        });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            privateKey,
            DOMAIN_SEPERATOR
        );

        // Perform the swap and deposit via GeniusExecutor
        geniusExecutor.tokenSwapAndDeposit(
            address(testERC20), // Targeting the LBRouter for the swap
            transferCalldata,
            0, // No ETH value is sent
            permitBatch,
            signature,
            trader
        );

        assertEq(testERC20.balanceOf(address(geniusExecutor)), 0, "Executor should have 0 test tokens");
        assertEq(testERC20.balanceOf(address(geniusPool)), 5 ether, "Executor should have 5 test tokens");
        assertEq(geniusPool.totalAssets(), 5 ether, "Pool should have 5 test tokens available");
        assertEq(geniusPool.availableAssets(), 5 ether, "Pool should have 90% of test tokens available");
        assertEq(geniusPool.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }

    function testNativeSwapAndDeposit() public {
        address target = makeAddr("target");

        testERC20.transfer(target, 10 ether);
        vm.prank(target);
        testERC20.approve(address(geniusExecutor), 10 ether);

        // Encode a transferFrom call to the target address to the executor contract
        bytes memory transferCalldata = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            target,
            address(geniusExecutor),
            10 ether
        );


        geniusExecutor.nativeSwapAndDeposit(
            address(testERC20),
            transferCalldata,
            0,
            trader
        );

        assertEq(testERC20.balanceOf(address(geniusExecutor)), 0, "Executor should have 0 test tokens");
        assertEq(testERC20.balanceOf(address(geniusPool)), 10 ether, "Executor should have 10 test tokens");
        assertEq(geniusPool.totalAssets(), 10 ether, "Pool should have 10 test tokens available");
        assertEq(geniusPool.availableAssets(), 10 ether, "Pool should have 10 test tokens available");
        assertEq(geniusPool.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }


    function testMultiSwapAndDeposit() public {
        address holderOne = makeAddr("holderOne");
        address holderTwo = makeAddr("holderTwo");

        // Create the targets, data, and vlues arrays
        address target = address(testERC20);
        address[] memory targets = new address[](2);
        targets[0] = target;
        targets[1] = target;

        
        uint256[] memory values = new uint256[](2);
        values[0] = 0;
        values[1] = 0;


        testERC20.transfer(trader, 100 ether);
        testERC20.transfer(holderOne, 100 ether);
        testERC20.transfer(holderTwo, 100 ether);

        vm.prank(trader);
        testERC20.approve(address(permit2), 100 ether);

        vm.prank(holderOne);
        testERC20.approve(address(permit2), 100 ether);
        vm.prank(holderOne);
        testERC20.approve(address(geniusExecutor), 100 ether);

        vm.prank(holderTwo);
        testERC20.approve(address(permit2), 100 ether);
        vm.prank(holderTwo);
        testERC20.approve(address(geniusExecutor), 100 ether);

        // Encode a transferFrom call to the target address to the executor contract
        bytes memory transferCalldata_one = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderOne,
            address(geniusExecutor),
            10 ether
        );

        bytes memory transferCalldata_two = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)",
            holderTwo,
            address(geniusExecutor),
            10 ether
        );

        bytes[] memory data = new bytes[](2);
        data[0] = transferCalldata_one;
        data[1] = transferCalldata_two;

        IAllowanceTransfer.PermitDetails[] memory permitDetails = new IAllowanceTransfer.PermitDetails[](1);
        permitDetails[0] = IAllowanceTransfer.PermitDetails({
            token: address(testERC20),
            amount: 100 ether,
            expiration: 1900000000,
            nonce: 0
        });

        IAllowanceTransfer.PermitBatch memory permitBatch = IAllowanceTransfer.PermitBatch({
            details: permitDetails,
            spender: address(geniusExecutor),
            sigDeadline: 1900000000
        });

        bytes memory signature = sigUtils.getPermitBatchSignature(
            permitBatch,
            privateKey,
            DOMAIN_SEPERATOR
        );

        address[] memory routers = new address[](1);
        routers[0] = makeAddr("fakeRouter1");

        uint256 traderBalance = testERC20.balanceOf(trader);

        vm.prank(trader);
        geniusExecutor.multiSwapAndDeposit(
            targets,
            data,
            values,
            routers,
            permitBatch,
            signature,
            trader
        );

        assertEq(testERC20.balanceOf(address(geniusExecutor)), 0, "Executor should have 0 test tokens");
        assertEq(testERC20.balanceOf(address(geniusPool)), 120 ether, "Executor should have 120 test tokens");
        assertEq(testERC20.balanceOf(holderOne), 90 ether, "Holder One should have 90 test tokens");
        assertEq(testERC20.balanceOf(holderTwo), 90 ether, "Holder Two should have 90 test tokens");
        assertEq(testERC20.balanceOf(trader), traderBalance - 100 ether, "Trader should have expected balance");
        assertEq(geniusPool.totalAssets(), 120 ether, "Pool should have 120 test tokens available");
        assertEq(geniusPool.availableAssets(), 120 ether, "Pool should have 120 test tokens available");
        assertEq(geniusPool.totalStakedAssets(), 0, "Pool should have 0 test tokens staked");
    }
}