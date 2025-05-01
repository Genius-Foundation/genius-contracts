// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IFeeCollector
 * @notice Interface for the FeeCollector contract
 */
interface IFeeCollector {
    /**
     * @notice Emitted when fees are updated by the vault
     * @param protocolFee Amount of protocol fees added
     * @param lpFee Amount of LP fees added
     * @param baseFee Amount of base fees added
     */
    event FeesUpdated(uint256 protocolFee, uint256 lpFee, uint256 baseFee);

    /**
     * @notice Emitted when protocol fees are claimed
     * @param claimant The address that claimed the fees
     * @param amount The amount claimed
     */
    event ProtocolFeesClaimed(address indexed claimant, uint256 amount);

    /**
     * @notice Emitted when LP fees are claimed
     * @param claimant The address that claimed the fees
     * @param amount The amount claimed
     */
    event LPFeesClaimed(address indexed claimant, uint256 amount);

    /**
     * @notice Emitted when base fees are claimed
     * @param claimant The address that claimed the fees
     * @param amount The amount claimed
     */
    event BaseFeesClaimed(address indexed claimant, uint256 amount);

    /**
     * @notice Emitted when the vault address is set
     * @param vault The new vault address
     */
    event VaultSet(address vault);

    /**
     * @notice Emitted when fee distribution percentages are updated
     * @param protocolFeeBps The new protocol fee percentage (basis points)
     * @param lpFeeBps The new LP fee percentage (basis points)
     */
    event FeeDistributionUpdated(uint256 protocolFeeBps, uint256 lpFeeBps);

    /**
     * @notice Update the fees collected based on a new order
     * @param bpsFee The BPS fee component
     * @param baseFee The base fee component
     * @param feeSurplus Any surplus fees beyond the minimum required
     */
    function updateFees(
        uint256 bpsFee,
        uint256 baseFee,
        uint256 feeSurplus
    ) external;

    /**
     * @notice Allows admins to claim protocol fees
     * @return amount The amount of fees claimed
     */
    function claimProtocolFees() external returns (uint256 amount);

    /**
     * @notice Allows LP fee distributors to claim LP fees
     * @return amount The amount of fees claimed
     */
    function claimLPFees() external returns (uint256 amount);

    /**
     * @notice Allows workers to claim base fees for operational expenses
     * @return amount The amount of fees claimed
     */
    function claimBaseFees() external returns (uint256 amount);

    /**
     * @notice Sets the vault address that can update fees
     * @param _vault The vault contract address
     */
    function setVault(address _vault) external;

    /**
     * @notice Sets the fee distribution percentages
     * @param _protocolFeeBps Percentage (in basis points) allocated to protocol
     * @param _lpFeeBps Percentage (in basis points) allocated to LPs
     */
    function setFeeDistribution(
        uint256 _protocolFeeBps,
        uint256 _lpFeeBps
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
     * @notice Returns the total claimable base fees
     * @return Amount of base fees available to claim
     */
    function claimableBaseFees() external view returns (uint256);
}