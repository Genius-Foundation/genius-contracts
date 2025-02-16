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
        //     100000
        // );
        // geniusVault.setTargetChainMinFee(
        //     0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        //     42161,
        //     100000
        // );
        geniusVault.setTargetChainMinFee(
            0xaf88d065e77c8cC2239327C5EDb3A432268e5831,
            56,
            100000
        );
    }
}
