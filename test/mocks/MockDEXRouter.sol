// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {console} from "forge-std/Test.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockERC20.sol";

contract MockDEXRouter {
    using SafeERC20 for IERC20;

    // Mapping to store created mock tokens
    mapping(address => address) public mockTokens;
    uint256 public usdcAmountOut;

    // Fixed amount to mint when swapping (e.g., 1000 tokens)
    uint256 public constant MINT_AMOUNT = 1000 * 10 ** 18;

    // Native token address constant (same as in GeniusProxyCall)
    address public constant NATIVE_TOKEN =
        0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    function swapToStables(address usdc) external payable {
        if (msg.value < 1 wei) {
            revert("Must pay for USDC");
        }

        uint256 _usdcBalance = IERC20(usdc).balanceOf(address(this));
        uint256 _usdcAmount = _usdcBalance / 2;

        IERC20(usdc).transfer(msg.sender, _usdcAmount);

        usdcAmountOut = _usdcAmount;
    }

    function bridge(address usdc, uint256 amount) public {
        // Check the allowance of the msg.sender
        require(
            IERC20(usdc).allowance(msg.sender, address(this)) >= amount,
            "Insufficient allowance"
        );

        IERC20(usdc).transferFrom(msg.sender, address(this), amount);
    }

    function swapWithNoEffect(address, address) external pure {
        // Do nothing, simulating a swap that doesn't change balances
    }

    function swapERC20ToStables(
        address tokenIn,
        address usdc
    ) external payable {
        require(tokenIn != usdc, "Cannot swap same token");
        uint256 _usdcBalance = IERC20(usdc).balanceOf(address(this));
        uint256 _usdcAmount = _usdcBalance / 2;
        console.log("msg.sender: ", msg.sender);
        IERC20(usdc).transfer(msg.sender, _usdcAmount);
        console.log("USDC amount out: ", _usdcAmount);
    }

    function swapTo(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        address to
    ) external payable returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "Cannot swap same token");

        // Handle native token (ETH) as input
        if (tokenIn == address(0) || tokenIn == NATIVE_TOKEN) {
            require(msg.value == amountIn, "Incorrect ETH amount sent");
        } else {
            IERC20(tokenIn).safeTransferFrom(
                msg.sender,
                address(this),
                amountIn
            );
        }

        // Handle native token (ETH) as output
        if (tokenOut == NATIVE_TOKEN) {
            // Send half of the contract's ETH balance
            amountOut = address(this).balance / 2;
            require(amountOut > 0, "No ETH balance to swap");
            (bool success, ) = to.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            // Transfer ERC20 tokens
            amountOut = IERC20(tokenOut).balanceOf(address(this)) / 2;
            IERC20(tokenOut).safeTransfer(to, amountOut);
        }

        return amountOut;
    }

    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external payable returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "Cannot swap same token");

        // Handle native token (ETH) as input
        if (tokenIn == address(0) || tokenIn == NATIVE_TOKEN) {
            require(msg.value == amountIn, "Incorrect ETH amount sent");
        } else {
            // For ERC20 input, we don't actually need to transfer tokens
            // We just check if the caller has approved enough tokens
            require(
                IERC20(tokenIn).allowance(msg.sender, address(this)) >=
                    amountIn,
                "Insufficient allowance"
            );
        }

        // Handle native token (ETH) as output
        if (tokenOut == NATIVE_TOKEN) {
            // Send half of the contract's ETH balance
            amountOut = address(this).balance / 2;
            require(amountOut > 0, "No ETH balance to swap");
            (bool success, ) = msg.sender.call{value: amountOut}("");
            require(success, "ETH transfer failed");
        } else {
            // Mint or transfer output tokens
            address mockToken = _getOrCreateMockToken(tokenOut);
            MockERC20(mockToken).mint(msg.sender, MINT_AMOUNT);
            amountOut = MINT_AMOUNT;
        }

        return amountOut;
    }

    function _getOrCreateMockToken(
        address tokenAddress
    ) internal returns (address) {
        if (mockTokens[tokenAddress] == address(0)) {
            // Create a new mock token
            MockERC20 newToken = new MockERC20("Mock Token", "MOCK", 18);
            mockTokens[tokenAddress] = address(newToken);
        }
        return mockTokens[tokenAddress];
    }

    function swapETHToToken(address token, address to) external payable {
        // Mock the swap by transferring the predefined amount of tokens
        // In a real DEX, this would calculate the amount based on the ETH sent
        uint256 outAmount = IERC20(token).balanceOf(address(this)) / 2;
        IERC20(token).transfer(to, outAmount);
    }

    // New function to swap token to ETH
    function swapTokenToETH(
        address token,
        uint256 amountIn,
        address to
    ) external returns (uint256 amountOut) {
        // Transfer tokens from sender
        IERC20(token).safeTransferFrom(msg.sender, address(this), amountIn);

        // Send half of contract's ETH balance
        amountOut = address(this).balance / 2;
        require(amountOut > 0, "No ETH balance to swap");

        (bool success, ) = to.call{value: amountOut}("");
        require(success, "ETH transfer failed");

        return amountOut;
    }

    // Fallback function to receive ETH
    receive() external payable {}
}
