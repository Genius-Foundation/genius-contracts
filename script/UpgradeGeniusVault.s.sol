// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {BaseScriptContext} from "./utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title UpgradeGeniusVault
 * @dev Script to deploy a new GeniusVault implementation and upgrade the proxy
 * Deployment command:
 * source .env && DEPLOY_ENV=DEV forge script script/UpgradeGeniusVault.s.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract UpgradeGeniusVault is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get the vault address for this network and environment
        address vaultAddress = getVaultAddress();

        // Deploy new implementation
        GeniusVault newImplementation = new GeniusVault();
        console.log(
            "New GeniusVault implementation deployed at:",
            address(newImplementation)
        );

        // Upgrade proxy to new implementation
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            payable(vaultAddress)
        );
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("GeniusVault proxy upgraded to new implementation");

        vm.stopBroadcast();
    }
}
