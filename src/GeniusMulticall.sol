// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MultiSendCallOnly} from "./libs/MultiSendCallOnly.sol";
import {GeniusErrors} from "./libs/GeniusErrors.sol";

/**
 * @title GeniusMulticall
 * @author @altloot, @samuel_vdu
 *
 * @notice The GeniusMulticall contract that handles multicalls
 */
contract GeniusMulticall is MultiSendCallOnly {
    receive() external payable {}

    function multiSend(bytes memory transactions) external payable {
        _multiSend(transactions);

        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = msg.sender.call{value: balance}("");
            if (!success) revert GeniusErrors.InvalidAmount();
        }
    }
}
