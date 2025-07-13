// SPDX-License-Identifier: AGPL-3.0-only

pragma solidity ^0.8.21;

/**
 * @dev Interface of the MerkleDistributor contract.
 * Allows anyone to claim a token if they exist in a merkle root.
 */
interface IMerkleDistributor {
    /**
    * @dev Event for tracking merkle root updates.
    * @param sender - address of the transaction sender.
    * @param merkleRoot - new merkle root hash.
    * @param merkleProofs - link to the merkle proofs.
    */
    event MerkleRootUpdated(
        address indexed sender,
        bytes32 indexed merkleRoot,
        string merkleProofs
    );

    /**
    * @dev Event for tracking rewards submissions.
    * @param sender - address of the sender submitting rewards.
    * @param token - address of the token.
    * @param amount - amount of tokens submitted.
    * @param blockNumber - block number when rewards were submitted.
    */
    event RewardsSubmitted(
        address indexed sender,
        address indexed token,
        uint256 amount,
        uint256 blockNumber
    );

    /**
    * @dev Event for tracking tokens' claims.
    * @param account - the address of the user that has claimed the tokens.
    * @param index - the index of the user that has claimed the tokens.
    * @param tokens - list of token addresses the user got amounts in.
    * @param amounts - list of user token amounts.
    */
    event Claimed(address indexed account, uint256 index, address[] tokens, uint256[] amounts);

    /**
    * @dev Event for tracking oracle additions.
    * @param oracle - address of the oracle that was added.
    */
    event OracleAdded(address indexed oracle);

    /**
    * @dev Event for tracking oracle removals.
    * @param oracle - address of the oracle that was removed.
    */
    event OracleRemoved(address indexed oracle);

    /**
    * @dev Function for getting the current merkle root.
    */
    function merkleRoot() external view returns (bytes32);

    /**
    * @dev Function for retrieving the last merkle root update block number.
    */
    function lastMerkleUpdateBlockNumber() external view returns (uint256);

    /**
    * @dev Function for retrieving the last rewards update block number.
    */
    function lastRewardsUpdateBlockNumber() external view returns (uint256);

    /**
    * @dev Function for getting the oracle count.
    */
    function oracleCount() external view returns (uint256);

    /**
    * @dev Function for checking the claimed bit map.
    * @param _merkleRoot - the merkle root hash.
    * @param _wordIndex - the word index of the bit map.
    */
    function claimedBitMap(bytes32 _merkleRoot, uint256 _wordIndex) external view returns (uint256);

    /**
    * @dev Function for checking whether an account is an oracle.
    * @param account - address to check.
    */
    function isOracle(address account) external view returns (bool);

    /**
    * @dev Function for adding a new oracle. Can only be called by admin.
    * @param account - address of the oracle to add.
    */
    function addOracle(address account) external;

    /**
    * @dev Function for removing an oracle. Can only be called by admin.
    * @param account - address of the oracle to remove.
    */
    function removeOracle(address account) external;

    /**
    * @dev Function for checking whether merkle root voting is active.
    */
    function isMerkleRootVoting() external view returns (bool);

    /**
    * @dev Function for changing the merkle root. Can only be called by oracles with enough signatures.
    * @param newMerkleRoot - new merkle root hash.
    * @param newMerkleProofs - URL to the merkle proofs.
    * @param signatures - array of oracle signatures.
    */
    function setMerkleRoot(bytes32 newMerkleRoot, string calldata newMerkleProofs, bytes[] calldata signatures) external;

    /**
    * @dev Function for submitting rewards to the distributor.
    * Can only be called by accounts with DISTRIBUTOR_ROLE.
    * @param token - address of the token to submit.
    * @param amount - amount of tokens to submit.
    */
    function submitRewards(address token, uint256 amount) external;

    /**
    * @dev Function for checking whether the tokens were already claimed.
    * @param index - the index of the user that is part of the merkle root.
    */
    function isClaimed(uint256 index) external view returns (bool);

    /**
    * @dev Function for claiming the given amount of tokens to the account address.
    * Reverts if the inputs are invalid or the merkle root is being updated.
    * @param index - the index of the user that is part of the merkle root.
    * @param account - the address of the user that is part of the merkle root.
    * @param tokens - list of the token addresses.
    * @param amounts - list of token amounts.
    * @param merkleProof - an array of hashes to verify whether the user is part of the merkle root.
    */
    function claim(
        uint256 index,
        address account,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata merkleProof
    ) external;
}