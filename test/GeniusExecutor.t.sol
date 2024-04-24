// // SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Utils
import {Test, console} from "forge-std/Test.sol";
import {PermitSignature} from "./utils/SigUtils.sol";

// Contracts
import {GeniusExecutor} from "../src/GeniusExecutor.sol";
import {GeniusPool} from "../src/GeniusPool.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

// DEX contracts
import {LBQuoter} from "joe-v2/LBQuoter.sol";
import {LBRouter} from "joe-v2/LBRouter.sol";

// Interfaces
import {ILBRouter} from "joe-v2/interfaces/ILBRouter.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IAllowanceTransfer, IEIP712 } from "permit2/interfaces/IAllowanceTransfer.sol";

// Mocks
import {TestERC20} from "./mocks/TestERC20.sol";


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
    LBRouter public lbRouter;
    LBQuoter public lbQuoter;
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

        lbRouter = LBRouter(routerAddress);
        lbQuoter = LBQuoter(quoterAddress);
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
        geniusVault = new GeniusVault(address(testERC20));

        vm.prank(owner);
        geniusPool.initialize(address(geniusVault));

        geniusExecutor = new GeniusExecutor(
            permit2Address,
            address(geniusPool)
        );

        deal(address(wavaxContract), trader, 100 ether);
        deal(address(meowContract), trader, 100 ether);
        deal(address(testERC20), trader, 100 ether);

        vm.prank(trader);
        wavaxContract.approve(permit2Address, 100 ether);

        vm.prank(trader);
        meowContract.approve(permit2Address, 100 ether);
    }

    function testAggregateWithPermit2() public {

        uint128 amountInOne = 1 ether;
        uint128 amountInTwo = 2 ether;

        address receiverOne = makeAddr("fakeReceiverOne");
        address receiverTwo = makeAddr("fakeReceiverTwo");

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_one = abi.encodeWithSignature(
            "transfer(address,uint256)",
            receiverOne,
            amountInOne
        );

        // Create call data for swapExactNATIVEForTokens
        bytes memory transferCalldata_two = abi.encodeWithSignature(
            "transfer(address,uint256)",
            receiverTwo,
            amountInTwo
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
            amount: amountInOne,
            expiration: 1900000000,
            nonce: 0
        });

        permitDetails[1] = IAllowanceTransfer.PermitDetails({
            token: meow,
            amount: amountInTwo,
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


        assertEq(wavaxContract.balanceOf(receiverOne), amountInOne, "Receiver One should have 1 wavax");
        assertEq(meowContract.balanceOf(receiverTwo), amountInTwo, "Receiver Two should have 2 meow");
        assertEq(wavaxContract.balanceOf(address(geniusExecutor)), 0, "Executor should have no wavax");
        assertEq(meowContract.balanceOf(address(geniusExecutor)), 0, "Executor should have no meow");
        assertEq(wavaxContract.balanceOf(trader), 99 ether, "Trader should have 99 wavax");
        assertEq(meowContract.balanceOf(trader), 98 ether, "Trader should have 98 meow");
    }


    function testTokenSwapAndDeposit() public {
        // Setup initial balances and approvals
        uint256 initialWavaxBalance = wavaxContract.balanceOf(address(geniusExecutor));
        uint256 initialTestERC20Balance = testERC20.balanceOf(address(geniusExecutor));
        uint256 initialPoolTestERC20Balance = testERC20.balanceOf(address(geniusPool));
        
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

        // Verify balances after operation
        uint256 finalWavaxBalance = wavaxContract.balanceOf(address(geniusExecutor));
        uint256 finalTestERC20Balance = testERC20.balanceOf(address(geniusExecutor));
        uint256 finalPoolTestERC20Balance = testERC20.balanceOf(address(geniusPool));

        assertEq(finalWavaxBalance, initialWavaxBalance - transferAmount, "Executor should have less wavax after swap");
        assertGt(finalTestERC20Balance, initialTestERC20Balance, "Executor should have more testERC20 after swap");
        assertGt(finalPoolTestERC20Balance, initialPoolTestERC20Balance, "Pool should have more testERC20 after deposit");
    }
}