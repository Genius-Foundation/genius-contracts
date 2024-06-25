// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/Test.sol";

contract MockSwapTarget {
    event SwapCalled(address tokenIn, address trader, address recipient, uint256 amountIn, address tokenOut, address poolAddress, uint256 amountOut);
    event BalanceAndAllowance(address token, uint256 balance, uint256 allowance);
    event TransferExecuted(address token, address from, address to, uint256 amount);

    function mockSwap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        address poolAddress,
        uint256 amountOut
    ) external returns (bool, uint256) {
        // Transfer tokenIn from poolAddress to this contract
        IERC20(tokenIn).transferFrom(poolAddress, address(this), amountIn);

        // Transfer tokenOut from this contract to recipient
        IERC20(tokenOut).transfer(poolAddress, amountOut);
        
        return (true, amountOut);
    }
}