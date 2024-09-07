// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Test.sol";

contract MockSwapTarget {
    
    function mockSwap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        address poolAddress,
        uint256 amountOut
    ) external payable returns (bool, uint256) {
       
       if (msg.value > 0) {
            console.log("Received ETH: ", msg.value);

            IERC20(tokenOut).transfer(poolAddress, amountOut);
            return (true, amountOut);
        } else {
            // Transfer tokenIn from poolAddress to this contract
            console.log("Transfering tokenIn from poolAddress to this contract");
            IERC20(tokenIn).transferFrom(poolAddress, address(this), amountIn);
            console.log("SUCCESS: Transfered tokenIn from poolAddress to this contract");

            // Transfer tokenOut from this contract to recipient
            console.log("Transfering tokenOut from this contract to poolAddress");
            IERC20(tokenOut).transfer(poolAddress, amountOut);
            console.log("SUCCESS: Transfered tokenOut from this contract to poolAddress");
            return (true, amountOut);
        }
    }
}