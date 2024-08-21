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

    struct Action {
        bytes32 label;
        string ipfsHash;
        bool active;
    }

    uint256 nextActionId = 1;
    uint256 inactiveCount = 0;

    mapping(uint256 => Action) private idToAction;
    mapping(bytes32 => uint256) private hashToId;
    mapping(bytes32 => uint256) private labelToId;

    constructor(address initialOwner) Ownable(initialOwner) {
        require(initialOwner != msg.sender, "Initial owner cannot be the contract deployer");
    }

    /**
     * @dev Adds a new action with the given IPFS hash.
     * @param ipfsHash The IPFS hash of the action.
     */
    function addAction(bytes32 actionLabel, string memory ipfsHash) public onlyOwner {
        bytes32 actionHash = _getActionHashFromIpfsHash(ipfsHash);
        require(labelToId[actionLabel] == 0, "Label already exists");
        require(hashToId[actionHash] == 0, "IPFS hash already exists");
        _newAction(actionLabel, actionHash, ipfsHash);
    }

    function updateActionStatusByHash(bytes32 actionHash, bool active) public onlyOwner {
        uint256 actionId = hashToId[actionHash];
        require(actionId != 0, "Action does not exist");
        require(idToAction[actionId].active != active, "Status is already set to this value");
        
        if (active) {
            inactiveCount--;
        } else {
            inactiveCount++;
        }

        idToAction[actionId].active = active;
    }

    function updateActionStatusByLabel(bytes32 actionLabel, bool active) public onlyOwner {
        uint256 actionId = labelToId[actionLabel];
        require(actionId != 0, "Action does not exist");
        require(idToAction[actionId].active != active, "Status is already set to this value");
        
        if (active) {
            inactiveCount--;
        } else {
            inactiveCount++;
        }

        idToAction[actionId].active = active;
    }

    function updateActionIpfsHashByHash(bytes32 actionHash, string memory newIpfsHash) public onlyOwner {
        uint256 actionId = hashToId[actionHash];
        require(actionId != 0, "Action does not exist");
        
        _updateActionIpfsHash(actionHash, actionId, newIpfsHash);
    }

    function updateActionIpfsHashByLabel(bytes32 actionLabel, string memory newIpfsHash) public onlyOwner {
        uint256 actionId = labelToId[actionLabel];
        require(actionId != 0, "Action does not exist");

        bytes32 actionHash = _getActionHashFromIpfsHash(idToAction[actionId].ipfsHash);
        
        _updateActionIpfsHash(actionHash, actionId, newIpfsHash);
    }

    function getActionByIpfsHash(string memory _ipfsHash) public view returns (Action memory) {
        return getActionByActionHash(_getActionHashFromIpfsHash(_ipfsHash));
    }

    function getActionByActionHash(bytes32 _actionHash) public view returns (Action memory) {
        Action memory action = idToAction[hashToId[_actionHash]];
        require(bytes(action.ipfsHash).length != 0, "Action does not exist");
        return action;
    }

    function getActionByActionLabel(bytes32 _actionLabel) public view returns (Action memory) {
        Action memory action = idToAction[labelToId[_actionLabel]];
        require(bytes(action.ipfsHash).length != 0, "Action does not exist");
        return action;
    }

    function getActiveActions() public view returns (Action[] memory) {
        Action[] memory result = new Action[](activeCount());
        uint256 activeIndex = 0;

        for (uint256 i = 1; i < nextActionId; i++) {
            Action memory action = idToAction[i];
            if (action.active) {
                result[activeIndex] = action;
                activeIndex++;
            }
        }

        return result;
    }

    function getInactiveActions() public view returns (Action[] memory) {
        Action[] memory result = new Action[](inactiveCount);
        uint256 inactiveIndex = 0;

        for (uint256 i = 1; i < nextActionId; i++) {
            Action memory action = idToAction[i];
            if (!action.active) {
                result[inactiveIndex] = action;
                inactiveIndex++;
            }
        }

        return result;
    }

    function activeCount() public view returns (uint256) {
        return nextActionId - 1 - inactiveCount;
    }

    function _updateActionIpfsHash(bytes32 actionHash, uint256 actionId, string memory newIpfsHash) internal {
        bytes32 newActionHash = _getActionHashFromIpfsHash(newIpfsHash);
        require(hashToId[newActionHash] == 0, "New IPFS hash already exists");

        hashToId[actionHash] = 0;
        hashToId[newActionHash] = actionId;      
        idToAction[actionId].ipfsHash = newIpfsHash;
    }

    function _newAction(bytes32 label, bytes32 actionHash, string memory ipfsHash) internal {
        idToAction[nextActionId] = Action(label, ipfsHash, true);
        labelToId[label] = nextActionId;
        hashToId[actionHash] = nextActionId;
        nextActionId++;
    }

    function _getActionHashFromIpfsHash(string memory ipfsHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ipfsHash));
    }
}