// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "permit2/interfaces/IAllowanceTransfer.sol";

/**
 * @title GeniusVault
 * @author altloot
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps.
 *         and other Genius related activities.
 */

contract GeniusVault is Ownable {

    // =============================================================
    //                          INTERFACES
    // =============================================================

    IAllowanceTransfer public immutable PERMIT2;
    IERC20 public immutable STABLECOIN;

    // =============================================================
    //                          VARIABLES
    // =============================================================

    uint256 public currentDeposits;
    mapping(address => uint256) public isOrchestrator;
    mapping(address => uint256) public traderDeposits;

    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The msg.sender is not an orchestrator.
     */
    error NotOrchestrator();

    /**
     * @dev Error thrown when an invalid spender is encountered.
     */
    error InvalidSpender();

    /**
     * @dev Error thrown when an invalid trader is encountered.
     */
    error InvalidTrader();

    /**
     * @dev Error thrown when an invalid amount is encountered.
     */
    error InvalidAmount();

    /**
     * @dev Error thrown when an invalid deposit token is encountered.
     */
     error InvalidDepositToken();

    // =============================================================
    //                          EVENTS
    // =============================================================

    event Deposit(address indexed trader, uint256 amountDeposited, uint256 oldDepositAmount, uint256 newDepositAmount, bool isOrchestrator);
    event Withdrawal(address indexed trader, uint256 amountWithdrawn);

    // =============================================================
    //                          MODIFIERS
    // =============================================================

    /**
     * @dev Modifier that allows only the orchestrator to call the function.
     * @notice This modifier is used to restrict access to certain functions only to the orchestrator.
     * @notice The orchestrators are the only address that can call functions with this modifier.
     * @notice If non orchestrators tries to call a function with this modifier, a revert with an error message is triggered.
     */
    modifier onlyOrchestrator() {
            if (isOrchestrator[msg.sender] != 1) {
                revert NotOrchestrator();
            }
        _;
    }

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    /**
     * @dev Constructor function for the GeniusVault contract.
     * @param _stablecoin The address of the STABLECOIN contract.
     *
     * @dev The deployer of the vault is the initial owner of the contract
            so that they can add orchestrators to the vault.
     */
    constructor(address _stablecoin, address _permit2) Ownable(msg.sender) {
        STABLECOIN = IERC20(_stablecoin);
        PERMIT2 = IAllowanceTransfer(_permit2);
    }

    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @dev Internal function to permit and deposit tokens into the GeniusVault contract.
     * @param _permitSingle The permit data for the token transfer.
     * @param _signature The signature for the permit data.
     * @param _trader The address of the trader making the deposit.
     */
    function _permitAndDeposit(
        IAllowanceTransfer.PermitSingle calldata _permitSingle,
        bytes calldata _signature,
        address _trader
    ) private {
       if (_permitSingle.spender != address(this)) revert InvalidSpender();
       if (_permitSingle.details.token != address(STABLECOIN)) revert InvalidDepositToken();

       PERMIT2.permit(msg.sender, _permitSingle, _signature);
       PERMIT2.transferFrom(msg.sender, address(this), _permitSingle.details.amount, _permitSingle.details.token);

       traderDeposits[_trader] += _permitSingle.details.amount;
   }

    /**
     * @notice Deposits tokens into the vault
     * @param _trader The address of the trader that tokens are being deposited for
     * @param _permitSingle The permit details for the token
     * @param _signature The signature for the permit
     */
    function addLiquidity(
        address _trader,
        IAllowanceTransfer.PermitSingle calldata _permitSingle,
        bytes calldata _signature
    ) external {
        if (_permitSingle.spender != address(this)) revert InvalidSpender();
        if (_permitSingle.details.token != address(STABLECOIN)) revert InvalidDepositToken();
        if (_permitSingle.details.amount == 0) revert InvalidAmount();
        if (msg.sender != _trader && isOrchestrator[msg.sender] != 1) {
            revert NotOrchestrator();
        }

        uint256 oldDepositAmount = traderDeposits[_trader];

        _permitAndDeposit(_permitSingle, _signature, _trader);
        currentDeposits = STABLECOIN.balanceOf(address(this));

        uint256 newDepositAmount = traderDeposits[_trader];
        bool isSenderOrchestrator = isOrchestrator[msg.sender] == 1 ? true : false;

        emit Deposit(
            _trader,
            _permitSingle.details.amount,
            oldDepositAmount,
            newDepositAmount,
            isSenderOrchestrator
        );
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquidity(address _trader, uint256 _amount) external onlyOrchestrator {
        if (_amount == 0) revert InvalidAmount();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();


        IERC20(STABLECOIN).transfer(_trader, _amount);
        currentDeposits -= STABLECOIN.balanceOf(address(this));
        
        emit Withdrawal(_trader, _amount);
    }

    /**
    * @notice Adds an orchestrator to the vault
    * @param _orchestrator The address of the orchestrator to add
     */
    function addOrchestrator(address _orchestrator) external onlyOwner {
        require(_orchestrator != address(0), "GeniusVault: orchestrator is the zero address");
        require(isOrchestrator[_orchestrator] == 0, "GeniusVault: orchestrator already exists");

        isOrchestrator[_orchestrator] = 1;
    }

    /**
    * @notice Removes an orchestrator from the vault
    * @param _orchestrator The address of the orchestrator to remove
    */
    function removeOrchestrator(address _orchestrator) external onlyOwner {
        require(_orchestrator != address(0), "GeniusVault: orchestrator is the zero address");
        require(isOrchestrator[_orchestrator] == 1, "GeniusVault: orchestrator does not exist");

        isOrchestrator[_orchestrator] = 0;
    }
}