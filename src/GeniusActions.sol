// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC725Y} from "./libs/erc725/ERC725Y.sol";

contract GeniusActions is ERC725Y {
    // Pass initialOwner to both ERC725Y and Ownable constructors
    constructor(address initialOwner) payable ERC725Y(initialOwner) {}
}
