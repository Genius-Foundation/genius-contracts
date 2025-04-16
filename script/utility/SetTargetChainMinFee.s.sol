// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract SetTargetChainMinFee is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusVault = GeniusVault(0xB820A29D82aD13b4B2aD8BF77ae586A13caa00DA);
        address stableAddress = 0x29219dd400f2Bf60E5a23d13Be72B486D4038894;

        address[] memory feeTokens = new address[](9);
        feeTokens[0] = stableAddress; // USDC
        feeTokens[1] = stableAddress; // USDC
        feeTokens[2] = stableAddress; // USDC
        feeTokens[3] = stableAddress; // USDC
        feeTokens[4] = stableAddress; // USDC
        feeTokens[5] = stableAddress; // USDC
        feeTokens[6] = stableAddress; // USDC
        feeTokens[7] = stableAddress; // USDC
        feeTokens[8] = stableAddress; // USDC

        uint256[] memory minFeeAmounts = new uint256[](9);
        minFeeAmounts[0] = 50000; // $0.05
        minFeeAmounts[1] = 50000; // $0.05
        minFeeAmounts[2] = 50000; // $0.05
        minFeeAmounts[3] = 50000; // $0.05
        minFeeAmounts[4] = 50000; // $0.05
        minFeeAmounts[5] = 50000; // $0.05
        minFeeAmounts[6] = 50000; // $0.05
        minFeeAmounts[7] = 50000; // $0.05
        minFeeAmounts[8] = 50000; // $0.05

        uint256[] memory targetNetworks = new uint256[](9);
        targetNetworks[0] = 8453; // BASE
        targetNetworks[1] = 10; // OPTIMISM
        targetNetworks[2] = 42161; // ARBITRUM
        targetNetworks[3] = 1; // ETHEREUM
        targetNetworks[4] = 43114; // AVALANCHE
        targetNetworks[5] = 1399811149; // SOLANA
        targetNetworks[6] = 137; //POLYGON
        targetNetworks[7] = 146; //SONIC
        targetNetworks[8] = 56; //BSC

        for (uint256 i = 0; i < feeTokens.length; i++) {
            uint256 targetChainMinFee = geniusVault.targetChainMinFee(
                feeTokens[i],
                targetNetworks[i]
            );

            if (
                targetChainMinFee != minFeeAmounts[i] &&
                block.chainid != targetNetworks[i]
            ) {
                geniusVault.setTargetChainMinFee(
                    feeTokens[i],
                    targetNetworks[i],
                    minFeeAmounts[i]
                );
            }
        }
    }
}
