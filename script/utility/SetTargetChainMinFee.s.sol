// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {FeeCollector} from "../../src/fees/FeeCollector.sol";

contract SetTargetChainMinFee is Script {
    FeeCollector public feeCollector;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        feeCollector = FeeCollector(0xB0C54E20c45D79013876DBD69EC4bec260f24F83);

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

        for (uint256 i = 0; i < targetNetworks.length; i++) {
            uint256 targetChainMinFee = feeCollector.targetChainMinFee(
                targetNetworks[i]
            );

            if (
                targetChainMinFee != minFeeAmounts[i] &&
                block.chainid != targetNetworks[i]
            ) {
                feeCollector.setTargetChainMinFee(
                    targetNetworks[i],
                    minFeeAmounts[i]
                );
            }
        }
    }
}
