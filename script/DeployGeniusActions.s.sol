// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";

import {GeniusActions} from "../../src/GeniusActions.sol";

/**
 * @title DeployPolygonGeniusEcosystem
 * @dev A contract for deploying the GeniusActions contract.
        Deployment commands:
        `source .env` // Load environment variables
        source .env; forge script script/DeployGeniusActions.s.sol --rpc-url $BASE_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusActions is Script {
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address owner = vm.envAddress("OWNER_ADDRESS");

        geniusActions = new GeniusActions(owner);

        console.log("geniusActions deployed at: ", address(geniusActions));
    }
}
