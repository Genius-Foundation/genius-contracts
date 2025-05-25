// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockDepositContract {
    using SafeERC20 for IERC20;

    mapping(address => mapping(address => uint256)) public deposits;
    mapping(address => uint256) public ethDeposits;

    event Deposited(
        address indexed user,
        address indexed token,
        uint256 amount
    );
    event ETHDeposited(address indexed user, uint256 amount);

    function deposit(address token, uint256 amount) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender][token] += amount;
        emit Deposited(msg.sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(deposits[msg.sender][token] >= amount, "Insufficient balance");
        deposits[msg.sender][token] -= amount;
        IERC20(token).safeTransfer(msg.sender, amount);
    }

    // Function to deposit ETH
    function depositETH() external payable {
        require(msg.value > 0, "No ETH sent");
        ethDeposits[msg.sender] += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }

    // Receive function to accept ETH
    receive() external payable {
        ethDeposits[msg.sender] += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }

    // Fallback function
    fallback() external payable {
        ethDeposits[msg.sender] += msg.value;
        emit ETHDeposited(msg.sender, msg.value);
    }
}
