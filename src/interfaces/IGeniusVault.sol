// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IGeniusPool} from "./IGeniusPool.sol";

/**
 * @title IGeniusVault
 * @dev Interface for a contract that represents a vault for holding assets and interacting with the GeniusPool contract.
 */
interface IGeniusVault {
    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @dev Initializes the GeniusVault contract.
     * @param _geniusPool The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address _geniusPool) external;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    function geniusPool() external view returns (IGeniusPool);
    function initialized() external view returns (bool);
}