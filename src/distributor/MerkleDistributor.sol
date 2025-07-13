// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IMerkleDistributor} from "../interfaces/IMerkleDistributor.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {GeniusErrors} from "../libs/GeniusErrors.sol";

/**
 * @title MerkleDistributor
 *
 * @dev MerkleDistributor contract distributes.
 */
contract MerkleDistributor is IMerkleDistributor, UUPSUpgradeable, AccessControlUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");

    // @dev Merkle Root for proving rewards ownership.
    bytes32 public override merkleRoot;

    // @dev Merkle nonce is used to protect from submitting the same merkle root vote several times.
    uint256 private merkleNonce;

    uint256 public override oracleCount;

    // @dev Last merkle root update block number.
    uint256 public override lastMerkleUpdateBlockNumber;
    
    // @dev Last rewards update block number.
    uint256 public override lastRewardsUpdateBlockNumber;
    
    // This is a packed array of booleans.
    mapping (bytes32 => mapping (uint256 => uint256)) private _claimedBitMap;

        /**
     * @dev See {IGeniusVault-initialize}.
     */
    function initialize(
        address _admin
    ) external initializer {
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();

        __AccessControl_init();
        __Pausable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /**
     * @dev See {IOracles-addOracle}.
     */
    function addOracle(address account) external override {
        require(account != address(0), "Oracles: invalid oracle address");
        require(!hasRole(ORACLE_ROLE, account), "Oracles: oracle already exists");
        grantRole(ORACLE_ROLE, account);
        oracleCount++;
        emit OracleAdded(account);
    }

    /**
     * @dev See {IOracles-removeOracle}.
     */
    function removeOracle(address account) external override {
        require(hasRole(ORACLE_ROLE, account), "Oracles: oracle do not exists");
        revokeRole(ORACLE_ROLE, account);
        oracleCount--;
        emit OracleRemoved(account);
    }

    /**
     * @dev See {IMerkleDistributor-isMerkleRootVoting}.
     */
    function isMerkleRootVoting() public view override returns (bool) {
        uint256 lastRewardBlockNumber = lastRewardsUpdateBlockNumber;
        return
            lastMerkleUpdateBlockNumber < lastRewardBlockNumber &&
            lastRewardBlockNumber != block.number;
    }

    /**
     * @dev Function for checking whether the number of signatures is enough to update the value.
     * @param signaturesCount - number of signatures.
     */
    function isEnoughSignatures(uint256 signaturesCount) internal view returns (bool) {
        return oracleCount >= signaturesCount && signaturesCount * 3 > oracleCount * 2;
    }

    /**
     * @dev See {IMerkleDistributor-claimedBitMap}.
     */
    function claimedBitMap(bytes32 _merkleRoot, uint256 _wordIndex) external view override returns (uint256) {
        return _claimedBitMap[_merkleRoot][_wordIndex];
    }

    /**
     * @dev See {IMerkleDistributor-setMerkleRoot}.
     */
    function setMerkleRoot(bytes32 newMerkleRoot, string calldata newMerkleProofs, bytes[] calldata signatures) external override {
        require(isMerkleRootVoting(), "Oracles: too early");
        require(isEnoughSignatures(signatures.length), "Oracles: invalid number of signatures");
        require(hasRole(ORACLE_ROLE, msg.sender), "MerkleDistributor: access denied");

        uint256 nonce = merkleNonce;
        bytes32 candidateId = keccak256(abi.encode(nonce, newMerkleProofs, newMerkleRoot));

        // check signatures and calculate number of submitted oracle votes
        _verifySignatures(candidateId, signatures);

        // increment nonce for future signatures
        merkleNonce++;

        merkleRoot = newMerkleRoot;
        lastMerkleUpdateBlockNumber = block.number;
        emit MerkleRootUpdated(msg.sender, newMerkleRoot, newMerkleProofs);
    }

    function submitRewards(address token, uint256 amount) external override {
        require(hasRole(DISTRIBUTOR_ROLE, msg.sender), "MerkleDistributor: access denied");
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        lastRewardsUpdateBlockNumber = block.number;
        emit RewardsSubmitted(msg.sender, token, amount, block.number);
    }

    /**
     * @dev See {IMerkleDistributor-isClaimed}.
     */
    function isClaimed(uint256 index) external view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = _claimedBitMap[merkleRoot][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index, bytes32 _merkleRoot) internal {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = _claimedBitMap[_merkleRoot][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        require(claimedWord & mask != mask, "MerkleDistributor: already claimed");
        _claimedBitMap[_merkleRoot][claimedWordIndex] = claimedWord | mask;
    }

    /**
     * @dev See {IMerkleDistributor-claim}.
     */
    function claim(
        uint256 index,
        address account,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata merkleProof
    )
        external override whenNotPaused
    {
        require(account != address(0), "MerkleDistributor: invalid account");
        require(
            lastRewardsUpdateBlockNumber < lastMerkleUpdateBlockNumber,
            "MerkleDistributor: merkle root updating"
        );

        // verify the merkle proof
        bytes32 _merkleRoot = merkleRoot; // gas savings
        bytes32 node = keccak256(abi.encode(index, tokens, account, amounts));
        require(MerkleProof.verify(merkleProof, _merkleRoot, node), "MerkleDistributor: invalid proof");

        // mark index claimed
        _setClaimed(index, _merkleRoot);

        // send the tokens
        uint256 tokensCount = tokens.length;
        for (uint256 i = 0; i < tokensCount; i++) {
            address token = tokens[i];
            uint256 amount = amounts[i];
            IERC20(token).safeTransfer(account, amount);
        }
        emit Claimed(account, index, tokens, amounts);
    }

    /**
     * @dev verifySignatures
     *
     * @param candidateId - The hashed value signed by the oracles
     * @param signatures - The array of signatures
     * @return An array of addresses representing the signed oracles
     *
     * @dev Verifies the signatures provided by the oracles and returns an array of addresses
     * that represent the oracles who signed the candidateId.
     */
    function _verifySignatures(
        bytes32 candidateId,
        bytes[] calldata signatures
    ) internal view returns (address[] memory) {
        address[] memory signedOracles = new address[](signatures.length);
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory signature = signatures[i];
            address signer = ECDSA.recover(candidateId, signature);
            require(hasRole(ORACLE_ROLE, signer), "Oracles: invalid signer");

            for (uint256 j = 0; j < i; j++) {
                require(signedOracles[j] != signer, "Oracles: repeated signature");
            }
            signedOracles[i] = signer;
        }
        return signedOracles;
    }

    /**
     * @dev Required by the OZ UUPSUpgradeable contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}