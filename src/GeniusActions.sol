// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IGeniusActions.sol";
import "./libs/GeniusErrors.sol";

/**
 * @title GeniusActions
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusActions contract is a contract that manages the actions that can be executed by the Genius Protocol.
 *         It allows for the addition, removal, and updating of actions that can be executed by the protocol.
 */
contract GeniusActions is IGeniusActions, AccessControl {
    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        IMMUTABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL_ROLE");

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         VARIABLES                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    uint256 nextActionId;

    mapping(uint256 => Action) internal idToAction;
    mapping(bytes32 => uint256) internal hashToId;
    mapping(bytes32 => uint256) internal labelToId;
    mapping(address => bool) internal authorizedOrchestrators;
    mapping(bytes32 => bool) internal authorizedCommitHashes;

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                        CONSTRUCTOR                        ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @notice Initializes the contract with an initial admin
     * @dev Sets up the initial admin with both DEFAULT_ADMIN_ROLE and SENTINEL_ROLE
     * @param _admin Address of the initial admin
     */
    constructor(address _admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(SENTINEL_ROLE, _admin);
        nextActionId = 1;
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                         MODIFIERS                         ║
    // ╚═══════════════════════════════════════════════════════════╝

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert GeniusErrors.AccessDenied();
        _;
    }

    modifier onlySentinel() {
        if (!hasRole(SENTINEL_ROLE, msg.sender))
            revert GeniusErrors.AccessDenied();
        _;
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      WRITE FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusActions-setOrchestratorAuthorized}.
     */
    function setOrchestratorAuthorized(
        address _orchestrator,
        bool _authorized
    ) external onlyAdmin {
        authorizedOrchestrators[_orchestrator] = _authorized;
        emit OrchestratorAuthorized(_orchestrator, _authorized);
    }

    function setBatchOrchestratorAuthorized(
        address[] calldata _orchestrators,
        bool _authorized
    ) external onlyAdmin {
        for (uint256 i = 0; i < _orchestrators.length; i++) {
            authorizedOrchestrators[_orchestrators[i]] = _authorized;
            emit OrchestratorAuthorized(_orchestrators[i], _authorized);
        }
    }

    /**
     * @dev See {IGeniusActions-setCommitHashAuthorized}.
     */
    function setCommitHashAuthorized(
        bytes32 _commitHash,
        bool _authorized
    ) external onlyAdmin {
        authorizedCommitHashes[_commitHash] = _authorized;
        emit CommitHashAuthorized(_commitHash, _authorized);
    }

    /**
     * @dev See {IGeniusActions-setBatchCommitHashAuthorized}.
     */
    function setBatchCommitHashAuthorized(
        bytes32[] calldata _commitHashes,
        bool _authorized
    ) external onlyAdmin {
        for (uint256 i = 0; i < _commitHashes.length; i++) {
            authorizedCommitHashes[_commitHashes[i]] = _authorized;
            emit CommitHashAuthorized(_commitHashes[i], _authorized);
        }
    }

    /**
     * @dev See {IGeniusActions-isAuthorizedCommitHash}.
     */
    function isAuthorizedCommitHash(
        bytes32 _commitHash
    ) external view returns (bool) {
        return authorizedCommitHashes[_commitHash];
    }

    /**
     * @dev See {IGeniusActions-addAction}.
     */
    function addAction(
        bytes32 actionLabel,
        string memory ipfsHash
    ) external onlyAdmin {
        bytes32 actionHash = getActionHashFromIpfsHash(ipfsHash);
        if (labelToId[actionLabel] != 0)
            revert GeniusErrors.LabelAlreadyExists();
        if (hashToId[actionHash] != 0)
            revert GeniusErrors.IpfsHashAlreadyExists();
        if (bytes(ipfsHash).length < 40)
            revert GeniusErrors.IncorrectIpfsHash();
        _newAction(actionLabel, actionHash, ipfsHash);
    }

    /**
     * @dev See {IGeniusActions-updateActionStatusByHash}.
     */
    function updateActionStatusByHash(
        bytes32 actionHash,
        bool active
    ) external onlyAdmin {
        uint256 actionId = hashToId[actionHash];
        _updateActionStatus(actionId, active);
    }

    /**
     * @dev See {IGeniusActions-updateActionStatusByLabel}.
     */
    function updateActionStatusByLabel(
        bytes32 actionLabel,
        bool active
    ) external onlyAdmin {
        uint256 actionId = labelToId[actionLabel];
        _updateActionStatus(actionId, active);
    }

    /**
     * @dev See {IGeniusActions-updateActionIpfsHashByHash}.
     */
    function updateActionIpfsHashByHash(
        bytes32 actionHash,
        string memory newIpfsHash
    ) external onlyAdmin {
        uint256 actionId = hashToId[actionHash];
        if (actionId == 0) revert GeniusErrors.ActionDoesNotExist();
        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
    }

    /**
     * @dev See {IGeniusActions-updateActionIpfsHashByLabel}.
     */
    function updateActionIpfsHashByLabel(
        bytes32 actionLabel,
        string memory newIpfsHash
    ) external onlyAdmin {
        uint256 actionId = labelToId[actionLabel];
        if (actionId == 0) revert GeniusErrors.ActionDoesNotExist();
        bytes32 actionHash = getActionHashFromIpfsHash(
            idToAction[actionId].ipfsHash
        );
        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
    }

    /**
     * @dev See {IGeniusActions-emergencyDisableActionById}.
     */
    function emergencyDisableActionById(
        uint256 actionId
    ) external onlySentinel {
        _updateActionStatus(actionId, false);
    }

    /**
     * @dev See {IGeniusActions-emergencyDisableActionByHash}.
     */
    function emergencyDisableActionByHash(
        bytes32 actionHash
    ) external onlySentinel {
        uint256 actionId = hashToId[actionHash];
        _updateActionStatus(actionId, false);
    }

    /**
     * @dev See {IGeniusActions-emergencyDisableActionByLabel}.
     */
    function emergencyDisableActionByLabel(
        bytes32 actionLabel
    ) external onlySentinel {
        uint256 actionId = labelToId[actionLabel];
        _updateActionStatus(actionId, false);
    }

    /**
     * @dev See {IGeniusActions-emergencyDisableOrchestrator}.
     */
    function emergencyDisableOrchestrator(
        address _orchestrator
    ) external onlySentinel {
        authorizedOrchestrators[_orchestrator] = false;
        emit OrchestratorAuthorized(_orchestrator, false);
    }

    /**
     * @dev See {IGeniusActions-emergencyDisableCommitHash}.
     */
    function emergencyDisableCommitHash(
        bytes32 _commitHash
    ) external onlySentinel {
        authorizedCommitHashes[_commitHash] = false;
        emit CommitHashAuthorized(_commitHash, false);
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                       READ FUNCTIONS                      ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev See {IGeniusActions-isAuthorizedOrchestrator}.
     */
    function isAuthorizedOrchestrator(
        address _orchestrator
    ) external view returns (bool) {
        return authorizedOrchestrators[_orchestrator];
    }

    /**
     * @dev See {IGeniusActions-isActionActive}.
     */
    function isActionActive(
        string memory _ipfsHash
    ) external view returns (bool) {
        return
            idToAction[hashToId[getActionHashFromIpfsHash(_ipfsHash)]].active;
    }

    /**
     * @dev See {IGeniusActions-getActionByIpfsHash}.
     */
    function getActionByIpfsHash(
        string memory _ipfsHash
    ) external view returns (Action memory) {
        return getActionByActionHash(getActionHashFromIpfsHash(_ipfsHash));
    }

    /**
     * @dev See {IGeniusActions-getActionByActionHash}.
     */
    function getActionByActionHash(
        bytes32 _actionHash
    ) public view returns (Action memory) {
        Action memory action = idToAction[hashToId[_actionHash]];
        if (bytes(action.ipfsHash).length == 0)
            revert GeniusErrors.ActionDoesNotExist();
        return action;
    }

    /**
     * @dev See {IGeniusActions-getActionByActionLabel}.
     */
    function getActionByActionLabel(
        bytes32 _actionLabel
    ) external view returns (Action memory) {
        Action memory action = idToAction[labelToId[_actionLabel]];
        if (bytes(action.ipfsHash).length == 0)
            revert GeniusErrors.ActionDoesNotExist();
        return action;
    }

    /**
     * @dev See {IGeniusActions-getActionHashFromIpfsHash}.
     */
    function getActionHashFromIpfsHash(
        string memory ipfsHash
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ipfsHash));
    }

    // ╔═══════════════════════════════════════════════════════════╗
    // ║                      INTERNAL FUNCTIONS                   ║
    // ╚═══════════════════════════════════════════════════════════╝

    /**
     * @dev Internal function to update an action's IPFS hash
     * @param actionId The ID of the action to update
     * @param prevActionHash The previous action hash
     * @param newIpfsHash The new IPFS hash
     */
    function _updateActionIpfsHash(
        uint256 actionId,
        bytes32 prevActionHash,
        string memory newIpfsHash
    ) internal {
        bytes32 newActionHash = getActionHashFromIpfsHash(newIpfsHash);
        if (prevActionHash == newActionHash) revert GeniusErrors.SameIpfsHash();
        if (hashToId[newActionHash] != 0)
            revert GeniusErrors.IpfsHashAlreadyExists();

        hashToId[prevActionHash] = 0;
        hashToId[newActionHash] = actionId;
        idToAction[actionId].ipfsHash = newIpfsHash;

        emit ActionIpfsHashUpdated(actionId, newIpfsHash);
    }

    /**
     * @dev Internal function to update an action's label
     * @param actionId The ID of the action to update
     * @param oldLabel The current label of the action
     * @param newLabel The new label for the action
     */
    function _updateActionLabel(
        uint256 actionId,
        bytes32 oldLabel,
        bytes32 newLabel
    ) internal {
        if (labelToId[newLabel] != 0) revert GeniusErrors.NewLabelExists();

        labelToId[oldLabel] = 0;
        labelToId[newLabel] = actionId;
        idToAction[actionId].label = newLabel;

        emit ActionLabelUpdated(actionId, newLabel);
    }

    /**
     * @dev Internal function to create a new action
     * @param label The label for the new action
     * @param actionHash The hash of the new action
     * @param ipfsHash The IPFS hash of the new action
     */
    function _newAction(
        bytes32 label,
        bytes32 actionHash,
        string memory ipfsHash
    ) internal {
        uint256 actionId = nextActionId;
        idToAction[actionId] = Action(label, ipfsHash, true);
        labelToId[label] = actionId;
        hashToId[actionHash] = actionId;

        emit ActionAdded(actionId, label, ipfsHash);

        nextActionId++;
    }

    /**
     * @dev Internal function to update an action's status
     * @param id The ID of the action to update
     * @param active The new status of the action
     */
    function _updateActionStatus(uint256 id, bool active) internal {
        Action storage action = idToAction[id];
        if (bytes(action.ipfsHash).length == 0)
            revert GeniusErrors.ActionDoesNotExist();
        if (action.active == active) revert GeniusErrors.StatusAlreadySet();

        action.active = active;
        emit ActionStatusUpdated(id, active);
    }
}
