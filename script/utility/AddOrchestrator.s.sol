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

        address[] memory orchestrators = new address[](11);
        orchestrators[0] = 0x039dA65e692cb4dd93d6DE2ca6A15268F9cF6Fb6;
        orchestrators[1] = 0x924dEF89eAB8bf12fC0065253D1bC89D1AcEAdc6;
        orchestrators[2] = 0x479417C01FA532632655579814607E94e6B27550;
        orchestrators[3] = 0x06247B5d327Aa90Fd84bf909C61eC8Eea65961C3;
        orchestrators[4] = 0x30641364A0613443381d1DC64D3337A02dc01FAA;
        orchestrators[5] = 0x1283Ba98C0Dae54d7A49Bd8c77cbC0Be8b65D223;
        orchestrators[6] = 0x9473c973c33E3924017FeF02C9E407907f6E8530;
        orchestrators[7] = 0xBcd7efa8235F85A349EBE79Bf107a6E794435a4D;
        orchestrators[8] = 0x74C440B89A00087E77364b26CFa5640714dCfA4f;
        orchestrators[9] = 0xc241Ef90fc2e24e897900bc5e6E487e1CE6C9071;
        orchestrators[10] = 0xd76f6b71b7Cea442834E6E40619C9dfF260C7148;

        for (uint i = 0; i < orchestrators.length; i++) {
            geniusVault.grantRole(ORCHESTRATOR_ROLE, orchestrators[i]);
            console.log("Orchestrator added to GeniusVault:", orchestrators[i]);
        }

        console.log("All orchestrators added to GeniusVault");

        address[] memory orchestratorsToRevoke = new address[](2);
        orchestratorsToRevoke[0] = 0xCEfB2c7B2fEE67C15Aa0657E7dE3815dC680Ed03;
        orchestratorsToRevoke[1] = 0x491BC2ABDb526bac6006D72928f430daC3DbD99d;

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
