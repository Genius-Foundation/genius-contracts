// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { GeniusErrors } from "../../src/libs/GeniusErrors.sol";

contract OrchestrableERC20 is ERC20, AccessControl {
        bytes32 public constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");
    
    constructor(address _owner) ERC20("Test ERC20", "tERC20") {
        _grantRole(DEFAULT_ADMIN_ROLE, _owner);
        this;
    }

    modifier onlyOrchestrator() {
        if(!hasRole(ORCHESTRATOR_ROLE, msg.sender)) revert GeniusErrors.IsNotOrchestrator();
        _;
    }

    function mint(address _to, uint256 _amount) external onlyOrchestrator {
        _mint(_to, _amount);
    }
}