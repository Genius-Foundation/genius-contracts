// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockUSDC is ERC20 {
    constructor() ERC20("Mock USD Coin", "mUSDC") {
        _mint(msg.sender, 100_000_000 * 10 ** 18); // example supply
    }

    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}
