// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "permit2/interfaces/IAllowanceTransfer.sol";

/**
 * @title GeniusPool
 * @author altloot
 * 
 * @notice Contract allows for Genius Orchestrators to credit and debit
 *         trader STABLECOIN balances for cross-chain swaps.
 *         and other Genius related activities.
 */

contract GeniusPool is Ownable {

    // =============================================================
    //                          INTERFACES
    // =============================================================

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

    event Deposit(
        address indexed trader,
        uint256 amountDeposited,
        uint256 oldDepositAmount,
        uint256 newDepositAmount,
        bool isOrchestrator
    );

    event Withdrawal(
        address indexed trader,
        uint256 amountWithdrawn
    );

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
            if (isOrchestrator[tx.origin] != 1) {
                revert NotOrchestrator();
            }
        _;
    }

    // =============================================================
    //                          CONSTRUCTOR
    // =============================================================

    constructor(address _stablecoin, address _owner) Ownable(_owner) {
        require(_stablecoin != address(0), "GeniusVault: STABLECOIN address is the zero address");
        require(_owner != address(0), "GeniusVault: Owner address is the zero address");
        require(_owner == address(msg.sender), "GeniusVault: Owner address is not the deployer");

        STABLECOIN = IERC20(_stablecoin);
    }

    // =============================================================
    //                      EXTERNAL FUNCTIONS
    // =============================================================

    /**
     * @notice Deposits tokens into the vault
     * @param _trader The address of the trader that tokens are being deposited for
     * @param _amount The amount of tokens to deposit
     */
    function addLiquidity(
        address _trader,
        uint256 _amount
    ) external {
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount == 0) revert InvalidAmount();

        uint256 oldDepositAmount = traderDeposits[_trader];

        // Transfer the amount from the trader to the vault
        IERC20(STABLECOIN).transferFrom(msg.sender, address(this), _amount);

        currentDeposits = STABLECOIN.balanceOf(address(this));

        traderDeposits[_trader] += _amount;

        uint256 newDepositAmount = traderDeposits[_trader];

        bool isSenderOrchestrator = isOrchestrator[tx.origin] == 1 ? true : false;

        emit Deposit(
            _trader,
            _amount,
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
        if (_amount > currentDeposits) revert InvalidAmount();
        if (_trader == address(0)) revert InvalidTrader();
        if (_amount > IERC20(STABLECOIN).balanceOf(address(this))) revert InvalidAmount();


        IERC20(STABLECOIN).transfer(msg.sender, _amount);
        currentDeposits = STABLECOIN.balanceOf(address(this));
        
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