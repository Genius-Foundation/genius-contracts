// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseScriptContext} from "../utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/**
 * @title ChangeAdminOwnership
 * @dev Script to change admin ownership of contracts using AccessControl
 * First grants DEFAULT_ADMIN_ROLE to new admin, then revokes from previous admin
 *
 * Usage:
 * source .env && DEPLOY_ENV=DEV forge script script/admin/ChangeAdminOwnership.s.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 */
contract ChangeAdminOwnership is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get admin addresses from environment
        address newAdmin = vm.envAddress("NEW_ADMIN_ADDRESS");
        address previousAdmin = vm.envAddress("PREVIOUS_ADMIN_ADDRESS");

        console.log("New Admin:", newAdmin);
        console.log("Previous Admin:", previousAdmin);
        console.log("Network:", network);
        console.log("Environment:", deployEnv);

        // Process Vault
        console.log("\n=== Processing Vault ===");
        address vaultAddress = tryGetContractAddress("VAULT");
        if (vaultAddress != address(0)) {
            console.log("Vault address:", vaultAddress);
            changeAdmin(vaultAddress, newAdmin, previousAdmin, "Vault");
        } else {
            console.log(
                "Skipping Vault: Address not found for this environment"
            );
        }

        // Process ProxyCall
        console.log("\n=== Processing ProxyCall ===");
        address proxyCallAddress = tryGetContractAddress("PROXY_CALL");
        if (proxyCallAddress != address(0)) {
            console.log("ProxyCall address:", proxyCallAddress);
            changeAdmin(proxyCallAddress, newAdmin, previousAdmin, "ProxyCall");
        } else {
            console.log(
                "Skipping ProxyCall: Address not found for this environment"
            );
        }

        // Process FeeCollector
        console.log("\n=== Processing FeeCollector ===");
        address feeCollectorAddress = tryGetContractAddress("FEE_COLLECTOR");
        if (feeCollectorAddress != address(0)) {
            console.log("FeeCollector address:", feeCollectorAddress);
            changeAdmin(
                feeCollectorAddress,
                newAdmin,
                previousAdmin,
                "FeeCollector"
            );
        } else {
            console.log(
                "Skipping FeeCollector: Address not found for this environment"
            );
        }

        vm.stopBroadcast();

        console.log("\n=== Admin ownership change complete ===");
    }

    function changeAdmin(
        address contractAddress,
        address newAdmin,
        address previousAdmin,
        string memory contractName
    ) internal {
        IAccessControl accessControl = IAccessControl(contractAddress);

        // Check current admin status
        bool previousHasAdmin = accessControl.hasRole(
            DEFAULT_ADMIN_ROLE,
            previousAdmin
        );
        bool newHasAdmin = accessControl.hasRole(DEFAULT_ADMIN_ROLE, newAdmin);

        console.log(
            "%s - Previous admin has role: %s",
            contractName,
            previousHasAdmin
        );
        console.log("%s - New admin has role: %s", contractName, newHasAdmin);

        // Grant admin role to new admin if they don't have it
        if (!newHasAdmin) {
            console.log(
                "Granting DEFAULT_ADMIN_ROLE to new admin for %s...",
                contractName
            );
            accessControl.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
            console.log(
                "Granted DEFAULT_ADMIN_ROLE to new admin for %s",
                contractName
            );
        } else {
            console.log(
                "New admin already has DEFAULT_ADMIN_ROLE for %s",
                contractName
            );
        }

        // Revoke admin role from previous admin if they have it
        if (previousHasAdmin) {
            console.log(
                "Revoking DEFAULT_ADMIN_ROLE from previous admin for %s...",
                contractName
            );
            accessControl.revokeRole(DEFAULT_ADMIN_ROLE, previousAdmin);
            console.log(
                "Revoked DEFAULT_ADMIN_ROLE from previous admin for %s",
                contractName
            );
        } else {
            console.log(
                "Previous admin does not have DEFAULT_ADMIN_ROLE for %s",
                contractName
            );
        }

        // Verify the changes
        bool newAdminVerified = accessControl.hasRole(
            DEFAULT_ADMIN_ROLE,
            newAdmin
        );
        bool previousAdminVerified = accessControl.hasRole(
            DEFAULT_ADMIN_ROLE,
            previousAdmin
        );

        console.log("\nVerification for %s:", contractName);
        console.log("New admin has DEFAULT_ADMIN_ROLE: %s", newAdminVerified);
        console.log(
            "Previous admin has DEFAULT_ADMIN_ROLE: %s",
            previousAdminVerified
        );

        require(
            newAdminVerified,
            string.concat(contractName, ": New admin role not granted")
        );
        require(
            !previousAdminVerified,
            string.concat(contractName, ": Previous admin role not revoked")
        );
    }

    // Helper function to safely get contract addresses
    function tryGetContractAddress(
        string memory baseName
    ) internal view returns (address) {
        string memory varName;

        // Try environment-specific network var (e.g., VAULT_BASE_DEV)
        varName = string.concat(baseName, "_", network, "_", deployEnv);
        try vm.envAddress(varName) returns (address addr) {
            return addr;
        } catch {
            // Try network-specific var (e.g., VAULT_BASE)
            varName = string.concat(baseName, "_", network);
            try vm.envAddress(varName) returns (address addr) {
                return addr;
            } catch {
                // Try generic var (e.g., VAULT_ADDRESS)
                varName = string.concat(baseName, "_ADDRESS");
                try vm.envAddress(varName) returns (address addr) {
                    return addr;
                } catch {
                    // Return zero address if not found
                    return address(0);
                }
            }
        }
    }
}
