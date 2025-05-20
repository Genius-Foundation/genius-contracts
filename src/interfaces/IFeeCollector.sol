// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IFeeCollector
 * @notice Interface for the FeeCollector contract
 */
interface IFeeCollector {
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
     * @notice Emitted when fees are updated by the vault
     * @param orderHash The hash of the order processed
     * @param protocolFee Amount of protocol fees added
     * @param lpFee Amount of LP fees added
     * @param operatorFee Amount of operator fees added
     */
    event FeesCollectedFromVault(
        bytes32 indexed orderHash,
        uint256 protocolFee,
        uint256 lpFee,
        uint256 operatorFee
    );

    /**
     * @notice Emitted when protocol fees are claimed
     * @param claimant The address that initiated the claim
     * @param receiver The address that received the fees
     * @param amount The amount claimed
     */
    event ProtocolFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );

    /**
     * @notice Emitted when LP fees are claimed
     * @param claimant The address that initiated the claim
     * @param receiver The address that received the fees
     * @param amount The amount claimed
     */
    event LPFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );

    /**
     * @notice Emitted when operator fees are claimed
     * @param claimant The address that initiated the claim
     * @param receiver The address that received the fees
     * @param amount The amount claimed
     */
    event OperatorFeesClaimed(
        address indexed claimant,
        address indexed receiver,
        uint256 amount
    );

    /**
     * @notice Emitted when the protocol fee receiver is set
     * @param receiver The new protocol fee receiver
     */
    event ProtocolFeeReceiverSet(address receiver);

    /**
     * @notice Emitted when the LP fee receiver is set
     * @param receiver The new LP fee receiver
     */
    event LPFeeReceiverSet(address receiver);

    /**
     * @notice Emitted when the operator fee receiver is set
     * @param receiver The new operator fee receiver
     */
    event OperatorFeeReceiverSet(address receiver);

    /**
     * @notice Emitted when the vault address is set
     * @param vault The new vault address
     */
    event VaultSet(address vault);

    /**
     * @notice Emitted when the protocol fee percentage is updated
     * @param protocolFee The new protocol fee percentage
     */
    event ProtocolFeeUpdated(uint256 protocolFee);

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
     * @param targetChainId The id of the target chain
     * @param newMinFee The new minimum fee for the target chain
     */
    event TargetChainMinFeeChanged(uint256 targetChainId, uint256 newMinFee);

    /**
     * @notice Collects and processes fees for an order
     * @dev Can only be called by the vault
     * @param _orderHash The hash of the order
     * @param _amountIn The order amount
     * @param _destChainId The destination chain ID
     * @param _orderFee The total fee amount provided with the order
     * @return amountToTransfer The amount of fees to transfer to the fee collector
     */
    function collectFromVault(
        bytes32 _orderHash,
        uint256 _amountIn,
        uint256 _destChainId,
        uint256 _orderFee
    ) external returns (uint256 amountToTransfer);

    /**
     * @notice Allows admins to claim protocol fees for the designated receiver
     * @return amount The amount of fees claimed
     */
    function claimProtocolFees() external returns (uint256 amount);

    /**
     * @notice Allows LP fee distributors to claim LP fees for the designated receiver
     * @return amount The amount of fees claimed
     */
    function claimLPFees() external returns (uint256 amount);

    /**
     * @notice Allows workers to claim operator fees for the designated receiver
     * @return amount The amount of fees claimed
     */
    function claimOperatorFees() external returns (uint256 amount);

    /**
     * @notice Sets the protocol fee receiver address
     * @param _receiver The address to receive protocol fees
     */
    function setProtocolFeeReceiver(address _receiver) external;

    /**
     * @notice Sets the LP fee receiver address
     * @param _receiver The address to receive LP fees
     */
    function setLPFeeReceiver(address _receiver) external;

    /**
     * @notice Sets the operator fee receiver address
     * @param _receiver The address to receive operator fees
     */
    function setOperatorFeeReceiver(address _receiver) external;

    /**
     * @notice Sets the vault address that can update fees
     * @param _vault The vault contract address
     */
    function setVault(address _vault) external;

    /**
     * @notice Sets the protocol fee percentage
     * @param _protocolFee Percentage of the BPS fees allocated to protocol
     */
    function setProtocolFee(uint256 _protocolFee) external;

    /**
     * @notice Sets the minimum fee for a target chain
     * @param _targetChainId The id of the target chain
     * @param _minFee The new minimum fee for the target chain
     */
    function setTargetChainMinFee(
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

    /**
     * @notice Returns the total claimable protocol fees
     * @return Amount of protocol fees available to claim
     */
    function claimableProtocolFees() external view returns (uint256);

    /**
     * @notice Returns the total claimable LP fees
     * @return Amount of LP fees available to claim
     */
    function claimableLPFees() external view returns (uint256);

    /**
     * @notice Returns the total claimable operator fees
     * @return Amount of operator fees available to claim
     */
    function claimableOperatorFees() external view returns (uint256);

    /**
     * @notice Calculates the complete fee breakdown for an order
     * @param _amount The order amount
     * @param _destChainId The destination chain ID
     * @return A FeeBreakdown struct containing the breakdown of fees
     */
    function getOrderFees(
        uint256 _amount,
        uint256 _destChainId
    ) external view returns (FeeBreakdown memory);
}
