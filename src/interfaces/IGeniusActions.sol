// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/**
 * @title IGeniusActions
 * @author looter
 * @notice Interface for managing Genius Protocol actions and their associated IPFS hashes.
 */
interface IGeniusActions {
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

    /**
     * @notice Changes the authorization status of an orchestrator
     * @param _orchestrator the address of the orchestrator
     * @param _authorized the new authorization status
     */
    function setOrchestratorAuthorized(address _orchestrator, bool _authorized) external;

    /**
     * @notice Changes the authorization status of a mutliple orchestrators
     * @param _orchestrators the array of orchestrators to set the authorization status for
     * @param _authorized the new authorization status for all the orchestrators
     */
    function setBatchOrchestratorAuthorized(address[] calldata _orchestrators, bool _authorized) external;

    /**
     * @notice Changes the authorization status of a commit hash
     * @param _commitHash the commit hash to authorize or deauthorize
     * @param _authorized the new authorization status
     */
    function setCommitHashAuthorized(bytes32 _commitHash, bool _authorized) external;

    /**
     * @notice Changes the authorization status of multiple commit hashes
     * @param _commitHashes the array of commit hashes to set the authorization status for
     * @param _authorized the new authorization status for all the commit hashes
     */
    function setBatchCommitHashAuthorized(bytes32[] calldata _commitHashes, bool _authorized) external;

    /**
     * @notice Checks whether a commit hash is authorized or not
     * @param _commitHash The commit hash to check
     * @return whether the commit hash is authorized or not
     */
    function isAuthorizedCommitHash(bytes32 _commitHash) external view returns (bool);

    /**
     * @notice Adds a new action with the given label and IPFS hash
     * @param actionLabel The label for the new action
     * @param ipfsHash The IPFS hash of the action
     */
    function addAction(bytes32 actionLabel, string memory ipfsHash) external;

    /**
     * @notice Updates the status of an action identified by its hash
     * @param actionHash The hash of the action to update
     * @param active The new status of the action
     */
    function updateActionStatusByHash(bytes32 actionHash, bool active) external;

    /**
     * @notice Updates the status of an action identified by its label
     * @param actionLabel The label of the action to update
     * @param active The new status of the action
     */
    function updateActionStatusByLabel(bytes32 actionLabel, bool active) external;

    /**
     * @notice Updates the IPFS hash of an action identified by its hash
     * @param actionHash The current hash of the action
     * @param newIpfsHash The new IPFS hash for the action
     */
    function updateActionIpfsHashByHash(bytes32 actionHash, string memory newIpfsHash) external;

    /**
     * @notice Updates the IPFS hash of an action identified by its label
     * @param actionLabel The label of the action
     * @param newIpfsHash The new IPFS hash for the action
     */
    function updateActionIpfsHashByLabel(bytes32 actionLabel, string memory newIpfsHash) external;

    /**
     * @notice Emergency function to disable an action by its ID
     * @param actionId The ID of the action to disable
     */
    function emergencyDisableActionById(uint256 actionId) external;

    /**
     * @notice Emergency function to disable an action by its hash
     * @param actionHash The hash of the action to disable
     */
    function emergencyDisableActionByHash(bytes32 actionHash) external;

    /**
     * @notice Emergency function to disable an action by its label
     * @param actionLabel The label of the action to disable
     */
    function emergencyDisableActionByLabel(bytes32 actionLabel) external;

    /**
     * @notice Emergency function to disable an orchestrator
     * @param _orchestrator The address of the orchestrator
     */
    function emergencyDisableOrchestrator(address _orchestrator) external;

    /**
     * @notice Emergency function to disable a commit hash
     * @param _commitHash The commit hash to disable
     */
    function emergencyDisableCommitHash(bytes32 _commitHash) external;

    /**
     * @notice Checks wether an orchestrator is authorized or not
     * @param _orchestrator The address of the orchestrator
     * @return whether the orchestrator is authorized or not
     */
    function isAuthorizedOrchestrator(address _orchestrator) external view returns (bool);

    /**
     * @notice Verify if an action is active or not
     * @param _ipfsHash The IPFS hash of the action
     * @return whether the action is active or not
     */
    function isActionActive(string memory _ipfsHash) external view returns (bool);

    /**
     * @notice Retrieves an action by its IPFS hash
     * @param _ipfsHash The IPFS hash of the action
     * @return Action struct containing the action details
     */
    function getActionByIpfsHash(string memory _ipfsHash) external view returns (Action memory);

    /**
     * @notice Retrieves an action by its action hash
     * @param _actionHash The action hash
     * @return Action struct containing the action details
     */
    function getActionByActionHash(bytes32 _actionHash) external view returns (Action memory);

    /**
     * @notice Retrieves an action by its label
     * @param _actionLabel The label of the action
     * @return Action struct containing the action details
     */
    function getActionByActionLabel(bytes32 _actionLabel) external view returns (Action memory);

    /**
     * @notice Generates an action hash from an IPFS hash
     * @param ipfsHash The IPFS hash to convert
     * @return The generated action hash
     */
    function getActionHashFromIpfsHash(string memory ipfsHash) external pure returns (bytes32);
}