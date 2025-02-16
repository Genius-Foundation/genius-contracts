// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract SetTargetChainMinFee is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusVault = GeniusVault(0x05167A214DBC6EBB561dABe07d78e542B1C372B2);
        geniusVault.setTargetChainMinFee(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            43114,
            100000
        );
        geniusVault.setTargetChainMinFee(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            42161,
            100000
        );
        geniusVault.setTargetChainMinFee(
            0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            56,
            100000
        );
    }
}
