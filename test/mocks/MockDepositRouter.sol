// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MockDepositContract} from "./MockDeposit.sol";

contract MockDepositRouter {
    using SafeERC20 for IERC20;

    MockDepositContract public depositContract;

    constructor(address _depositContract) {
        depositContract = MockDepositContract(payable(_depositContract));
    }

    function depositBalance(address token) public payable {
        uint256 balance = IERC20(token).balanceOf(address(this));
        IERC20(token).approve(address(depositContract), balance);
        depositContract.deposit(token, balance);
        IERC20(token).approve(address(depositContract), 0);
    }

    function depositBalances(address[] memory tokens) public payable {
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            IERC20(tokens[i]).approve(address(depositContract), balance);
            depositContract.deposit(tokens[i], balance);
            IERC20(tokens[i]).approve(address(depositContract), 0);
        }
    }

    function depositETH() external payable {
        require(msg.value > 0, "No ETH sent");
        (bool success, ) = address(depositContract).call{value: msg.value}("");
        require(success, "ETH deposit failed");
    }

    // New function that deposits both token balance and ETH
    function depositBalanceAndETH(address token) external payable {
        // Deposit token balance
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance > 0) {
            IERC20(token).approve(address(depositContract), balance);
            depositContract.deposit(token, balance);
        }

        // Deposit ETH
        if (msg.value > 0) {
            (bool success, ) = address(depositContract).call{value: msg.value}(
                ""
            );
            require(success, "ETH deposit failed");
        }
    }

    // Function that always reverts (for testing)
    function depositETHWithRevert() external payable {
        revert("Deposit failed");
    }

    // Receive function to accept ETH
    receive() external payable {}
}
