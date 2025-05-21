// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title BaseScriptContext
 * @dev Base contract for deployment scripts providing common functionality for handling
 * different networks and environments
 */
abstract contract BaseScriptContext is Script {
    // Environment and network info
    string public network;
    string public deployEnv;
    uint256 public chainId;
    address public owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909; // Default owner
    uint256 public deployerPrivateKey;

    // Chain IDs
    uint256 constant ETHEREUM = 1;
    uint256 constant OPTIMISM = 10;
    uint256 constant BSC = 56;
    uint256 constant POLYGON = 137;
    uint256 constant SONIC = 146;
    uint256 constant ARBITRUM = 42161;
    uint256 constant AVAX = 43114;
    uint256 constant BASE = 8453;
    uint256 constant SOLANA = 1399811149;

    // Role constants
    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 constant ORCHESTRATOR_ROLE = keccak256("ORCHESTRATOR_ROLE");

    /**
     * @dev Constructor that initializes the context
     */
    constructor() {
        initializeContext();
    }

    /**
     * @dev Initializes the deployment context with chain ID, network name, and environment
     */
    function initializeContext() internal {
        // Get deployer private key
        deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");

        // Detect current network
        chainId = block.chainid;
        network = getNetworkName(chainId);
        console.log("Detected network:", network);

        // Get the deployment environment (DEV, STAGING, PRODUCTION, etc.)
        try vm.envString("DEPLOY_ENV") returns (string memory env) {
            deployEnv = env;
            console.log("Deployment environment:", deployEnv);
        } catch {
            // Default to DEV if not specified
            deployEnv = "DEV";
            console.log("Using default environment: DEV");
        }
    }

    /**
     * @dev Maps chain ID to network name
     */
    function getNetworkName(
        uint256 _chainId
    ) internal pure returns (string memory) {
        if (_chainId == AVAX) return "AVAX";
        if (_chainId == BASE) return "BASE";
        if (_chainId == ARBITRUM) return "ARBITRUM";
        if (_chainId == OPTIMISM) return "OPTIMISM";
        if (_chainId == SONIC) return "SONIC";
        if (_chainId == POLYGON) return "POLYGON";
        if (_chainId == BSC) return "BSC";
        if (_chainId == ETHEREUM) return "ETHEREUM";
        if (_chainId == SOLANA) return "SOLANA";
        return "UNKNOWN";
    }

    /**
     * @dev Gets address from environment variable with network and environment context
     * @param baseName The base name of the contract (e.g., "VAULT")
     */
    function getContractAddress(
        string memory baseName
    ) internal view returns (address) {
        string memory varName;
        address contractAddress;

        // Try environment-specific network var (e.g., VAULT_BASE_DEV)
        varName = string.concat(baseName, "_", network, "_", deployEnv);
        try vm.envAddress(varName) returns (address addr) {
            contractAddress = addr;
            console.log("Using address from %s: %s", varName, contractAddress);
            return contractAddress;
        } catch {
            // Try network-specific var (e.g., VAULT_BASE)
            varName = string.concat(baseName, "_", network);
            try vm.envAddress(varName) returns (address addr) {
                contractAddress = addr;
                console.log(
                    "Using address from %s: %s",
                    varName,
                    contractAddress
                );
                return contractAddress;
            } catch {
                // Try generic var (e.g., VAULT_ADDRESS)
                varName = string.concat(baseName, "_ADDRESS");
                try vm.envAddress(varName) returns (address addr) {
                    contractAddress = addr;
                    console.log(
                        "Using address from %s: %s",
                        varName,
                        contractAddress
                    );
                    return contractAddress;
                } catch {
                    revert(
                        string.concat("Failed to get address for ", baseName)
                    );
                }
            }
        }
    }

    /**
     * @dev Gets the stablecoin address for the current network
     */
    function getStablecoinAddress() internal view returns (address) {
        return getContractAddress("STABLECOIN");
    }

    /**
     * @dev Gets the vault address for the current network
     */
    function getVaultAddress() internal view returns (address) {
        return getContractAddress("VAULT");
    }

    /**
     * @dev Gets the fee collector address for the current network
     */
    function getFeeCollectorAddress() internal view returns (address) {
        return getContractAddress("FEE_COLLECTOR");
    }
}
