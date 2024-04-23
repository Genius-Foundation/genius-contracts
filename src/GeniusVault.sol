// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {GeniusPool} from "./GeniusPool.sol";


/**
 * @title GeniusVault
 * @dev A contract that represents a vault for holding assets and interacting with the GeniusPool contract.
 */
contract GeniusVault is ERC4626, Ownable {

    // =============================================================
    //                          INTERFACES
    // =============================================================

    GeniusPool public geniusPool;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    bool initialized;

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev Error thrown when a function is called on an uninitialized contract.
     */
    error NotInitialized();

    /**
     * @dev Error thrown when the contract is already initialized.
     */
    error Initialized();

    /**
     * @dev Error thrown when an invalid amount is passed to a function.
     */
    error InvalidAmount(uint256 assets, uint256 shares);

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(
        ERC20 _asset,
        address _geniusPool
    ) ERC4626(_asset, "Genius USD", "gUSD") Ownable(msg.sender) {
        initialized = false;
        geniusPool = GeniusPool(_geniusPool);
    }

    // =============================================================
    //                     INTERNAL OVERRIDES
    // =============================================================

    /**
     * @dev Returns the total assets held in the GeniusVault contract.
     * @return uint256 total amount of assets held in the GeniusVault contract.
     */
    function totalAssets() public view override returns (uint256) {
        return geniusPool.totalStakedDeposits();
    }

    /**
     * @dev Initializes the GeniusVault contract.
     * @param _geniusPool The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address _geniusPool) external onlyOwner {
        if (initialized) revert Initialized();
        geniusPool = GeniusPool(_geniusPool);
        initialized = true;
    }

    /**
     * @dev This internal function is called after a deposit is made to the GeniusVault contract.
     * It is responsible for handling the deposit by approving the transfer of assets to the GeniusPool contract
     * and staking the liquidity on behalf of the depositor.
     *
     * @param assets The amount of assets being deposited.
     * @param shares The amount of shares being deposited.
     *
     * @dev Throws a `NotInitialized` exception if the contract is not initialized.
     * Throws an `InvalidAmount` exception if either the assets or shares amount is zero.
     */
    function afterDeposit(uint256 assets, uint256 shares) internal override {
        if (!initialized) revert NotInitialized();
        if (assets == 0 || shares == 0) revert InvalidAmount(assets, shares);

        asset.approve(address(geniusPool), assets);
        geniusPool.stakeLiquidity(msg.sender, assets);
    }

    /**
     * @dev This internal function is called before a withdrawal is made from the GeniusVault contract.
     * It performs various checks to ensure the withdrawal is valid.
     * 
     * Requirements:
     * - The contract must be initialized.
     * - The assets and shares being withdrawn must be greater than zero.
     * - The assets being withdrawn must not exceed the total deposits in the GeniusPool contract.
     * 
     * @param assets The amount of assets being withdrawn.
     * @param shares The amount of shares being withdrawn.
     * 
     * @throws NotInitialized if the contract is not initialized.
     * @throws InvalidAmount if the assets or shares being withdrawn are zero.
     * @throws InvalidAmount if the assets being withdrawn exceed the total deposits in the GeniusPool contract.
     */
    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        if (!initialized) revert NotInitialized();
        if (assets == 0 || shares == 0) revert InvalidAmount(assets, shares);

        uint256 vaultDeposits = geniusPool.totalDeposits();
        if (assets > vaultDeposits) revert InvalidAmount(assets, shares);

        geniusPool.removeStakedLiquidity(msg.sender, assets);
    }
}