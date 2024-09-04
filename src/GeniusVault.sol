// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusVaultAbstract} from "./GeniusVaultAbstract.sol";

contract GeniusVault is GeniusVaultAbstract {
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address stablecoin,
        address admin,
        address executor
    ) external initializer {
        GeniusVaultAbstract._initialize(stablecoin, admin, executor);
    }
}