// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusVault} from "../../src/GeniusVault.sol";

contract SetTargetChainMinFee is Script {
    GeniusVault public geniusVault;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusVault = GeniusVault(vm.envAddress("GENIUS_VAULT_ADDRESS"));
        uint256 targetChainId = vm.envUint("TARGET_CHAIN_ID");
        uint256 minFee = vm.envUint("MIN_FEE");
        address feeToken = vm.envAddress("FEE_TOKEN");
        geniusVault.setTargetChainMinFee(feeToken, targetChainId, minFee);
    }
}
