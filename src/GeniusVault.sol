// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GeniusVault
 * @author altloot
 * 
 * @notice Contract allows for genius orchestrators to credit and debit
 *         trader balances cross-chain
 */

contract GeniusVault {

    // =============================================================
    //                          VARIABLES
    // =============================================================

    IERC20 public immutable stablecoin;

    /**
    * @brihu23: We could possible track the max amount of tokens that can be borrowed here
    * uint256 public maxBorrowAmount;
    * Could be X% of the total amount of tokens in the vault or a fixed amount
    */ 


    // =============================================================
    //                            ERRORS
    // =============================================================

    /**
     * @dev The msg.sender is not an orchestrator.
     */
    error NotOrchestrator();

    /**
        * @dev Mapping of orchestrator addresses to their status
        *      0: Not an orchestrator
        *      1: Is an orchestrator
     */
    mapping(address => uint256) public isOrchestrator;
    // =============================================================
    //                          EVENTS
    // =============================================================

    event Deposit(address indexed trader, uint256 amount, bool isOrchestrator);
    event Withdrawal(address indexed trader, uint256 amount);

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

    constructor(address _stablecoin) {
        stablecoin = IERC20(_stablecoin);
    }

    // =============================================================
    //                          FUNCTIONS
    // =============================================================

    /**
     * @notice Deposits tokens into the vault
     * @param _trader The address of the trader that is dep
     * @param _amount The amount of tokens to deposit
     */
    function addLiquidity(address _trader, uint256 _amount) external {
        require(_amount > 0, "GeniusVault: Amount must be greater than 0");
        require(_trader != address(0), "GeniusVault: Invalid trader address");

        /**
            * @dev If the msg.sender is not the trader, then the msg.sender must be an orchestrator
                   This is so that events can be used for backend processing
         */
        if (msg.sender != _trader && isOrchestrator[msg.sender] != 1) {
            revert NotOrchestrator();
        }

        IERC20(stablecoin).transferFrom(msg.sender, address(this), _amount);

        bool isSenderOrchestrator = isOrchestrator[msg.sender] == 1 ? true : false;

        emit Deposit(_trader, _amount, isSenderOrchestrator);
    }

    /**
     * @notice Withdraws tokens from the vault
     * @param _trader The address of the trader to use for 
     * @param _amount The amount of tokens to withdraw
     */
    function removeLiquidity(address _trader, uint256 _amount) external onlyOrchestrator {
        require(_amount > 0, "GeniusVault: Amount must be greater than 0");
        require(IERC20(stablecoin).balanceOf(address(this)) > _amount, "GeniusVault: Insufficient balance");
        require(_trader != address(0), "GeniusVault: Invalid trader address");


        IERC20(stablecoin).transfer(_trader, _amount);
        emit Withdrawal(_trader, _amount);
    }
}