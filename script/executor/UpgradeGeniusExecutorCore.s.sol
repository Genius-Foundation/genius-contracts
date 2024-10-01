// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusExecutor} from "../../src/GeniusExecutor.sol";
import {GeniusVault} from "../../src/GeniusVault.sol";

contract UpgradeGeniusExecutorCore is Script {
    function _run(
        address _geniusVault,
        address _permit2,
        address _stablecoin,
        address[] memory authorizedTargets
    ) internal {
        // Load deployment addresses from environment variables
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // Deploy new implementation
        GeniusExecutor newExecutor = new GeniusExecutor(
            _permit2,
            _geniusVault,
            _stablecoin,
            authorizedTargets
        );
        console.log("New GeniusExecutor deployed at:", address(newExecutor));

        // Upgrade proxy to new implementation
        GeniusVault vault = GeniusVault(_geniusVault);
        vault.setExecutor(address(newExecutor));

        vm.stopBroadcast();
    }
}
