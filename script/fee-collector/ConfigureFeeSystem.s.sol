// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FeeCollector} from "../../src/fees/FeeCollector.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";

/**
 * @title ConfigureFeeSystem
 * @dev Script to configure fee tiers and parameters
 * Deployment command:
 * source .env && forge script script/ConfigureFeeSystem.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract ConfigureFeeSystem is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeCollectorAddress = vm.envAddress("FEE_COLLECTOR_BASE_DEV");
        address vaultAddress = vm.envAddress("VAULT_BASE_DEV");

        vm.startBroadcast(deployerPrivateKey);

        FeeCollector feeCollector = FeeCollector(feeCollectorAddress);
        GeniusVault vault = GeniusVault(vaultAddress);

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

        // Set insurance fee tiers
        feeCollector.setInsuranceFeeTiers(thresholdAmounts, bpsFees);
        console.log("Set insurance fee tiers");

        // Set minimum fees for target chains
        uint256[] memory chainIds = new uint256[](9);
        chainIds[0] = 56; // BSC
        chainIds[1] = 8453; // BASE
        chainIds[2] = 42161; // ARBITRUM
        chainIds[3] = 10; // OPTIMISM
        chainIds[4] = 43114; // AVALANCHE
        chainIds[5] = 1399811149; // SOLANA
        chainIds[6] = 137; // POLYGON
        chainIds[7] = 146; // SONIC
        chainIds[8] = 1; // ETHEREUM

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

        for (uint256 i = 0; i < chainIds.length; i++) {
            if (chainIds[i] == block.chainid) {
                continue; // Skip current chain
            }
            feeCollector.setTargetChainMinFee(chainIds[i], minFees[i]);
            console.log(
                "Set min fee for chain %s to %s",
                chainIds[i],
                minFees[i]
            );
        }

        console.log("Fee system configuration complete");

        vm.stopBroadcast();
    }
}
