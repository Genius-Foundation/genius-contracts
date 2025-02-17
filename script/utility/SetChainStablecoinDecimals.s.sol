// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract SetTargetChainMinFee is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusVault = GeniusVault(vm.envAddress("GENIUS_VAULT_ADDRESS"));
        geniusVault.setChainStablecoinDecimals(10, 6);
        geniusVault.setChainStablecoinDecimals(1, 6);
        geniusVault.setChainStablecoinDecimals(8453, 6);
        geniusVault.setChainStablecoinDecimals(42161, 6);
        geniusVault.setChainStablecoinDecimals(43114, 6);
        geniusVault.setChainStablecoinDecimals(56, 18);
        geniusVault.setChainStablecoinDecimals(1399811149, 6);
    }
}
