
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Orchestrable
 * @author altloot
 * @dev A contract for managing Genius Orchestrator permissions. Only allows EOA orchestrators, as 
 *      instead of using msg.sender we use tx.origin to check the orchestrator. As a result,
 *      contracts cannot be orchestrators.
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

    event OrchestratorAdded(address indexed orchestrator);
    event OrchestratorRemoved(address indexed orchestrator);

    modifier onlyOrchestrator() {
            _checkOrchestrator();
        _;
    }

    /**
     * @dev Internal function to check if the caller is the orchestrator.
     * @dev Throws a `NotOrchestrator` error if the caller is not the orchestrator.
     */
    function _checkOrchestrator() internal view virtual {
        Status status = isOrchestrator[tx.origin];

        if (status != Status.AUTHORIZED) revert NotOrchestrator(tx.origin);
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
        Status status = isOrchestrator[tx.origin];

        if (status == Status.UNAUTHORIZED) revert NotOrchestrator(_orchestrator);

        _editOrchestrator(_orchestrator, Status.UNAUTHORIZED);
        emit OrchestratorRemoved(_orchestrator);
    }

    function orchestrator(address _orchestrator) external view returns (bool) {
        return isOrchestrator[_orchestrator] == Status.AUTHORIZED;
    }

    /**
     * @dev Internal function to edit the status of an orchestrator.
     * @param _orchestrator The address of the orchestrator to be edited.
     * @param _status The new status to be set for the orchestrator.
     */
    function _editOrchestrator(address _orchestrator, Status _status) internal virtual {
        isOrchestrator[_orchestrator] = _status;
    }
}
