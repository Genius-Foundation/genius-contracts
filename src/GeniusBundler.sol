// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { console } from "forge-std/console.sol";

contract GeniusBundler {
    uint256 public constant MAX_PAYLOADS = 16;
    uint256 public constant MAX_PAYLOAD_BYTES = 1024;

    struct Payload {
        address target;
        bytes callData;
        uint256 value;
    }

    function execute(
        Payload[] memory payloads,
        bool returnOnFirstFailure,
        bool executeAllPayloads
        ) external payable returns (bool) {
            require(payloads.length > 0, "No payloads");
            require(payloads.length <= MAX_PAYLOADS, "Too many payloads");

            unchecked {
                for (uint i = 0; i < payloads.length;) {
                    require(payloads[i].callData.length <= MAX_PAYLOAD_BYTES, "Payload too large");
                    
                    (bool success, ) = payloads[i].target.call{value: payloads[i].value}(payloads[i].callData);
                    
                    if (!executeAllPayloads && !success) {
                        if (returnOnFirstFailure) {
                            return false;
                        } 
                    }

                    i++;
                }
            }

        return true;
    }
}
