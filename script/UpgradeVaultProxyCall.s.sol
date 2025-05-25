// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {GeniusProxyCall} from "../../src/GeniusProxyCall.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {BaseScriptContext} from "./utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title UpgradeGeniusProxyCall
 * @dev Script to deploy a new GeniusProxyCall and update all references
 *
 * Required environment variables:
 * - DEPLOYER_PRIVATE_KEY: Private key for deployment
 * - VAULT_<NETWORK>_<ENV> or VAULT_<NETWORK> or VAULT_ADDRESS: Vault contract address
 *
 * Deployment command:
 * source .env && DEPLOY_ENV=DEV forge script script/deploy/UpgradeGeniusProxyCall.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract UpgradeGeniusProxyCall is BaseScriptContext {
    bytes32 constant CALLER_ROLE = keccak256("CALLER_ROLE");

    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        console.log("Starting GeniusProxyCall upgrade...");

        // Get existing contract addresses
        address vaultAddress = getVaultAddress();

        // Validate all required addresses are available
        require(vaultAddress != address(0), "Vault address not found");

        console.log("Vault address:", vaultAddress);

        // Deploy new GeniusProxyCall
        GeniusProxyCall newProxyCall = new GeniusProxyCall(
            owner,
            new address[](0)
        );
        console.log("New GeniusProxyCall deployed at:", address(newProxyCall));

        // Grant CALLER_ROLE to all necessary contracts
        newProxyCall.grantRole(CALLER_ROLE, vaultAddress);
        console.log("Granted CALLER_ROLE to Vault");

        // Update the vault to use the new proxy call
        GeniusVault vault = GeniusVault(vaultAddress);
        vault.setProxyCall(address(newProxyCall));
        console.log("Updated Vault to use new ProxyCall");


        console.log("");
        console.log("=== UPGRADE COMPLETE ===");
        console.log("New GeniusProxyCall:", address(newProxyCall));
        console.log("");
        console.log("IMPORTANT: Update the following in your .env file:");
        console.log(
            "PROXY_CALL_%s_%s=%s",
            network,
            deployEnv,
            address(newProxyCall)
        );
        vm.stopBroadcast();
    }
}
