// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusPool} from "../src/GeniusPool.sol";

/**
 * @title DeployGeniusPool
 * @dev A contract for deploying the GeniusVault contract.
        Deployment command: 
        AVALANCHE: forge script script/DeployGeniusPool.s.sol:DeployGeniusPool --rpc-url $AVALANCHE_RPC_URL --broadcast --verify -vvvv --via-ir
        BASE: forge script script/DeployGeniusPool.s.sol:DeployGeniusPool --rpc-url $BASE_RPC_URL --broadcast --verify -vvvv --via-ir
 */
contract DeployGeniusPool is Script {

    /**
     * @dev Executes the deployment of the GeniusVault contract.
     */

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        GeniusPool geniusPool = new GeniusPool(
            0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E,
            0x5CC11Ef1DE86c5E00259a463Ac3F3AE1A0fA2909
        );

        console.log("GeniusPool deployed at: ", address(geniusPool));

        // Initialize the GeniusPool contract
        geniusPool.initialize(0x11Fc9cba7055eEe21FCAeA973F46E26F09f0A289, 0x11Fc9cba7055eEe21FCAeA973F46E26F09f0A289);
    }
}