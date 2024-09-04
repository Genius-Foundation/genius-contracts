// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusVaultCore} from "./GeniusVaultCore.sol";

contract GeniusVault is GeniusVaultCore {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address stablecoin,
        address admin
    ) external initializer {
        GeniusVaultCore._initialize(stablecoin, admin);
    }
}