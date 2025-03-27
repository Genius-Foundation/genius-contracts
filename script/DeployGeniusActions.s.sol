// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {GeniusActions} from "../src/GeniusActions.sol";

/**
 * @title DeployGeniusActions
 * @dev A contract for deploying the GeniusActions contract.
 *      Deployment commands:
 *      `source .env` // Load environment variables
 *      ETHEREUM: source .env; forge script script/DeployGeniusActions.s.sol:DeployGeniusActions --rpc-url $ETHEREUM_RPC_URL --broadcast -vvvv --via-ir
 *      POLYGON: source .env; forge script script/DeployGeniusActions.s.sol:DeployGeniusActions --rpc-url $POLYGON_RPC_URL --broadcast -vvvv --via-ir
 */
contract DeployGeniusActions is Script {
    GeniusActions public geniusActions;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address owner = vm.envAddress("OWNER_ADDRESS");
        vm.startBroadcast(deployerPrivateKey);

        geniusActions = new GeniusActions(owner);

        console.log("GeniusActions deployed at: ", address(geniusActions));

        vm.stopBroadcast();
    }
}