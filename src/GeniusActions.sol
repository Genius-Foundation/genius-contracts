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

    mapping(uint256 => Action) public idToAction;
    mapping(bytes32 => uint256) public hashToId;
    mapping(bytes32 => uint256) public labelToId;

    // Events
    event ActionAdded(uint256 indexed actionId, bytes32 indexed label, string ipfsHash);
    event ActionStatusUpdated(uint256 indexed actionId, bool active);
    event ActionIpfsHashUpdated(uint256 indexed actionId, string newIpfsHash);
    event ActionLabelUpdated(uint256 indexed actionId, bytes32 newLabel);

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
        _updateActionStatus(actionId, active);
    }

    function updateActionStatusByLabel(bytes32 actionLabel, bool active) public onlyOwner {
        uint256 actionId = labelToId[actionLabel];
        _updateActionStatus(actionId, active);
    }

    function updateActionIpfsHashByHash(bytes32 actionHash, string memory newIpfsHash) public onlyOwner {
        uint256 actionId = hashToId[actionHash];
        require(actionId != 0, "Action does not exist");
        
        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
    }

    function updateActionIpfsHashByLabel(bytes32 actionLabel, string memory newIpfsHash) public onlyOwner {
        uint256 actionId = labelToId[actionLabel];
        require(actionId != 0, "Action does not exist");

        bytes32 actionHash = _getActionHashFromIpfsHash(idToAction[actionId].ipfsHash);
        
        _updateActionIpfsHash(actionId, actionHash, newIpfsHash);
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

    function _updateActionIpfsHash(uint256 actionId, bytes32 prevActionHash, string memory newIpfsHash) internal {
        bytes32 newActionHash = _getActionHashFromIpfsHash(newIpfsHash);
        require(hashToId[newActionHash] == 0, "New IPFS hash already exists");

        hashToId[prevActionHash] = 0;
        hashToId[newActionHash] = actionId;      
        idToAction[actionId].ipfsHash = newIpfsHash;
                
        emit ActionIpfsHashUpdated(actionId, newIpfsHash);
    }

    function _updateActionLabel(uint256 actionId, bytes32 oldLabel, bytes32 newLabel) internal {
        require(labelToId[newLabel] == 0, "New label already exists");

        labelToId[oldLabel] = 0;
        labelToId[newLabel] = actionId;
        idToAction[actionId].label = newLabel;

        emit ActionLabelUpdated(actionId, newLabel);
    }

    function _newAction(bytes32 label, bytes32 actionHash, string memory ipfsHash) internal returns (uint256) {
        uint256 actionId = nextActionId;
        idToAction[actionId] = Action(label, ipfsHash, true);
        labelToId[label] = actionId;
        hashToId[actionHash] = actionId;

        emit ActionAdded(actionId, label, ipfsHash);

        nextActionId++;
    }

    function _updateActionStatus(uint256 id, bool active) internal {
        require(id != 0, "Action does not exist");

        Action storage action = idToAction[id];

        require(action.active != active, "Status is already set to this value");
        
        if (active) {
            inactiveCount--;
        } else {
            inactiveCount++;
        }

        action.active = active;
        emit ActionStatusUpdated(id, active);
    }

    function _getActionHashFromIpfsHash(string memory ipfsHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(ipfsHash));
    }
}