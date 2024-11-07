// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";

contract AaveV3Proxy {
    using SafeERC20 for IERC20;

    // Optimism Aave V3 Pool address
    address public constant AAVE_POOL =
        0x794a61358D6845594F94dc1DB02A252b5b4814aD;

    /**
     * @dev Deposits available balance of a token into Aave
     * @param asset The address of the token to deposit
     * @param onBehalfOf The address that will receive the aTokens
     * @return amount The amount that was deposited
     */
    function depositAvailableBalance(
        address asset,
        address onBehalfOf
    ) external returns (uint256 amount) {
        // Get the current balance of the token in this contract
        amount = IERC20(asset).balanceOf(address(this));
        require(amount > 0, "No balance available");

        // Approve Aave Pool to spend the tokens
        IERC20(asset).approve(AAVE_POOL, amount);

        // Deposit into Aave
        IPool(AAVE_POOL).supply(asset, amount, onBehalfOf, 0);

        IERC20(asset).approve(AAVE_POOL, 0); // Clear any existing allowance

        return amount;
    }

    /**
     * @dev Returns the current balance of a token in this contract
     * @param token The token address to check
     * @return The balance of the token
     */
    function getBalance(address token) external view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }
}
