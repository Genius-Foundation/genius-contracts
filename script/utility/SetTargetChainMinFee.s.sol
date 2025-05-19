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
        // geniusVault.setTargetChainMinFee(
        //     0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        //     43114,
        //     100000  // minFee (fixed amount)
        // );
        // geniusVault.setTargetChainMinFee(
        //     0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        //     42161,
        //     100000  // minFee (fixed amount)
        // );
        feeCollector.setTargetChainMinFee(
            56,
            100000 // minFee (fixed amount)
        );

        // Note: Fee tiers are now set in the FeeCollector, not the vault
        // This code is deprecated and should be removed
        // See DeployMergedFeeCollector.s.sol for the new approach
    }
}
