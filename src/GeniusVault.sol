// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC4626, ERC20} from "@solmate/tokens/ERC4626.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {GeniusPool} from "./GeniusPool.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";


/**
 * @title GeniusVault
 * @dev A contract that represents a vault for holding assets and interacting with the GeniusPool contract.
 */
contract GeniusVault is ERC4626, Ownable {

    // =============================================================
    //                          IMMUTABLES
    // =============================================================

    GeniusPool public geniusPool;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    bool initialized;

    // =============================================================
    //                         CONSTRUCTOR
    // =============================================================

    constructor(
        address _asset
    ) ERC4626(ERC20(_asset), "Genius USD", "gUSD") Ownable(tx.origin) {
        initialized = false;
    }

    // =============================================================
    //                     INTERNAL OVERRIDES
    // =============================================================

    /**
     * @dev Returns the total assets held in the GeniusVault contract.
     * @return uint256 total amount of assets held in the GeniusVault contract.
     */
    function totalAssets() public view override returns (uint256) {
        return geniusPool.totalStakedAssets();
    }

    /**
     * @dev Initializes the GeniusVault contract.
     * @param _geniusPool The address of the GeniusPool contract.
     * @notice This function can only be called once to initialize the contract.
     */
    function initialize(address _geniusPool) external onlyOwner {
        if (initialized) revert GeniusErrors.Initialized();
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
     * Throws an `InvalidAssetAmount` exception if either the assets or shares amount is zero.
     */
    function afterDeposit(uint256 assets, uint256 shares) internal override {
        if (!initialized) revert GeniusErrors.NotInitialized();
        if (assets == 0 || shares == 0) revert GeniusErrors.InvalidAssetAmount(assets, shares);

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
     */
    function beforeWithdraw(uint256 assets, uint256 shares) internal override {
        if (!initialized) revert GeniusErrors.NotInitialized();
        if (assets == 0 || shares == 0) revert GeniusErrors.InvalidAssetAmount(assets, shares);

        uint256 vaultDeposits = geniusPool.totalStakedAssets();

        if (assets > vaultDeposits) revert GeniusErrors.InvalidAssetAmount(assets, shares);

        geniusPool.removeStakedLiquidity(msg.sender, assets);
    }
}