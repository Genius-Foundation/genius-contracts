// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Upgradeable contract and ownable
import "@openzeppelin/contracts/access/Ownable.sol";

contract GeniusActions is Ownable {
    mapping(string => string) public actionTypeToIpfsHash;

    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != msg.sender, "Initial owner cannot be the contract deployer");
    }

    /**
     * @dev Adds a new action with the given IPFS hash.
     * @param ipfsHash The IPFS hash of the action.
     */
    function addAction(string memory action, string memory ipfsHash) public onlyOwner {
        require(bytes(actionTypeToIpfsHash[action]).length == 0, "Action already exists");
        actionTypeToIpfsHash[action] = ipfsHash;
    }

    /**
     * @dev Removes an action from the `actionTypeToIpfsHash` array at the specified index.
     * @param action The index of the action to be removed.
     * @notice Only the contract owner can call this function.
     * @dev Throws an error if the index is out of bounds.
     */
    function removeAction(string memory action) public onlyOwner {
        // Requre that the action exists
        require(bytes(actionTypeToIpfsHash[action]).length != 0, "Action does not exist");
        delete actionTypeToIpfsHash[action];
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
}
