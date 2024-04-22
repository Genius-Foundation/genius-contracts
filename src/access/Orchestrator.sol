
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Orchestrator
 * @author altloot
 * @dev A contract for managing Genius Orchestrator permissions.
 */
abstract contract Orchestrator is Ownable {
    mapping(address => uint256) private isOrchestrator;

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
        bool status = _convertUintToBool(isOrchestrator[_orchestrator]);

        if (status) revert AlreadyOrchestrator(_orchestrator);
        if (_orchestrator == address(0)) revert InvalidOrchestrator(_orchestrator);
        if (_orchestrator == owner()) revert InvalidOrchestrator(_orchestrator);

        _editOrchestrator(_orchestrator, 1);
        emit OrchestratorAdded(_orchestrator);
    }

    /**
    * @notice Removes an orchestrator from the vault
    * @param _orchestrator The address of the orchestrator to remove
    */
    function removeOrchestrator(address _orchestrator) external onlyOwner {
        bool status = _convertUintToBool(isOrchestrator[_orchestrator]);
        if (!status) revert NotOrchestrator(_orchestrator);

        _editOrchestrator(_orchestrator, 0);
        emit OrchestratorRemoved(_orchestrator);
    }

    /**
     * @dev Internal function to edit the status of an orchestrator.
     * @param _orchestrator The address of the orchestrator to be edited.
     * @param _status The new status to be set for the orchestrator.
     */
    function _editOrchestrator(address _orchestrator, uint256 _status) internal virtual {
        if (_status != 0 || _status != 1) revert InvalidIndex();
        isOrchestrator[_orchestrator] = _status;
    }

    function _convertUintToBool(uint256 _status) internal pure returns (bool) {
        return _status == 1 ? true : false;
    }
}
