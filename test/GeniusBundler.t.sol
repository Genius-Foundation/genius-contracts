// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {GeniusBundler} from "../src/GeniusBundler.sol";
import {TestERC20} from "../src/TestERC20.sol";

contract GeniusBundlerTest is Test {
    address public trader = makeAddr("trader");
    address public coinReceiver = makeAddr("coinReceiver");

    GeniusBundler public geniusBundler = new GeniusBundler();
    TestERC20 public testERC20 = new TestERC20();
    address public testERC20Address = address(testERC20);

    function test_bundler_with_no_payloads() public {
        vm.expectRevert();
        geniusBundler.execute(new GeniusBundler.Payload[](0), false, false);
    }

    function test_bundler_with_too_many_payloads() public {
        vm.expectRevert();
        geniusBundler.execute(new GeniusBundler.Payload[](17), false, false);
    }

    function test_expect_return_false_after_first_failure() public {
        vm.prank(trader);
        TestERC20 testContract = new TestERC20();
        address testContractAddress = address(testContract);

        // Assuming trader does not have enough balance for the first callData
        bytes memory callDataOne = abi.encodeWithSignature("transfer(address,uint256)", coinReceiver, 2000000000000000000000000);
        bytes memory callDataTwo = abi.encodeWithSignature("transfer(address,uint256)", coinReceiver, 1000000000000000000000000);

        GeniusBundler.Payload[] memory payloads = new GeniusBundler.Payload[](2);
        payloads[0] = GeniusBundler.Payload(testContractAddress, callDataOne, 0);
        payloads[1] = GeniusBundler.Payload(testContractAddress, callDataTwo, 0);

        bool success = geniusBundler.execute(payloads, true, false);
        assertEq(success, false, "The execute function should return false after the first failed payload");

        // Verifying that the receiver's balance hasnt changed
        assertEq(testContract.balanceOf(coinReceiver), 0, "The coin receiver's balance should remain unchanged after the failed execution");
    }

    /**
     * @dev This function is a test case for the successful execution of the `execute` function in the `geniusBundler` contract.
     * It performs the following steps:
     * 1. Transfers 500 tokens from `testERC20` contract to the `trader` address.
     * 2. Asserts that the balance of the `trader` address is 500 tokens.
     * 3. Calls the `deal` function in the `vm` contract, passing `trader` and 1 ether as arguments.
     * 4. Encodes two `transfer` function calls with different `callData` values.
     * 5. Creates an array of `GeniusBundler.Payload` structs with the encoded `callData` values.
     * 6. Calls the `execute` function in the `geniusBundler` contract with the array of payloads, setting both `revertOnFail` and `useDelegateCall` to false.
     * 7. Asserts that the `execute` function returns true, indicating success.
     * 8. Asserts that the `coinReceiver` address received 400 tokens after the successful execution.
     */
    function test_expect_successful_execution () public {
        testERC20.transfer(trader, 500);
        assertEq(testERC20.balanceOf(trader), 500, "The trader balance should be 500 after the transfer");

        vm.deal(trader, 1 ether);

        // Direct approval from trader to GeniusBundler to allow token transfer
        vm.prank(trader);
        testERC20.approve(address(geniusBundler), 1000);

        bytes memory callDataOne = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)", 
            trader, 
            address(coinReceiver), 
            250
        );

        bytes memory callDataTwo = abi.encodeWithSignature(
            "transferFrom(address,address,uint256)", 
            trader, 
            address(coinReceiver), 
            250
        );

        GeniusBundler.Payload[] memory payloads = new GeniusBundler.Payload[](2);
        payloads[0] = GeniusBundler.Payload(testERC20Address, callDataOne, 0);
        payloads[1] = GeniusBundler.Payload(testERC20Address, callDataTwo, 0);
        

        bool success = geniusBundler.execute(payloads, true, true);

        assertTrue(success, "Execute function did not return true as expected.");
        assertEq(testERC20.balanceOf(coinReceiver), 500, "The coin receiver balance should be 500 after the successful execution");
    }
}