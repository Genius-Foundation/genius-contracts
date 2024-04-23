
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import {console} from "forge-std/Test.sol";

/**
 * @title Orchestrable
 * @author altloot
 * @dev A contract for managing Genius Orchestrator permissions.
 */
abstract contract Orchestrable is Ownable {

    enum Status {
        UNAUTHORIZED,
        AUTHORIZED
    }

    mapping(address => Status) private isOrchestrator;

    error AlreadyOrchestrator(address orchestrator);
    error InvalidOrchestrator(address orchestrator);
    error NotOrchestrator(address orchestrator);
    error InvalidIndex();

    event OrchestratorAdded(address indexed orchestrator);
    event OrchestratorRemoved(address indexed orchestrator);

    modifier onlyOrchestrator() {
            _checkOrchestrator();
        _;
    }

    function _checkOrchestrator() internal view virtual {
        bool status = _convertUintToBool(isOrchestrator[tx.origin]);

        if (!status) {
            revert NotOrchestrator(tx.origin);
        }
    }

    /**
    * @notice Adds an orchestrator to the vault
    * @param _orchestrator The address of the orchestrator to add
    */
    function addOrchestrator(address _orchestrator) external onlyOwner {
        Status status = isOrchestrator[_orchestrator];

        if (status == Status.AUTHORIZED) revert AlreadyOrchestrator(_orchestrator);
        if (_orchestrator == address(0)) revert InvalidOrchestrator(_orchestrator);
        if (_orchestrator == owner()) revert InvalidOrchestrator(_orchestrator);

        _editOrchestrator(_orchestrator, Status.AUTHORIZED);
        emit OrchestratorAdded(_orchestrator);
    }

    /**
    * @notice Removes an orchestrator from the vault
    * @param _orchestrator The address of the orchestrator to remove
    */
    function removeOrchestrator(address _orchestrator) external onlyOwner {
        bool status = _convertUintToBool(isOrchestrator[_orchestrator]);
        if (!status) revert NotOrchestrator(_orchestrator);

        _editOrchestrator(_orchestrator, Status.UNAUTHORIZED);
        emit OrchestratorRemoved(_orchestrator);
    }

    function orchestrator(address _orchestrator) external view returns (bool) {
        return _convertUintToBool(isOrchestrator[_orchestrator]);
    }

    /**
     * @dev Internal function to edit the status of an orchestrator.
     * @param _orchestrator The address of the orchestrator to be edited.
     * @param _status The new status to be set for the orchestrator.
     */
    function _editOrchestrator(address _orchestrator, Status _status) internal virtual {
        isOrchestrator[_orchestrator] = _status;
    }

    function _convertUintToBool(Status _status) internal pure returns (bool) {
        return _status == Status.AUTHORIZED ? true : false;
    }
}
