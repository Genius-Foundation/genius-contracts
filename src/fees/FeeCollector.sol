// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusErrors} from "../libs/GeniusErrors.sol";
import {IFeeCollector} from "../interfaces/IFeeCollector.sol";
import {IGeniusVault} from "../interfaces/IGeniusVault.sol";

/**
 * @title FeeCollector
 * @notice Handles the distribution and collection of fees in the Genius protocol
 * @dev This contract is upgradeable and receives fees from the vault
 */
contract FeeCollector is
    IFeeCollector,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant WORKER_ROLE = keccak256("WORKER_ROLE");

    // Protocol/LP/Base fees accounting
    uint256 public protocolFeesCollected;
    uint256 public protocolFeesClaimed;
    uint256 public lpFeesCollected;
    uint256 public lpFeesClaimed;
    uint256 public baseFeesCollected;
    uint256 public baseFeesClaimed;

    // Fee settings
    uint256 public protocolFeeBps; // What percentage of fees goes to protocol
    uint256 public lpFeeBps; // What percentage of fees goes to LPs

    // The token (stablecoin) used for fees
    IERC20 public stablecoin;

    // Only the vault can update fees collected
    address public vault;

    // Constructor disables initialization for implementation contract
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FeeCollector contract
     * @param _admin Admin address that can manage fee settings
     * @param _stablecoin The stablecoin used for fee payments
     * @param _protocolFeeBps The percentage (in basis points) of fees allocated to protocol
     * @param _lpFeeBps The percentage (in basis points) of fees allocated to LPs
     */
    function initialize(
        address _admin,
        address _stablecoin,
        uint256 _protocolFeeBps,
        uint256 _lpFeeBps
    ) external initializer {
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();

        // Protocol + LP fees cannot exceed 100%
        if (_protocolFeeBps + _lpFeeBps > 10000)
            revert GeniusErrors.InvalidPercentage();

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        stablecoin = IERC20(_stablecoin);
        protocolFeeBps = _protocolFeeBps;
        lpFeeBps = _lpFeeBps;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Update the fees collected based on a new order
     * @dev Can only be called by the vault
     * @param bpsFee The BPS fee component
     * @param baseFee The base fee component
     * @param feeSurplus Any surplus fees beyond the minimum required
     */
    function updateFees(
        uint256 bpsFee,
        uint256 baseFee,
        uint256 feeSurplus
    ) external {
        if (msg.sender != vault) revert GeniusErrors.NotAuthorized();

        // Calculate fee distribution based on percentages
        uint256 protocolFee = (bpsFee * protocolFeeBps) / 10000;
        uint256 lpFee = (bpsFee * lpFeeBps) / 10000;

        // Add fees to their respective buckets
        protocolFeesCollected += protocolFee;
        lpFeesCollected += lpFee;

        // Add base fee plus any surplus to the base fees
        baseFeesCollected += baseFee + feeSurplus;

        emit FeesUpdated(protocolFee, lpFee, baseFee + feeSurplus);
    }

    /**
     * @notice Allows admins to claim protocol fees
     * @return amount The amount of fees claimed
     */
    function claimProtocolFees()
        external
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
        returns (uint256 amount)
    {
        // Ensure all fees are transferred from the vault first
        _claimFeesFromVault();
        
        amount = protocolFeesCollected - protocolFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        protocolFeesClaimed += amount;
        stablecoin.safeTransfer(msg.sender, amount);

        emit ProtocolFeesClaimed(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Allows LP fee distributors to claim LP fees
     * @return amount The amount of fees claimed
     */
    function claimLPFees()
        external
        nonReentrant
        onlyRole(DISTRIBUTOR_ROLE)
        returns (uint256 amount)
    {
        // Ensure all fees are transferred from the vault first
        _claimFeesFromVault();
        
        amount = lpFeesCollected - lpFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        lpFeesClaimed += amount;
        stablecoin.safeTransfer(msg.sender, amount);

        emit LPFeesClaimed(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Allows workers to claim base fees for operational expenses
     * @return amount The amount of fees claimed
     */
    function claimBaseFees()
        external
        nonReentrant
        onlyRole(WORKER_ROLE)
        returns (uint256 amount)
    {
        // Ensure all fees are transferred from the vault first
        _claimFeesFromVault();
        
        amount = baseFeesCollected - baseFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        baseFeesClaimed += amount;
        stablecoin.safeTransfer(msg.sender, amount);

        emit BaseFeesClaimed(msg.sender, amount);
        return amount;
    }
    
    /**
     * @dev Internal function to claim all pending fees from the vault
     */
    function _claimFeesFromVault() internal {
        if (vault != address(0)) {
            // Call the vault's claimFees function to transfer fees to this contract
            try IGeniusVault(vault).claimFees() {
                // Successfully claimed fees from vault
            } catch {
                // If the call fails, we still proceed with the claim operation
                // using whatever funds are already in this contract
            }
        }
    }

    /**
     * @notice Sets the vault address that can update fees
     * @param _vault The vault contract address
     */
    function setVault(address _vault) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_vault == address(0)) revert GeniusErrors.NonAddress0();
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @notice Sets the fee distribution percentages
     * @param _protocolFeeBps Percentage (in basis points) allocated to protocol
     * @param _lpFeeBps Percentage (in basis points) allocated to LPs
     */
    function setFeeDistribution(
        uint256 _protocolFeeBps,
        uint256 _lpFeeBps
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Protocol + LP fees cannot exceed 100%
        if (_protocolFeeBps + _lpFeeBps > 10000)
            revert GeniusErrors.InvalidPercentage();

        protocolFeeBps = _protocolFeeBps;
        lpFeeBps = _lpFeeBps;

        emit FeeDistributionUpdated(_protocolFeeBps, _lpFeeBps);
    }

    /**
     * @notice Returns the total claimable protocol fees
     * @return Amount of protocol fees available to claim
     */
    function claimableProtocolFees() external view returns (uint256) {
        return protocolFeesCollected - protocolFeesClaimed;
    }

    /**
     * @notice Returns the total claimable LP fees
     * @return Amount of LP fees available to claim
     */
    function claimableLPFees() external view returns (uint256) {
        return lpFeesCollected - lpFeesClaimed;
    }

    /**
     * @notice Returns the total claimable base fees
     * @return Amount of base fees available to claim
     */
    function claimableBaseFees() external view returns (uint256) {
        return baseFeesCollected - baseFeesClaimed;
    }

    /**
     * @dev Authorizes contract upgrades
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
