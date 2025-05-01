// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {GeniusErrors} from "../libs/GeniusErrors.sol";
import {IFeeCalculator} from "../interfaces/IFeeCalculator.sol";

/**
 * @title FeeCalculator
 * @notice Handles the calculation of fees for Genius protocol orders
 * @dev This contract is upgradeable and handles all fee-related calculations
 */
contract FeeCalculator is 
    IFeeCalculator, 
    UUPSUpgradeable, 
    AccessControlUpgradeable 
{
    uint256 public constant BASE_PERCENTAGE = 10_000;

    // Fee tiers for order size (sorted from smallest to largest threshold)
    FeeTier[] public feeTiers;
    FeeTier[] public insuranceFeeTiers;

    // Minimum fees per chain (token => chainId => minFee)
    mapping(address => mapping(uint256 => uint256)) public targetChainMinFee;

    // Constructor disables initialization for implementation contract
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FeeCalculator contract
     * @param _admin Admin address that can manage fee settings
     */
    function initialize(address _admin) external initializer {
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();

        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Calculates the complete fee breakdown for an order
     * @param _tokenIn The token being sent in the order
     * @param _amount The order amount
     * @param _destChainId The destination chain ID
     * @return A FeeBreakdown struct containing the breakdown of fees
     */
    function getOrderFees(
        address _tokenIn,
        uint256 _amount,
        uint256 _destChainId
    ) external view returns (FeeBreakdown memory) {
        return _calculateFeeBreakdown(_tokenIn, _amount, _destChainId);
    }

    /**
     * @notice Sets the minimum fee for a target chain
     * @param _token The address of the token used for the fees
     * @param _targetChainId The id of the target chain
     * @param _minFee The new minimum fee for the target chain
     */
    function setTargetChainMinFee(
        address _token,
        uint256 _targetChainId,
        uint256 _minFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setTargetChainMinFee(_token, _targetChainId, _minFee);
    }

    /**
     * @notice Sets the fee tiers based on order size
     * @param _thresholdAmounts Array of threshold amounts for each tier (minimum order size)
     * @param _bpsFees Array of basis point fees for each tier
     */
    function setFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFeeTiers(_thresholdAmounts, _bpsFees);
    }

    /**
     * @notice Sets the tiered insurance fee structure based on order size
     * @param _thresholdAmounts Array of threshold amounts for each tier
     * @param _bpsFees Array of basis point fees for each tier
     */
    function setInsuranceFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setInsuranceFeeTiers(_thresholdAmounts, _bpsFees);
    }

    /**
     * @dev Internal function to set the minimum fee for a target chain.
     * @param _token The address of the token to spend.
     * @param _targetChainId The target chain ID.
     * @param _minFee The minimum fee required.
     */
    function _setTargetChainMinFee(
        address _token,
        uint256 _targetChainId,
        uint256 _minFee
    ) internal {
        if (_targetChainId == block.chainid)
            revert GeniusErrors.InvalidDestChainId(_targetChainId);

        targetChainMinFee[_token][_targetChainId] = _minFee;
        emit TargetChainMinFeeChanged(_token, _targetChainId, _minFee);
    }

    /**
     * @dev Internal function to set fee tiers based on order size.
     * The tiers should be ordered from smallest to largest threshold amount.
     * @param _thresholdAmounts Array of threshold amounts for each tier (minimum order size for tier)
     * @param _bpsFees Array of basis point fees for each tier
     */
    function _setFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) internal {
        if (_thresholdAmounts.length == 0 || _bpsFees.length == 0)
            revert GeniusErrors.EmptyArray();

        if (_thresholdAmounts.length != _bpsFees.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        // Clear existing tiers
        delete feeTiers;

        // Validate inputs and add new tiers
        uint256 prevThreshold = 0;

        for (uint256 i = 0; i < _thresholdAmounts.length; i++) {
            // Ensure tiers are in ascending order
            if (i > 0 && _thresholdAmounts[i] <= prevThreshold)
                revert GeniusErrors.InvalidAmount();

            // Validate bps fee
            if (_bpsFees[i] > BASE_PERCENTAGE)
                revert GeniusErrors.InvalidPercentage();

            prevThreshold = _thresholdAmounts[i];

            // Add the tier
            feeTiers.push(
                FeeTier({
                    thresholdAmount: _thresholdAmounts[i],
                    bpsFee: _bpsFees[i]
                })
            );
        }

        emit FeeTiersUpdated(_thresholdAmounts, _bpsFees);
    }

    /**
     * @dev Internal function to set insurance fee tiers based on order size.
     * The tiers should be ordered from smallest to largest threshold amount.
     * @param _thresholdAmounts Array of threshold amounts for each tier (minimum order size for tier)
     * @param _bpsFees Array of basis point fees for each tier
     */
    function _setInsuranceFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) internal {
        if (_thresholdAmounts.length == 0 || _bpsFees.length == 0)
            revert GeniusErrors.EmptyArray();

        if (_thresholdAmounts.length != _bpsFees.length)
            revert GeniusErrors.ArrayLengthsMismatch();

        // Clear existing tiers
        delete insuranceFeeTiers;

        // Validate inputs and add new tiers
        uint256 prevThreshold = 0;

        for (uint256 i = 0; i < _thresholdAmounts.length; i++) {
            // Ensure tiers are in ascending order
            if (i > 0 && _thresholdAmounts[i] <= prevThreshold)
                revert GeniusErrors.InvalidAmount();

            // Validate bps fee
            if (_bpsFees[i] > BASE_PERCENTAGE)
                revert GeniusErrors.InvalidPercentage();

            prevThreshold = _thresholdAmounts[i];

            // Add the tier
            insuranceFeeTiers.push(
                FeeTier({
                    thresholdAmount: _thresholdAmounts[i],
                    bpsFee: _bpsFees[i]
                })
            );
        }

        emit InsuranceFeeTiersUpdated(_thresholdAmounts, _bpsFees);
    }

    /**
     * @dev Internal function to determine the basis points fee based on order size.
     * Returns the bps fee for the appropriate tier.
     * If no tiers are set or amount is below the first tier, returns 0.
     * @param _amount The order amount to determine the fee for
     * @return bpsFee The basis points fee to apply
     */
    function _getBpsFeeForAmount(
        uint256 _amount
    ) internal view returns (uint256 bpsFee) {
        if (feeTiers.length == 0) return 0;

        // Default to the lowest tier fee
        bpsFee = feeTiers[0].bpsFee;

        // Find the highest tier that the amount qualifies for
        for (uint256 i = 0; i < feeTiers.length; i++) {
            if (_amount >= feeTiers[i].thresholdAmount) {
                bpsFee = feeTiers[i].bpsFee;
            } else {
                // Found a tier with threshold higher than amount, so break
                break;
            }
        }

        return bpsFee;
    }

    /**
     * @dev Internal function to determine the insurance fee basis points based on order size.
     * Returns the bps fee for the appropriate tier.
     * If no tiers are set or amount is below the first tier, returns 0.
     * @param _amount The order amount to determine the fee for
     * @return bpsFee The basis points fee to apply
     */
    function _getInsuranceFeeBpsForAmount(
        uint256 _amount
    ) internal view returns (uint256 bpsFee) {
        if (insuranceFeeTiers.length == 0) return 0;

        // Default to the lowest tier fee
        bpsFee = insuranceFeeTiers[0].bpsFee;

        // Find the highest tier that the amount qualifies for
        for (uint256 i = 0; i < insuranceFeeTiers.length; i++) {
            if (_amount >= insuranceFeeTiers[i].thresholdAmount) {
                bpsFee = insuranceFeeTiers[i].bpsFee;
            } else {
                // Found a tier with threshold higher than amount, so break
                break;
            }
        }

        return bpsFee;
    }

    /**
     * @dev Internal function to calculate the complete fee breakdown for an order
     * @param _tokenIn The token being sent in the order
     * @param _amount The order amount
     * @param _destChainId The destination chain ID
     * @return FeeBreakdown containing the breakdown of fees
     */
    function _calculateFeeBreakdown(
        address _tokenIn,
        uint256 _amount,
        uint256 _destChainId
    ) internal view returns (FeeBreakdown memory) {
        uint256 baseFee = targetChainMinFee[_tokenIn][_destChainId];

        // Calculate BPS fee
        uint256 bpsFeePercentage = _getBpsFeeForAmount(_amount);
        uint256 bpsFee = (_amount * bpsFeePercentage) / BASE_PERCENTAGE;

        // Calculate insurance fee
        uint256 insuranceFeePercentage = _getInsuranceFeeBpsForAmount(_amount);
        uint256 insuranceFee = (_amount * insuranceFeePercentage) / BASE_PERCENTAGE;

        // Calculate total fee
        uint256 totalFee = baseFee + bpsFee + insuranceFee;

        return
            FeeBreakdown({
                baseFee: baseFee,
                bpsFee: bpsFee,
                insuranceFee: insuranceFee,
                totalFee: totalFee
            });
    }

    /**
     * @dev Authorizes contract upgrades
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}