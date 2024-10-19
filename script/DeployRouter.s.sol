// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusRouter} from "../src/GeniusRouter.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusExecutor contract.
        Deployment commands:
        `source .env` // Load environment variables
        POLYGON: forge script script/deployment/DeployPolygonGeniusEcosystem.s.sol:DeployPolygonGeniusEcosystem --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployRouter is Script {
    GeniusRouter public geniusRouter;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        geniusRouter = new GeniusRouter(
            vm.envAddress("PERMIT2_ADDRESS"),
            vm.envAddress("GENIUS_VAULT_ADDRESS"),
            vm.envAddress("GENIUS_MULTICALL_ADDRESS")
        );

        console.log("GeniusRouter deployed at: ", address(geniusRouter));
    }
}
