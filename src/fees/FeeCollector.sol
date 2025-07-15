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

    // Fee receivers for each fee type
    address public protocolFeeReceiver;
    address public lpFeeReceiver;
    address public operatorFeeReceiver;

    // Fee settings
    uint256 public protocolFee; // What percentage of the bps fees goes to protocol

    // Fee tiers for order size (sorted from smallest to largest threshold)
    FeeTier[] public feeTiers;
    FeeTier[] public insuranceFeeTiers;

    // Minimum fees per chain (token => chainId => minFee)
    mapping(uint256 => uint256) public targetChainMinFee;

    // The token (stablecoin) used for fees
    IERC20 public stablecoin;

    // Only the vault can add fees
    address public vault;

    // The distributor address
    address public distributor;

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender))
            revert GeniusErrors.IsNotAdmin();
        _;
    }

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
        uint256 _protocolFee,
        address _protocolFeeReceiver,
        address _lpFeeReceiver,
        address _operatorFeeReceiver
    ) external initializer {
        if (_admin == address(0)) revert GeniusErrors.NonAddress0();
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();

        // Protocol + LP fees cannot exceed 100%
        if (_protocolFee > BASE_PERCENTAGE)
            revert GeniusErrors.InvalidPercentage();

        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _setStablecoin(_stablecoin);
        _setProtocolFee(_protocolFee);

        // Set default receivers to admin
        _setProtocolFeeReceiver(_protocolFeeReceiver);
        _setLPFeeReceiver(_lpFeeReceiver);
        _setOperatorFeeReceiver(_operatorFeeReceiver);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

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
    ) external returns (uint256 amountToTransfer) {
        if (msg.sender != vault) revert GeniusErrors.NotAuthorized();
        if (_amountIn == 0) revert GeniusErrors.InvalidAmount();

        // Calculate fee breakdown
        FeeBreakdown memory feeBreakdown = _calculateFeeBreakdown(
            _amountIn,
            _destChainId
        );

        // Check if the provided fee is sufficient
        if (_orderFee < feeBreakdown.totalFee)
            revert GeniusErrors.InsufficientFees(
                _orderFee,
                feeBreakdown.totalFee
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

        emit FeesCollectedFromVault(
            _orderHash,
            protocolFeeAmount,
            lpFee,
            feeBreakdown.baseFee + feeSurplus
        );
        return amountToTransfer;
    }

    /**
     * @notice Allows admins to claim protocol fees for the designated receiver
     * @return amount The amount of fees claimed
     */
    function claimProtocolFees()
        external
        nonReentrant
        onlyAdmin
        returns (uint256 amount)
    {
        amount = protocolFeesCollected - protocolFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();
        if (protocolFeeReceiver == address(0))
            revert GeniusErrors.NonAddress0();

        protocolFeesClaimed += amount;
        stablecoin.safeTransfer(protocolFeeReceiver, amount);

        emit ProtocolFeesClaimed(msg.sender, protocolFeeReceiver, amount);
        return amount;
    }

    /**
     * @notice Allows LP fee distributors to claim LP fees for the designated receiver
     * @return amount The amount of fees claimed
     */
    function claimLPFees()
        external
        nonReentrant
        onlyRole(DISTRIBUTOR_ROLE)
        returns (uint256 amount)
    {
        address _lpFeeReceiver = lpFeeReceiver;
        if (_lpFeeReceiver == address(0)) revert GeniusErrors.NonAddress0();

        amount = lpFeesCollected - lpFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        lpFeesClaimed += amount;
        stablecoin.safeTransfer(_lpFeeReceiver, amount);

        emit LPFeesClaimed(msg.sender, _lpFeeReceiver, amount);
        return amount;
    }

    /**
     * @notice Allows LP fee distributors to send LP fees to the distributor
     * @dev Can only be called by a DISTRIBUTOR_ROLE
     */
    function sendLpFeesToDistributor() external onlyRole(DISTRIBUTOR_ROLE) {
        address _distributor = distributor;
        if (_distributor == address(0)) revert GeniusErrors.NonAddress0();

        uint256 amount = lpFeesCollected - lpFeesClaimed;
        if (amount == 0) revert GeniusErrors.InvalidAmount();

        lpFeesClaimed += amount;   
        stablecoin.safeTransfer(_distributor, amount);

        emit LpFeesSentToDistributor(msg.sender, _distributor, amount);
    }

    /**
     * @notice Allows workers to claim operator fees for the designated receiver
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
        if (operatorFeeReceiver == address(0))
            revert GeniusErrors.NonAddress0();

        operatorFeesClaimed += amount;
        stablecoin.safeTransfer(operatorFeeReceiver, amount);

        emit OperatorFeesClaimed(msg.sender, operatorFeeReceiver, amount);
        return amount;
    }

    /**
     * @notice Sets the protocol fee receiver address
     * @param _receiver The address to receive protocol fees
     */
    function setProtocolFeeReceiver(address _receiver) external onlyAdmin {
        _setProtocolFeeReceiver(_receiver);
    }

    /**
     * @notice Sets the LP fee receiver address
     * @param _receiver The address to receive LP fees
     */
    function setLPFeeReceiver(address _receiver) external onlyAdmin {
        _setLPFeeReceiver(_receiver);
    }

    /**
     * @notice Sets the operator fee receiver address
     * @param _receiver The address to receive operator fees
     */
    function setOperatorFeeReceiver(address _receiver) external onlyAdmin {
        _setOperatorFeeReceiver(_receiver);
    }

    /**
     * @notice Sets the vault address that can update fees
     * @param _vault The vault contract address
     */
    function setVault(address _vault) external onlyAdmin {
        _setVault(_vault);
    }

    /**
     * @notice Sets the distributor address that can send LP fees to
     * @param _distributor The distributor contract address
     */
    function setDistributor(address _distributor) external onlyAdmin {
        _setDistributor(_distributor);
    }

    /**
     * @notice Sets the protocol fee percentage
     * @param _protocolFee Percentage of the BPS fees allocated to protocol
     */
    function setProtocolFee(uint256 _protocolFee) external onlyAdmin {
        _setProtocolFee(_protocolFee);
    }

    /**
     * @notice Sets the minimum fee for a target chain
     * @param _targetChainId The id of the target chain
     * @param _minFee The new minimum fee for the target chain
     */
    function setTargetChainMinFee(
        uint256 _targetChainId,
        uint256 _minFee
    ) external onlyAdmin {
        _setTargetChainMinFee(_targetChainId, _minFee);
    }

    /**
     * @notice Sets the fee tiers based on order size
     * @param _thresholdAmounts Array of threshold amounts for each tier (minimum order size)
     * @param _bpsFees Array of basis point fees for each tier
     */
    function setFeeTiers(
        uint256[] calldata _thresholdAmounts,
        uint256[] calldata _bpsFees
    ) external onlyAdmin {
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
    ) external onlyAdmin {
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
     * @param _amount The order amount
     * @param _destChainId The destination chain ID
     * @return A FeeBreakdown struct containing the breakdown of fees
     */
    function getOrderFees(
        uint256 _amount,
        uint256 _destChainId
    ) external view returns (FeeBreakdown memory) {
        return _calculateFeeBreakdown(_amount, _destChainId);
    }

    /**
     * @dev Internal function to set the stablecoin address
     * @param _stablecoin The address of the stablecoin
     */
    function _setStablecoin(address _stablecoin) internal {
        if (_stablecoin == address(0)) revert GeniusErrors.NonAddress0();
        stablecoin = IERC20(_stablecoin);
    }

    /**
     * @dev Internal function to set the protocol fee receiver address
     * @param _receiver The address to receive protocol fees
     */
    function _setProtocolFeeReceiver(address _receiver) internal {
        if (_receiver == address(0)) revert GeniusErrors.NonAddress0();
        protocolFeeReceiver = _receiver;
        emit ProtocolFeeReceiverSet(_receiver);
    }

    /**
     * @dev Internal function to set the LP fee receiver address
     * @param _receiver The address to receive LP fees
     */
    function _setLPFeeReceiver(address _receiver) internal {
        if (_receiver == address(0)) revert GeniusErrors.NonAddress0();
        lpFeeReceiver = _receiver;
        emit LPFeeReceiverSet(_receiver);
    }

    /**
     * @dev Internal function to set the operator fee receiver address
     * @param _receiver The address to receive operator fees
     */
    function _setOperatorFeeReceiver(address _receiver) internal {
        if (_receiver == address(0)) revert GeniusErrors.NonAddress0();
        operatorFeeReceiver = _receiver;
        emit OperatorFeeReceiverSet(_receiver);
    }

    /**
     * @dev Internal function to set the vault address
     * @param _vault The vault contract address
     */
    function _setVault(address _vault) internal {
        if (_vault == address(0)) revert GeniusErrors.NonAddress0();
        vault = _vault;
        emit VaultSet(_vault);
    }

    /**
     * @dev Internal function to set the distributor address
     * @param _distributor The distributor contract address
     */
    function _setDistributor(address _distributor) internal {
        if (_distributor == address(0)) revert GeniusErrors.NonAddress0();
        distributor = _distributor;
        emit DistributorSet(_distributor);
    }

    /**
     * @dev Internal function to set the protocol fee percentage
     * @param _protocolFee Percentage of the BPS fees allocated to protocol
     */
    function _setProtocolFee(uint256 _protocolFee) internal {
        // Protocol + LP fees cannot exceed 100%
        if (_protocolFee > BASE_PERCENTAGE)
            revert GeniusErrors.InvalidPercentage();

        protocolFee = _protocolFee;
        emit ProtocolFeeUpdated(_protocolFee);
    }

    /**
     * @dev Internal function to set the minimum fee for a target chain.
     * @param _targetChainId The target chain ID.
     * @param _minFee The minimum fee required.
     */
    function _setTargetChainMinFee(
        uint256 _targetChainId,
        uint256 _minFee
    ) internal {
        if (_targetChainId == block.chainid)
            revert GeniusErrors.InvalidDestChainId(_targetChainId);

        targetChainMinFee[_targetChainId] = _minFee;
        emit TargetChainMinFeeChanged(_targetChainId, _minFee);
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
     * @param _amount The order amount
     * @param _destChainId The destination chain ID
     * @return FeeBreakdown containing the breakdown of fees
     */
    function _calculateFeeBreakdown(
        uint256 _amount,
        uint256 _destChainId
    ) internal view returns (FeeBreakdown memory) {
        uint256 baseFee = targetChainMinFee[_destChainId];

        if (baseFee == 0) {
            revert GeniusErrors.InvalidDestChainId(_destChainId);
        }

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
    ) internal override onlyAdmin {}
}
