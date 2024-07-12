
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import { GeniusExecutor } from "../GeniusExecutor.sol";

/**
 * @title Executable
 * @author altloot
 * @dev A contract for managing Genius Executor permissions.
 */
abstract contract Executable {

    GeniusExecutor public EXECUTOR;

    constructor (
        address executor
    ) {
        EXECUTOR = GeniusExecutor(executor);
    }

    error NotExecutor(address orchestrator);

    modifier onlyExecutor() {
            _checkExecutor();
        _;
    }

    /**
     * @dev Internal function to check if the caller is the GeniusExecutor contract.
     * @dev Throws a `NotExecutor` error if the caller is not the GeniusExectorContract.
     */
    function _checkExecutor() internal view virtual {
        if (msg.sender != address(EXECUTOR)) revert NotExecutor(msg.sender);
    }
}
