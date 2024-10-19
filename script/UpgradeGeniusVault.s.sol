// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract UpgradeGeniusVault is Script {
    function run() external {
        // Load deployment addresses from environment variables
        address geniusVaultProxy = vm.envAddress("GENIUS_VAULT_ADDRESS");

        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        GeniusVault newImplementation = new GeniusVault();
        console.log("New GeniusVault implementation deployed at:", address(newImplementation));

        // Upgrade proxy to new implementation
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(payable(geniusVaultProxy));
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("GeniusVault proxy upgraded to new implementation");

        vm.stopBroadcast();
    }
}