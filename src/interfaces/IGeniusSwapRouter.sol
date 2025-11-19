// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title IGeniusSwapRouter
 * @notice Interface for the GeniusSwapRouter contract
 * @dev Defines all external and public functions for the router
 */
interface IGeniusSwapRouter {
    // ========== ERRORS ==========
    
    error InvalidAddress();
    error InvalidFeeCollectorAddress();
    error InvalidUserAddress();
    error InvalidRouterAddress();
    error InvalidOwnerAddress();
    error FeeRateExceedsMaximum();
    error AmountMustBeGreaterThanZero();
    error ETHAmountMismatch();
    error ETHSentForTokenSwap();
    error TokenTransferFailed();
    error TokenInSweepFailed();
    error TokenOutSweepFailed();
    error ETHSweepFailed();
    error NoTokensReceived();
    error FeeCollectorNotSet();
    error FeeTransferFailed();
    error TokenApprovalFailed();
    error RouterCallFailed();
    error DirectETHTransfersNotAllowed();
    error FunctionDoesNotExist();
    
    // ========== EVENTS ==========
    
    event FeeRateUpdated(address indexed user, uint256 feeRate);
    event DefaultFeeRateUpdated(uint256 feeRate);
    event FeeCollectorUpdated(address indexed oldCollector, address indexed newCollector);
    event SwapExecuted(
        address indexed user,
        address indexed router,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 actualReceived,
        uint256 fee
    );
    
    // ========== ADMINISTRATIVE FUNCTIONS ==========
    
    /**
     * @notice Set a custom fee rate for a specific user
     * @param user Address of the user
     * @param feeRate Fee rate in basis points (0-10000)
     */
    function setUserFeeRate(address user, uint256 feeRate) external;
    
    /**
     * @notice Set the default fee rate for users without custom rates
     * @param feeRate Fee rate in basis points (0-10000)
     */
    function setDefaultFeeRate(uint256 feeRate) external;
    
    /**
     * @notice Set the fee collector address
     * @param newFeeCollector Address that will receive collected fees
     */
    function setFeeCollector(address newFeeCollector) external;
    
    // ========== MAIN SWAP FUNCTION ==========
    
    /**
     * @notice Execute a swap through a whitelisted router with fee deduction
     * @param router Address of the whitelisted DEX router to use
     * @param tokenIn Address of the input token (use address(0) for native ETH)
     * @param amountIn Amount of input tokens (before fee deduction)
     * @param swapCalldata The calldata to forward to the router (already adjusted for fee)
     * @return result The return data from the router call
     */
    function executeSwap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata swapCalldata
    ) external payable returns (bytes memory result);
    
    // ========== VIEW FUNCTIONS ==========
    
    /**
     * @notice Get the custom fee rate for a specific user
     * @param user Address of the user
     * @return Fee rate in basis points
     */
    function userFeeRate(address user) external view returns (uint256);
    
    /**
     * @notice Get the default fee rate
     * @return Fee rate in basis points
     */
    function defaultFeeRate() external view returns (uint256);
    
    /**
     * @notice Get the fee collector address
     * @return Address of the fee collector
     */
    function feeCollector() external view returns (address);
    
    /**
     * @notice Get the fee denominator constant
     * @return Fee denominator value (10000)
     */
    function FEE_DENOMINATOR() external view returns (uint256);
}
