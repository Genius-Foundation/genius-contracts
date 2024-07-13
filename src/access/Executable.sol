
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {GeniusExecutor} from "../GeniusExecutor.sol";

/**
 * @title Executable
 * @author altloot
 * @dev A contract for managing Genius Executor permissions.
 */
abstract contract Executable is Ownable {

    GeniusExecutor public EXECUTOR;
    uint256 public isExecutable = 0;

    error NotExecutor(address orchestrator);

    modifier onlyExecutor() {
            _checkExecutor();
        _;
    }

    /**
     * @dev Initializes the executor contract.
     * @param executor The address of the executor contract.
     */
    function _initializeExecutor(address payable executor) internal onlyOwner {
        require(isExecutable == 0, "Executor already initialized");
        EXECUTOR = GeniusExecutor(executor);

        isExecutable = 1;
    }

    /**
     * @dev Internal function to check if the caller is the GeniusExecutor contract.
     * @dev Throws a `NotExecutor` error if the caller is not the GeniusExectorContract.
     */
    function _checkExecutor() internal view virtual {
        require(isExecutable == 1, "Executor not initialized");
        if (msg.sender != address(EXECUTOR)) revert NotExecutor(msg.sender);
    }
}
