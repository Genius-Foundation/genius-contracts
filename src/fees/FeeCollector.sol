// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GeniusErrors} from "../libs/GeniusErrors.sol";
import {IFeeCollector} from "../interfaces/IFeeCollector.sol";

/**
 * @title FeeCollector
 * @notice Handles the calculation, collection, and distribution of fees in the Genius protocol
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
    uint256 public constant BASE_PERCENTAGE = 10_000;

    // Protocol/LP/Operator fees accounting
    uint256 public protocolFeesCollected;
    uint256 public protocolFeesClaimed;
    uint256 public lpFeesCollected;
    uint256 public lpFeesClaimed;
    uint256 public operatorFeesCollected;
    uint256 public operatorFeesClaimed;

    // Fee settings
    uint256 public protocolFee; // What percentage of the bps fees goes to protocol

    // Fee tiers for order size (sorted from smallest to largest threshold)
    FeeTier[] public feeTiers;
    FeeTier[] public insuranceFeeTiers;

    // Minimum fees per chain (token => chainId => minFee)
    mapping(address => mapping(uint256 => uint256)) public targetChainMinFee;

    // The token (stablecoin) used for fees
    IERC20 public stablecoin;

    // Only the vault can add fees
    address public vault;

    // Constructor disables initialization for implementation contract
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the FeeCollector contract
     * @param _admin Admin address that can manage fee settings
     * @param _stablecoin The stablecoin used for fee payments
     * @param _protocolFee The percentage of the bps fees allocated to protocol
     */
    function initialize(
        address _admin,
        address _stablecoin,
        uint256 _protocolFee
    ) external initializer {
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();

        // Protocol + LP fees cannot exceed 100%
        if (_protocolFee > BASE_PERCENTAGE)
            revert GeniusErrors.InvalidPercentage();

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        stablecoin = IERC20(_stablecoin);
        protocolFee = _protocolFee;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Collects and processes fees for an order
     * @dev Can only be called by the vault
     * @param _tokenIn The token being sent in the order
     * @param _amountIn The order amount
     * @param _destChainId The destination chain ID
     * @param _orderFee The total fee amount provided with the order
     * @return amountToTransfer The amount of fees to transfer to the fee collector
     */
    function collectFromVault(
        address _tokenIn,
        uint256 _amountIn,
        uint256 _destChainId,
        uint256 _orderFee
    ) external returns (uint256 amountToTransfer) {
        if (msg.sender != vault) revert GeniusErrors.NotAuthorized();

        // Calculate fee breakdown
        FeeBreakdown memory feeBreakdown = _calculateFeeBreakdown(
            _tokenIn,
            _amountIn,
            _destChainId
        );

        // Check if the provided fee is sufficient
        if (_orderFee < feeBreakdown.totalFee)
            revert GeniusErrors.InsufficientFees(
                _orderFee,
                feeBreakdown.totalFee,
                _tokenIn
            );

        // Calculate any surplus fee over the required minimum
        uint256 feeSurplus = 0;
        if (_orderFee > feeBreakdown.totalFee) {
            feeSurplus = _orderFee - feeBreakdown.totalFee;
        }

        // Calculate fee distribution based on percentages
        uint256 protocolFeeAmount = (feeBreakdown.bpsFee * protocolFee) /
            BASE_PERCENTAGE;
        uint256 lpFee = feeBreakdown.bpsFee - protocolFeeAmount;

        // Add fees to their respective buckets
        protocolFeesCollected += protocolFeeAmount;
        lpFeesCollected += lpFee;

        // Add base fee plus any surplus to the operator fees
        operatorFeesCollected += feeBreakdown.baseFee + feeSurplus;

        // The vault should transfer the total fee minus insurance fee to the fee collector
        amountToTransfer = _orderFee - feeBreakdown.insuranceFee;

        emit FeesCollectedFromVault(protocolFeeAmount, lpFee, feeBreakdown.baseFee + feeSurplus);
        return amountToTransfer;
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
        amount = lpFeesCollected - lpFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        lpFeesClaimed += amount;
        stablecoin.safeTransfer(msg.sender, amount);

        emit LPFeesClaimed(msg.sender, amount);
        return amount;
    }

    /**
     * @notice Allows workers to claim operator fees for operational expenses
     * @return amount The amount of fees claimed
     */
    function claimOperatorFees()
        external
        nonReentrant
        onlyRole(WORKER_ROLE)
        returns (uint256 amount)
    {
        amount = operatorFeesCollected - operatorFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        operatorFeesClaimed += amount;
        stablecoin.safeTransfer(msg.sender, amount);

        emit OperatorFeesClaimed(msg.sender, amount);
        return amount;
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
     * @notice Sets the protocol fee percentage
     * @param _protocolFee Percentage of the BPS feesallocated to protocol
     */
    function setProtocolFee(
        uint256 _protocolFee
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Protocol + LP fees cannot exceed 100%
        if (_protocolFee > BASE_PERCENTAGE)
            revert GeniusErrors.InvalidPercentage();

        protocolFee = _protocolFee;

        emit ProtocolFeeUpdated(_protocolFee);
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
     * @notice Returns the total claimable operator fees
     * @return Amount of operator fees available to claim
     */
    function claimableOperatorFees() external view returns (uint256) {
        return operatorFeesCollected - operatorFeesClaimed;
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
        uint256 insuranceFee = (_amount * insuranceFeePercentage) /
            BASE_PERCENTAGE;

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
