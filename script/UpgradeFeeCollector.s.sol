// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";
import {BaseScriptContext} from "./utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title UpgradeFeeCollector
 * @dev Script to deploy a new FeeCollector implementation and upgrade the proxy
 * Deployment command:
 * source .env && DEPLOY_ENV=DEV forge script script/UpgradeFeeCollector.s.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract UpgradeFeeCollector is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get the fee collector address for this network and environment
        address feeCollectorAddress = getFeeCollectorAddress();

        // Deploy new implementation
        FeeCollector newImplementation = new FeeCollector();
        console.log(
            "New FeeCollector implementation deployed at:",
            address(newImplementation)
        );

        // Upgrade proxy to new implementation
        ITransparentUpgradeableProxy proxy = ITransparentUpgradeableProxy(
            payable(feeCollectorAddress)
        );
        proxy.upgradeToAndCall(address(newImplementation), "");
        console.log("FeeCollector proxy upgraded to new implementation");

        vm.stopBroadcast();
    }
} 