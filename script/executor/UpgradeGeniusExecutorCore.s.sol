// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";

contract UpgradeGeniusExecutorCore is Script {
    function _run(
        address _geniusVault,
        address _permit2,
        address[] memory authorizedTargets
    ) internal {
        // Load deployment addresses from environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        GeniusExecutor newExecutor = new GeniusExecutor(
            _permit2,
            _geniusVault,
            0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909,
            authorizedTargets
        );
        console.log("New GeniusExecutor deployed at:", address(newExecutor));

        // Upgrade proxy to new implementation
        GeniusVault vault = GeniusVault(_geniusVault);
        vault.setExecutor(address(newExecutor));

        vm.stopBroadcast();
    }
}
