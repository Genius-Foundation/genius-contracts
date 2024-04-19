// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {GeniusVault} from "../src/GeniusVault.sol";

/**
 * @title DeployGeniusVault
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command: 
        AVALANCHE: forge script script/DeployGeniusVault.s.sol:DeployGeniusVault --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployGeniusVault.s.sol:DeployGeniusVault --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployGeniusVault is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.broadcast(deployerPrivateKey);

        GeniusVault geniusVault = new GeniusVault(
            0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E,
            0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909
        );
    }
}