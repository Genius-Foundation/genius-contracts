// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IFeeCalculator
 * @notice Interface for the FeeCalculator contract
 */
interface IFeeCalculator {
    /**
     * @notice Struct representing a fee tier based on order size
     * @param thresholdAmount Minimum amount for this tier
     * @param bpsFee Basis points fee for this tier
     */
    struct FeeTier {
        uint256 thresholdAmount; // Minimum amount for this tier
        uint256 bpsFee; // Basis points fee for this tier
    }

    /**
     * @notice Breakdown of different fee components for an order
     * @param baseFee Base fee that goes to operations
     * @param bpsFee BPS fee that goes to fee collector
     * @param insuranceFee Insurance fee that gets re-injected into liquidity
     * @param totalFee Total fee (sum of all components)
     */
    struct FeeBreakdown {
        uint256 baseFee;
        uint256 bpsFee;
        uint256 insuranceFee;
        uint256 totalFee;
    }

    /**
     * @notice Emitted when the fee tiers based on order size are updated
     * @param thresholdAmounts Array of threshold amounts for each tier
     * @param bpsFees Array of basis point fees for each tier
     */
    event FeeTiersUpdated(uint256[] thresholdAmounts, uint256[] bpsFees);

    /**
     * @notice Emitted when insurance fee tiers are updated
     */
    event InsuranceFeeTiersUpdated(
        uint256[] thresholdAmounts,
        uint256[] bpsFees
    );

    /**
     * @notice Emitted when the minimum fee for a target chain has changed
     * @param token The address of the token used as a fee
     * @param targetChainId The id of the target chain
     * @param newMinFee The new minimum fee for the target chain
     */
    event TargetChainMinFeeChanged(
        address token,
        uint256 targetChainId,
        uint256 newMinFee
    );

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
    ) external view returns (FeeBreakdown memory);

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
    ) external;

    /**
     * @notice Sets the fee tiers based on order size
     * @param _thresholdAmounts Array of threshold amounts for each tier (minimum order size)
     * @param _bpsFees Array of basis point fees for each tier
     */
    function setFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) external;

    /**
     * @notice Sets the tiered insurance fee structure based on order size
     * @param _thresholdAmounts Array of threshold amounts for each tier
     * @param _bpsFees Array of basis point fees for each tier
     */
    function setInsuranceFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) external;
}