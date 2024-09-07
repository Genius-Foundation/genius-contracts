// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GeniusExecutor} from "../../src/GeniusExecutor.sol";

contract MaliciousToken is ERC20 {
    GeniusExecutor public EXECUTOR;
    address public attacker;

    constructor(address _executor) ERC20("MaliciousToken", "MTKN") {
        EXECUTOR = GeniusExecutor(payable(_executor));
        attacker = msg.sender;
        _mint(msg.sender, 1000000 * 10**decimals());
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool success) {
        _transfer(_msgSender(), recipient, amount);

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool success) {        
        if (recipient == address(EXECUTOR)) {
            // Attempt to call back into the EXECUTOR
            address[] memory targets = new address[](1);
            targets[0] = address(this);
            
            bytes[] memory data = new bytes[](1);
            data[0] = "0x";
            
            uint256[] memory values = new uint256[](1);
            values[0] = 1 ether;

            try EXECUTOR.aggregate(targets, data, values) {
            } catch {
                revert("Failed to call back into the EXECUTOR");
            }
        } else {

            _transfer(sender, recipient, amount);


            return true;
        }
    }
}