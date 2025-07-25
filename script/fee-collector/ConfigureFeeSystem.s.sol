// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";
import {BaseScriptContext} from "../utils/BaseScriptContext.sol";
import {console} from "forge-std/Script.sol";

/**
 * @title ConfigureFeeSystem
 * @dev Script to configure fee tiers and parameters
 * Deployment command:
 * source .env && DEPLOY_ENV=DEV forge script script/deploy/ConfigureFeeSystem.sol --rpc-url $<NETWORK>_RPC_URL --broadcast -vvvv --via-ir
 * Optionally specify environment: DEPLOY_ENV=STAGING forge script...
 */
contract ConfigureFeeSystem is BaseScriptContext {
    function run() external {
        vm.startBroadcast(deployerPrivateKey);

        // Get addresses for this network and environment
        address feeCollectorAddress = getFeeCollectorAddress();
        address vaultAddress = getVaultAddress();

        FeeCollector feeCollector = FeeCollector(feeCollectorAddress);
        GeniusVault vault = GeniusVault(vaultAddress);

        // Link contracts
        vault.setFeeCollector(feeCollectorAddress);
        console.log("Set FeeCollector in Vault");

        feeCollector.setVault(vaultAddress);
        console.log("Set Vault in FeeCollector");

        // Configure fee tiers and parameters
        uint256[] memory thresholdAmounts = new uint256[](4);
        thresholdAmounts[0] = 0; // Smallest orders
        thresholdAmounts[1] = 100_000_000; // Medium orders (above 100 dollars)
        thresholdAmounts[2] = 1_000_000_000; // Large orders (above 1000 dollars)
        thresholdAmounts[3] = 10_000_000_000; // Large orders (above 10k dollars)

        uint256[] memory bpsFees = new uint256[](4);
        bpsFees[0] = 25; // 0.25% for smallest orders
        bpsFees[1] = 15; // 0.15% for medium orders
        bpsFees[2] = 10; // 0.1% for large orders
        bpsFees[3] = 5; // 0.05% for large orders

        feeCollector.setFeeTiers(thresholdAmounts, bpsFees);
        console.log("Set fee tiers");

        uint256[] memory insuranceThresholdAmounts = new uint256[](1);
        thresholdAmounts[0] = 0; // Smallest orders

        uint256[] memory insuranceFees = new uint256[](1);
        bpsFees[0] = 1; // 0.01% for smallest orders

        // Set insurance fee tiers
        feeCollector.setInsuranceFeeTiers(
            insuranceThresholdAmounts,
            insuranceFees
        );
        console.log("Set insurance fee tiers");

        // Set minimum fees for target chains
        configureTargetChainMinFees(feeCollector);

        console.log("Fee system configuration complete");

        vm.stopBroadcast();
    }

    function configureTargetChainMinFees(FeeCollector feeCollector) internal {
        // Define all supported chains and their min fees
        uint256[] memory allChainIds = new uint256[](9);
        allChainIds[0] = 56; // BSC
        allChainIds[1] = 8453; // BASE
        allChainIds[2] = 42161; // ARBITRUM
        allChainIds[3] = 10; // OPTIMISM
        allChainIds[4] = 43114; // AVALANCHE
        allChainIds[5] = 1399811149; // SOLANA
        allChainIds[6] = 137; // POLYGON
        allChainIds[7] = 146; // SONIC
        allChainIds[8] = 1; // ETHEREUM

        uint256[] memory minFees = new uint256[](9);
        minFees[0] = 100_000; // $0.1 BSC
        minFees[1] = 100_000; // $0.1 BASE
        minFees[2] = 100_000; // $0.1 ARBITRUM
        minFees[3] = 100_000; // $0.1 OPTIMISM
        minFees[4] = 100_000; // $0.1 AVALANCHE
        minFees[5] = 100_000; // $0.1 SOLANA
        minFees[6] = 100_000; // $0.1 POLYGON
        minFees[7] = 100_000; // $0.1 SONIC
        minFees[8] = 1_000_000; // $1 ETHEREUM

        // Set min fees for all chains except the current one
        for (uint256 i = 0; i < allChainIds.length; i++) {
            if (allChainIds[i] == chainId) {
                continue; // Skip current chain
            }
            feeCollector.setTargetChainMinFee(allChainIds[i], minFees[i]);
            console.log(
                "Set min fee for chain %s (%s) to %s",
                allChainIds[i],
                getNetworkName(allChainIds[i]),
                minFees[i]
            );
        }
    }
}
