// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusSwapRouter} from "../src/GeniusSwapRouter.sol";

/**
 * @title DeployMultiChain
 * @notice Script to deploy GeniusSwapRouter across multiple chains
 * 
 * @dev Usage:
 * forge script script/deployment/DeployMultiChain.s.sol \
 *   --private-key $SWAPROUTER_DEPLOYER_PRIVATE_KEY \
 *   --multi
 */
contract DeployMultiChain is Script {
    struct DeploymentResult {
        string network;
        address routerAddress;
        bool success;
    }
    
    DeploymentResult[] public deployments;
    
    function run() public {
        // Get configuration
        address feeCollector = vm.envAddress("SWAPROUTER_FEE_COLLECTOR_ADDRESS");
        address swapRouterAdmin = vm.envAddress("SWAPROUTER_ADMIN_ADDRESS");
        
        // Define chains to deploy to
        string[6] memory chains = [
            "avalanche",
            "base", 
            "arbitrum",
            "optimism",
            "bsc",
            "polygon"
        ];
        
        string[6] memory rpcEnvVars = [
            "AVALANCHE_RPC_URL",
            "BASE_RPC_URL",
            "ARBITRUM_RPC_URL", 
            "OPTIMISM_RPC_URL",
            "BSC_RPC_URL",
            "POLYGON_RPC_URL"
        ];
        
        console.log("===========================================");
        console.log("Starting Multi-Chain Deployment");
        console.log("===========================================");
        console.log("Fee Collector:", feeCollector);
        console.log("Admin Address:", swapRouterAdmin);
        console.log("===========================================\n");
        
        // Deploy to each chain
        for (uint i = 0; i < chains.length; i++) {
            string memory rpcUrl = vm.envString(rpcEnvVars[i]);
            
            console.log("Deploying to", chains[i], "...");
            
            try this.deployToChain(rpcUrl, feeCollector, swapRouterAdmin) returns (address routerAddress) {
                deployments.push(DeploymentResult({
                    network: chains[i],
                    routerAddress: routerAddress,
                    success: true
                }));
                console.log("Success! Deployed at:", routerAddress);
            } catch {
                deployments.push(DeploymentResult({
                    network: chains[i],
                    routerAddress: address(0),
                    success: false
                }));
                console.log("Failed to deploy on", chains[i]);
            }
            console.log("");
        }
        
        // Print summary
        printDeploymentSummary();
    }
    
    function deployToChain(string memory rpcUrl, address feeCollector, address swapRouterAdmin) external returns (address) {
        vm.createSelectFork(rpcUrl);
        
        vm.startBroadcast();
        GeniusSwapRouter router = new GeniusSwapRouter(swapRouterAdmin, feeCollector);
        vm.stopBroadcast();
        
        return address(router);
    }
    
    function printDeploymentSummary() internal view {
        console.log("\n===========================================");
        console.log("DEPLOYMENT SUMMARY");
        console.log("===========================================\n");
        
        uint successCount = 0;
        
        for (uint i = 0; i < deployments.length; i++) {
            DeploymentResult memory result = deployments[i];
            
            if (result.success) {
                console.log(string.concat("[SUCCESS] ", result.network));
                console.log("  Address:", result.routerAddress);
                successCount++;
            } else {
                console.log(string.concat("[FAILED]  ", result.network));
            }
            console.log("");
        }
        
        console.log("===========================================");
        console.log("Total Deployments:", deployments.length);
        console.log("Successful:", successCount);
        console.log("Failed:", deployments.length - successCount);
        console.log("===========================================");
    }
}
