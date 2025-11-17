// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IGeniusSwapRouter.sol";

/**
 * @title GeniusSwapRouter
 * @notice Wraps DEX routers and takes configurable fees on swaps
 * @dev Users pay fees based on tiered whitelist system before tokens reach the router
 * @dev Supports both native ETH and ERC20 token swaps
 * @dev Handles transfer tax tokens by measuring actual received amounts
 */
contract GeniusSwapRouter is IGeniusSwapRouter, Ownable, ReentrancyGuard {
    // ========== STATE VARIABLES ==========
    
    /// @notice Custom fee rate per user in basis points (0-10000, where 10000 = 100%)
    mapping(address => uint256) public userFeeRate;
    
    /// @notice Address that receives collected fees
    address public feeCollector;

    /// @notice Default fee rate applied to users without a custom rate (in basis points)
    uint256 public defaultFeeRate = 100; // Default to 1%
    
    /// @notice Denominator for fee calculations (10000 = 100%)
    uint256 public FEE_DENOMINATOR = 10000;

    /// @notice Placeholder address to represent native ETH in events and logic
    address public constant NATIVE_PLACEHOLDER = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    
    // ========== CONSTRUCTOR ==========
    
    /**
     * @notice Initialize the contract
     * @param _feeCollector Initial fee collector address
     */
    constructor(address _feeCollector) Ownable(msg.sender) {
        if (_feeCollector == address(0)) revert InvalidFeeCollectorAddress();
        
        feeCollector = _feeCollector;
    }
    
    // ========== ADMINISTRATIVE FUNCTIONS ==========

    /**
     * @notice Set a custom fee rate for a specific user
     * @param user Address of the user
     * @param feeRate Fee rate in basis points (0-10000)
     */
    function setUserFeeRate(address user, uint256 feeRate) external onlyOwner {
        if (user == address(0)) revert InvalidUserAddress();
        if (feeRate > FEE_DENOMINATOR) revert FeeRateExceedsMaximum();
        userFeeRate[user] = feeRate;
        emit FeeRateUpdated(user, feeRate);
    }
    
    /**
     * @notice Set the default fee rate for users without custom rates
     * @param feeRate Fee rate in basis points (0-10000)
     */
    function setDefaultFeeRate(uint256 feeRate) external onlyOwner {
        if (feeRate > FEE_DENOMINATOR) revert FeeRateExceedsMaximum();
        defaultFeeRate = feeRate;
        emit DefaultFeeRateUpdated(feeRate);
    }
    
    /**
     * @notice Set the fee collector address
     * @param newFeeCollector Address that will receive collected fees
     */
    function setFeeCollector(address newFeeCollector) external onlyOwner {
        if (newFeeCollector == address(0)) revert InvalidFeeCollectorAddress();
        address oldCollector = feeCollector;
        feeCollector = newFeeCollector;
        emit FeeCollectorUpdated(oldCollector, newFeeCollector);
    }
    
    // ========== MAIN SWAP FUNCTION ==========
    
    /**
     * @notice Execute a swap through a whitelisted router with fee deduction
     * @param router Address of the whitelisted DEX router to use
     * @param tokenIn Address of the input token (use address(0) for native ETH)
     * @param amountIn Amount of input tokens (before fee deduction)
     * @param swapCalldata The calldata to forward to the router (already adjusted for fee)
     * @return result The return data from the router call
     * @dev Handles transfer tax tokens by measuring actual received balance
     */
    function executeSwap(
        address router,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        bytes calldata swapCalldata
    ) external payable nonReentrant returns (bytes memory result) {
        // Validation checks
        if (amountIn == 0) revert AmountMustBeGreaterThanZero();
        if (router == address(0)) revert InvalidRouterAddress();
        
        uint256 fee;
        uint256 amountAfterFee;
        uint256 actualReceived;
        
        // Handle token transfers and approvals based on swap type
        if (tokenIn == NATIVE_PLACEHOLDER) {
            // Native ETH swap
            (fee, amountAfterFee, actualReceived) = _handleNativeSwap(amountIn);
        } else {
            // ERC20 token swap with transfer tax support
            (fee, amountAfterFee, actualReceived) = _handleTokenSwap(tokenIn, amountIn, router);
        }
        
        // Measure balances BEFORE router call
        uint256 ethBalanceBefore = address(this).balance;
        uint256 tokenInBalanceBefore = (tokenIn != NATIVE_PLACEHOLDER) ? IERC20(tokenIn).balanceOf(address(this)) : 0;
        uint256 tokenOutBalanceBefore = (tokenOut != NATIVE_PLACEHOLDER) ? IERC20(tokenOut).balanceOf(address(this)) : 0;
        
        // Execute the router call
        bool success;
        
        if (tokenIn == NATIVE_PLACEHOLDER) {
            // Native ETH swap - send amountAfterFee as msg.value
            (success, result) = router.call{value: amountAfterFee}(swapCalldata);
        } else {
            // ERC20 token swap - no ETH value needed
            (success, result) = router.call(swapCalldata);
        }
        
        if (!success) revert RouterCallFailed();
        
        // Reset token approval to 0 for security (only for ERC20 swaps)
        if (tokenIn != NATIVE_PLACEHOLDER) {
            IERC20(tokenIn).approve(router, 0);
        }

        // Sweep any residual tokens back to the user (only the delta from this transaction)
        _sweepResidualsToUser(
            tokenIn, 
            tokenOut, 
            ethBalanceBefore, 
            tokenInBalanceBefore, 
            tokenOutBalanceBefore
        );
        
        // Emit event with both requested amount and actual received amount
        emit SwapExecuted(msg.sender, router, tokenIn, amountIn, actualReceived, fee);
        
        return result;
    }

    
    // ========== PRIVATE HELPER FUNCTIONS ==========
    
    /**
     * @notice Handle native ETH swap logic
     * @param amountIn Amount of ETH sent
     * @return fee The fee amount collected
     * @return amountAfterFee The amount after fee deduction
     * @return actualReceived The actual amount received (same as amountIn for ETH)
     * @dev Private function for gas optimization
     */
    function _handleNativeSwap(uint256 amountIn) 
        private 
        returns (uint256 fee, uint256 amountAfterFee, uint256 actualReceived) 
    {
        if (msg.value != amountIn) revert ETHAmountMismatch();
        
        // For ETH, there's no transfer tax, so actualReceived = amountIn
        actualReceived = amountIn;
        
        // Calculate fee and amount after fee
        (fee, amountAfterFee) = _calculateFee(msg.sender, actualReceived);
        
        // Transfer fee to feeCollector
        if (fee > 0) {
            _transferNativeFee(fee);
        }
        
        return (fee, amountAfterFee, actualReceived);
    }
    
    /**
     * @notice Handle ERC20 token swap logic with transfer tax support
     * @param tokenIn Address of the input token
     * @param amountIn Amount of tokens to swap
     * @param router Address of the router (for approval)
     * @return fee The fee amount collected
     * @return amountAfterFee The amount after fee deduction
     * @return actualReceived The actual amount received after transfer
     * @dev Private function for gas optimization
     */
    function _handleTokenSwap(address tokenIn, uint256 amountIn, address router) 
        private 
        returns (uint256 fee, uint256 amountAfterFee, uint256 actualReceived) 
    {
        if (msg.value != 0) revert ETHSentForTokenSwap();
        
        // Measure actual received amount (supports transfer tax tokens)
        actualReceived = _transferTokensFromUser(tokenIn, amountIn);
        
        // Calculate fee based on ACTUAL received amount
        (fee, amountAfterFee) = _calculateFee(msg.sender, actualReceived);
        
        // Transfer fee to feeCollector
        if (fee > 0) {
            amountAfterFee = _transferTokenFee(tokenIn, fee);
        }
        
        // Approve the router to spend amountAfterFee tokens
        if (!IERC20(tokenIn).approve(router, amountAfterFee)) {
            revert TokenApprovalFailed();
        }
        
        return (fee, amountAfterFee, actualReceived);
    }
    
    /**
     * @notice Transfer tokens from user and measure actual received amount
     * @param tokenIn Address of the input token
     * @param amountIn Amount to transfer
     * @return actualReceived The actual amount received after transfer
     * @dev Private function for gas optimization and transfer tax handling
     */
    function _transferTokensFromUser(address tokenIn, uint256 amountIn) 
        private 
        returns (uint256 actualReceived) 
    {
        // Measure balance BEFORE transfer
        uint256 balanceBefore = IERC20(tokenIn).balanceOf(address(this));
        
        // Transfer amountIn from user to this contract
        if (!IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn)) {
            revert TokenTransferFailed();
        }
        
        // Measure balance AFTER transfer to get actual received amount
        uint256 balanceAfter = IERC20(tokenIn).balanceOf(address(this));
        actualReceived = balanceAfter - balanceBefore;
        
        // Ensure we received something
        if (actualReceived == 0) revert NoTokensReceived();
        
        return actualReceived;
    }
    
    /**
     * @notice Transfer native ETH fee to fee collector
     * @param fee Amount of ETH to transfer as fee
     * @dev Private function for gas optimization
     */
    function _transferNativeFee(uint256 fee) private {
        if (feeCollector == address(0)) revert FeeCollectorNotSet();
        (bool feeTransferSuccess, ) = feeCollector.call{value: fee}("");
        if (!feeTransferSuccess) revert FeeTransferFailed();
    }
    
    /**
     * @notice Transfer ERC20 token fee to fee collector
     * @param tokenIn Address of the token
     * @param fee Amount of tokens to transfer as fee
     * @return amountAfterFee The remaining balance after fee transfer (accounts for transfer tax)
     * @dev Private function for gas optimization
     */
    function _transferTokenFee(address tokenIn, uint256 fee)
        private
        returns (uint256 amountAfterFee) 
    {
        if (feeCollector == address(0)) revert FeeCollectorNotSet();
        
        if (!IERC20(tokenIn).transfer(feeCollector, fee)) {
            revert FeeTransferFailed();
        }
        
        // Recalculate amountAfterFee based on what's left in the contract
        // This ensures we don't try to approve more than we have
        amountAfterFee = IERC20(tokenIn).balanceOf(address(this));
        
        return amountAfterFee;
    }
    
    /**
     * @notice Calculate the fee and amount after fee for a given user and amount
     * @param user Address of the user initiating the swap
     * @param amount Original swap amount (or actual received amount for transfer tax tokens)
     * @return fee The fee amount to be collected
     * @return amountAfterFee The amount that will be forwarded to the router (amount - fee)
     * @dev Private function for gas optimization (saves ~200 gas per call vs internal)
     */
    function _calculateFee(address user, uint256 amount) 
        private 
        view 
        returns (uint256 fee, uint256 amountAfterFee) 
    {
        // Get the user's fee rate, defaulting to defaultFeeRate if user has no custom rate
        uint256 feeRate = userFeeRate[user];
        if (feeRate == 0) {
            feeRate = defaultFeeRate;
        }
        
        // Calculate fee: fee = (amount * feeRate) / FEE_DENOMINATOR
        fee = (amount * feeRate) / FEE_DENOMINATOR;
        
        // Calculate amount after fee deduction
        amountAfterFee = amount - fee;
        
        return (fee, amountAfterFee);
    }

    /**
    * @notice Sweep residual tokens back to user (only delta from this transaction)
    * @param tokenIn Address of input token
    * @param tokenOut Address of output token
    * @param ethBalanceBefore ETH balance before router call
    * @param tokenInBalanceBefore tokenIn balance before router call
    * @param tokenOutBalanceBefore tokenOut balance before router call
    * @dev Only sweeps the difference in balances from before/after router call
    */
    function _sweepResidualsToUser(
        address tokenIn,
        address tokenOut,
        uint256 ethBalanceBefore,
        uint256 tokenInBalanceBefore,
        uint256 tokenOutBalanceBefore
    ) private {
        // Sweep residual ETH (from ETH refunds) - only the delta
        uint256 ethBalanceAfter = address(this).balance;
        if (ethBalanceAfter > ethBalanceBefore) {
            uint256 ethDelta = ethBalanceAfter - ethBalanceBefore;
            (bool success, ) = msg.sender.call{value: ethDelta}("");
            if (!success) revert ETHTransferFailed();
        }
        
        // Sweep residual tokenIn (from partial fills or refunds) - only the delta
        if (tokenIn != NATIVE_PLACEHOLDER) {
            uint256 tokenInBalanceAfter = IERC20(tokenIn).balanceOf(address(this));
            if (tokenInBalanceAfter > tokenInBalanceBefore) {
                uint256 tokenInDelta = tokenInBalanceAfter - tokenInBalanceBefore;
                if (!IERC20(tokenIn).transfer(msg.sender, tokenInDelta)) {
                    revert TokenTransferFailed();
                }
            }
        }
        
        // Sweep residual tokenOut (if router sent output to contract) - only the delta
        if (tokenOut != NATIVE_PLACEHOLDER) {
            uint256 tokenOutBalanceAfter = IERC20(tokenOut).balanceOf(address(this));
            if (tokenOutBalanceAfter > tokenOutBalanceBefore) {
                uint256 tokenOutDelta = tokenOutBalanceAfter - tokenOutBalanceBefore;
                if (!IERC20(tokenOut).transfer(msg.sender, tokenOutDelta)) {
                    revert TokenTransferFailed();
                }
            }
        }
    }
    
    // ========== FALLBACK FUNCTIONS ==========
    
    /**
     * @notice Reject direct ETH transfers
     * @dev ETH should only be sent via executeSwap function
     */
    receive() external payable {
        revert DirectETHTransfersNotAllowed();
    }
    
    /**
     * @notice Reject calls to non-existent functions
     */
    fallback() external payable {
        revert FunctionDoesNotExist();
    }
}
