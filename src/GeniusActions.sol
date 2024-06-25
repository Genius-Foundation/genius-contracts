// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

/**
 * @title GeniusActions
 * @author looter
 *
 * @notice A contract for managing Genius Protocol actions and their associated IPFS hashes.
 */

import "@openzeppelin/contracts/access/Ownable.sol";

contract GeniusActions is Ownable {

    string[] private activeActions;
    string[] private inactiveActions;

    mapping(string => string) private actionTypeToIpfsHash;
    mapping(string => string) private inactiveActionTypeToIpfsHash;

    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != msg.sender, "Initial owner cannot be the contract deployer");
    }

    /**
     * @dev Adds a new action with the given IPFS hash.
     * @param ipfsHash The IPFS hash of the action.
     */
    function addAction(string memory action, string memory ipfsHash) public onlyOwner {
        require(bytes(actionTypeToIpfsHash[action]).length == 0, "Action already exists");
        actionTypeToIpfsHash[action] = ipfsHash; // Add to mapping
        activeActions.push(action); // Add to active actions array
    }

    /**
     * @dev Removes an action from the `actionTypeToIpfsHash` array at the specified index.
     * @param action The index of the action to be removed.
     * @notice Only the contract owner can call this function.
     * @dev Throws an error if the index is out of bounds.
     */
    function removeAction(string memory action) public onlyOwner {
        require(bytes(actionTypeToIpfsHash[action]).length != 0, "Action does not exist");
        
        inactiveActionTypeToIpfsHash[action] = actionTypeToIpfsHash[action];
        
        delete actionTypeToIpfsHash[action];
        for (uint256 i = 0; i < activeActions.length;) {
            if (keccak256(abi.encodePacked(activeActions[i])) == keccak256(abi.encodePacked(action))) {
                activeActions[i] = activeActions[activeActions.length - 1];
                activeActions.pop();
                break;
            }

            unchecked {
                i++;
            }
        }

        inactiveActions.push(action);
    }

    /**
     * @dev Updates the IPFS hash for a specific action type.
     * @param action The index of the action type to update.
     * @param ipfsHash The new IPFS hash to set for the action type.
     * @notice Only the contract owner can call this function.
     * @dev Throws an error if the index is out of bounds.
     */
    function updateAction(string memory action, string memory ipfsHash) public onlyOwner {
        require(bytes(actionTypeToIpfsHash[action]).length != 0, "Action does not exist");
        actionTypeToIpfsHash[action] = ipfsHash;
    }

    /**
     * @dev Retrieves the IPFS hash associated with the action at the specified index.
     * @param action The index of the action.
     * @return The IPFS hash of the action.
     * @notice Throws an error if the index is out of bounds.
     */
    function getAction(string memory action) public view returns (string memory) {
        require(bytes(actionTypeToIpfsHash[action]).length != 0, "Action does not exist");
        return actionTypeToIpfsHash[action];
    }

    /**
     * @dev Retrieves the IPFS hash associated with the historical action at the specified index.
     * @param action The index of the historical action.
     * @return The IPFS hash of the historical action.
     * @notice Throws an error if the index is out of bounds.
     */
    function getInactiveAction(string memory action) public view returns (string memory) {
        require(bytes(inactiveActionTypeToIpfsHash[action]).length != 0, "Historical action does not exist");
        return inactiveActionTypeToIpfsHash[action];
    }

    /**
     * @dev Gets all of the names of the actions (unoptimized for gas efficiency)
     * @return string[] An array of all the active action names.
     */
    function activeActionNames() public view returns (string[] memory) {
        require(activeActions.length > 0, "No active actions");
        return activeActions;
    }

    /**
     * @dev Retrieves the IPFS hash associated with the historical action at the specified index.
     * @return string[] An array of all the historical action names.
     */
    function inactiveActionNames() public view returns (string[] memory) {
        require(inactiveActions.length > 0, "No historical actions");
        return inactiveActions;
    }

    /**
     * @dev Returns the active action name at the specified index.
     * @return string The active action name.
     */
    function getActiveActionName(uint256 index) public view returns (string memory) {
        require(index < activeActions.length, "Index out of bounds");
        return activeActions[index];
    }

    /**
     * @dev Returns the historical action name at the specified index.
     * @return string The historical action name.
     */
    function getInactiveActionName(uint256 index) public view returns (string memory) {
        require(index < inactiveActions.length, "Index out of bounds");
        return inactiveActions[index];
    }

}