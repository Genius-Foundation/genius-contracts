// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";

/**
 * @title AddOrchestrator
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command:
        AVALANCHE: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
        ARBITRUM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $ARBITRUM_RPC_URL --broadcast --verify -vvvv --via-ir
        OPTIMISM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $OPTIMISM_RPC_URL --broadcast --verify -vvvv --via-ir
        FANTOM: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $FANTOM_RPC_URL --broadcast --verify -vvvv --via-ir
        POLYGON: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $POLYGON_RPC_URL --broadcast --verify -vvvv --via-ir
        BSC: forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $BSC_RPC_URL --broadcast --verify -vvvv --via-ir

        To specify an environment (like STAGING or PRODUCTION), set the DEPLOY_ENV environment variable:
        DEPLOY_ENV=STAGING forge script script/utility/AddOrchestrator.s.sol:AddOrchestrator --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract AddOrchestrator is Script {
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    // Chain ID to network name mapping for determining which vault address to use
    function getNetworkName(
        uint256 chainId
    ) internal pure returns (string memory) {
        if (chainId == 43114) return "AVAX";
        if (chainId == 8453) return "BASE";
        if (chainId == 42161) return "ARBITRUM";
        if (chainId == 10) return "OPTIMISM";
        if (chainId == 146) return "SONIC";
        if (chainId == 137) return "POLYGON";
        if (chainId == 56) return "BSC";
        if (chainId == 1) return "ETHEREUM";
        return "UNKNOWN";
    }

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Detect current network
        uint256 chainId = block.chainid;
        string memory network = getNetworkName(chainId);
        console.log("Detected network:", network);

        // Get the deployment environment (STAGING, PRODUCTION, etc.) if specified
        string memory deployEnv;
        try vm.envString("DEPLOY_ENV") returns (string memory env) {
            deployEnv = env;
            console.log("Deployment environment:", deployEnv);
        } catch {
            deployEnv = ""; // Empty string if not set
            console.log("No specific deployment environment set");
        }

        // Get the appropriate vault address based on network and environment
        address vaultAddress;
        string memory vaultVarName;

        // Try environment-specific network vault (e.g., VAULT_BASE_STAGING)
        if (bytes(deployEnv).length > 0) {
            vaultVarName = string.concat("VAULT_", network, "_", deployEnv);
            try vm.envAddress(vaultVarName) returns (address addr) {
                vaultAddress = addr;
                console.log(
                    "Using environment-specific vault address from:",
                    vaultVarName
                );
            } catch {
                // Try regular network-specific vault (e.g., VAULT_BASE)
                vaultVarName = string.concat("VAULT_", network);
                try vm.envAddress(vaultVarName) returns (address addr) {
                    vaultAddress = addr;
                    console.log(
                        "Using network-specific vault address from:",
                        vaultVarName
                    );
                } catch {
                    // Fallback to generic GENIUS_VAULT_ADDRESS
                    vaultAddress = vm.envAddress("GENIUS_VAULT_ADDRESS");
                    console.log("Using generic GENIUS_VAULT_ADDRESS");
                }
            }
        } else {
            // No environment specified, try network-specific (e.g., VAULT_BASE)
            vaultVarName = string.concat("VAULT_", network);
            try vm.envAddress(vaultVarName) returns (address addr) {
                vaultAddress = addr;
                console.log(
                    "Using network-specific vault address from:",
                    vaultVarName
                );
            } catch {
                // Fallback to generic GENIUS_VAULT_ADDRESS
                vaultAddress = vm.envAddress("GENIUS_VAULT_ADDRESS");
                console.log("Using generic GENIUS_VAULT_ADDRESS");
            }
        }

        console.log("Vault address:", vaultAddress);

        GeniusVault geniusVault = GeniusVault(payable(vaultAddress));

        address[] memory orchestrators = new address[](2);
        orchestrators[0] = 0x57C26D20ecAcfd4F058Df888785ecBF06A47972E;
        orchestrators[1] = 0xDcc94F2A35dAD658B799C4F6c43FffF98E04e6DA;

        for (uint i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
            console.log("Orchestrator added to GeniusVault:", orchestrators[i]);
        }

        console.log("All orchestrators added to GeniusVault");

        address[] memory orchestratorsToRevoke = new address[](1);
        orchestratorsToRevoke[0] = 0x924dEF89eAB8bf12fC0065253D1bC89D1AcEAdc6;

        for (uint i = 0; i < orchestratorsToRevoke.length; i++) {
            geniusVault.revokeRole(ORCHESTRATOR_ROLE, orchestratorsToRevoke[i]);
            console.log(
                "Orchestrator revoked from GeniusVault:",
                orchestratorsToRevoke[i]
            );
        }

        vm.stopBroadcast();
    }
}
