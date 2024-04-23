// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Orchestrable, Ownable} from "./access/Orchestrable.sol";

contract OrchestrableERC20 is ERC20, Orchestrable {
    constructor(address _owner) ERC20("Test ERC20", "tERC20") Ownable(_owner) {
        this;
    }

    function mint(address _to, uint256 _amount) external onlyOrchestrator {
        _mint(_to, _amount);
    }
}