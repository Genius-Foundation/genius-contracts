// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/**
 * @title GeniusActions
 * @author looter
 * @notice A contract for managing Genius Protocol actions and their associated IPFS hashes.
 * @dev This contract inherits from OpenZeppelin's AccessControl for role-based access control.
 */

import "@openzeppelin/contracts/access/AccessControl.sol";

contract GeniusActions is AccessControl {

    // Structs
    struct Action {
        bytes32 label;
        string ipfsHash;
        bool active;
    }

    // Events
    event ActionAdded(uint256 indexed actionId, bytes32 indexed label, string ipfsHash);
    event ActionStatusUpdated(uint256 indexed actionId, bool active);
    event ActionIpfsHashUpdated(uint256 indexed actionId, string newIpfsHash);
    event ActionLabelUpdated(uint256 indexed actionId, bytes32 newLabel);
    event OrchestratorAuthorized(address indexed orchestrator, bool authorized);
    event CommitHashAuthorized(bytes32 indexed commitHash, bool authorized);

    // Constants
    bytes32 public constant SENTINEL_ROLE = keccak256("SENTINEL_ROLE");

    // State variables
    uint256 nextActionId = 1;

    mapping(uint256 => Action) internal idToAction;
    mapping(bytes32 => uint256) internal hashToId;
    mapping(bytes32 => uint256) internal labelToId;
    mapping(address => bool) internal authorizedOrchestrators;
    // commit Hash is bytes32(commitHash) => bool
    mapping(bytes32 => bool) internal authorizedCommitHashes;

    /**
     * @notice Initializes the contract with an initial admin
     * @dev Sets up the initial admin with both DEFAULT_ADMIN_ROLE and SENTINEL_ROLE
     * @param initialAdmin Address of the initial admin
     */
    constructor(address initialAdmin) {
        require(initialAdmin != msg.sender, "Initial owner cannot be the contract deployer");
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(SENTINEL_ROLE, initialAdmin);
    }

    // Modifiers

    /**
     * @dev Modifier for checking whether the caller is an admin.
     */
    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "OwnablePausable: access denied");
        _;
    }

    /**
     * @dev Modifier for checking whether the caller has the SENTINEL_ROLE.
     */
    modifier onlySentinel() {
        require(hasRole(SENTINEL_ROLE, msg.sender), "OwnablePausable: access denied");
        _;
    }

    /**
     * @notice Changes the authorization status of an orchestrator
     * @param _orchestrator the address of the orchestrator
     * @param _authorized the new authorization status
     */
    function setOrchestratorAuthorized(address _orchestrator, bool _authorized) external onlyAdmin {
        authorizedOrchestrators[_orchestrator] = _authorized;
        emit OrchestratorAuthorized(_orchestrator, _authorized);
    }

    /**
     * @notice Changes the authorization status of a mutliple orchestrators
     * @param _orchestrators the array of orchestrators to set the authorization status for
     * @param _authorized the new authorization status for all the orchestrators
     */
    function setBatchOrchestratorAuthorized(address[] calldata _orchestrators, bool _authorized) external onlyAdmin {
        for (uint256 i = 0; i < _orchestrators.length; i++) {
            authorizedOrchestrators[_orchestrators[i]] = _authorized;
            emit OrchestratorAuthorized(_orchestrators[i], _authorized);
        }
    }

    /**
     * @notice Changes the authorization status of a commit hash
     * @param _commitHash the commit hash to authorize or deauthorize
     * @param _authorized the new authorization status
     */
    function setCommitHashAuthorized(bytes32 _commitHash, bool _authorized) external onlyAdmin {
        authorizedCommitHashes[_commitHash] = _authorized;
        emit CommitHashAuthorized(_commitHash, _authorized);
    }

    /**
     * @notice Changes the authorization status of multiple commit hashes
     * @param _commitHashes the array of commit hashes to set the authorization status for
     * @param _authorized the new authorization status for all the commit hashes
     */
    function setBatchCommitHashAuthorized(bytes32[] calldata _commitHashes, bool _authorized) external onlyAdmin {
        for (uint256 i = 0; i < _commitHashes.length; i++) {
            authorizedCommitHashes[_commitHashes[i]] = _authorized;
            emit CommitHashAuthorized(_commitHashes[i], _authorized);
        }
    }

    /**
     * @notice Checks whether a commit hash is authorized or not
     * @param _commitHash The commit hash to check
     * @return whether the commit hash is authorized or not
     */
    function isAuthorizedCommitHash(bytes32 _commitHash) external view returns (bool) {
        return authorizedCommitHashes[_commitHash];
    }

    /**
     * @notice Adds a new action with the given label and IPFS hash
     * @dev Only callable by admin
     * @param actionLabel The label for the new action
     * @param ipfsHash The IPFS hash of the action
     */
    function addAction(bytes32 actionLabel, string memory ipfsHash) external onlyAdmin {
        bytes32 actionHash = getActionHashFromIpfsHash(ipfsHash);
        require(labelToId[actionLabel] == 0, "Label already exists");
        require(hashToId[actionHash] == 0, "IPFS hash already exists");
        require(bytes(ipfsHash).length >= 40, "incorrect IPFS hash");
        _newAction(actionLabel, actionHash, ipfsHash);
    }

    /**
     * @notice Updates the status of an action identified by its hash
     * @dev Only callable by admin
     * @param actionHash The hash of the action to update
     * @param active The new status of the action
     */
    function updateActionStatusByHash(bytes32 actionHash, bool active) external onlyAdmin {
        uint256 actionId = hashToId[actionHash];
        _updateActionStatus(actionId, active);
    }

    /**
     * @notice Updates the status of an action identified by its label
     * @dev Only callable by admin
     * @param actionLabel The label of the action to update
     * @param active The new status of the action
     */
    function updateActionStatusByLabel(bytes32 actionLabel, bool active) external onlyAdmin {
        uint256 actionId = labelToId[actionLabel];
        _updateActionStatus(actionId, active);
    }

    /**
     * @notice Updates the IPFS hash of an action identified by its hash
     * @dev Only callable by admin
     * @param actionHash The current hash of the action
     * @param newIpfsHash The new IPFS hash for the action
     */
    function updateActionIpfsHashByHash(bytes32 actionHash, string memory newIpfsHash) external onlyAdmin {
        uint256 actionId = hashToId[actionHash];
        require(actionId != 0, "Action does not exist");

        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
    }

    /**
     * @notice Updates the IPFS hash of an action identified by its label
     * @dev Only callable by admin
     * @param actionLabel The label of the action
     * @param newIpfsHash The new IPFS hash for the action
     */
    function updateActionIpfsHashByLabel(bytes32 actionLabel, string memory newIpfsHash) external onlyAdmin {
        uint256 actionId = labelToId[actionLabel];
        require(actionId != 0, "Action does not exist");

        bytes32 actionHash = getActionHashFromIpfsHash(idToAction[actionId].ipfsHash);

        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
    }

    /**
     * @notice Emergency function to disable an action by its ID
     * @dev Only callable by accounts with SENTINEL_ROLE
     * @param actionId The ID of the action to disable
     */
    function emergencyDisableActionById(uint256 actionId) external onlySentinel {
        _updateActionStatus(actionId, false);
    }

    /**
     * @notice Emergency function to disable an action by its hash
     * @dev Only callable by accounts with SENTINEL_ROLE
     * @param actionHash The hash of the action to disable
     */
    function emergencyDisableActionByHash(bytes32 actionHash) external onlySentinel {
        uint256 actionId = hashToId[actionHash];
        _updateActionStatus(actionId, false);
    }

    /**
     * @notice Emergency function to disable an action by its label
     * @dev Only callable by accounts with SENTINEL_ROLE
     * @param actionLabel The label of the action to disable
     */
    function emergencyDisableActionByLabel(bytes32 actionLabel) external onlySentinel {
        uint256 actionId = labelToId[actionLabel];
        _updateActionStatus(actionId, false);
    }

    /**
     * @notice Emergency function to disable an orchestrator
     * @dev Only callable by accounts with SENTINEL_ROLE
     * @param _orchestrator The address of the orchestrator
     */
    function emergencyDisableOrchestrator(address _orchestrator) external onlySentinel {
        authorizedOrchestrators[_orchestrator] = false;
        emit OrchestratorAuthorized(_orchestrator, false);
    }

    /**
     * @notice Emergency function to disable a commit hash
     * @dev Only callable by accounts with SENTINEL_ROLE
     * @param _commitHash The commit hash to disable
     */
    function emergencyDisableCommitHash(bytes32 _commitHash) external onlySentinel {
        authorizedCommitHashes[_commitHash] = false;
        emit CommitHashAuthorized(_commitHash, false);
    }

    /**
     * @notice Checks wether an orchestrator is authorized or not
     * @param _orchestrator The address of the orchestrator
     * @return whether the orchestrator is authorized or not
     */
    function isAuthorizedOrchestrator(address _orchestrator) external view returns (bool) {
        return authorizedOrchestrators[_orchestrator];
    }

    /**
     * @notice Verify if an action is active or not
     * @param _ipfsHash The IPFS hash of the action
     * @return whether the action is active or not
     */
    function isActionActive(string memory _ipfsHash) external view returns (bool) {
        return idToAction[hashToId[getActionHashFromIpfsHash(_ipfsHash)]].active;
    }

    /**
     * @notice Retrieves an action by its IPFS hash
     * @param _ipfsHash The IPFS hash of the action
     * @return Action struct containing the action details
     */
    function getActionByIpfsHash(string memory _ipfsHash) external view returns (Action memory) {
        return getActionByActionHash(getActionHashFromIpfsHash(_ipfsHash));
    }

    /**
     * @notice Retrieves an action by its action hash
     * @param _actionHash The action hash
     * @return Action struct containing the action details
     */
    function getActionByActionHash(bytes32 _actionHash) public view returns (Action memory) {
        Action memory action = idToAction[hashToId[_actionHash]];
        require(bytes(action.ipfsHash).length != 0, "Action does not exist");
        return action;
    }

    /**
     * @notice Retrieves an action by its label
     * @param _actionLabel The label of the action
     * @return Action struct containing the action details
     */
    function getActionByActionLabel(bytes32 _actionLabel) external view returns (Action memory) {
        Action memory action = idToAction[labelToId[_actionLabel]];
        require(bytes(action.ipfsHash).length != 0, "Action does not exist");
        return action;
    }

    /**
     * @notice Generates an action hash from an IPFS hash
     * @param ipfsHash The IPFS hash to convert
     * @return The generated action hash
     */
    function getActionHashFromIpfsHash(string memory ipfsHash) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(ipfsHash));
    }

    /**
     * @dev Internal function to update an action's IPFS hash
     * @param actionId The ID of the action to update
     * @param prevActionHash The previous action hash
     * @param newIpfsHash The new IPFS hash
     */
    function _updateActionIpfsHash(uint256 actionId, bytes32 prevActionHash, string memory newIpfsHash) internal {
        bytes32 newActionHash = getActionHashFromIpfsHash(newIpfsHash);
        require(prevActionHash != newActionHash, "New IPFS hash is the same as the old one");
        require(hashToId[newActionHash] == 0, "New IPFS hash already exists");

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
    function _updateActionLabel(uint256 actionId, bytes32 oldLabel, bytes32 newLabel) internal {
        require(labelToId[newLabel] == 0, "New label already exists");

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
    function _newAction(bytes32 label, bytes32 actionHash, string memory ipfsHash) internal {
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
        require(bytes(action.ipfsHash).length != 0, "Action does not exist");

        require(action.active != active, "Status is already set to this value");

        action.active = active;
        emit ActionStatusUpdated(id, active);
    }
}