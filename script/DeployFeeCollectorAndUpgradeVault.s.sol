// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ITransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {GeniusVault} from "../src/GeniusVault.sol";
import {FeeCollector} from "../src/fees/FeeCollector.sol";

/**
 * @title DeployFeeCollectorAndUpgradeVault
 * @dev Script to deploy FeeCollector, upgrade GeniusVault, and configure the fee system in one transaction
 * Deployment command:
 * source .env &&forge script script/DeployFeeCollectorAndUpgradeVault.sol --rpc-url $BASE_RPC_URL --broadcast --verify --etherscan-api-key $BASESCAN_API_KEY --verifier-url $BASESCAN_VERIFIER_URL -vvvv --via-ir
 */
contract DeployFeeCollectorAndUpgradeVault is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address vaultAddress = vm.envAddress("VAULT_BASE_DEV");
        address owner = 0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909; // Match with DeployEthereumGeniusEcosystem
        address stablecoin = vm.envAddress("STABLECOIN_BASE_DEV");

        address protocolFeeReceiver = owner;
        address lpFeeReceiver = owner;
        address operatorFeeReceiver = owner;

        vm.startBroadcast(deployerPrivateKey);

        // STEP 1: Deploy FeeCollector
        FeeCollector feeCollectorImpl = new FeeCollector();
        console.log(
            "FeeCollector implementation deployed at:",
            address(feeCollectorImpl)
        );

        bytes memory feeCollectorInitData = abi.encodeWithSelector(
            FeeCollector.initialize.selector,
            owner, // admin address
            stablecoin, // stablecoin address
            1000, // 10% protocol fee
            protocolFeeReceiver,
            lpFeeReceiver,
            operatorFeeReceiver
        );

        ERC1967Proxy feeCollectorProxy = new ERC1967Proxy(
            address(feeCollectorImpl),
            feeCollectorInitData
        );
        console.log(
            "FeeCollector proxy deployed at:",
            address(feeCollectorProxy)
        );

        FeeCollector feeCollector = FeeCollector(address(feeCollectorProxy));

        // STEP 2: Deploy new GeniusVault implementation
        GeniusVault newVaultImpl = new GeniusVault();
        console.log(
            "New GeniusVault implementation deployed at:",
            address(newVaultImpl)
        );

        // STEP 3: Upgrade GeniusVault proxy
        ITransparentUpgradeableProxy vaultProxy = ITransparentUpgradeableProxy(
            payable(vaultAddress)
        );
        vaultProxy.upgradeToAndCall(address(newVaultImpl), "");
        console.log("GeniusVault proxy upgraded to new implementation");

        GeniusVault vault = GeniusVault(vaultAddress);

        // STEP 4: Link contracts
        vault.setFeeCollector(address(feeCollectorProxy));
        console.log("Set FeeCollector in Vault");

        feeCollector.setVault(vaultAddress);
        console.log("Set Vault in FeeCollector");

        // STEP 5: Configure fee tiers and parameters
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
                continue; // Skip if chain ID is 0
            }
            feeCollector.setTargetChainMinFee(chainIds[i], minFees[i]);
            console.log("Set min fee for chain", chainIds[i], "to", minFees[i]);
        }

        console.log("Fee system deployment and configuration complete");
        vm.stopBroadcast();
    }
}
