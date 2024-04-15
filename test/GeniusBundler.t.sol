// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;


import {Test, console} from "forge-std/Test.sol";
import {Permit2Multicaller} from "../src/Permit2Multicaller.sol";
import {LBQuoter} from "joe-v2/LBQuoter.sol";
import {LBRouter} from "joe-v2/LBRouter.sol";
import {ILBRouter} from "joe-v2/interfaces/ILBRouter.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestERC20} from "../src/TestERC20.sol";

contract MulticallerWithSenderTest is Test {
    // All of the addresses used in the tests
    address public trader = makeAddr("trader");
    address public coinReceiver = makeAddr("coinReceiver");
    address public quoterAddress = 0xd76019A16606FDa4651f636D9751f500Ed776250;
    address payable routerAddress = payable(0xb4315e873dBcf96Ffd0acd8EA43f689D8c20fB30);

    // The instances of the contracts used in the tests
    LBRouter public lbRouter = LBRouter(routerAddress);
    LBQuoter lbQuoter = LBQuoter(quoterAddress);

    Permit2Multicaller public multicallerWithSender = new Permit2Multicaller(0x000000000022D473030F116dDEE9F6B43aC78BA3);
    TestERC20 public testERC20 = new TestERC20();

    function test_should_get_quote() public {

        address wavax = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
        address meow = 0x8aD25B0083C9879942A64f00F20a70D3278f6187;
        address coq = 0x420FcA0121DC28039145009570975747295f2329;

        address[] memory route1 = new address[](2);
        route1[0] = wavax;
        route1[1] = coq;

        address[] memory route2 = new address[](2);
        route2[0] = wavax;
        route2[1] = meow;

        uint128 amountInOne = 1 ether;
        uint128 amountInTwo = 2 ether;

        vm.deal(trader, 10 ether);
        assertEq(address(trader).balance, 10 ether, "The trader should have 10 AVAX after the deal");

        LBQuoter.Quote memory quoteOne = lbQuoter.findBestPathFromAmountIn(route1, amountInOne);
        LBQuoter.Quote memory quoteTwo = lbQuoter.findBestPathFromAmountIn(route2, amountInTwo);

        address[] memory addressArrayOne = quoteOne.route;
        address[] memory addressArrayTwo = quoteTwo.route;

        IERC20[] memory ierc20ArrayOne = new IERC20[](addressArrayOne.length);
        IERC20[] memory ierc20ArrayTwo = new IERC20[](addressArrayTwo.length);

        for (uint i = 0; i < addressArrayOne.length; i++) {
            ierc20ArrayOne[i] = IERC20(addressArrayOne[i]);
        }

        for (uint i = 0; i < addressArrayTwo.length; i++) {
            ierc20ArrayTwo[i] = IERC20(addressArrayTwo[i]);
        }


        // Initialize the first Path instance
        ILBRouter.Path memory pathOne = ILBRouter.Path({
            pairBinSteps: quoteOne.binSteps,
            versions: quoteOne.versions,
            tokenPath: ierc20ArrayOne
        });

        // Initialize the second Path instance
        ILBRouter.Path memory pathTwo = ILBRouter.Path({
            pairBinSteps: quoteTwo.binSteps,
            versions: quoteTwo.versions,
            tokenPath: ierc20ArrayTwo
        });


        // Create call data for swapExactNATIVEForTokens
        bytes memory swapOneCallData = abi.encodeWithSignature(
            "swapExactNATIVEForTokens(uint256 amountOutMin, Path memory path, address to, uint256 deadline)",
            amountInOne / 2,
            pathOne,
            address(trader),
            block.timestamp + 1000
        );

        // Create call data for swapExactNATIVEForTokens
        bytes memory swapTwoCallData = abi.encodeWithSignature(
            "swapExactNATIVEForTokens(uint256 amountOutMin, Path memory path, address to, uint256 deadline)",
            amountInTwo / 2,
            pathTwo,
            address(trader),
            block.timestamp + 1000
        );

        vm.prank(trader);

        /**
            address[] calldata targets,
            bytes[] calldata data,
            uint256[] calldata values
         */

        // Declare the arrays in memory instead of calldata
        address[] memory targets = new address[](2);
        targets[0] = address(lbRouter);
        targets[1] = address(lbRouter);

        bytes[] memory data = new bytes[](2);
        data[0] = swapOneCallData; // Assuming swapOneCallData is already defined elsewhere
        data[1] = swapTwoCallData; // Assuming swapTwoCallData is already defined elsewhere

        uint256[] memory values = new uint256[](2);
        values[0] = amountInOne; // Assuming amountInOne is already defined elsewhere
        values[1] = amountInTwo; // Assuming amountInTwo is already defined elsewhere


    }
}