// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MultiSendCallOnly} from "./libs/MultiSendCallOnly.sol";

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
    }
}
