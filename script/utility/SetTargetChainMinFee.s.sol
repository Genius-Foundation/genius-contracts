// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract SetTargetChainMinFee is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusVault = GeniusVault(0xB0C54E20c45D79013876DBD69EC4bec260f24F83);
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
        geniusVault.setTargetChainMinFee(
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            56,
            100000  // minFee (fixed amount)
        );
        
        // Set up fee tiers based on order size
        uint256[] memory thresholdAmounts = new uint256[](3);
        thresholdAmounts[0] = 0;        // First tier starts at 0 (smallest orders)
        thresholdAmounts[1] = 1000000;  // 1000 USD (with 6 decimals)
        thresholdAmounts[2] = 10000000; // 10000 USD (with 6 decimals)
        
        uint256[] memory bpsFees = new uint256[](3);
        bpsFees[0] = 30; // 0.3% for smallest orders
        bpsFees[1] = 20; // 0.2% for medium orders
        bpsFees[2] = 10; // 0.1% for large orders
        
        geniusVault.setFeeTiers(thresholdAmounts, bpsFees);
    }
}
